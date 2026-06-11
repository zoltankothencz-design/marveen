#!/bin/bash
# job-scan-enforcer.sh
# OS-szintű kényszer-trigger: garantálja hogy a napi job scan lefusson.
# Cron futtatja (11:05, 11:45), session-független.

INSTALL_DIR="/home/userzoltan/marveen"
LOCK_FILE="/tmp/job-scan-$(date +%Y-%m-%d).done"
LOG="/home/userzoltan/marveen/store/job-scan-enforcer.log"
NOTIFY="bash $INSTALL_DIR/scripts/notify.sh"
JOB_SESSION="agent-job-hunter"
TOKEN=$(cat "$INSTALL_DIR/store/.dashboard-token" 2>/dev/null)

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG"; }

log "=== job-scan-enforcer fut ==="

# 1. Lockfile check -- ha már triggereltük ma, nem csináljuk újra
if [ -f "$LOCK_FILE" ]; then
    log "Lockfile megvan ($LOCK_FILE) -- scan már elindult ma. Kilépés."
    exit 0
fi

# 2. Ellenőrizd a napi logot is (ha a scan már lefutott és maga írta a logot)
if [ -n "$TOKEN" ]; then
    TODAY=$(date +%Y-%m-%d)
    LOG_CHECK=$(curl -s "http://localhost:3420/api/daily-log?agent_id=job-hunter&limit=10" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null)
    if echo "$LOG_CHECK" | grep -q "$TODAY"; then
        log "Daily log tartalmaz mai job-hunter bejegyzést -- scan lefutott. Kilépés."
        touch "$LOCK_FILE"
        exit 0
    fi
fi

log "Scan nem futott ma -- kényszerindítás"

# 3. Job-hunter session ellenőrzés + automatikus újraindítás
if ! tmux has-session -t "$JOB_SESSION" 2>/dev/null; then
    log "HIBA: $JOB_SESSION session nem fut -- automatikus újraindítás"
    bash "$INSTALL_DIR/scripts/start-job-hunter.sh" >> "$LOG" 2>&1
    sleep 20
    if ! tmux has-session -t "$JOB_SESSION" 2>/dev/null; then
        log "ÚJRAINDÍTÁS SIKERTELEN"
        $NOTIFY "JOB SCAN ENFORCER: agent-job-hunter újraindítás SIKERTELEN. Manuális beavatkozás kell."
        exit 1
    fi
    log "Session újraindult -- várakozás 10s"
    sleep 10
fi

# 3b. Resume prompt feloldás
PANE=$(tmux capture-pane -t "$JOB_SESSION" -p -S -15 2>/dev/null)
if echo "$PANE" | grep -qE "Resume from summary|Resume full session"; then
    log "RESUME PROMPT detektálva -- feloldás (option 1)"
    tmux send-keys -t "$JOB_SESSION" "1" Enter
    sleep 5
fi

# 3c. Ha már aktív (11:00-s schedule runner már triggerelt) -- kihagyás
PANE2=$(tmux capture-pane -t "$JOB_SESSION" -p -S -5 2>/dev/null)
if echo "$PANE2" | grep -qE "Baked for|Cooked for|esc to interrupt"; then
    log "Agent már aktív (dashboard schedule lefutott) -- lockfile és kilépés"
    touch "$LOCK_FILE"
    exit 0
fi

# 4. Scan parancs küldése a job-hunter sessionbe
SCAN_CMD="Napi álláskeresési scan futtatása. Menj végig az összes konfigurált portálon (profession.hu, linkedin, gamblingcareers.com és a többi konfigurált portal), gyűjtsd össze a releváns találatokat, készítsd el a CV-ket, és küldd az eredményt notify.sh-val Telegramon."

tmux send-keys -t "$JOB_SESSION" "$SCAN_CMD" Enter
log "Scan parancs elküldve a $JOB_SESSION sessionbe"

# 5. Lockfile létrehozása -- nem triggerelünk kétszer
touch "$LOCK_FILE"
log "Lockfile létrehozva: $LOCK_FILE"

# 6. Marveen értesítés (nem Telegram -- csak log)
log "=== job-scan-enforcer kész ==="
