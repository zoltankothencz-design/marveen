#!/bin/bash
# Watchdog: Gibraltar dashboard HTTP server + Cloudflare quick tunnel
# Ha bármelyik meghal, újraindítja és értesíti Marveen-t az új URL-ről.

DASH_DIR="/home/userzoltan/marveen/agents/engineer/projects/gibraltar-igaming-dashboard"
TUNNEL_LOG="/tmp/cloudflared-tunnel.log"
TOKEN_FILE="/home/userzoltan/marveen/store/.dashboard-token"
NOTIFY="/home/userzoltan/marveen/scripts/notify.sh"
LAST_URL_FILE="/tmp/cf-last-url"

log() {
  echo "$(date '+%H:%M:%S') [tunnel-wd] $*"
}

get_current_url() {
  grep -o 'https://[a-z0-9-]*.trycloudflare.com' "$TUNNEL_LOG" 2>/dev/null | tail -1
}

notify_marveen() {
  local msg="$1"
  local TOKEN
  TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null)
  curl -s -X POST http://localhost:3420/api/messages \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "{\"from\":\"engineer\",\"to\":\"marveen\",\"content\":\"${msg}\"}" > /dev/null
}

while true; do
  # 1. HTTP server ellenőrzés
  if ! ss -tlnp 2>/dev/null | grep -q ':8765'; then
    log "HTTP server meghalt -- ujrainditom"
    cd "$DASH_DIR" && python3 -m http.server 8765 &>/tmp/dashboard-http.log &
    sleep 3
  fi

  # 2. cloudflared process ellenőrzés
  if ! pgrep -f "cloudflared tunnel --url" > /dev/null 2>&1; then
    log "cloudflared megalt -- ujrainditom"
    > "$TUNNEL_LOG"
    cloudflared tunnel --url http://localhost:8765 --no-autoupdate \
      >> "$TUNNEL_LOG" 2>&1 &
    sleep 10

    NEW_URL=$(get_current_url)
    if [ -n "$NEW_URL" ]; then
      log "Uj tunnel URL: $NEW_URL"
      notify_marveen "Gibraltar Dashboard uj URL (tunnel ujraindult): ${NEW_URL}"
      echo "$NEW_URL" > "$LAST_URL_FILE"
    else
      log "URL meg nem jelent meg -- varok tovabb"
    fi
  fi

  sleep 30
done
