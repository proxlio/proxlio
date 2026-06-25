#!/usr/bin/env bash
# Proxlio installer — NPM + AdGuard Home + Cloudflare Tunnel
# https://proxlio.com
set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (disabled if not a tty or terminal doesn't support them)
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1 && [ "$(tput colors)" -ge 8 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BOLD="" RESET=""
fi

info()    { printf '%s[*]%s %s\n'  "$YELLOW" "$RESET" "$*"; }
ok()      { printf '%s[+]%s %s\n'  "$GREEN"  "$RESET" "$*"; }
err()     { printf '%s[!]%s %s\n'  "$RED"    "$RESET" "$*" >&2; }
die()     { err "$*"; exit 1; }
banner()  { printf '\n%s%s%s\n\n' "$BOLD" "$*" "$RESET"; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
    else
        die "Cannot detect OS (/etc/os-release not found). Supported: Debian, Ubuntu, Raspberry Pi OS."
    fi

    case "$OS_ID" in
        debian|ubuntu|raspbian) return 0 ;;
        *)
            # Accept distros that are debian/ubuntu derivatives
            case "$OS_LIKE" in
                *debian*|*ubuntu*) return 0 ;;
                *) die "Unsupported OS: $OS_ID. Proxlio requires Debian, Ubuntu, or Raspberry Pi OS." ;;
            esac
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Docker check / install
# ---------------------------------------------------------------------------
check_docker() {
    local need_docker=0
    local need_compose=0

    if ! command -v docker >/dev/null 2>&1; then
        need_docker=1
    fi

    # Check for docker compose v2 (plugin) or v1 (standalone)
    if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        need_compose=1
    fi

    if [ "$need_docker" -eq 1 ] || [ "$need_compose" -eq 1 ]; then
        info "Docker$([ "$need_compose" -eq 1 ] && echo ' Compose') not found."
        printf '%sInstall Docker automatically? [Y/n]: %s' "$YELLOW" "$RESET"
        read -r answer
        case "${answer:-Y}" in
            [Yy]*|"")
                install_docker
                ;;
            *)
                die "Docker is required. Install it manually: https://docs.docker.com/engine/install/"
                ;;
        esac
    else
        ok "Docker is installed: $(docker --version)"
    fi
}

install_docker() {
    info "Installing Docker via official convenience script..."
    if ! command -v curl >/dev/null 2>&1; then
        SUDO_CMD=$(get_sudo) || die "Cannot get sudo"
        $SUDO_CMD apt-get update -qq && $SUDO_CMD apt-get install -y -qq curl
    fi
    curl -fsSL https://get.docker.com | sh
    # Add current user to docker group to avoid sudo for docker commands
    local current_user
    current_user=$(id -un)
    if ! groups "$current_user" | grep -q docker; then
        SUDO_CMD=$(get_sudo) || die "Cannot get sudo"
        $SUDO_CMD usermod -aG docker "$current_user"
        info "Added $current_user to docker group. You may need to log out and back in for group changes to take effect."
        info "For this session, commands will run with sudo if needed."
    fi
    ok "Docker installed."
}

# Returns "sudo" if needed, "" if docker runs as current user, exits on failure
get_sudo() {
    if docker info >/dev/null 2>&1; then
        echo ""
    elif sudo -n docker info >/dev/null 2>&1; then
        echo "sudo"
    else
        # Prompt for sudo
        if sudo docker info >/dev/null 2>&1; then
            echo "sudo"
        else
            return 1
        fi
    fi
}

# Resolve docker compose command (v2 plugin or v1 standalone)
docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        die "docker compose not available."
    fi
}

# ---------------------------------------------------------------------------
# Interactive prompt helper
# Usage: prompt_value VAR_NAME "Question text" "default value"
# ---------------------------------------------------------------------------
prompt_value() {
    local var_name="$1"
    local question="$2"
    local default="$3"

    if [ -n "$default" ]; then
        printf '%s%s [%s]: %s' "$YELLOW" "$question" "$default" "$RESET"
    else
        printf '%s%s: %s' "$YELLOW" "$question" "$RESET"
    fi

    read -r input
    if [ -z "$input" ] && [ -n "$default" ]; then
        eval "${var_name}=\"\${default}\""
    else
        eval "${var_name}=\"\${input}\""
    fi
}

# Prompt for a non-empty value (retries until provided or default used)
prompt_required() {
    local var_name="$1"
    local question="$2"
    local default="${3:-}"
    local value=""

    while [ -z "$value" ]; do
        prompt_value "$var_name" "$question" "$default"
        eval "value=\"\${${var_name}}\""
        if [ -z "$value" ]; then
            err "This field is required."
        fi
    done
}

# ---------------------------------------------------------------------------
# Gather configuration
# ---------------------------------------------------------------------------
gather_config() {
    banner "Proxlio — Configuration"

    prompt_required DOMAIN \
        "Primary domain (e.g. example.com)" \
        ""

    prompt_required LETSENCRYPT_EMAIL \
        "Let's Encrypt email (for SSL certificates)" \
        ""

    info "Cloudflare API Token: create one at https://dash.cloudflare.com/profile/api-tokens"
    info "Required permissions: Zone:Read (all zones) + Cloudflare Tunnel:Edit"
    prompt_required CF_API_TOKEN \
        "Cloudflare API Token" \
        ""

    prompt_required CF_TUNNEL_NAME \
        "Cloudflare Tunnel name (e.g. my-homelab)" \
        "proxlio"

    local default_dir
    default_dir="${HOME}/proxlio"
    prompt_value INSTALL_DIR \
        "Installation directory" \
        "$default_dir"

    # Expand ~ if present
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
}

# ---------------------------------------------------------------------------
# Confirm before proceeding
# ---------------------------------------------------------------------------
confirm_config() {
    banner "Configuration Summary"
    printf '  Domain         : %s%s%s\n' "$BOLD" "$DOMAIN" "$RESET"
    printf '  LE Email       : %s\n' "$LETSENCRYPT_EMAIL"
    printf '  CF Token       : %s****%s\n' "${CF_API_TOKEN:0:6}" "${CF_API_TOKEN: -4}"
    printf '  Tunnel name    : %s\n' "$CF_TUNNEL_NAME"
    printf '  Install dir    : %s\n' "$INSTALL_DIR"
    printf '\n'
    printf '%sProceed with installation? [Y/n]: %s' "$YELLOW" "$RESET"
    read -r answer
    case "${answer:-Y}" in
        [Yy]*|"") ;;
        *) die "Installation cancelled." ;;
    esac
}

# ---------------------------------------------------------------------------
# Write .env
# ---------------------------------------------------------------------------
write_env() {
    local env_file="${INSTALL_DIR}/.env"
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || host_ip=""

    info "Writing ${env_file}..."
    cat > "$env_file" <<EOF
# Proxlio environment — generated by install.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
CF_API_TOKEN=${CF_API_TOKEN}
CF_TUNNEL_NAME=${CF_TUNNEL_NAME}
HOST_IP=${host_ip}
ADGUARD_PORT=3000
# CLOUDFLARE_TUNNEL_TOKEN= (populated by setup_tunnel if cloudflared is available)
EOF
    chmod 600 "$env_file"
    ok ".env written (permissions: 600)"
}

# ---------------------------------------------------------------------------
# Write docker-compose.yml
# Prefers a compose file shipped alongside install.sh (repo mode).
# Falls back to an embedded copy for curl-pipe installs.
# ---------------------------------------------------------------------------
write_compose() {
    local compose_file="${INSTALL_DIR}/docker-compose.yml"
    # If install.sh is running from the repo directory, reuse the existing file.
    local script_dir
    script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || script_dir=""
    local repo_compose="${script_dir}/docker-compose.yml"

    if [ -f "$repo_compose" ] && [ "$repo_compose" != "$compose_file" ]; then
        info "Copying docker-compose.yml from $(dirname "$0")..."
        cp "$repo_compose" "$compose_file"
        ok "docker-compose.yml copied from repo"
        return 0
    fi

    info "Writing embedded docker-compose.yml to ${compose_file}..."
    cat > "$compose_file" <<'COMPOSE'
services:

  # ─────────────────────────────────────────────
  # AdGuard Home — DNS local + ad blocking
  # Admin UI : http://<host>:3000
  # DNS      : port 53 UDP/TCP
  #
  # Note: disable systemd-resolved before starting:
  #   sudo systemctl stop systemd-resolved
  #   sudo systemctl disable systemd-resolved
  # ─────────────────────────────────────────────
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    restart: unless-stopped
    networks:
      - proxlio
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "${ADGUARD_PORT:-3000}:3000/tcp"
    volumes:
      - adguard_conf:/opt/adguardhome/conf
      - adguard_work:/opt/adguardhome/work

  # ─────────────────────────────────────────────
  # Nginx Proxy Manager — reverse proxy + SSL auto (Let's Encrypt)
  # Admin UI : http://<host>:81
  #   Default email    : admin@example.com
  #   Default password : changeme  (change on first login)
  # HTTP  : port 80
  # HTTPS : port 443
  # ─────────────────────────────────────────────
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    networks:
      - proxlio
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
    depends_on:
      - adguard

  # ─────────────────────────────────────────────
  # Cloudflare Tunnel — external access without port forwarding
  # No ports exposed: the tunnel is initiated outbound to Cloudflare.
  # Token: create a tunnel at https://one.dash.cloudflare.com → Networks → Tunnels
  # Start with: docker compose --profile tunnel up -d
  # ─────────────────────────────────────────────
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    profiles: ["tunnel"]
    networks:
      - proxlio
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    depends_on:
      - npm

networks:
  proxlio:
    name: proxlio
    driver: bridge

volumes:
  npm_data:
    name: proxlio_npm_data
  npm_letsencrypt:
    name: proxlio_npm_letsencrypt
  adguard_conf:
    name: proxlio_adguard_conf
  adguard_work:
    name: proxlio_adguard_work
COMPOSE
    ok "docker-compose.yml written"
}

# ---------------------------------------------------------------------------
# Cloudflare Tunnel — create and get token
# Requires cloudflared CLI; falls back to manual instructions if not available.
# ---------------------------------------------------------------------------
setup_tunnel() {
    info "Setting up Cloudflare Tunnel '${CF_TUNNEL_NAME}'..."

    if ! command -v cloudflared >/dev/null 2>&1; then
        info "cloudflared CLI not found — skipping automatic tunnel creation."
        info "To finish tunnel setup:"
        info "  1. Go to https://one.dash.cloudflare.com/ -> Networks -> Tunnels"
        info "  2. Create a tunnel named '${CF_TUNNEL_NAME}'"
        info "  3. Copy the tunnel token and set it in ${INSTALL_DIR}/.env:"
        info "     CLOUDFLARE_TUNNEL_TOKEN=<your-token>"
        info "  4. Then run: cd ${INSTALL_DIR} && docker compose up -d cloudflared"
        CLOUDFLARE_TUNNEL_TOKEN=""
        return 0
    fi

    # Authenticate
    info "Running: cloudflared tunnel login (browser will open)"
    cloudflared tunnel login

    # Create tunnel (ignore error if already exists)
    # tunnel list output: ID | NAME | CREATED | CONNECTIONS — name is column 2
    if ! cloudflared tunnel list 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$CF_TUNNEL_NAME"; then
        cloudflared tunnel create "$CF_TUNNEL_NAME"
        ok "Tunnel '${CF_TUNNEL_NAME}' created."
    else
        ok "Tunnel '${CF_TUNNEL_NAME}' already exists."
    fi

    # Get tunnel token
    CLOUDFLARE_TUNNEL_TOKEN=$(cloudflared tunnel token "$CF_TUNNEL_NAME")
    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        err "Could not retrieve tunnel token. Set CLOUDFLARE_TUNNEL_TOKEN manually in ${INSTALL_DIR}/.env"
        CLOUDFLARE_TUNNEL_TOKEN=""
    else
        # Update the placeholder line in .env with the real token
        sed -i "s|^# CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}|" "${INSTALL_DIR}/.env"
        ok "Tunnel token saved to .env"
    fi
}

# ---------------------------------------------------------------------------
# Copy scripts/ to install directory
# ---------------------------------------------------------------------------
copy_scripts() {
    local script_dir
    script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || script_dir=""
    local src_scripts="${script_dir}/scripts"
    local dst_scripts="${INSTALL_DIR}/scripts"

    if [ -d "$src_scripts" ]; then
        info "Copying scripts to ${dst_scripts}..."
        cp -r "$src_scripts" "$dst_scripts"
        chmod +x "${dst_scripts}"/*.sh 2>/dev/null || true
        ok "Scripts copied to ${dst_scripts}"
    else
        # curl-pipe install: no local scripts dir available — warn the user
        info "Note: helper scripts not found (curl-pipe install mode)."
        info "To get add-service.sh, clone the repo after installation:"
        info "  git clone https://github.com/proxlio/proxlio /tmp/proxlio"
        info "  cp -r /tmp/proxlio/scripts ${INSTALL_DIR}/scripts"
        info "  chmod +x ${INSTALL_DIR}/scripts/*.sh"
    fi
}

# ---------------------------------------------------------------------------
# Check port 53 availability (systemd-resolved conflict)
# ---------------------------------------------------------------------------
check_port_53() {
    if ss -lnup 2>/dev/null | grep -q ':53\b' || ss -lntp 2>/dev/null | grep -q ':53\b'; then
        err "Port 53 is already in use. AdGuard Home cannot bind to it."
        info "On Ubuntu/Debian, systemd-resolved usually occupies port 53."
        info "To free it, run:"
        info "  sudo systemctl stop systemd-resolved"
        info "  sudo systemctl disable systemd-resolved"
        info "  sudo rm -f /etc/resolv.conf"
        info "  echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf"
        printf '%sContinue anyway? [y/N]: %s' "$YELLOW" "$RESET"
        read -r answer
        case "${answer:-N}" in
            [Yy]*) info "Continuing — AdGuard may fail to start. Fix the port conflict if it does." ;;
            *) die "Aborted. Free port 53 first, then re-run install.sh." ;;
        esac
    else
        ok "Port 53 is available."
    fi
}

# ---------------------------------------------------------------------------
# Launch stack
# ---------------------------------------------------------------------------
launch_stack() {
    local compose_args=(-f "${INSTALL_DIR}/docker-compose.yml" --env-file "${INSTALL_DIR}/.env" --project-directory "${INSTALL_DIR}")
    if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        info "Starting Proxlio stack with Cloudflare Tunnel (docker compose --profile tunnel up -d)..."
        docker_compose "${compose_args[@]}" --profile tunnel up -d
    else
        info "Starting Proxlio stack without tunnel (docker compose up -d)..."
        docker_compose "${compose_args[@]}" up -d
    fi
    ok "Stack started."
}

# ---------------------------------------------------------------------------
# Post-install summary
# ---------------------------------------------------------------------------
print_summary() {
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || host_ip="<your-host-ip>"

    banner "Proxlio is running!"

    printf '%sService URLs:%s\n' "$BOLD" "$RESET"
    printf '  NPM Admin UI  : %shttp://%s:81%s\n'       "$GREEN" "$host_ip" "$RESET"
    printf '  AdGuard Home  : %shttp://%s:3000%s\n'     "$GREEN" "$host_ip" "$RESET"
    printf '\n'
    printf '%sNPM default credentials:%s\n' "$BOLD" "$RESET"
    printf '  Email    : admin@example.com\n'
    printf '  Password : changeme\n'
    printf '%s  -> Change these immediately after first login!%s\n' "$RED" "$RESET"
    printf '\n'
    printf '%sNext steps:%s\n' "$BOLD" "$RESET"
    printf '  1. Log in to NPM and change the default password\n'
    printf '  2. Complete the AdGuard setup wizard (port 3000)\n'
    printf '  3. In NPM: add a Proxy Host for each service on your network\n'
    printf '  4. In AdGuard: set DNS rewrites to point subdomains to this host\n'
    if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        printf '  5. Complete Cloudflare Tunnel setup manually (see instructions above)\n'
    else
        printf '  5. Configure Cloudflare Tunnel routes in the Zero Trust dashboard\n'
        printf '     https://one.dash.cloudflare.com/ -> Networks -> Tunnels -> %s\n' "$CF_TUNNEL_NAME"
    fi
    printf '\n'
    printf '%sTo stop the stack:%s  cd %s && docker compose down\n' "$YELLOW" "$RESET" "$INSTALL_DIR"
    printf '%sTo view logs:%s       cd %s && docker compose logs -f\n' "$YELLOW" "$RESET" "$INSTALL_DIR"
    printf '\n'
    ok "Installation complete. Enjoy Proxlio!"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    banner "Proxlio Installer v0.1"

    detect_os
    ok "OS: $(. /etc/os-release && echo "${PRETTY_NAME}")"

    check_docker

    gather_config
    confirm_config

    # Create install directory
    mkdir -p "$INSTALL_DIR"
    ok "Install directory ready: ${INSTALL_DIR}"

    write_env
    write_compose
    copy_scripts
    check_port_53
    setup_tunnel
    launch_stack
    print_summary
}

main "$@"
