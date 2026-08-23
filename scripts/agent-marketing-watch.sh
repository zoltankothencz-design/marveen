#!/bin/bash
# Live observation for the recurring ~10:32 agent-marketing tmux session
# disappearance (see memory project_boot_compact_bak_cleanup_delegation).
# Polls every 5s for ~13 minutes and logs session state + watchdog.log deltas
# so the exact moment/cause of disappearance can be pinpointed afterwards.
set -u
OUT="/home/userzoltan/marveen/store/marketing-watch-$(date +%F).log"
WD="/home/userzoltan/marveen/store/watchdog.log"
: > "$OUT"
END=$(( $(date +%s) + 780 ))
LAST_WD_LINE=$(wc -l < "$WD" 2>/dev/null || echo 0)

while [ "$(date +%s)" -lt "$END" ]; do
  TS=$(date +%H:%M:%S)
  if tmux has-session -t agent-marketing 2>/dev/null; then
    echo "=== $TS session_alive=yes ===" >> "$OUT"
    tmux capture-pane -t agent-marketing -p 2>/dev/null | tail -3 >> "$OUT"
  else
    echo "=== $TS session_alive=NO ===" >> "$OUT"
  fi
  ps -eo pid,ppid,etimes,cmd | grep -i "[m]arketing" >> "$OUT" 2>/dev/null
  NEW_LINES=$(wc -l < "$WD" 2>/dev/null || echo 0)
  if [ "$NEW_LINES" -gt "$LAST_WD_LINE" ]; then
    tail -n +"$((LAST_WD_LINE + 1))" "$WD" | grep -i marketing >> "$OUT"
    LAST_WD_LINE=$NEW_LINES
  fi
  sleep 5
done
echo "=== MONITOR DONE $(date +%H:%M:%S) ===" >> "$OUT"
