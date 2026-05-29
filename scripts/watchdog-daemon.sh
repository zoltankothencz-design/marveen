#!/bin/bash
# marveen-telegram-watchdog-daemon.sh
# Dedikalt tmux sessionben fut, 15 masodpercenkent ellenorzi a channels sessiont.
# Mintatazat alapu detektas: MINDEN stuck allapotot elfog (szo lista nelkul).
# Inditas: bash scripts/watchdog-daemon.sh  (a start-watchdog-daemon.sh hivja)

INSTALL_DIR="/home/userzoltan/marveen"
SESSION="marveen-channels"
STUCK_TIMEOUT=60      # masodperc elott stuck -> Ctrl-C
RESTART_TIMEOUT=90    # masodperc elott stuck -> RESTART (Ctrl-C utan)
COOLDOWN=90           # minimum ido ket ujrainditas kozott
CHECK_INTERVAL=15     # ellenorzesi intervallum masodpercben
LOG="/tmp/marveen-watchdog-daemon.log"
STUCK_FILE="/tmp/mcd-stuck-start"
LAST_RESTART="/tmp/mcd-last-restart"

log() {
  local msg="$(date -Iseconds) $*"
  echo "$msg" >> "$LOG"
  echo "$msg"  # stdout -> tmux pane-ben is latszik
}

can_restart() {
  local NOW
  NOW=$(date +%s)
  if [ -f "$LAST_RESTART" ]; then
    local LAST
    LAST=$(cat "$LAST_RESTART")
    local ELAPSED=$(( NOW - LAST ))
    if [ "$ELAPSED" -lt "$COOLDOWN" ]; then
      log "DAEMON: cooldown ($ELAPSED/${COOLDOWN}s) -- skip restart"
      return 1
    fi
  fi
  return 0
}

restart_channels() {
  if ! can_restart; then return; fi
  date +%s > "$LAST_RESTART"
  rm -f "$STUCK_FILE"
  log "DAEMON: === RESTART: kill session + bun cleanup ==="
  tmux kill-session -t "$SESSION" 2>/dev/null
  sleep 1
  pkill -f 'bun server.ts' 2>/dev/null
  pkill -f 'bun run.*telegram' 2>/dev/null
  pkill -f 'bun.*server' 2>/dev/null
  sleep 2
  cd "$INSTALL_DIR" && nohup bash scripts/channels.sh >> "$LOG" 2>&1 &
  log "DAEMON: channels.sh elindult (hatter)"
}

log "=== WATCHDOG DAEMON INDUL (interval=${CHECK_INTERVAL}s, stuck_timeout=${STUCK_TIMEOUT}s) ==="

ITER=0
while true; do
  sleep "$CHECK_INTERVAL"
  ITER=$(( ITER + 1 ))
  # Minden 20. iteracio = kb 5 percenkent ALIVE log
  if [ $(( ITER % 20 )) -eq 0 ]; then
    log "DAEMON: ALIVE iter=$ITER, channels=$(tmux has-session -t $SESSION 2>/dev/null && echo OK || echo DEAD)"
  fi

  # 1. Session halott?
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "DAEMON: '$SESSION' session nem letezik -- restart"
    restart_channels
    sleep 20
    continue
  fi

  PANE=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)

  # 2. Stuck allapot: mintazat "[SzO]ing... (Xs)" vagy "[Szo]ed for Xs"
  #    Ez megfog MINDEN gondolkodo szot (Calculating, Flummoxing, Contemplating, stb.)
  # Timer minta: '(Xm Ys)' vagy '(Xs · ...)' - csak aktiv feldolgozas kozben jelenik meg
  STUCK_LINE=$(echo "$PANE" | grep -oP '\(\d+m \d+s[^)]*\)|\(\d+s ·[^)]*\)|\(\d+m[^)]+\)' | head -1)

  if [ -n "$STUCK_LINE" ]; then
    NOW=$(date +%s)
    if [ ! -f "$STUCK_FILE" ]; then
      echo "$NOW" > "$STUCK_FILE"
      log "DAEMON: stuck eszlelve: '$STUCK_LINE'"
    else
      START=$(cat "$STUCK_FILE")
      ELAPSED=$(( NOW - START ))
      if [ "$ELAPSED" -ge "$RESTART_TIMEOUT" ]; then
        log "DAEMON: stuck ${ELAPSED}s ($STUCK_LINE) -- RESTART"
        restart_channels
      elif [ "$ELAPSED" -ge "$STUCK_TIMEOUT" ]; then
        log "DAEMON: stuck ${ELAPSED}s ($STUCK_LINE) -- Ctrl-C"
        tmux send-keys -t "$SESSION" C-c
        sleep 3
        PANE2=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null)
        NEW_STUCK=$(echo "$PANE2" | grep -oP '\(\d+m \d+s[^)]*\)|\(\d+s ·[^)]*\)|\(\d+m[^)]+\)' | head -1)
        if [ -n "$NEW_STUCK" ]; then
          log "DAEMON: meg stuck Ctrl-C utan ($NEW_STUCK) -- RESTART"
          restart_channels
        else
          log "DAEMON: Ctrl-C utan feloldva"
          rm -f "$STUCK_FILE"
        fi
      fi
    fi

  # 3. "Interrupted" allapot
  elif echo "$PANE" | tail -15 | grep -q "Interrupted"; then
    log "DAEMON: Interrupted -- Enter kuldese"
    tmux send-keys -t "$SESSION" "" Enter
    sleep 6
    if tmux capture-pane -t "$SESSION" -p 2>/dev/null | tail -15 | grep -q "Interrupted"; then
      log "DAEMON: meg Interrupted Enter utan -- RESTART"
      restart_channels
    else
      rm -f "$STUCK_FILE"
    fi

  # 4. Model hiba
  elif echo "$PANE" | grep -q "issue with the selected model"; then
    log "DAEMON: model hiba -- RESTART"
    restart_channels

  # 5. Ures pane
  elif [ -z "$(echo "$PANE" | tr -d '[:space:]')" ]; then
    log "DAEMON: ures pane -- RESTART"
    restart_channels

  # 6. Egeszseges allapot
  else
    rm -f "$STUCK_FILE"
  fi
done
