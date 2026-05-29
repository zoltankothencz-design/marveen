#!/bin/bash
# start-watchdog-daemon.sh
# Elindítja a watchdog daemontot egy dedikált tmux sessionben.
# Ha már fut, nem csinál semmit.

INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_SESSION="marveen-watchdog"

if tmux has-session -t "$DAEMON_SESSION" 2>/dev/null; then
  echo "Watchdog daemon mar fut ($DAEMON_SESSION)"
  exit 0
fi

tmux new-session -d -s "$DAEMON_SESSION" \
  "bash $INSTALL_DIR/scripts/watchdog-daemon.sh"

echo "Watchdog daemon elindult: $DAEMON_SESSION"
