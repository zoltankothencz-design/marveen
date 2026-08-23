#!/bin/bash
# Telegram polling daemon v4
# - Saját Telegram polling (a --channels plugin alternatívája)
# - Channel-formátumú inject a marveen-channels sessionbe

TOKEN="$(grep '^TELEGRAM_BOT_TOKEN=' /home/userzoltan/marveen/.env | cut -d= -f2-)"
SESSION="marveen-channels"
OFFSET_FILE="/tmp/tg-offset"
LOG="/tmp/tg-poller.log"
ALLOWED="7397490330"
LOCK="/tmp/tg-inject.lock"

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG"; }

is_idle() {
  local P
  P=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null | tail -5)
  echo "$P" | grep -qE '^\● |⠋|⠙|⠹|Bash\(|Read\(|Write\(' && return 1
  echo "$P" | grep -qE '\([0-9]+s|\([0-9]+m' && return 1
  return 0
}

inject() {
  local MSG="$1"
  exec 9>"$LOCK"
  flock -n 9 || { log "SKIP (locked): ${MSG:0:60}"; return; }
  local i=0
  while [ $i -lt 20 ]; do
    is_idle && break
    sleep 3; i=$((i+1))
  done
  tmux send-keys -t "$SESSION" "$MSG" 2>/dev/null
  sleep 0.3
  tmux send-keys -t "$SESSION" "" Enter 2>/dev/null
  log "INJECTED: ${MSG:0:100}"
  flock -u 9
}

log "=== TG POLLER v4 INDUL ==="

if [ ! -f "$OFFSET_FILE" ]; then
  OFF=$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates?limit=1&offset=-1" |     python3 -c "import sys,json; d=json.load(sys.stdin); us=d.get('result',[]); print(us[-1]['update_id']+1 if us else 0)" 2>/dev/null || echo 0)
  echo "${OFF}" > "$OFFSET_FILE"
  log "Start offset: $OFF"
fi

while true; do
  sleep 3
  ! tmux has-session -t "$SESSION" 2>/dev/null && sleep 10 && continue
  OFF=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)

  MSGS=$(python3 - "$TOKEN" "$OFF" "$ALLOWED" "$OFFSET_FILE" << 'PYEOF'
import sys, json, urllib.request
token, offset, allowed, offset_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
url = f"https://api.telegram.org/bot{token}/getUpdates?offset={offset}&limit=5&timeout=0"
try:
    with urllib.request.urlopen(url, timeout=8) as r:
        data = json.loads(r.read())
except:
    sys.exit(0)
for u in data.get('result', []):
    uid = u['update_id']
    msg = u.get('message', {})
    chat_id = str(msg.get('chat', {}).get('id', ''))
    text = msg.get('text', '').strip()
    user = msg.get('from', {}).get('first_name', 'User')
    ts = msg.get('date', 0)
    msg_id = msg.get('message_id', uid)
    with open(offset_file, 'w') as f:
        f.write(str(uid + 1))
    if not text or chat_id != allowed:
        continue
    channel_msg = f'<channel source="telegram" chat_id="{chat_id}" message_id="{msg_id}" user="{user}" ts="{ts}">{text}</channel>'
    safe = channel_msg.replace("'", "\'")
    print(f"MSG:{safe}", flush=True)
PYEOF
  )

  while IFS= read -r line; do
    if [[ "$line" == MSG:* ]]; then
      inject "${line#MSG:}"
    fi
  done <<< "$MSGS"
done
