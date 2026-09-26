#!/bin/bash
# marveen-guard.sh -- oranket cron (2026-09-16 incidens utan)
# Ha a tmux szerver/fo sessionok eltuntek (pl. pkill -f megolte a szervert),
# a watchdog sem el, igy semmi nem hozza vissza a rendszert. Ez a script igen.
# Csak akkor lep, ha a hiba 60s mulva is fennall (ne zavarja a watchdog
# sajat ujrainditasait), es nem a boot elso 5 perceben fut.

export PATH="$HOME/.npm-global/bin:$HOME/.bun/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
INSTALL_DIR="/home/userzoltan/marveen"
LOG="$INSTALL_DIR/store/guard.log"

log() { echo "$(date -Iseconds) [guard] $*" >> "$LOG"; }

exec 9>/tmp/marveen-guard.lock
flock -n 9 || exit 0

UPTIME_S=$(cut -d. -f1 /proc/uptime)
[ "$UPTIME_S" -lt 300 ] && exit 0

missing() {
    local m=""
    for s in marveen-channels marveen-watchdog tg-bridge-wd marveen-dashboard; do
        tmux has-session -t "$s" 2>/dev/null || m="$m $s"
    done
    echo "$m"
}

M1=$(missing)
[ -z "$M1" ] && exit 0

sleep 60
M2=$(missing)
[ -z "$M2" ] && { log "atmeneti hiany ($M1), 60s mulva rendben"; exit 0; }

log "HIANYZO SESSIONOK:$M2 -- marveen-start.sh inditasa"
bash "$INSTALL_DIR/scripts/marveen-start.sh" >> "$LOG" 2>&1
sleep 45
M3=$(missing)
if [ -z "$M3" ]; then
    log "helyreallitva"
    bash "$INSTALL_DIR/scripts/notify.sh" "GUARD: a Marveen sessionok hianyoztak ($M2), ujrainditottam, minden fut." >/dev/null 2>&1
else
    log "HIBA: inditas utan is hianyzik:$M3"
fi
