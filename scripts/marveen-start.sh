#!/bin/bash
# marveen-start.sh -- Teljes rendszer egygombos inditas
# Biztonságos: ha valami mar fut, nem inditja ujra.

INSTALL_DIR="/home/userzoltan/marveen"
LOG="/home/userzoltan/marveen/store/boot.log"

log() { echo "$(date -Iseconds) [start] $*" | tee -a "$LOG"; }

log "=== MARVEEN INDITAS KEZDETE ==="

# 1. Tmux szerver inditas
tmux start-server 2>/dev/null || true

# 2. Dashboard -- kozvetlenul tmux sessionben, nem systemd-vel
DASH_LOG="$INSTALL_DIR/store/dashboard.log"
DASH_LOG_MAX=$((20 * 1024 * 1024))  # 20 MB
if [ -f "$DASH_LOG" ] && [ "$(stat -c%s "$DASH_LOG" 2>/dev/null || echo 0)" -gt "$DASH_LOG_MAX" ]; then
    mv "$DASH_LOG" "${DASH_LOG}.1"
    log "Dashboard log rotalt (>20MB) -> dashboard.log.1"
fi
if ! tmux has-session -t marveen-dashboard 2>/dev/null; then
    log "Dashboard inditas (node)..."
    tmux new-session -d -s marveen-dashboard -c "$INSTALL_DIR" \
        "WEB_HOST=0.0.0.0 node dist/index.js >> $DASH_LOG 2>&1"
    sleep 3
    log "Dashboard session elindult"
else
    log "Dashboard mar fut"
fi

# 3. Osszes agent + watchdog + tg-bridge
log "Sessions inditas..."
bash "$INSTALL_DIR/scripts/start-sessions.sh"

log "=== MARVEEN INDITAS KESZ ==="
