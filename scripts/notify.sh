#!/bin/bash
# ClaudeClaw - Ertesites kuldes Telegram-ra + dashboard chat napló
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then echo 'Hiba: .env nincs'; exit 1; fi
TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
CHAT_ID=$(grep '^ALLOWED_CHAT_ID=' "$ENV_FILE" | cut -d= -f2-)
[ -z "$TOKEN" ] && { echo 'TOKEN hianyzik'; exit 1; }
[ -z "$CHAT_ID" ] && { echo 'CHAT_ID hianyzik'; exit 1; }

# Uzenet: argumentumbol VAGY stdin-bol (hosszu szoveghez)
if [ -n "$1" ]; then
  MESSAGE="$1"
else
  MESSAGE=$(cat)
fi
[ -z "$MESSAGE" ] && { echo 'Hasznalat: $0 "uzenet"  VAGY  echo "uzenet" | $0'; exit 1; }

# Optional inline keyboard buttons: $2 = reply_markup JSON (pl. {"inline_keyboard":[[...]]})
BUTTONS="$2"

if [ -n "$BUTTONS" ]; then
  # Gombok eseten egyszeru JSON POST (approval card, rovid szoveg, nincs chunking)
  TEXT_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$MESSAGE")
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${CHAT_ID}\",\"text\":${TEXT_JSON},\"reply_markup\":${BUTTONS}}" > /dev/null
else
  # Telegram: 4096 char limit per uzenet, hosszabb szoveg darabolva
  MAX=4000
  LENGTH=${#MESSAGE}
  OFFSET=0
  while [ $OFFSET -lt $LENGTH ]; do
    CHUNK="${MESSAGE:$OFFSET:$MAX}"
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
      --data-urlencode "text=${CHUNK}" \
      -d "chat_id=${CHAT_ID}" \
      -d "parse_mode=" > /dev/null
    OFFSET=$((OFFSET + MAX))
  done
fi

# Dashboard chat log -- newline-ok escaped-kent tarolva (\n literal),
# kulonben a tobbsoros uzenet soronkent irodik es a parser csak az elso sort olvassa.
ESCAPED=$(printf '%s' "$MESSAGE" | sed 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
printf '%s|%s\n' "$(date +%s)" "$ESCAPED" >> /home/userzoltan/marveen/store/notify.log

echo 'Ertesites elkuldve.'
