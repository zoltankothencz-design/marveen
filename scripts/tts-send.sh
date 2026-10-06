#!/bin/bash
# tts-send.sh "szoveg"  (vagy stdin-bol)
# Szoveg -> edge-tts (hu-HU-NoemiNeural, kulcs nem kell) -> ffmpeg OGG/Opus -> Telegram sendVoice Zoltan chatjebe.
# CSAK akkor hasznald, ha Zoltan kifejezetten azt kerte: "olvasd fel". Alapertelmezett valasz: szoveg.
# A tg-bridge.py-t NEM erinti. Hiba eseten nem kuld semmit, nem nulla kilepesi kodot ad: ekkor szovegben valaszolj.

D="/home/userzoltan/marveen"
ENV_FILE="$D/.env"
LOG="$D/store/tts-send.log"
PY="/home/userzoltan/.whisper-venv/bin/python3"
VOICE="hu-HU-NoemiNeural"
MAX_CHARS=3000

if [ -n "$1" ]; then TEXT="$1"; else TEXT="$(cat)"; fi
[ -z "$TEXT" ] && { echo "Hasznalat: $0 \"szoveg\""; exit 1; }

TMP="$(mktemp -d /tmp/tts.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Felolvasasra alkalmas szoveg: URL -> "link", markdown/emoji jelek ki
printf '%s' "$TEXT" | "$PY" -c '
import re, sys
t = sys.stdin.read()
t = re.sub(r"https?://\S+", "link", t)
t = re.sub(r"[*_`#>|~]+", " ", t)
t = re.sub(r"[\U0001F000-\U0001FAFF☀-➿️]", "", t)
t = re.sub(r"[ \t]+", " ", t)
t = re.sub(r"\n{2,}", "\n", t).strip()
sys.stdout.write(t)
' > "$TMP/text.txt"

LEN=$(wc -m < "$TMP/text.txt")
if [ "$LEN" -gt "$MAX_CHARS" ]; then
  echo "HIBA: a szoveg $LEN karakter, a limit $MAX_CHARS. Rovidits vagy oszd ketto fele."
  echo "$(date -Iseconds) ELUTASITVA len=$LEN" >> "$LOG"; exit 2
fi
[ "$LEN" -lt 2 ] && { echo "HIBA: ures szoveg a tisztitas utan"; exit 1; }

TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" | cut -d= -f2-)
CHAT_ID=$(grep '^ALLOWED_CHAT_ID=' "$ENV_FILE" | cut -d= -f2-)
{ [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; } && { echo "HIBA: Telegram token/chat_id hianyzik"; exit 1; }

# 1) edge-tts -> MP3
timeout 90 "$PY" -m edge_tts --voice "$VOICE" --file "$TMP/text.txt" --write-media "$TMP/out.mp3" 2> "$TMP/err.txt"
if [ $? -ne 0 ] || [ ! -s "$TMP/out.mp3" ]; then
  echo "$(date -Iseconds) EDGE-TTS HIBA len=$LEN err=$(tail -1 "$TMP/err.txt" | cut -c1-150)" >> "$LOG"
  echo "HIBA: hanggeneralas sikertelen (edge-tts). Valaszolj szovegben."; exit 3
fi

# 2) MP3 -> OGG/Opus (Telegram hanguzenet formatum)
ffmpeg -y -i "$TMP/out.mp3" -c:a libopus -b:a 32k -ar 48000 -ac 1 "$TMP/out.ogg" -loglevel error \
  || { echo "$(date -Iseconds) FFMPEG HIBA" >> "$LOG"; echo "HIBA: ffmpeg atalakitas. Valaszolj szovegben."; exit 4; }

# 3) Telegram sendVoice
RESP=$(curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendVoice" -F "chat_id=${CHAT_ID}" -F "voice=@$TMP/out.ogg")
if echo "$RESP" | grep -q '"ok":true'; then
  echo "$(date -Iseconds) OK len=$LEN voice=$VOICE" >> "$LOG"; echo "OK: hangüzenet elküldve ($LEN karakter)"
else
  echo "$(date -Iseconds) TELEGRAM HIBA len=$LEN resp=${RESP:0:150}" >> "$LOG"; echo "HIBA: Telegram sendVoice. Valaszolj szovegben."; exit 5
fi
