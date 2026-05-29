#!/bin/bash
# /home/userzoltan/marveen/scripts/wsl-boot.sh
# WSL indulasakor fut (root-kent, /etc/wsl.conf [boot] via).
# Elinditja a Marveen dashboard-ot es a Telegram bot-ot.

USER="userzoltan"
INSTALL_DIR="/home/userzoltan/marveen"
LOG="/tmp/marveen-boot.log"

echo "$(date -Iseconds) WSL boot: Marveen autostart..." >> "$LOG"

# Halozat stabilizalasa
sleep 4

# Marveen inditasa a user neveben
su -l "$USER" -c "bash $INSTALL_DIR/scripts/boot-as-user.sh" >> "$LOG" 2>&1 &

echo "$(date -Iseconds) WSL boot: launch done (background)" >> "$LOG"