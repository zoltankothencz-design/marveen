#!/bin/bash
# marveen-watchdog-daemon.sh
INSTALL_DIR="/home/userzoltan/marveen"
SESSION="marveen-channels"
CHECK_INTERVAL=15
STUCK_TIMEOUT=900
# (boot compact state tracked via BOOT_COMPACT_CD_FILE, no session-local flag needed)
LOG="/home/userzoltan/marveen/store/watchdog.log"
STUCK_SINCE_FILE="/home/userzoltan/marveen/store/mcd-stuck-since"
STUCK_LAST_PANE_FILE="/home/userzoltan/marveen/store/mcd-stuck-last-pane"
INTERRUPTED_COOLDOWN_FILE="/home/userzoltan/marveen/store/mcd-interrupted-cd"

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG"; }

# OAuth token auto-refresh -- lejárt vagy 30 percen belül lejáró token megújítása.
# exit 0: token érvényes, nincs teendő
# exit 1: valódi auth hiba (HTTP 4xx, invalid response stb.)
# exit 2: sikeresen megújítva -- marveen-channels restart kell
# exit 3: hálózati hiba (DNS, timeout, connection refused -- WSL2 átmeneti probléma)
TOKEN_REFRESH_COOLDOWN_FILE="$INSTALL_DIR/store/token-refresh-cd"
TOKEN_REFRESH_COOLDOWN=3600  # 1 óra: valódi auth hiba esetén max 1 alert/óra

TOKEN_DNS_COOLDOWN_FILE="$INSTALL_DIR/store/token-dns-cd"
TOKEN_DNS_COOLDOWN=14400  # 4 óra: DNS/hálózati hibánál 1 alert per 4 óra, nem 1 per 5 perc

maybe_refresh_token() {
    local result
    result=$(python3 "$INSTALL_DIR/scripts/refresh-token.py" 2>&1)
    local exit_code=$?
    # exit 0: érvényes, nincs teendő
    if [ $exit_code -eq 0 ]; then
        rm -f "$TOKEN_DNS_COOLDOWN_FILE"   # DNS hiba sorozat véget ért
        return 0
    fi
    log "$result"
    # exit 2: sikeresen megújítva
    if [ $exit_code -eq 2 ]; then
        rm -f "$TOKEN_DNS_COOLDOWN_FILE"
        return 2
    fi
    # exit 3: hálózati hiba (DNS/timeout) -- WSL2-ben gyakori, ne spammelje a channelt
    # Csak az első hibánál riaszt egy sorozatban, aztán 4 óra csend.
    if [ $exit_code -eq 3 ]; then
        local NOW LAST
        NOW=$(date +%s)
        LAST=0
        [ -f "$TOKEN_DNS_COOLDOWN_FILE" ] && LAST=$(cat "$TOKEN_DNS_COOLDOWN_FILE")
        if [ $((NOW - LAST)) -ge $TOKEN_DNS_COOLDOWN ]; then
            log "TOKEN-REFRESH DNS/hálózati hiba -- Telegram értesítés (4 óra cooldown)"
            bash "$INSTALL_DIR/scripts/notify.sh" "⚠️ MARVEEN: Token refresh hálózati hiba (DNS/timeout, WSL2?). Automatikusan újra próbál." &
            echo "$NOW" > "$TOKEN_DNS_COOLDOWN_FILE"
        fi
        return 1
    fi
    # exit 1: valódi auth hiba -- 1 óra cooldown
    local NOW LAST
    NOW=$(date +%s)
    LAST=0
    [ -f "$TOKEN_REFRESH_COOLDOWN_FILE" ] && LAST=$(cat "$TOKEN_REFRESH_COOLDOWN_FILE")
    if [ $((NOW - LAST)) -ge $TOKEN_REFRESH_COOLDOWN ]; then
        log "TOKEN-REFRESH HIBA -- Telegram értesítés"
        bash "$INSTALL_DIR/scripts/notify.sh" "⚠️ MARVEEN: Claude Code OAuth token refresh SIKERTELEN. Kézi /login szükséges!" &
        echo "$NOW" > "$TOKEN_REFRESH_COOLDOWN_FILE"
    fi
    return 1
}

restart_channels() {
    log "RESTART: $SESSION leallitasa es ujrainditas"
    # Token refresh restart előtt -- ha lejárt, ne induljon el hiába
    maybe_refresh_token
    local tr=$?
    if [ $tr -eq 1 ]; then
        log "RESTART ABORT: token refresh sikertelen, nem indítjuk újra (vár következő ciklusig)"
        return
    fi
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
        # Csak gyors ismételt restart esetén értesít (10 percen belüli 2. restart)
        # Az első napi leállás (>10 perc óta nem volt restart) csendes
        ELAPSED=$((NOW - LAST))
        if [ "$ELAPSED" -lt 600 ] && [ "$LAST" -gt 0 ]; then
            bash "$INSTALL_DIR/scripts/notify.sh" "WATCHDOG: ${SESSION_NAME} gyorsan ujraindult (${ELAPSED}s) -- vizsgald meg." &
        fi
        bash "$INSTALL_DIR/scripts/$SCRIPT" >> "$LOG" 2>&1 &
        echo "$NOW" > "$CD_FILE"
    done
}



COMPACT_THRESHOLD_K=170
COMPACT_COOLDOWN=600  # 10 perc cooldown /compact kozott

check_agent_tokens() {
    # Ha egy agent-* session idle es >COMPACT_THRESHOLD_K tokennél jár,
    # automatikusan /compact-ot kuldunk.
    # agent-* es marveen-channels sessionokra vonatkozik.
    local ALL_SESSIONS
    ALL_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "^agent-|^marveen-channels$") || return

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


BOOT_COMPACT_FILE="$INSTALL_DIR/store/boot-compact-done"
BOOT_COMPACT_CD_FILE="$INSTALL_DIR/store/boot-compact-cd"
BOOT_COMPACT_RETRY_INTERVAL=3600  # 1 óra: ha nem volt idle, ennyit vár az újrapróbálás előtt

do_boot_compact() {
    # Napi auto-compact: egyszer per nap, orankenei ujraprobalkozas ha nem idle (max 23:00-ig)
    local today
    today=$(date +%Y-%m-%d)
    [ -f "$BOOT_COMPACT_FILE" ] && [ "$(cat "$BOOT_COMPACT_FILE")" = "$today" ] && return

    # 23:00 utan mar nem probalkozunk
    local hour
    hour=$(date +%-H 2>/dev/null || date +%H | awk '{printf "%d",$1}')
    [ "${hour:-0}" -ge 23 ] && return

    local pane
    pane=$(tmux capture-pane -t marveen-channels -p 2>/dev/null) || return

    # Csak idle allapotban compact-olunk
    echo "$pane" | grep -qE "bypass permissions on|\? for shortcuts" || return
    echo "$pane" | grep -qP '\(\d+m \d+s|\(\d+s ·' && return
    echo "$pane" | tail -10 | grep -q "esc to interrupt" && return

    log "BOOT-COMPACT: /compact kuldese marveen-channels-nek (napi clean start)"
    bash "$INSTALL_DIR/scripts/notify.sh" "WATCHDOG: napi /compact elindítva." &
    tmux send-keys -t marveen-channels "/compact" Enter
    echo "$today" > "$BOOT_COMPACT_FILE"
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

check_resume_dialogs() {
    # Proaktiv resume dialog detektalo: minden agent-* session-t megvizsgal.
    # Ha "Resume from summary / Resume full session" dialog latszik, Enter-t kuldunk
    # (az alapertelmezett "Resume from summary" opciora), majd 3s varunk.
    # Miert kell: ha a session 2+ napos es ujraindul, a Claude Code megjeleniti ezt
    # a dialogot. Ilyenkor a tmux send-keys parancsok bekeruulnek az input mezobe
    # de NEM FUTNAK LE -- a feladat csendben megbukik.
    local ALL_SESSIONS
    ALL_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^agent-") || return

    while IFS= read -r sess; do
        [ -z "$sess" ] && continue
        local pane
        pane=$(tmux capture-pane -t "$sess" -p 2>/dev/null) || continue
        # Ket feltetel egyszerre: "Resume" szoveg ES "Enter to confirm" footer
        # Ez az egyedi mintaja a Claude Code resume dialognak.
        # Csak "Resume" szoveg ellenorzese false positive-ot okoz (pl. ha a terminal
        # kimeneteben megjelenik a szoveg tesztelesnel vagy log outputnal).
        echo "$pane" | grep -qE "Resume from summary|Resume full session" || continue
        echo "$pane" | grep -q "Enter to confirm" || continue
        log "RESUME-DIALOG: $sess -- feloldas (Enter, option 1 alapertelmezett)"
        tmux send-keys -t "$sess" "" Enter
        sleep 3
    done <<< "$ALL_SESSIONS"
}

check_job_scan() {
    # Csak 11:05 és 14:00 között fut (ha a system felébredt és a cron kihagyta)
    # 10# prefix: elkeruli hogy bash octal-kent ertelmezze a vezeto nullas
    # ertekeket (pl. "09" ervenytelen octal -> "value too great for base" hiba)
    HOUR=$(date +%H)
    MIN=$(date +%M)
    HHMM=$((10#$HOUR * 60 + 10#$MIN))
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

    # Resume dialog feloldasa kuldes elott -- ha dialog van, a send-keys bekerul
    # az input mezobe de nem fut le. Az Enter dismiss utan 3s varakozas szukseges.
    local _pane
    _pane=$(tmux capture-pane -t "agent-job-hunter" -p 2>/dev/null)
    if echo "$_pane" | grep -qE "Resume from summary|Resume full session" && echo "$_pane" | grep -q "Enter to confirm"; then
        log "JOB-SCAN: resume-dialog van agent-job-hunterben -- feloldas elobb"
        tmux send-keys -t "agent-job-hunter" "" Enter
        sleep 3
    fi

    log "JOB-SCAN: watchdog kényszerindítja a napi scant (cron kihagyta)"
    tmux send-keys -t "agent-job-hunter" "Napi álláskeresési scan futtatása. Menj végig az összes konfigurált portálon (profession.hu, linkedin, gamblingcareers.com és a többi konfigurált portal), gyűjtsd össze a releváns találatokat, készítsd el a CV-ket, és küldd az eredményt notify.sh-val Telegramon." Enter
    touch "$LOCK"
    echo "$NOW" > "$JOB_SCAN_COOLDOWN_FILE"
}

log "=== WATCHDOG INDUL (interval=${CHECK_INTERVAL}s, stuck_timeout=${STUCK_TIMEOUT}s) ==="

while true; do
    sleep "$CHECK_INTERVAL"

    # 0. Resume dialog proaktiv feloldas -- ELOBB mint barmi mas,
    # hogy a tobbi check ne kuldjoen parancsot blokkolt sessionba
    check_resume_dialogs

    # 0x. OAuth token proaktív refresh (lejárat előtt 30 perccel, 5 perces cooldown)
    TOKEN_CHECK_CD_FILE="$INSTALL_DIR/store/token-check-cd"
    TOKEN_CHECK_INTERVAL=300  # 5 percenként ellenőriz
    _NOW=$(date +%s)
    _LAST_CHECK=0
    [ -f "$TOKEN_CHECK_CD_FILE" ] && _LAST_CHECK=$(cat "$TOKEN_CHECK_CD_FILE")
    if [ $((_NOW - _LAST_CHECK)) -ge $TOKEN_CHECK_INTERVAL ]; then
        echo "$_NOW" > "$TOKEN_CHECK_CD_FILE"
        maybe_refresh_token
        _tr=$?
        if [ $_tr -eq 2 ]; then
            # Token megújítva: marveen-channels restart kell hogy felvegye az új tokent
            log "TOKEN-REFRESH: token megujult -- marveen-channels restart"
            bash "$INSTALL_DIR/scripts/notify.sh" "🔄 MARVEEN: OAuth token megújítva, Marveen újraindul." &
            restart_channels
            sleep 30
            continue
        fi
    fi

    # 0a. Job scan kényszer-check (WSL2 suspend/wakeup védelem)
    check_job_scan

    # 0b. Agent session watchdog
    check_agent_sessions

    # Napi boot compact -- orankenei ujraprobalkozas ha nem volt idle
    if ! { [ -f "$BOOT_COMPACT_FILE" ] && [ "$(cat "$BOOT_COMPACT_FILE" 2>/dev/null)" = "$(date +%Y-%m-%d)" ]; }; then
        _NOW_BC=$(date +%s)
        _LAST_BC=0
        [ -f "$BOOT_COMPACT_CD_FILE" ] && _LAST_BC=$(cat "$BOOT_COMPACT_CD_FILE")
        if [ $((_NOW_BC - _LAST_BC)) -ge "$BOOT_COMPACT_RETRY_INTERVAL" ]; then
            echo "$_NOW_BC" > "$BOOT_COMPACT_CD_FILE"
            do_boot_compact &
        fi
    fi

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
    # Ha "esc to interrupt" látszik, Marveen aktívan dolgozik -- ne avatkozz közbe.
    if echo "$PANE" | tail -10 | grep -q "esc to interrupt"; then
        rm -f "$STUCK_SINCE_FILE" "$STUCK_LAST_PANE_FILE"
    elif echo "$PANE" | grep -qP '\(\d+m \d+s|\(\d+s ·'; then
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
