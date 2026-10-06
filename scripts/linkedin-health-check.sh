#!/bin/bash
# linkedin-health-check.sh
# Napi egyszer: a publikus LinkedIn jobs-guest API elerheto-e a VPS-rol (session/login NEM kell).
# Ha 2 egymas utani napon nem ad talalatot (vagy hiba), Telegram-riasztas. Visszaallaskor is szol.
# Cron: 30 10 * * *  (az 11:05-os job-scan-enforcer elott)

D="/home/userzoltan/marveen"
STATE="$D/store/linkedin-health.json"
LOG="$D/store/linkedin-health.log"
OUT="$(mktemp /tmp/li-health.XXXXXX)"
ERR="$(mktemp /tmp/li-health-err.XXXXXX)"
trap 'rm -f "$OUT" "$ERR"' EXIT

timeout 120 node "$D/scripts/linkedin-jobs-search.cjs" > "$OUT" 2> "$ERR"
RC=$?

python3 - "$RC" "$OUT" "$ERR" "$STATE" "$LOG" "$D/scripts/notify.sh" <<'PY'
import json, sys, subprocess, time, os
rc, out, err, state_f, log_f, notify = int(sys.argv[1]), *sys.argv[2:]
MIN_JOBS = 5
try:
    count = len(json.load(open(out)))
except Exception:
    count = 0
ok = rc == 0 and count >= MIN_JOBS
try:
    st = json.load(open(state_f))
except Exception:
    st = {"fail_streak": 0, "last_ok": None}
now = time.strftime("%Y-%m-%dT%H:%M:%S%z")
prev = st.get("fail_streak", 0)
if ok:
    st["fail_streak"] = 0
    st["last_ok"] = now
    msg = None
    if prev >= 2:
        msg = f"LinkedIn allaskereses ujra mukodik ({count} talalat)."
else:
    st["fail_streak"] = prev + 1
    msg = None
    if st["fail_streak"] in (2, 7):
        tail = open(err).read().strip().splitlines()[-1:] or ["nincs hibauzenet"]
        msg = (f"LinkedIn allaskereses {st['fail_streak']} napja nem ad talalatot a VPS-rol "
               f"(rc={rc}, talalat={count}). Utolso hiba: {tail[0][:120]}. Session nem kell, "
               f"valoszinuleg rate limit/blokk; a keresest kezzel a laptoprol erdemes nezni.")
st["last_run"] = now
st["last_count"] = count
json.dump(st, open(state_f, "w"))
open(log_f, "a").write(f"{now} rc={rc} count={count} ok={ok} streak={st['fail_streak']}\n")
if msg:
    subprocess.run(["bash", notify, msg])
PY
