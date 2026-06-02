#!/bin/bash
# Marveen tmux session indito (dashboard nelkul -- azt systemd kezeli)
INSTALL_DIR="/home/userzoltan/marveen"
LOG="/home/userzoltan/marveen/store/boot.log"

echo "$(date -Iseconds) [sessions] start" >> "$LOG"

tmux start-server 2>/dev/null || true
sleep 1

# Keepalive
if ! tmux has-session -t keepalive 2>/dev/null; then
    tmux new-session -d -s keepalive -x 220 -y 50
    tmux send-keys -t keepalive "while true; do sleep 30; done" Enter
    echo "$(date -Iseconds) [sessions] keepalive inditva" >> "$LOG"
fi

# Channels (Telegram + Claude Code bot)
if ! tmux has-session -t marveen-channels 2>/dev/null; then
    sleep 3
    bash "$INSTALL_DIR/scripts/channels.sh" >> "$LOG" 2>&1 &
    echo "$(date -Iseconds) [sessions] channels.sh elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] channels mar fut" >> "$LOG"
fi

# Job Hunter agent
if ! tmux has-session -t agent-job-hunter 2>/dev/null; then
    sleep 2
    bash "$INSTALL_DIR/scripts/start-job-hunter.sh" >> "$LOG" 2>&1 &
    echo "$(date -Iseconds) [sessions] job-hunter elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] job-hunter mar fut" >> "$LOG"
fi

# Marketing agent
if ! tmux has-session -t agent-marketing 2>/dev/null; then
    sleep 2
    bash "$INSTALL_DIR/scripts/start-marketing.sh" >> "$LOG" 2>&1 &
    echo "$(date -Iseconds) [sessions] marketing elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] marketing mar fut" >> "$LOG"
fi

# Optimus agent (rendszermernok / full-stack fejleszto)
if ! tmux has-session -t agent-engineer 2>/dev/null; then
    sleep 2
    bash "$INSTALL_DIR/scripts/start-optimus.sh" >> "$LOG" 2>&1 &
    echo "$(date -Iseconds) [sessions] optimus elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] optimus mar fut" >> "$LOG"
fi

# Marveen dashboard chat session (Telegram plugin NELKUL -- kulonben minden
# valasz Telegramba menne, a dashboard chat ablak nem mukodne)
if ! tmux has-session -t marveen-dashboard-chat 2>/dev/null; then
    TMUX='' tmux new-session -d -s marveen-dashboard-chat -c "$INSTALL_DIR" \
      "bash -c 'export PATH=\"\$HOME/.npm-global/bin:\$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin\"; claude --continue --dangerously-skip-permissions'"
    echo "$(date -Iseconds) [sessions] marveen-dashboard-chat elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] marveen-dashboard-chat mar fut" >> "$LOG"
fi

# Telegram bridge watchdog
if ! tmux has-session -t tg-bridge-wd 2>/dev/null; then
    tmux new-session -d -s tg-bridge-wd "bash $INSTALL_DIR/scripts/tg-bridge-watchdog.sh"
    echo "$(date -Iseconds) [sessions] tg-bridge-wd elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] tg-bridge-wd mar fut" >> "$LOG"
fi

# Watchdog daemon
if ! tmux has-session -t marveen-watchdog 2>/dev/null; then
    bash "$INSTALL_DIR/scripts/start-watchdog-daemon.sh" >> "$LOG" 2>&1
    echo "$(date -Iseconds) [sessions] watchdog elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [sessions] watchdog mar fut" >> "$LOG"
fi

echo "$(date -Iseconds) [sessions] KESZ" >> "$LOG"
