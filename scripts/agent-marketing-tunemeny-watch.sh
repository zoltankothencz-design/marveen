#!/bin/bash
# Élő diagnosztika: agent-marketing tmux session ismétlődő eltűnése ~10:32-kor
# 5s-es polling, kb 12 percig fut

LOGFILE="/home/userzoltan/marveen/store/agent-marketing-tunemeny-watch-$(date +%F).log"
WATCHDOG_LOG="/home/userzoltan/marveen/store/watchdog.log"
DURATION=720  # 12 perc
INTERVAL=5

echo "=== MONITOR START $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOGFILE"

# initial watchdog.log line count baseline
LAST_LINE=$(wc -l < "$WATCHDOG_LOG" 2>/dev/null || echo 0)

END=$((SECONDS + DURATION))
PREV_ALIVE=""
while [ $SECONDS -lt $END ]; do
  TS=$(date '+%Y-%m-%d %H:%M:%S.%3N' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
  if tmux has-session -t agent-marketing 2>/dev/null; then
    ALIVE="yes"
  else
    ALIVE="NO"
  fi

  echo "[$TS] session_alive=$ALIVE" >> "$LOGFILE"

  if [ "$ALIVE" != "$PREV_ALIVE" ] && [ -n "$PREV_ALIVE" ]; then
    echo "[$TS] *** STATE CHANGE: $PREV_ALIVE -> $ALIVE ***" >> "$LOGFILE"
    echo "--- ps snapshot at change ---" >> "$LOGFILE"
    ps -eo pid,ppid,etimes,cmd 2>/dev/null | grep -i "marketing\|claude" | grep -v grep >> "$LOGFILE"
    echo "--- tmux list-sessions at change ---" >> "$LOGFILE"
    tmux list-sessions 2>&1 >> "$LOGFILE"
  fi
  PREV_ALIVE="$ALIVE"

  if [ "$ALIVE" = "yes" ]; then
    echo "--- capture-pane tail ---" >> "$LOGFILE"
    tmux capture-pane -t agent-marketing -p 2>/dev/null | tail -5 >> "$LOGFILE"
  fi

  # new watchdog.log lines since baseline
  CUR_LINE=$(wc -l < "$WATCHDOG_LOG" 2>/dev/null || echo 0)
  if [ "$CUR_LINE" -gt "$LAST_LINE" ]; then
    echo "--- NEW watchdog.log lines ---" >> "$LOGFILE"
    tail -n +$((LAST_LINE + 1)) "$WATCHDOG_LOG" | head -n $((CUR_LINE - LAST_LINE)) >> "$LOGFILE"
    LAST_LINE=$CUR_LINE
  fi

  sleep $INTERVAL
done

echo "=== MONITOR DONE $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOGFILE"
