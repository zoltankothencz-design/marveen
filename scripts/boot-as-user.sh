#!/bin/bash
# /home/userzoltan/marveen/scripts/boot-as-user.sh
# Userzoltan neveben fut. Elindit minden Marveen folyamatot.

INSTALL_DIR="/home/userzoltan/marveen"
LOG="/tmp/marveen-boot.log"

echo "$(date -Iseconds) [user] boot-as-user start" >> "$LOG"

# Tmux szerver inditasa (ha nem fut)
tmux start-server 2>/dev/null || true
sleep 1

# Keepalive session
if ! tmux has-session -t keepalive 2>/dev/null; then
    tmux new-session -d -s keepalive -x 220 -y 50
    tmux send-keys -t keepalive "while true; do echo keepalive >> /tmp/marveen-keepalive.log; sleep 30; done" Enter
    echo "$(date -Iseconds) [user] keepalive session inditva" >> "$LOG"
fi

# Dashboard (node) -- ha mar nem fut
if ! pgrep -f "node dist/index.js" > /dev/null; then
    if ! tmux has-session -t marveen 2>/dev/null; then
        tmux new-session -d -s marveen -x 220 -y 50
    fi
    tmux send-keys -t marveen "cd $INSTALL_DIR && node dist/index.js" Enter
    echo "$(date -Iseconds) [user] dashboard inditva" >> "$LOG"
    sleep 6
else
    echo "$(date -Iseconds) [user] dashboard mar fut" >> "$LOG"
fi

# Channels session (Claude + Telegram bot)
if ! tmux has-session -t marveen-channels 2>/dev/null; then
    bash "$INSTALL_DIR/scripts/channels.sh" >> "$LOG" 2>&1 &
    echo "$(date -Iseconds) [user] channels.sh elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [user] channels mar fut" >> "$LOG"
fi


# Job Hunter agent session
if ! tmux has-session -t agent-job-hunter 2>/dev/null; then
    bash "$INSTALL_DIR/scripts/start-job-hunter.sh" >> "$LOG" 2>&1 &
    echo "$(date -Iseconds) [user] job-hunter agent elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [user] job-hunter mar fut" >> "$LOG"
fi

# Watchdog daemon (Telegram stability)
if ! tmux has-session -t marveen-watchdog 2>/dev/null; then
    bash "$INSTALL_DIR/scripts/start-watchdog-daemon.sh" >> "$LOG" 2>&1
    echo "$(date -Iseconds) [user] watchdog daemon elindult" >> "$LOG"
else
    echo "$(date -Iseconds) [user] watchdog daemon mar fut" >> "$LOG"
fi

echo "$(date -Iseconds) [user] boot-as-user KESZ" >> "$LOG"