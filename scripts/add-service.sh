#!/usr/bin/env bash
# add-service.sh — Add a service behind Proxlio (NPM proxy host + AdGuard DNS rewrite)
#
# Usage: ./scripts/add-service.sh
#
# Reads configuration from ../.env relative to this script.
# Required in .env: DOMAIN, HOST_IP
# Optional in .env: NPM_URL, NPM_EMAIL, NPM_PASSWORD, ADGUARD_URL, ADGUARD_USER, ADGUARD_PASSWORD

set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

err()  { echo -e "${RED}Error: $*${NC}" >&2; }
warn() { echo -e "${YELLOW}Warning: $*${NC}"; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }

# ─── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# ─── Dependency check ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  err "jq is required but not installed."
  echo "  Install it with: sudo apt-get install -y jq"
  exit 1
fi

if ! command -v curl &>/dev/null; then
  err "curl is required but not installed."
  echo "  Install it with: sudo apt-get install -y curl"
  exit 1
fi

# ─── Load .env FIRST, then set defaults ────────────────────────────────────────
# Loading .env before setting defaults allows values in .env to override them.
if [[ ! -f "$ENV_FILE" ]]; then
  err ".env file not found at $ENV_FILE"
  echo "  Run the install script first, or create .env manually with at least:"
  echo "    DOMAIN=yourdomain.com"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${DOMAIN:?DOMAIN is not set in .env — add: DOMAIN=yourdomain.com}"

if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
  warn "LETSENCRYPT_EMAIL is not set in $ENV_FILE — Let's Encrypt will reject the certificate request."
  warn "Add LETSENCRYPT_EMAIL=you@example.com to $ENV_FILE and re-run to get SSL."
fi

# Defaults applied AFTER source so .env values take precedence
NPM_URL="${NPM_URL:-http://localhost:81}"
ADGUARD_URL="${ADGUARD_URL:-http://localhost:3000}"
NPM_EMAIL="${NPM_EMAIL:-admin@example.com}"
NPM_PASSWORD="${NPM_PASSWORD:-changeme}"
ADGUARD_USER="${ADGUARD_USER:-}"
ADGUARD_PASSWORD="${ADGUARD_PASSWORD:-}"

# HOST_IP: IP of the machine running Proxlio (NPM listens here).
# Clients resolve subdomains to this IP so traffic goes through NPM.
# Populated by install.sh; fallback to auto-detection.
if [[ -z "${HOST_IP:-}" ]]; then
  HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || HOST_IP=""
fi
if [[ -z "$HOST_IP" ]]; then
  err "Cannot determine host IP. Set HOST_IP=<your-server-ip> in $ENV_FILE"
  exit 1
fi

# ─── Interactive prompts ───────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Add a service to Proxlio${NC}"
echo "──────────────────────────────────"
echo ""

read -rp "Service name (e.g. homeassistant): " SERVICE_NAME
read -rp "IP:Port of the service (e.g. 192.168.1.159:8123): " SERVICE_ADDR
read -rp "Subdomain (e.g. hass  →  hass.$DOMAIN): " SUBDOMAIN

echo ""

# ─── Validate inputs ───────────────────────────────────────────────────────────
[[ -z "$SERVICE_NAME" ]] && { err "Service name cannot be empty."; exit 1; }
[[ -z "$SERVICE_ADDR" ]] && { err "IP:Port cannot be empty."; exit 1; }
[[ -z "$SUBDOMAIN"    ]] && { err "Subdomain cannot be empty."; exit 1; }

if [[ "$SERVICE_ADDR" != *:* ]]; then
  err "Invalid format '$SERVICE_ADDR' — expected IP:Port (e.g. 192.168.1.159:8123)"
  exit 1
fi

FORWARD_HOST="${SERVICE_ADDR%%:*}"
FORWARD_PORT="${SERVICE_ADDR##*:}"

if [[ -z "$FORWARD_HOST" ]]; then
  err "IP address cannot be empty — expected format: 192.168.1.x:8080"
  exit 1
fi

if ! [[ "$FORWARD_PORT" =~ ^[0-9]+$ ]] || (( FORWARD_PORT < 1 || FORWARD_PORT > 65535 )); then
  err "Invalid port: $FORWARD_PORT"
  exit 1
fi

FQDN="${SUBDOMAIN}.${DOMAIN}"

# ─── Confirm before proceeding ─────────────────────────────────────────────────
echo "  → $SERVICE_NAME: $FQDN → $FORWARD_HOST:$FORWARD_PORT"
echo ""
read -rp "Create this service? [Y/n]: " confirm
case "${confirm:-Y}" in
  [Nn]*) echo "Cancelled."; exit 0 ;;
esac
echo ""

# ─── NPM: get auth token ───────────────────────────────────────────────────────
echo -n "  Connecting to NPM ($NPM_URL)... "

NPM_AUTH_BODY=$(jq -n --arg email "$NPM_EMAIL" --arg secret "$NPM_PASSWORD" \
  '{identity: $email, secret: $secret}')

if ! NPM_TOKEN_RESPONSE=$(curl -sf --max-time 10 \
  -X POST "$NPM_URL/api/tokens" \
  -H "Content-Type: application/json" \
  -d "$NPM_AUTH_BODY" 2>&1); then
  echo ""
  err "Cannot connect to NPM at $NPM_URL"
  echo "  Check that the stack is running:  docker compose ps"
  echo "  If NPM admin is bound to 127.0.0.1, run this script on the Proxlio host."
  exit 1
fi

NPM_TOKEN=$(echo "$NPM_TOKEN_RESPONSE" | jq -r '.token // empty')
if [[ -z "$NPM_TOKEN" ]]; then
  echo ""
  err "NPM authentication failed."
  echo "  Check NPM_EMAIL and NPM_PASSWORD in $ENV_FILE"
  echo "  Default credentials: admin@example.com / changeme"
  exit 1
fi
echo "OK"

# ─── NPM: create proxy host ────────────────────────────────────────────────────
echo -n "  Creating proxy host... "

PROXY_BODY=$(jq -n \
  --arg     fqdn "$FQDN" \
  --arg     host "$FORWARD_HOST" \
  --argjson port "$FORWARD_PORT" \
  '{
    domain_names:            [$fqdn],
    forward_scheme:          "http",
    forward_host:            $host,
    forward_port:            $port,
    access_list_id:          0,
    certificate_id:          0,
    ssl_forced:              0,
    caching_enabled:         0,
    block_exploits:          1,
    allow_websocket_upgrade: 1,
    http2_support:           0,
    locations:               []
  }')

if ! PROXY_RESPONSE=$(curl -sf --max-time 15 \
  -X POST "$NPM_URL/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $NPM_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PROXY_BODY" 2>&1); then
  echo ""
  err "Failed to create proxy host in NPM."
  echo "  Response: $PROXY_RESPONSE"
  exit 1
fi

PROXY_ID=$(echo "$PROXY_RESPONSE" | jq -r '.id // empty')
if [[ -z "$PROXY_ID" || "$PROXY_ID" == "null" ]]; then
  echo ""
  err "NPM returned an unexpected response."
  echo "  Response: $PROXY_RESPONSE"
  exit 1
fi
echo "OK (id: $PROXY_ID)"

# ─── NPM: request Let's Encrypt certificate ────────────────────────────────────
echo -n "  Requesting Let's Encrypt certificate (may take ~30s)... "

CERT_BODY=$(jq -n \
  --arg fqdn   "$FQDN" \
  --arg email  "${LETSENCRYPT_EMAIL:-}" \
  '{
    provider:     "letsencrypt",
    domain_names: [$fqdn],
    meta: {
      letsencrypt_agree: true,
      letsencrypt_email: $email,
      dns_challenge:     false
    }
  }')

SSL_ENABLED=false
CERT_ID=""

if CERT_RESPONSE=$(curl -sf --max-time 120 \
  -X POST "$NPM_URL/api/nginx/certificates" \
  -H "Authorization: Bearer $NPM_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CERT_BODY" 2>&1); then

  CERT_ID=$(echo "$CERT_RESPONSE" | jq -r '.id // empty' 2>/dev/null || true)
fi

if [[ -n "$CERT_ID" && "$CERT_ID" != "null" && "$CERT_ID" != "0" ]]; then
  UPDATE_BODY=$(jq -n \
    --arg     fqdn    "$FQDN" \
    --arg     host    "$FORWARD_HOST" \
    --argjson port    "$FORWARD_PORT" \
    --argjson cert_id "$CERT_ID" \
    '{
      domain_names:            [$fqdn],
      forward_scheme:          "http",
      forward_host:            $host,
      forward_port:            $port,
      access_list_id:          0,
      certificate_id:          $cert_id,
      ssl_forced:              1,
      caching_enabled:         0,
      block_exploits:          1,
      allow_websocket_upgrade: 1,
      http2_support:           1,
      locations:               []
    }')

  if curl -sf --max-time 15 \
    -X PUT "$NPM_URL/api/nginx/proxy-hosts/$PROXY_ID" \
    -H "Authorization: Bearer $NPM_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_BODY" >/dev/null 2>&1; then
    echo "OK (cert id: $CERT_ID, HTTPS enabled)"
    SSL_ENABLED=true
  else
    echo ""
    warn "Certificate issued but could not be attached to the proxy host."
    warn "Enable SSL manually: NPM admin → Proxy Hosts → $FQDN → Edit → SSL"
  fi
else
  echo ""
  warn "Let's Encrypt request failed — the domain is likely not publicly reachable yet."
  warn "This is expected before the Cloudflare Tunnel is configured."
  warn "Enable SSL later from NPM admin → Proxy Hosts → $FQDN → Edit → SSL"
fi

# ─── AdGuard: create DNS rewrite ───────────────────────────────────────────────
# Rewrite: FQDN → HOST_IP (the machine running NPM)
# Local clients resolve the subdomain to HOST_IP and connect to NPM (ports 80/443)
# instead of going through Cloudflare. Traffic stays on LAN.
echo -n "  Adding DNS rewrite in AdGuard ($ADGUARD_URL)... "

ADGUARD_REWRITE_BODY=$(jq -n \
  --arg domain "$FQDN" \
  --arg answer "$HOST_IP" \
  '{domain: $domain, answer: $answer}')

ADGUARD_HTTP_CODE=""

if [[ -n "$ADGUARD_USER" && -n "$ADGUARD_PASSWORD" ]]; then
  ADGUARD_HTTP_CODE=$(curl -s --max-time 10 \
    -X POST "$ADGUARD_URL/control/rewrite/add" \
    -u "$ADGUARD_USER:$ADGUARD_PASSWORD" \
    -H "Content-Type: application/json" \
    -d "$ADGUARD_REWRITE_BODY" \
    -w "%{http_code}" -o /dev/null 2>/dev/null) || true
else
  ADGUARD_HTTP_CODE=$(curl -s --max-time 10 \
    -X POST "$ADGUARD_URL/control/rewrite/add" \
    -H "Content-Type: application/json" \
    -d "$ADGUARD_REWRITE_BODY" \
    -w "%{http_code}" -o /dev/null 2>/dev/null) || true
fi

if [[ "$ADGUARD_HTTP_CODE" =~ ^2 ]]; then
  echo "OK ($FQDN → $HOST_IP)"
elif [[ -z "$ADGUARD_HTTP_CODE" ]]; then
  echo ""
  warn "Cannot connect to AdGuard at $ADGUARD_URL"
  warn "Add DNS rewrite manually: AdGuard admin → Settings → DNS rewrites → Add"
  warn "  Domain: $FQDN   Answer: $HOST_IP"
else
  echo ""
  warn "AdGuard returned HTTP $ADGUARD_HTTP_CODE."
  warn "Add DNS rewrite manually: AdGuard admin → Settings → DNS rewrites → Add"
  warn "  Domain: $FQDN   Answer: $HOST_IP"
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "$FQDN → $FORWARD_HOST:$FORWARD_PORT"
echo ""
echo "Next step — add a public hostname in your Cloudflare Tunnel:"
echo ""
echo "  Cloudflare Zero Trust → Networks → Tunnels → ${CF_TUNNEL_NAME:-your-tunnel} → Edit → Public Hostnames → Add"
echo "    Subdomain : $SUBDOMAIN"
echo "    Domain    : $DOMAIN"
echo "    Service   : http://localhost"
echo ""

if [[ "$SSL_ENABLED" == "false" ]]; then
  echo "Then enable SSL in NPM once the tunnel is live:"
  echo "  NPM admin → Proxy Hosts → $FQDN → Edit → SSL → Let's Encrypt"
  echo ""
fi
