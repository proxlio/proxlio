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
warn()    { printf '%s[~]%s %s\n'  "$YELLOW" "$RESET" "$*"; }
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
    # Use sudo directly here — get_sudo() requires docker to already be running
    if ! command -v curl >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq curl
    fi
    curl -fsSL https://get.docker.com | sh
    local current_user
    current_user=$(id -un)
    if ! groups "$current_user" | grep -q docker; then
        sudo usermod -aG docker "$current_user"
        info "Added $current_user to docker group."
        info "For this session, docker commands will run with sudo. Log out and back in to run without sudo."
    fi
    ok "Docker installed."
}

# Resolve docker compose command.
# After a fresh docker install the current session may not have the docker group yet.
# Uses an array to safely handle the optional sudo prefix.
docker_compose() {
    local -a pre=()
    if ! docker info >/dev/null 2>&1; then
        if sudo -n docker info >/dev/null 2>&1; then
            pre=(sudo)
        fi
    fi
    if "${pre[@]}" docker compose version >/dev/null 2>&1; then
        "${pre[@]}" docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        "${pre[@]}" docker-compose "$@"
    else
        die "docker compose not available."
    fi
}

# ---------------------------------------------------------------------------
# Interactive prompt helpers
# ---------------------------------------------------------------------------
prompt_value() {
    local var_name="$1"
    local question="$2"
    local default="$3"

    if [ -n "$default" ]; then
        printf '%s%s [%s] (Enter to keep): %s' "$YELLOW" "$question" "$default" "$RESET"
    else
        printf '%s%s: %s' "$YELLOW" "$question" "$RESET"
    fi

    read -r input
    if [ -z "$input" ] && [ -n "$default" ]; then
        printf -v "$var_name" '%s' "$default"
    else
        printf -v "$var_name" '%s' "$input"
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
        value="${!var_name}"
        if [ -z "$value" ]; then
            err "This field is required."
        fi
    done
}

# Prompt for a secret (input not echoed, retries until provided)
prompt_secret() {
    local var_name="$1"
    local question="$2"
    local value=""

    while [ -z "$value" ]; do
        printf '%s%s: %s' "$YELLOW" "$question" "$RESET"
        read -rs value
        printf '\n'
        if [ -z "$value" ]; then
            err "This field is required."
        fi
    done
    printf -v "$var_name" '%s' "$value"
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
    prompt_secret CF_API_TOKEN \
        "Cloudflare API Token"

    prompt_required CF_TUNNEL_NAME \
        "Cloudflare Tunnel name — internal label, only visible in your Cloudflare dashboard" \
        "proxlio"

    local default_dir
    default_dir="${HOME}/proxlio"
    prompt_value INSTALL_DIR \
        "Installation directory" \
        "$default_dir"

    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
}

# ---------------------------------------------------------------------------
# Confirm before proceeding
# ---------------------------------------------------------------------------
confirm_config() {
    banner "Configuration Summary"
    printf '  Domain               : %s%s%s\n' "$BOLD" "$DOMAIN" "$RESET"
    printf '  Let'"'"'s Encrypt email : %s\n'       "$LETSENCRYPT_EMAIL"
    printf '  Cloudflare API token : %s****\n'      "${CF_API_TOKEN:0:4}"
    printf '  Tunnel name          : %s\n'          "$CF_TUNNEL_NAME"
    printf '  Install dir          : %s\n'          "$INSTALL_DIR"
    printf '\n'
    printf '%sProceed with installation? [Y/n]: %s' "$YELLOW" "$RESET"
    read -r answer
    case "${answer:-Y}" in
        [Yy]*|"") ;;
        *) die "Installation cancelled." ;;
    esac
}

# ---------------------------------------------------------------------------
# Check port 53 availability (systemd-resolved conflict)
# Must run before writing any files so the user can abort cleanly.
# ---------------------------------------------------------------------------
check_port_53() {
    local port_in_use=0

    if command -v ss >/dev/null 2>&1; then
        if ss -lnup 2>/dev/null | grep -q ':53\b' || ss -lntp 2>/dev/null | grep -q ':53\b'; then
            port_in_use=1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -lnup 2>/dev/null | grep -q ':53\b' || netstat -lntp 2>/dev/null | grep -q ':53\b'; then
            port_in_use=1
        fi
    else
        warn "Cannot check port 53 (neither ss nor netstat found). Continuing — AdGuard may fail to bind."
        return 0
    fi

    if [ "$port_in_use" -eq 1 ]; then
        err "Port 53 is already in use. AdGuard Home cannot bind to it."
        info "On Ubuntu/Debian, systemd-resolved usually occupies port 53."
        info ""
        info "Recommended fix (non-destructive, Ubuntu 22.04/24.04):"
        info "  sudo mkdir -p /etc/systemd/resolved.conf.d"
        info "  echo -e '[Resolve]\nDNSStubListener=no' | sudo tee /etc/systemd/resolved.conf.d/no-stub.conf"
        info "  sudo systemctl restart systemd-resolved"
        info ""
        info "Alternative (simpler, fully disables systemd-resolved):"
        info "  sudo systemctl disable --now systemd-resolved"
        info "  echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf"
        printf '%sContinue anyway? [y/N]: %s' "$YELLOW" "$RESET"
        read -r answer
        case "${answer:-N}" in
            [Yy]*) warn "Continuing — AdGuard may fail to start. Fix the port conflict if it does." ;;
            *) die "Aborted. Free port 53 first, then re-run install.sh." ;;
        esac
    else
        ok "Port 53 is available."
    fi
}

# ---------------------------------------------------------------------------
# Write .env
# Backs up any existing .env before overwriting.
# ---------------------------------------------------------------------------
write_env() {
    local env_file="${INSTALL_DIR}/.env"

    if [ -f "$env_file" ]; then
        local backup="${env_file}.bak.$(date +%s)"
        cp "$env_file" "$backup"
        warn "Existing .env backed up to ${backup}"
    fi

    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || host_ip=""

    info "Writing ${env_file}..."
    cat > "$env_file" <<EOF
# Proxlio environment — generated by install.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
DOMAIN="${DOMAIN}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL}"
CF_API_TOKEN="${CF_API_TOKEN}"
CF_TUNNEL_NAME="${CF_TUNNEL_NAME}"
HOST_IP="${host_ip}"
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
  # Note: free port 53 before starting (systemd-resolved conflict on Ubuntu):
  #   sudo mkdir -p /etc/systemd/resolved.conf.d
  #   echo -e '[Resolve]\nDNSStubListener=no' | sudo tee /etc/systemd/resolved.conf.d/no-stub.conf
  #   sudo systemctl restart systemd-resolved
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
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 15s

  # ─────────────────────────────────────────────
  # Nginx Proxy Manager — reverse proxy + SSL auto (Let's Encrypt)
  # Admin UI : http://localhost:81  (bound to localhost — not accessible from LAN by default)
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
      - "127.0.0.1:81:81"
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
    depends_on:
      adguard:
        condition: service_healthy

  # ─────────────────────────────────────────────
  # Cloudflare Tunnel — external access without port forwarding
  # No ports exposed: the tunnel is initiated outbound to Cloudflare.
  # Token passed via TUNNEL_TOKEN env var.
  # Note: env vars are visible in 'docker inspect' — use Docker Secrets for production hardening.
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
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    depends_on:
      npm:
        condition: service_started

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
        info "Note: helper scripts not found (curl-pipe install mode)."
        info "To get add-service.sh, clone the repo after installation:"
        info "  git clone https://github.com/proxlio/proxlio /tmp/proxlio"
        info "  cp -r /tmp/proxlio/scripts ${INSTALL_DIR}/scripts"
        info "  chmod +x ${INSTALL_DIR}/scripts/*.sh"
    fi
}

# ---------------------------------------------------------------------------
# Cloudflare Tunnel — create and get token
# ---------------------------------------------------------------------------
setup_tunnel() {
    info "Setting up Cloudflare Tunnel '${CF_TUNNEL_NAME}'..."

    if ! command -v cloudflared >/dev/null 2>&1; then
        info "cloudflared CLI not found — skipping automatic tunnel creation."
        CLOUDFLARE_TUNNEL_TOKEN=""
        return 0
    fi

    # Warn headless users before cloudflared tries to open a browser
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        info "No display detected (headless server)."
        info "cloudflared tunnel login will print a URL — copy it and open it in a browser on another device."
    fi
    cloudflared tunnel login

    # tunnel list output: ID | NAME | CREATED | CONNECTIONS — name is column 2
    if ! cloudflared tunnel list 2>/dev/null | awk 'NR>1 {print $2}' | grep -qxF "$CF_TUNNEL_NAME"; then
        cloudflared tunnel create "$CF_TUNNEL_NAME"
        ok "Tunnel '${CF_TUNNEL_NAME}' created."
    else
        ok "Tunnel '${CF_TUNNEL_NAME}' already exists."
    fi

    CLOUDFLARE_TUNNEL_TOKEN=$(cloudflared tunnel token "$CF_TUNNEL_NAME")
    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        err "Could not retrieve tunnel token. Set CLOUDFLARE_TUNNEL_TOKEN manually in ${INSTALL_DIR}/.env"
        CLOUDFLARE_TUNNEL_TOKEN=""
    else
        # Use % as sed delimiter — Cloudflare tokens are base64url (no %)
        sed -i "s%^# CLOUDFLARE_TUNNEL_TOKEN=.*%CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}%" "${INSTALL_DIR}/.env"
        ok "Tunnel token saved to .env"
    fi
}

# ---------------------------------------------------------------------------
# Launch stack
# ---------------------------------------------------------------------------
launch_stack() {
    local compose_args=(-f "${INSTALL_DIR}/docker-compose.yml" --env-file "${INSTALL_DIR}/.env" --project-directory "${INSTALL_DIR}")
    if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        info "Starting Proxlio stack with Cloudflare Tunnel..."
        docker_compose "${compose_args[@]}" --profile tunnel up -d
    else
        info "Starting Proxlio stack (without tunnel)..."
        docker_compose "${compose_args[@]}" up -d
    fi
    ok "Stack started."

    # Wait for NPM to respond before printing access URLs
    info "Waiting for NPM to be ready (first start may take 15-30s)..."
    local i ready=0
    for i in $(seq 1 20); do
        if curl -sf --max-time 3 http://localhost:81 >/dev/null 2>&1; then
            ok "NPM is ready."
            ready=1
            break
        fi
        sleep 2
    done
    if [ "$ready" -eq 0 ]; then
        warn "NPM did not respond in 40s — check logs: docker compose -f ${INSTALL_DIR}/docker-compose.yml logs npm"
    fi
}

# ---------------------------------------------------------------------------
# Configure NPM defaults right after first start.
# Uses default credentials (guaranteed at this point — user hasn't changed them yet).
# Sets the default site to 404 so unrecognised hosts don't expose the NPM congratulations page.
# ---------------------------------------------------------------------------
configure_npm_defaults() {
    local npm_url="http://localhost:81"
    info "Configuring NPM defaults..."

    local auth_response token
    auth_response=$(curl -sf --max-time 10 \
        -X POST "${npm_url}/api/tokens" \
        -H "Content-Type: application/json" \
        -d '{"identity":"admin@example.com","secret":"changeme"}' 2>/dev/null) || true

    token=$(printf '%s' "$auth_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4) || true

    if [ -z "$token" ]; then
        warn "Could not authenticate with NPM to configure defaults (credentials may already be changed)."
        warn "Set the default site manually: NPM admin → Settings → Default Site → Page Not Found (404)"
        return 0
    fi

    local http_code
    http_code=$(curl -s --max-time 10 \
        -X PUT "${npm_url}/api/settings/default-site" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{"value":"404"}' \
        -w "%{http_code}" -o /dev/null 2>/dev/null) || true

    if [ "${http_code:-0}" = "200" ]; then
        ok "NPM default site set to 404 (hides the Congratulations page for unconfigured hosts)."
    else
        warn "Could not set NPM default site (HTTP ${http_code:-?}). Set it manually: Settings → Default Site → 404."
    fi
}

# ---------------------------------------------------------------------------
# Post-install summary
# ---------------------------------------------------------------------------
print_summary() {
    local host_ip
    host_ip=$(hostname -I 2>/dev/null | awk '{print $1}') || host_ip="<your-host-ip>"
    local current_user
    current_user=$(id -un)

    banner "Proxlio is running!"

    printf '%sService URLs (on this host):%s\n' "$BOLD" "$RESET"
    printf '  NPM Admin UI  : %shttp://localhost:81%s\n'    "$GREEN" "$RESET"
    printf '  AdGuard Home  : %shttp://localhost:3000%s\n'  "$GREEN" "$RESET"
    printf '\n'
    printf '%sAccessing NPM from another device (laptop, phone):%s\n' "$BOLD" "$RESET"
    printf '  NPM admin is bound to localhost for security. Access it via SSH tunnel:\n'
    printf '    ssh -L 8181:localhost:81 %s@%s\n' "$current_user" "$host_ip"
    printf '    Then open: http://localhost:8181\n'
    printf '\n'
    printf '%sNPM default credentials:%s\n' "$BOLD" "$RESET"
    printf '  Email    : admin@example.com\n'
    printf '  Password : changeme\n'
    printf '%s  -> Change these immediately after first login!%s\n' "$RED" "$RESET"
    printf '\n'
    printf '%sNext steps:%s\n' "$BOLD" "$RESET"
    printf '  1. Log in to NPM and change the default password\n'
    printf '  2. Complete the AdGuard setup wizard at http://%s:3000\n' "$host_ip"
    printf '  3. Add AdGuard credentials to .env (required for automatic DNS rewrites):\n'
    printf '     echo '"'"'ADGUARD_USER=<your-username>'"'"' >> %s/.env\n' "$INSTALL_DIR"
    printf '     echo '"'"'ADGUARD_PASSWORD=<your-password>'"'"' >> %s/.env\n' "$INSTALL_DIR"
    printf '     (Set during the AdGuard setup wizard in step 2)\n'
    printf '  4. Add your first service:\n'
    printf '     cd %s && ./scripts/add-service.sh\n' "$INSTALL_DIR"

    if [ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
        printf '\n'
        printf '%sCloudflare Tunnel setup (required for external access):%s\n' "$BOLD" "$RESET"
        printf '  1. Go to https://one.dash.cloudflare.com/ -> Networks -> Tunnels\n'
        printf '  2. Create a tunnel named '"'"'%s'"'"'\n' "$CF_TUNNEL_NAME"
        printf '  3. Copy the tunnel token and add it to %s/.env:\n' "$INSTALL_DIR"
        printf '     CLOUDFLARE_TUNNEL_TOKEN=<your-token>\n'
        printf '  4. Start the tunnel:\n'
        printf '     cd %s && docker compose --profile tunnel up -d cloudflared\n' "$INSTALL_DIR"
    else
        printf '  4. Add public hostnames in Cloudflare Zero Trust:\n'
        printf '     https://one.dash.cloudflare.com/ -> Networks -> Tunnels -> %s -> Edit\n' "$CF_TUNNEL_NAME"
    fi

    printf '\n'
    printf '%sTo stop the stack:%s  docker compose -f %s/docker-compose.yml down\n' "$YELLOW" "$RESET" "$INSTALL_DIR"
    printf '%sTo view logs:%s       docker compose -f %s/docker-compose.yml logs -f\n' "$YELLOW" "$RESET" "$INSTALL_DIR"
    printf '\n'
    ok "Installation complete. Enjoy Proxlio!"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    banner "Proxlio Installer v0.2"

    detect_os
    ok "OS: $(. /etc/os-release && echo "${PRETTY_NAME}")"

    check_docker

    gather_config
    confirm_config

    # Check port 53 BEFORE writing any files — user may abort here
    check_port_53

    mkdir -p "$INSTALL_DIR"
    ok "Install directory ready: ${INSTALL_DIR}"

    write_env
    write_compose
    copy_scripts
    setup_tunnel
    launch_stack
    configure_npm_defaults
    print_summary
}

main "$@"
