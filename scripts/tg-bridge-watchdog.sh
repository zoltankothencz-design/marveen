#!/bin/bash
# Egyszerű watchdog: ha a tg-bridge meghal, újraindítja
# 10s várakozás induláskor -- elkerüli a race condition-t amikor
# a tmux szerver még nem teljesen stabil a sessions service indulása után
sleep 10
while true; do
  # Pontos névegyezés: has-session prefix-alapon keres, ezert "tg-bridge" illeszkedne
  # a "tg-bridge-wd" sessionre is. list-sessions + grep -x = pontos egyezes.
  if ! tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -qx "tg-bridge"; then
    echo "$(date -Iseconds) tg-bridge MEGHALT -- restart" >> /home/userzoltan/marveen/store/tg-bridge.log
    TMUX='' tmux new-session -d -s tg-bridge 'cd /home/userzoltan/marveen && python3 scripts/tg-bridge.py'
  fi
  sleep 30
done
