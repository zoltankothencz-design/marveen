#!/bin/bash
# A Claude-alapu sessionok ujrainditasa (pl. kezi /login utan, amikor a futo
# sessionok meg a regi tokent tartjak memoriaban). A tmux szervert NEM bantja,
# a dashboard, watchdog, tg-bridge es keepalive session fut tovabb.
#
# Ujrainditas ELOTT: minden futo agent-*/marveen-channels sessionnek mentesi
# kerest kuld (felkesz munka, nyitott feladat, dontesek -> memoria), megvarja
# amig tetlen lesz (max SAVE_WAIT mp), csak utana kill + start.
#
# Hasznalat:
#   bash ~/marveen/scripts/restart-claude-sessions.sh           # mentes + varakozas + restart
#   bash ~/marveen/scripts/restart-claude-sessions.sh --check   # csak allapot: busy/idle, nem nyul semmihez
#   bash ~/marveen/scripts/restart-claude-sessions.sh --force   # mentesi kerp es varakozas nelkul (regi viselkedes)
export PATH=$HOME/.npm-global/bin:$PATH
LOG="$HOME/marveen/store/restart-claude-sessions.log"
SAVE_WAIT=180
SAVE_SESSIONS="marveen-channels agent-job-hunter agent-marketing agent-engineer agent-tester agent-igaming agent-sesa"
KILL_SESSIONS="marveen-channels marveen-dashboard-chat agent-job-hunter agent-marketing agent-engineer agent-tester agent-igaming agent-sesa"
MODE="${1:-}"

log() { echo "$(date -Iseconds) $*" >> "$LOG"; echo "$*"; }

# Ugyanaz az idle-felismeres, mint a watchdog-daemon.sh-ban
is_idle() {
  local pane
  pane=$(tmux capture-pane -t "$1" -p 2>/dev/null) || return 0   # nincs session: nincs mit varni
  echo "$pane" | grep -qP '\(\d+m \d+s|\(\d+s ·' && return 1
  echo "$pane" | grep -qE "bypass permissions on|\? for shortcuts" || return 1
  echo "$pane" | tail -10 | grep -q "esc to interrupt" && return 1
  return 0
}

busy_list() {
  local out="" s
  for s in $SAVE_SESSIONS; do
    tmux has-session -t "=$s" 2>/dev/null || continue
    is_idle "$s" || out="$out $s"
  done
  echo "$out"
}

if [ "$MODE" = "--check" ]; then
  for s in $SAVE_SESSIONS; do
    tmux has-session -t "=$s" 2>/dev/null || { echo "$s: nem fut"; continue; }
    is_idle "$s" && echo "$s: tetlen" || echo "$s: DOLGOZIK"
  done
  exit 0
fi

SAVE_MSG="RENDSZER: a Claude sessionok par percen belul ujraindulnak. Most azonnal mentsd a memoriaba (a megfelelo memory fajlba) a felkesz munkat, a nyitott feladatokat es a fontos, meg nem mentett donteseket, es ird le, mit kell a restart utan folytatni. Ha nincs mit menteni, ird: NINCS MENTENIVALO. Uj munkat ne kezdj."

if [ "$MODE" != "--force" ]; then
  log "RESTART: mentesi kerelem kuldese"
  for s in $SAVE_SESSIONS; do
    tmux has-session -t "=$s" 2>/dev/null || continue
    tmux send-keys -t "$s" -l "$SAVE_MSG"
    sleep 1
    tmux send-keys -t "$s" Enter
  done
  sleep 20   # hagyd, hogy a sessionok felvegyek a kerest (busy-ra valtsanak)
  waited=20
  while [ "$waited" -lt "$SAVE_WAIT" ]; do
    b=$(busy_list)
    [ -z "$b" ] && break
    sleep 5; waited=$((waited + 5))
  done
  b=$(busy_list)
  if [ -n "$b" ]; then
    log "FIGYELEM: ${SAVE_WAIT}s utan meg dolgozik:$b -- restart ennek ellenere folytatodik"
  else
    log "Minden session tetlen ${waited}s utan, mentes kesz"
  fi
fi

for s in $KILL_SESSIONS; do
  tmux kill-session -t "$s" 2>/dev/null && echo "killed $s"
done
sleep 2
bash $HOME/marveen/scripts/start-sessions.sh
sleep 45
tmux ls
echo =====
for s in marveen-channels agent-job-hunter marveen-dashboard-chat; do
  echo "--- $s"; tmux capture-pane -p -t "$s" | grep -v '^\s*$' | tail -6
done
log "RESTART kesz"
