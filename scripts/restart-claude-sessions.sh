#!/bin/bash
# A Claude-alapu sessionok ujrainditasa (pl. kezi /login utan, amikor a futo
# sessionok meg a regi tokent tartjak memoriaban). A tmux szervert NEM bantja,
# a dashboard, watchdog, tg-bridge es keepalive session fut tovabb.
# Hasznalat: bash ~/marveen/scripts/restart-claude-sessions.sh
export PATH=$HOME/.npm-global/bin:$PATH
for s in marveen-channels marveen-dashboard-chat agent-job-hunter agent-marketing agent-engineer agent-tester agent-igaming agent-sesa; do
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
