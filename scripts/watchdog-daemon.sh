#!/bin/bash
# marveen-watchdog-daemon.sh
INSTALL_DIR="/home/userzoltan/marveen"
SESSION="marveen-channels"
CHECK_INTERVAL=15
STUCK_TIMEOUT=1800
LOG="/home/userzoltan/marveen/store/watchdog.log"
STUCK_SINCE_FILE="/home/userzoltan/marveen/store/mcd-stuck-since"
STUCK_LAST_PANE_FILE="/home/userzoltan/marveen/store/mcd-stuck-last-pane"
INTERRUPTED_COOLDOWN_FILE="/home/userzoltan/marveen/store/mcd-interrupted-cd"

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG"; }

restart_channels() {
    log "RESTART: $SESSION leallitasa es ujrainditas"
    tmux kill-session -t "$SESSION" 2>/dev/null
    sleep 1
    pkill -f 'bun server.ts' 2>/dev/null; pkill -f 'bun.*telegram' 2>/dev/null
    sleep 2
    cd "$INSTALL_DIR" && nohup bash scripts/channels.sh >> "$LOG" 2>&1 &
    rm -f "$STUCK_SINCE_FILE" "$STUCK_LAST_PANE_FILE"
    rm -f "$INTERRUPTED_COOLDOWN_FILE"
    log "RESTART: channels.sh elindult"
}

JOB_SCAN_COOLDOWN_FILE="/home/userzoltan/marveen/store/watchdog-job-scan-cd"

# Agent session watchdog -- újraindítja az agent sessionöket ha kilépnek
# Minden agenthez külön cooldown fájl, hogy ne loop-oljon
AGENT_RESTART_COOLDOWN=300  # 5 perc cooldown agent restartonként

declare -A AGENT_SCRIPTS
AGENT_SCRIPTS["agent-job-hunter"]="start-job-hunter.sh"
AGENT_SCRIPTS["agent-marketing"]="start-marketing.sh"
AGENT_SCRIPTS["agent-engineer"]="start-optimus.sh"
AGENT_SCRIPTS["agent-igaming"]="start-igaming.sh"
AGENT_SCRIPTS["agent-tester"]="start-tester.sh"

check_agent_sessions() {
    for SESSION_NAME in "${!AGENT_SCRIPTS[@]}"; do
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            continue
        fi
        # Session hiányzik -- cooldown check
        CD_FILE="/home/userzoltan/marveen/store/watchdog-agent-cd-${SESSION_NAME}"
        NOW=$(date +%s)
        LAST=0
        [ -f "$CD_FILE" ] && LAST=$(cat "$CD_FILE")
        if [ $((NOW - LAST)) -lt "$AGENT_RESTART_COOLDOWN" ]; then
            continue  # Még cooldownban van
        fi
        SCRIPT="${AGENT_SCRIPTS[$SESSION_NAME]}"
        log "AGENT HIANYZIK: $SESSION_NAME -- ujrainditas ($SCRIPT)"
        bash "$INSTALL_DIR/scripts/$SCRIPT" >> "$LOG" 2>&1 &
        echo "$NOW" > "$CD_FILE"
    done
}



COMPACT_THRESHOLD_K=150
COMPACT_COOLDOWN=600  # 10 perc cooldown /compact kozott

check_agent_tokens() {
    # Ha egy agent-* session idle es >COMPACT_THRESHOLD_K tokennél jár,
    # automatikusan /compact-ot kuldunk.
    # Csak agent-* sessionokra vonatkozik (marveen-channels-t kihagyjuk,
    # annak kulon watchdog logikaja van).
    local ALL_SESSIONS
    ALL_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^agent-") || return

    while IFS= read -r sess; do
        [ -z "$sess" ] && continue

        local pane
        pane=$(tmux capture-pane -t "$sess" -p 2>/dev/null) || continue

        # Skip ha busy: spinner/token counter latszik a pane-ben
        echo "$pane" | grep -qP '\(\d+m \d+s|\(\d+s ·' && continue

        # Skip ha nincs idle footer
        echo "$pane" | grep -qE "bypass permissions on|\? for shortcuts" || continue

        # Skip ha az utolso 10 sorban "esc to interrupt" van (valodi busy)
        echo "$pane" | tail -10 | grep -q "esc to interrupt" && continue

        # Token szam parse-olasa
        local token_k
        token_k=$(echo "$pane" | grep -oP '~\K[0-9]+(?:\.[0-9]+)?(?=k uncached)' | head -1)
        if [ -z "$token_k" ]; then
            token_k=$(echo "$pane" | grep -oP 'save \K[0-9]+(?:\.[0-9]+)?(?=k tokens)' | head -1)
        fi
        [ -z "$token_k" ] && continue

        # Kuszob ellenorzeese (float osszehasonlitas awk-kal)
        local over
        over=$(awk -v v="$token_k" -v t="$COMPACT_THRESHOLD_K" 'BEGIN{print (v+0 >= t+0) ? "1" : "0"}')
        [ "$over" != "1" ] && continue

        # Cooldown check
        local cd_file="$INSTALL_DIR/store/compact-cd-${sess}"
        local now
        now=$(date +%s)
        local last=0
        [ -f "$cd_file" ] && last=$(cat "$cd_file")
        [ $((now - last)) -lt "$COMPACT_COOLDOWN" ] && continue

        # /compact kuldese
        log "AUTO-COMPACT: $sess ${token_k}k token (>=${COMPACT_THRESHOLD_K}k, idle) -- /compact kuldese"
        tmux send-keys -t "$sess" "/compact" Enter
        echo "$now" > "$cd_file"

    done <<< "$ALL_SESSIONS"
}


GOAL_CLEAR_COOLDOWN=60   # 1 perc grace period a /clear elott
GOAL_CLEAR_DELAY=30      # 30mp varakozas hogy az agent befejezze az utolso irasokat

check_goal_achieved() {
    # Ha egy agent-* session "Goal achieved"-et mutat es idle, /clear-eljuk
    # hogy ne epuljon fel felesleges context a kovetkezo feladathoz.
    local ALL_SESSIONS
    ALL_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^agent-") || return

    while IFS= read -r sess; do
        [ -z "$sess" ] && continue

        local pane
        pane=$(tmux capture-pane -t "$sess" -p 2>/dev/null) || continue

        # Csak ha "Goal achieved" latszik a pane-ben
        echo "$pane" | grep -q "Goal achieved" || continue

        # Skip ha meg busy (dolgozik)
        echo "$pane" | grep -qP '\(\d+m \d+s|\(\d+s ·' && continue
        echo "$pane" | tail -10 | grep -q "esc to interrupt" && continue

        # Skip ha nincs idle footer
        echo "$pane" | grep -qE "bypass permissions on|\? for shortcuts" || continue

        # Cooldown: ne cleareljuk tobbszor ugyanazt a goal-t
        local cd_file="$INSTALL_DIR/store/goal-clear-cd-${sess}"
        local now
        now=$(date +%s)
        local last=0
        [ -f "$cd_file" ] && last=$(cat "$cd_file")
        [ $((now - last)) -lt "$GOAL_CLEAR_COOLDOWN" ] && continue

        # Stamp most hogy ne fusson le ketszer parhuzamosan
        echo "$now" > "$cd_file"

        log "GOAL ACHIEVED: $sess -- ${GOAL_CLEAR_DELAY}s utan /clear kuldese"
        sleep "$GOAL_CLEAR_DELAY"

        # Ellenorzes hogy meg mindig idle es Goal achieved (nem indult uj feladat)
        local pane2
        pane2=$(tmux capture-pane -t "$sess" -p 2>/dev/null) || continue
        echo "$pane2" | grep -q "Goal achieved" || { log "GOAL CLEAR ABORT: $sess -- uj feladat indult"; continue; }
        echo "$pane2" | grep -qP '\(\d+m \d+s|\(\d+s ·' && { log "GOAL CLEAR ABORT: $sess -- busy lett"; continue; }
        echo "$pane2" | tail -10 | grep -q "esc to interrupt" && { log "GOAL CLEAR ABORT: $sess -- busy lett"; continue; }

        log "GOAL CLEAR: $sess -- /clear kuldese"
        tmux send-keys -t "$sess" "/clear" Enter

    done <<< "$ALL_SESSIONS"
}

check_job_scan() {
    # Csak 11:05 és 14:00 között fut (ha a system felébredt és a cron kihagyta)
    HOUR=$(date +%H)
    MIN=$(date +%M)
    HHMM=$((HOUR * 60 + MIN))
    # 11:05 = 665, 14:00 = 840
    [ "$HHMM" -lt 665 ] || [ "$HHMM" -gt 840 ] && return

    TODAY=$(date +%Y-%m-%d)
    LOCK="/tmp/job-scan-${TODAY}.done"
    [ -f "$LOCK" ] && return

    # Cooldown: ne triggerelj 30 percnél sűrűbben
    NOW=$(date +%s)
    LAST=0
    [ -f "$JOB_SCAN_COOLDOWN_FILE" ] && LAST=$(cat "$JOB_SCAN_COOLDOWN_FILE")
    [ $((NOW - LAST)) -lt 1800 ] && return

    if ! tmux has-session -t "agent-job-hunter" 2>/dev/null; then
        log "JOB-SCAN: agent-job-hunter session nem fut, nem tudok triggerelni"
        return
    fi

    log "JOB-SCAN: watchdog kényszerindítja a napi scant (cron kihagyta)"
    tmux send-keys -t "agent-job-hunter" "Napi álláskeresési scan futtatása. Menj végig az összes konfigurált portálon (profession.hu, linkedin, gamblingcareers.com és a többi konfigurált portal), gyűjtsd össze a releváns találatokat, készítsd el a CV-ket, és küldd az eredményt notify.sh-val Telegramon." Enter
    touch "$LOCK"
    echo "$NOW" > "$JOB_SCAN_COOLDOWN_FILE"
}

log "=== WATCHDOG INDUL (interval=${CHECK_INTERVAL}s, stuck_timeout=${STUCK_TIMEOUT}s) ==="

while true; do
    sleep "$CHECK_INTERVAL"

    # 0. Job scan kényszer-check (WSL2 suspend/wakeup védelem)
    check_job_scan

    # 0b. Agent session watchdog
    check_agent_sessions

    # 0c. Auto-compact magas token-szamu idle sessionoknel
    check_agent_tokens

    # 0d. Auto-clear Goal achieved sessionoknel
    check_goal_achieved

    # 1. Session él-e?
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        log "SESSION HIANYZIK -- restart"
        restart_channels
        sleep 30
        continue
    fi

    PANE=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)

    # 2. Stuck detektálás -- timer regex
    # Csak akkor valóban STUCK, ha a pane tartalma sem változott az előző check óta.
    # Ha Marveen halad (pane változik), nem STUCK -- csak dolgozik.
    if echo "$PANE" | grep -qP '\(\d+m \d+s|\(\d+s ·'; then
        NOW=$(date +%s)
        LAST_PANE=""
        [ -f "$STUCK_LAST_PANE_FILE" ] && LAST_PANE=$(cat "$STUCK_LAST_PANE_FILE")
        PANE_HASH=$(echo "$PANE" | md5sum | cut -d' ' -f1)
        echo "$PANE_HASH" > "$STUCK_LAST_PANE_FILE"

        if [ "$LAST_PANE" != "$PANE_HASH" ]; then
            # Pane változott -- Marveen halad, counter reset
            rm -f "$STUCK_SINCE_FILE"
        else
            # Pane nem változott (valóban frozen)
            if [ ! -f "$STUCK_SINCE_FILE" ]; then
                echo "$NOW" > "$STUCK_SINCE_FILE"
                log "STUCK eszlelve (pane frozen)"
            else
                SINCE=$(cat "$STUCK_SINCE_FILE")
                ELAPSED=$((NOW - SINCE))
                if [ "$ELAPSED" -ge "$STUCK_TIMEOUT" ]; then
                    log "STUCK ${ELAPSED}s (frozen) -- Ctrl-C"
                    tmux send-keys -t "$SESSION" C-c
                    sleep 20
                    rm -f "$INTERRUPTED_COOLDOWN_FILE" "$STUCK_LAST_PANE_FILE"
                    PANE2=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)
                    if echo "$PANE2" | grep -qP '\(\d+m \d+s|\(\d+s ·'; then
                        log "MEG STUCK Ctrl-C utan -- restart"
                        restart_channels
                    else
                        log "Ctrl-C utan feloldva"
                        rm -f "$STUCK_SINCE_FILE"
                    fi
                fi
            fi
        fi
    else
        rm -f "$STUCK_SINCE_FILE" "$STUCK_LAST_PANE_FILE"
    fi

    # 3. Interrupted -- 120s cooldown, hogy ne kaszkadozzon
    if echo "$PANE" | tail -15 | grep -q "Interrupted"; then
        NOW=$(date +%s)
        LAST_INT=0
        [ -f "$INTERRUPTED_COOLDOWN_FILE" ] && LAST_INT=$(cat "$INTERRUPTED_COOLDOWN_FILE")
        if [ $((NOW - LAST_INT)) -ge 120 ]; then
            log "INTERRUPTED -- Enter kuldese"
            tmux send-keys -t "$SESSION" "" Enter
            echo "$NOW" > "$INTERRUPTED_COOLDOWN_FILE"
        fi
    fi
done
