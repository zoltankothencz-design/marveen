#!/bin/bash
# job-scan-ensure.sh -- guarantees the daily job-hunter scan runs even after session loss
# OS cron: 5 11 * * * (11:05, after the schedule runner fires at 11:00)
# Falls back to direct tmux injection if the dashboard schedule missed it.

SESSION="agent-job-hunter"
LOG="/home/userzoltan/marveen/store/job-scan-ensure.log"
INSTALL_DIR="/home/userzoltan/marveen"
TOKEN=$(cat "$INSTALL_DIR/store/.dashboard-token")
PROMPT="Napi álláskereső scan: futtasd le a teljes napi álláskeresési feladatot (dreamjobs.hu, profession.hu, linkedin, egyéb konfigurált oldalak). Minden találatot küldj Telegramon."

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG"; }

notify_marveen() {
    curl -s -X POST http://localhost:3420/api/messages \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN" \
      -d "{\"from\":\"engineer\",\"to\":\"marveen\",\"content\":\"$1\"}" > /dev/null
}

log "=== JOB SCAN ENSURE START ==="

# 1. Session exists?
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "SESSION HIANYZIK -- ujrainditas"
    notify_marveen "job-scan-ensure: agent-job-hunter session hianyzott, ujrainditas folyamatban"
    bash "$INSTALL_DIR/scripts/start-job-hunter.sh" >> "$LOG" 2>&1
    sleep 15
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        log "SIKERTELEN UJRAINDITAS"
        notify_marveen "SURGOS: agent-job-hunter ujrainditas sikertelen, manualis beavatkozas kell"
        exit 1
    fi
    log "Session ujraindult -- varakozas 20s hogy Claude betoltson"
    sleep 20
fi

# 2. Blocked on resume prompt?
PANE=$(tmux capture-pane -t "$SESSION" -p -S -15 2>/dev/null)
if echo "$PANE" | grep -qE "Resume from summary|Resume full session"; then
    log "RESUME PROMPT -- feloldas (option 1)"
    tmux send-keys -t "$SESSION" "1" Enter
    sleep 5
fi

# 3. Check if still busy from the 11:00 schedule runner trigger
PANE2=$(tmux capture-pane -t "$SESSION" -p -S -5 2>/dev/null)
if echo "$PANE2" | grep -qE "Baked for|Cooked for|esc to interrupt"; then
    log "Agent mar dolgozik (schedule runner triggerelt) -- kihagyom"
    exit 0
fi

# 4. Inject prompt directly
log "PROMPT KULDESE"
tmux send-keys -t "$SESSION" "$PROMPT" Enter
log "=== JOB SCAN ENSURE DONE ==="
