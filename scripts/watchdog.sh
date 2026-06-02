#!/bin/bash
# marveen-watchdog.sh — multi-state recovery
# Cron hivja percenkent. Kezeli:
#  - session halott → ujrainditas
#  - ures pane → ujrainditas
#  - "Interrupted" → Enter → ha meg mindig → ujrainditas
#  - "issue with the selected model" → ujrainditas
#  - "Calculating" >180s → Ctrl-C → ha meg mindig → ujrainditas
#  - dashboard process halott → start.sh
#  - job-hunter session halott / model error → ujrainditas

INSTALL_DIR="/home/userzoltan/marveen"
SESSION="marveen-channels"
LOG="/tmp/marveen-watchdog.log"
COOLDOWN=90  # masodperc alap cooldown ujrainditasra

log() { echo "$(date -Iseconds) $*" >> "$LOG"; }

# Cooldown helper: needs_restart <flag_suffix>
needs_restart() {
  local flag="/tmp/marveen-watchdog-${1}-last"
  local now
  now=$(date +%s)
  if [ -f "$flag" ]; then
    local last
    last=$(cat "$flag")
    if [ $(( now - last )) -lt $COOLDOWN ]; then
      return 1  # cooldownon belul, NE inditsd ujra
    fi
  fi
  echo "$now" > "$flag"
  return 0  # OK, ujraindithat
}

# channels.sh ujrainditas: bun zombik cleanup + session kill + restart
restart_channels() {
  log "WATCHDOG: restart_channels() - bun cleanup + channels.sh ujrainditas"
  tmux kill-session -t "$SESSION" 2>/dev/null
  sleep 1
  pkill -f 'bun server.ts' 2>/dev/null
  pkill -f 'bun run.*telegram' 2>/dev/null
  pkill -f 'bun.*server' 2>/dev/null
  sleep 2
  cd "$INSTALL_DIR" && bash scripts/channels.sh >> "$LOG" 2>&1 &
  log "WATCHDOG: channels.sh elindult (hatter)"
}

# ===================== CHANNELS SESSION ELLENORZESE =====================

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  # Session teljesen halott
  if needs_restart "channels"; then
    log "WATCHDOG: $SESSION session nem talalhato -- ujrainditas"
    # Dashboard ellenorzese
    if ! pgrep -f "node dist/index.js" > /dev/null; then
      log "WATCHDOG: dashboard is le van allva -- start.sh..."
      cd "$INSTALL_DIR" && bash scripts/start.sh >> "$LOG" 2>&1 &
      sleep 5
    fi
    restart_channels
  fi
else
  # Session el -- belso allapot ellenorzese
  PANE=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)

  # 1. Ures pane (Claude kilepe de session meg al)
  if [ -z "$(echo "$PANE" | tr -d '[:space:]')" ]; then
    if needs_restart "empty"; then
      log "WATCHDOG: $SESSION pane ures -- ujrainditas"
      restart_channels
    fi

  # 2. Model error
  elif echo "$PANE" | grep -q "issue with the selected model"; then
    if needs_restart "model-err"; then
      log "WATCHDOG: $SESSION model hiba -- ujrainditas"
      restart_channels
    fi

  # 3. "Interrupted" allapot
  elif echo "$PANE" | tail -10 | grep -q "Interrupted"; then
    log "WATCHDOG: $SESSION Interrupted allapot eszlelve -- Enter kuldese"
    tmux send-keys -t "$SESSION" "" Enter
    sleep 5
    PANE2=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)
    if echo "$PANE2" | tail -10 | grep -q "Interrupted"; then
      if needs_restart "interrupted"; then
        log "WATCHDOG: $SESSION meg mindig Interrupted -- ujrainditas"
        restart_channels
      fi
    else
      log "WATCHDOG: $SESSION Interrupted feloldva Enter utan"
      rm -f /tmp/marveen-watchdog-interrupted-last
    fi

  # 4. "Calculating/Slithering/..." stuck elerzes
  elif echo "$PANE" | grep -qE '(Calculating|Flummoxing|Churning|Wandering|Pondering|Thinking|Cogitating|Mulling|Churned|Slithering|Ruminating|Musing|Deliberating|Reflecting|Contemplating|Simmering|Percolating|Noodling|Meandering|Untangling|Unraveling)'; then
    CALC_FILE="/tmp/marveen-channels-calc-start"
    NOW=$(date +%s)
    if [ ! -f "$CALC_FILE" ]; then
      echo "$NOW" > "$CALC_FILE"
      log "WATCHDOG: $SESSION thinking allapot kezdete rogzitve"
    else
      CALC_START=$(cat "$CALC_FILE")
      CALC_ELAPSED=$(( NOW - CALC_START ))
      if [ "$CALC_ELAPSED" -gt 180 ]; then
        log "WATCHDOG: $SESSION thinking ${CALC_ELAPSED}s -- Ctrl-C kuldese"
        tmux send-keys -t "$SESSION" C-c
        sleep 3
        rm -f "$CALC_FILE"
        PANE3=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)
        if echo "$PANE3" | grep -qE '(Calculating|Flummoxing|Churning|Wandering|Pondering|Thinking|Cogitating|Mulling|Churned|Slithering|Ruminating|Musing|Deliberating|Reflecting|Contemplating|Simmering|Percolating|Noodling|Meandering|Untangling|Unraveling)'; then
          if needs_restart "calc-stuck"; then
            log "WATCHDOG: $SESSION meg mindig thinking Ctrl-C utan -- ujrainditas"
            restart_channels
          fi
        else
          log "WATCHDOG: $SESSION thinking feloldva Ctrl-C utan"
        fi
      fi
    fi
  else
    # Normalisan mukodik -- Calculating timer torles
    rm -f /tmp/marveen-channels-calc-start
    rm -f /tmp/marveen-watchdog-interrupted-last
  fi
fi

# ===================== DASHBOARD ELLENORZESE =====================
if ! pgrep -f "node dist/index.js" > /dev/null; then
  log "WATCHDOG: dashboard process nem fut -- start.sh..."
  cd "$INSTALL_DIR" && bash scripts/start.sh >> "$LOG" 2>&1 &
fi

# ===================== JOB-HUNTER SESSION ELLENORZESE =====================
JH_SESSION="agent-job-hunter"
JH_COOLDOWN=90

jh_needs_restart() {
  local flag="/tmp/marveen-watchdog-jh-last"
  local now
  now=$(date +%s)
  if [ -f "$flag" ]; then
    local last
    last=$(cat "$flag")
    if [ $(( now - last )) -lt $JH_COOLDOWN ]; then
      return 1
    fi
  fi
  echo "$now" > "$flag"
  return 0
}

if tmux has-session -t "$JH_SESSION" 2>/dev/null; then
  JH_PANE=$(tmux capture-pane -t "$JH_SESSION" -p 2>/dev/null)
  if echo "$JH_PANE" | grep -q "issue with the selected model"; then
    log "WATCHDOG: $JH_SESSION model hiba -- ujrainditas"
    tmux kill-session -t "$JH_SESSION" 2>/dev/null
    sleep 2
    cd "$INSTALL_DIR" && bash scripts/start-job-hunter.sh >> "$LOG" 2>&1 &
  elif echo "$JH_PANE" | grep -q "Resume from summary\|Enter to confirm · Esc to cancel"; then
    log "WATCHDOG: $JH_SESSION resume-prompt -- '1' kuldese (summary)"
    tmux send-keys -t "$JH_SESSION" "1" Enter
  fi
fi

if ! tmux has-session -t "$JH_SESSION" 2>/dev/null; then
  if jh_needs_restart; then
    log "WATCHDOG: $JH_SESSION session nem talalhato -- ujrainditas"
    cd "$INSTALL_DIR" && bash scripts/start-job-hunter.sh >> "$LOG" 2>&1 &
    log "WATCHDOG: start-job-hunter.sh elindult (hatter)"
  fi
fi

# ===================== FROZEN PROMPT DETECIO (queued msg, no submit) =====================
# Ha a pane mutat egy ❯

