#!/usr/bin/env bash
# Simulates the Proxlio installer output for demo/GIF generation.
# Not the real installer — no Docker, no credentials needed.

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3); BOLD=$(tput bold); RESET=$(tput sgr0)
else
    RED="" GREEN="" YELLOW="" BOLD="" RESET=""
fi

info()   { printf '%s[*]%s %s\n' "$YELLOW" "$RESET" "$*"; }
ok()     { printf '%s[+]%s %s\n' "$GREEN"  "$RESET" "$*"; }
err()    { printf '%s[!]%s %s\n' "$RED"    "$RESET" "$*"; }
banner() { printf '\n%s%s%s\n\n' "$BOLD" "$*" "$RESET"; }
slow()   { local msg="$1" delay="${2:-0.04}"; for ((i=0; i<${#msg}; i++)); do printf '%s' "${msg:$i:1}"; sleep "$delay"; done; printf '\n'; }

banner "Proxlio Installer v0.2"

info "Detected OS: Ubuntu 24.04.1 LTS"
sleep 0.3
ok "Docker is installed: Docker version 27.3.1"
sleep 0.2

banner "Proxlio — Configuration"

printf '%sPrimary domain (e.g. example.com): %s' "$YELLOW" "$RESET"
slow "yourdomain.com" 0.07

printf '%sLet'"'"'s Encrypt email: %s' "$YELLOW" "$RESET"
slow "you@example.com" 0.07

printf '%sCloudflare API Token: %s' "$YELLOW" "$RESET"
slow "••••••••••••••••••••••••••••••••••••••••" 0.03

printf '%sTunnel name [proxlio]: %s' "$YELLOW" "$RESET"
slow "" 0.05
printf 'proxlio\n'
sleep 0.3

printf '%sInstallation directory [%s/proxlio]: %s' "$YELLOW" "$HOME" "$RESET"
slow "" 0.05
printf '%s/proxlio\n' "$HOME"
sleep 0.2

banner "Configuration Summary"
printf '  Domain               : %syourdomain.com%s\n' "$BOLD" "$RESET"
printf '  Let'"'"'s Encrypt email : you@example.com\n'
printf '  Cloudflare API token : ••••\n'
printf '  Tunnel name          : proxlio\n'
printf '  Install dir          : %s/proxlio\n' "$HOME"
printf '\n'
printf '%sProceed with installation? [Y/n]: %sY\n' "$YELLOW" "$RESET"
sleep 0.3

ok "Port 53 is available."
sleep 0.2
ok "Install directory ready: ${HOME}/proxlio"
sleep 0.2
info "Writing .env..."
sleep 0.5
ok ".env written (permissions: 600)"
sleep 0.2
info "Writing embedded docker-compose.yml..."
sleep 0.4
ok "docker-compose.yml written"
sleep 0.2
info "Copying scripts to ${HOME}/proxlio/scripts..."
sleep 0.3
ok "Scripts copied"
sleep 0.2

info "Setting up Cloudflare Tunnel 'proxlio'..."
sleep 1.0
printf 'You need to run the following command in a browser:\n\n'
printf '  https://dash.cloudflare.com/auth/sso/...\n\n'
sleep 0.8
ok "Logged in to Cloudflare."
sleep 0.4
ok "Tunnel 'proxlio' created."
sleep 0.5
ok "Tunnel token saved to .env"
sleep 0.3

info "Starting Proxlio stack with Cloudflare Tunnel..."
sleep 0.3
printf '[+] Network proxlio                  Created\n'
sleep 0.15
printf '[+] Volume proxlio_adguard_conf      Created\n'
sleep 0.1
printf '[+] Volume proxlio_adguard_work      Created\n'
sleep 0.1
printf '[+] Volume proxlio_npm_data          Created\n'
sleep 0.1
printf '[+] Volume proxlio_npm_letsencrypt   Created\n'
sleep 0.15
printf '[+] Container adguard                Started\n'
sleep 0.3
printf '[+] Container npm                    Started\n'
sleep 0.2
printf '[+] Container cloudflared            Started\n'
sleep 0.3
ok "Stack started."
sleep 0.5
info "Waiting for NPM to be ready (first start may take 15-30s)..."
sleep 2.5
ok "NPM is ready."
sleep 0.3

banner "Proxlio is running!"

printf '%sService URLs (on this host):%s\n' "$BOLD" "$RESET"
printf '  NPM Admin UI  : %shttp://localhost:81%s\n'    "$GREEN" "$RESET"
printf '  AdGuard Home  : %shttp://localhost:3000%s\n'  "$GREEN" "$RESET"
printf '\n'
printf '%sAccessing NPM from another device:%s\n' "$BOLD" "$RESET"
printf '  ssh -L 8181:localhost:81 %s@192.168.1.x\n' "$(id -un)"
printf '  Then open: http://localhost:8181\n'
printf '\n'
printf '%sNPM default credentials:%s\n' "$BOLD" "$RESET"
printf '  Email    : admin@example.com\n'
printf '  Password : changeme\n'
printf '%s  -> Change these immediately after first login!%s\n' "$RED" "$RESET"
printf '\n'
printf '%sNext steps:%s\n' "$BOLD" "$RESET"
printf '  1. Log in to NPM and change the default password\n'
printf '  2. Complete AdGuard setup wizard at http://192.168.1.x:3000\n'
printf '  3. Add AdGuard credentials to .env:\n'
printf '     echo '"'"'ADGUARD_USER=admin'"'"' >> %s/proxlio/.env\n' "$HOME"
printf '     echo '"'"'ADGUARD_PASSWORD=yourpassword'"'"' >> %s/proxlio/.env\n' "$HOME"
printf '  4. Add your first service:\n'
printf '     cd %s/proxlio && ./scripts/add-service.sh\n' "$HOME"
printf '\n'
ok "Installation complete. Enjoy Proxlio!"
