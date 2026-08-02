#!/bin/bash
# LinkedIn session ellenőrzés + automatikus megújítás ha lejárt
# Naponta fut cron-ból

SESSION_FILE="/home/userzoltan/marveen/store/linkedin-session.json"
LOGIN_SCRIPT="/mnt/c/temp/linkedin-login.cjs"
LOG="/tmp/linkedin-session-check.log"

echo "$(date -Iseconds) LinkedIn session ellenőrzés..." >> "$LOG"

# Session fájl megléte
if [ ! -f "$SESSION_FILE" ]; then
  echo "$(date -Iseconds) HIBA: session fájl nem létezik" >> "$LOG"
  bash /home/userzoltan/marveen/scripts/notify.sh "⚠️ LinkedIn session: fájl hiányzik. Futtasd: node C:\\temp\\linkedin-login.cjs"
  exit 1
fi

# li_at cookie kinyerése
LI_AT=$(python3 -c "
import json
d = json.load(open('$SESSION_FILE'))
for c in d['cookies']:
    if c['name'] == 'li_at':
        print(c['value'])
        break
" 2>/dev/null)

if [ -z "$LI_AT" ]; then
  echo "$(date -Iseconds) HIBA: li_at cookie hiányzik" >> "$LOG"
  bash /home/userzoltan/marveen/scripts/notify.sh "⚠️ LinkedIn session lejárt: li_at cookie hiányzik. Futtasd: node C:\\temp\\linkedin-login.cjs"
  exit 1
fi

# LinkedIn elérhetőség ellenőrzése a session cookie-val
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Cookie: li_at=$LI_AT" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  --max-time 15 \
  "https://www.linkedin.com/feed/" 2>/dev/null)

echo "$(date -Iseconds) HTTP válasz: $HTTP_CODE" >> "$LOG"

if [ "$HTTP_CODE" = "200" ]; then
  echo "$(date -Iseconds) Session OK" >> "$LOG"
  exit 0
else
  echo "$(date -Iseconds) Session LEJÁRT (HTTP $HTTP_CODE) - Telegram értesítés küldése" >> "$LOG"
  echo "$(date -Iseconds) Automatikus megújítás indítása..." >> "$LOG"
  bash /home/userzoltan/marveen/scripts/notify.sh "🔄 LinkedIn session lejárt – automatikus megújítás indul..."

  # Auto-login futtatása Windows oldalon
  RESULT=$(/mnt/c/Windows/System32/cmd.exe /c "node C:\\temp\\linkedin-auto-login.cjs" 2>&1)
  EXIT=$?

  if [ $EXIT -eq 0 ]; then
    echo "$(date -Iseconds) Automatikus megújítás sikeres" >> "$LOG"
    bash /home/userzoltan/marveen/scripts/notify.sh "✅ LinkedIn session sikeresen megújítva"
  else
    echo "$(date -Iseconds) Automatikus megújítás SIKERTELEN: $RESULT" >> "$LOG"
    bash /home/userzoltan/marveen/scripts/notify.sh "❌ LinkedIn session megújítás sikertelen. Kézi beavatkozás szükséges: node C:\\temp\\linkedin-login.cjs"
  fi
  exit $EXIT
fi
