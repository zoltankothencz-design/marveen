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

# 2b. Kozvetlen SQLite ellenorzes (az /api/daily-log uresen is visszaterhet)
RAN_TODAY=$(python3 -c "
import sqlite3, datetime
c = sqlite3.connect('/home/userzoltan/marveen/store/claudeclaw.db')
r = c.execute(\"SELECT count(*) FROM daily_logs WHERE agent_id='job-hunter' AND date(created_at,'unixepoch','localtime')=?\", (datetime.date.today().isoformat(),)).fetchone()
print(r[0])
" 2>/dev/null)
if [ "${RAN_TODAY:-0}" -gt 0 ] 2>/dev/null; then
    log "SQLite: mai job-hunter napi log megvan -- scan lefutott. Kilépés."
    touch "$LOCK_FILE"
    exit 0
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
if echo "$PANE2" | grep -q "esc to interrupt"; then
    log "Agent már aktív (dashboard schedule lefutott) -- lockfile és kilépés"
    touch "$LOCK_FILE"
    exit 0
fi

# 4. Scan parancs küldése a job-hunter sessionbe
SCAN_CMD="Napi álláskeresési scan futtatása. Menj végig az összes konfigurált portálon (profession.hu, linkedin, gamblingcareers.com és a többi konfigurált portal), gyűjtsd össze a releváns találatokat, készítsd el a CV-ket, és küldd az eredményt notify.sh-val Telegramon."

# Kuldes igazolt indulassal (literal szoveg, kulon Enter, beragadt input uritese).
# Lockfile CSAK akkor jon letre, ha a scan tenyleg elindult.
bash "$INSTALL_DIR/scripts/tmux-send-verified.sh" "$JOB_SESSION" "$SCAN_CMD"
RC=$?
case $RC in
    0)
        log "POST-SEND OK: agent aktív állapotban van, scan elindult"
        touch "$LOCK_FILE"
        log "Lockfile létrehozva: $LOCK_FILE"
        ;;
    2)
        log "Agent már dolgozik -- nem küldtem semmit, lockfile NEM jön létre (a következő futás újra ellenőriz)"
        exit 0
        ;;
    *)
        log "POST-SEND FAIL (rc=$RC): a scan nem indult el -- lockfile NEM jön létre, a következő enforcer/watchdog újrapróbál"
        exit 1
        ;;
esac

# 6. Marveen értesítés (nem Telegram -- csak log)
log "=== job-scan-enforcer kész ==="
