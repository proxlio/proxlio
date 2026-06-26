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
banner() { printf '\n%s%s%s\n\n' "$BOLD" "$*" "$RESET"; }
slow()   { local msg="$1" delay="${2:-0.05}"; for ((i=0; i<${#msg}; i++)); do printf '%s' "${msg:$i:1}"; sleep "$delay"; done; printf '\n'; }

banner "Proxlio Installer v0.2"

info "Detected OS: Ubuntu 24.04.1 LTS"
sleep 0.2
ok "Docker is installed: Docker version 27.3.1"
sleep 0.2

banner "Proxlio — Configuration"

printf '%sPrimary domain (e.g. example.com): %s' "$YELLOW" "$RESET"
slow "yourdomain.com" 0.06

printf '%sLet'"'"'s Encrypt email: %s' "$YELLOW" "$RESET"
slow "you@example.com" 0.06

printf '%sCloudflare API Token: %s' "$YELLOW" "$RESET"
slow "••••••••••••••••••••••••••••••••••••••" 0.02

printf '%sTunnel name [proxlio] (Enter to keep): %s' "$YELLOW" "$RESET"
printf 'proxlio\n'
sleep 0.2

printf '%sInstallation directory [~/proxlio] (Enter to keep): %s' "$YELLOW" "$RESET"
printf '~/proxlio\n'
sleep 0.2

banner "Configuration Summary"
printf '  Domain               : %syourdomain.com%s\n' "$BOLD" "$RESET"
printf '  Let'"'"'s Encrypt email : you@example.com\n'
printf '  Cloudflare API token : ••••\n'
printf '  Tunnel name          : proxlio\n'
printf '  Install dir          : ~/proxlio\n'
printf '\n'
printf '%sProceed with installation? [Y/n]: %sY\n' "$YELLOW" "$RESET"
sleep 0.2

ok "Port 53 is available."
sleep 0.1
ok "Install directory ready: ~/proxlio"
sleep 0.1
info "Writing .env..."
sleep 0.3
ok ".env written (permissions: 600)"
info "Writing docker-compose.yml..."
sleep 0.3
ok "docker-compose.yml written"
info "Copying scripts..."
sleep 0.2
ok "Scripts copied"

info "Setting up Cloudflare Tunnel 'proxlio'..."
sleep 0.6
ok "Logged in to Cloudflare."
sleep 0.3
ok "Tunnel 'proxlio' created."
sleep 0.3
ok "Tunnel token saved to .env"
sleep 0.2

info "Starting Proxlio stack..."
sleep 0.2
printf '[+] Container adguard      Started\n'; sleep 0.2
printf '[+] Container npm          Started\n'; sleep 0.2
printf '[+] Container cloudflared  Started\n'; sleep 0.2
ok "Stack started."
sleep 0.3
info "Waiting for NPM to be ready..."
sleep 1.5
ok "NPM is ready."
sleep 0.3

banner "Proxlio is running!"

printf '%sService URLs (on this host):%s\n' "$BOLD" "$RESET"
printf '  NPM Admin UI  : %shttp://localhost:81%s\n'   "$GREEN" "$RESET"
printf '  AdGuard Home  : %shttp://localhost:3000%s\n' "$GREEN" "$RESET"
printf '\n'
printf '%sNext steps:%s\n' "$BOLD" "$RESET"
printf '  1. Log in to NPM — change the default password\n'
printf '  2. Complete AdGuard setup wizard at http://192.168.1.x:3000\n'
printf '  3. Add your first service:\n'
printf '     cd ~/proxlio && ./scripts/add-service.sh\n'
printf '\n'
ok "Installation complete. Enjoy Proxlio!"
