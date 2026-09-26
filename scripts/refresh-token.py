#!/usr/bin/env python3
"""
Claude Code OAuth token auto-refresh.
Megújítja az access_token-t a refresh_token segítségével,
ha az lejárt vagy 30 percen belül lejár.

Exit kódok:
  0 -- token még érvényes (nem kellett refreshelni)
  1 -- hiba (refresh sikertelen, Telegram alert szükséges)
  2 -- token sikeresen megújítva (marveen-channels restart szükséges)
"""
import json, sys, time, urllib.request, urllib.error, os, shutil, subprocess

CREDS_FILE  = os.path.expanduser("~/.claude/.credentials.json")
TOKEN_ENDPOINT = "https://platform.claude.com/v1/oauth/token"
CLIENT_ID   = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
REFRESH_MARGIN_S = 1800  # 30 perc
# A refresh tokennek kemeny lejarata van (refreshTokenExpiresAt). Utana csak kezi /login segit,
# es a Claude Code az invalid_grant-nal kiuresiti a credentials fajlt. Ezert elore szolunk.
RT_WARN_S = 3 * 86400
RT_WARN_STAMP = os.path.expanduser("~/marveen/store/refresh-token-expiry-warned")
NOTIFY_SH = os.path.expanduser("~/marveen/scripts/notify.sh")


def log(msg):
    ts = time.strftime("%Y-%m-%dT%H:%M:%S")
    print(f"{ts} [token-refresh] {msg}", flush=True)


def load_creds():
    with open(CREDS_FILE) as f:
        return json.load(f)


def save_creds(data):
    tmp = CREDS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    shutil.move(tmp, CREDS_FILE)


def warn_refresh_token_expiry(oauth: dict):
    rt_exp_ms = oauth.get("refreshTokenExpiresAt")
    if not isinstance(rt_exp_ms, (int, float)) or not oauth.get("refreshToken"):
        return
    left = rt_exp_ms / 1000 - time.time()
    if left <= 0 or left > RT_WARN_S:
        return
    today = time.strftime("%Y-%m-%d")
    try:
        if open(RT_WARN_STAMP).read().strip() == today:
            return
    except OSError:
        pass
    when = time.strftime("%m-%d %H:%M", time.localtime(rt_exp_ms / 1000))
    log(f"FIGYELEM: refresh token lejar {when}-kor ({left/3600:.0f} ora mulva) -- kezi /login kell elotte")
    subprocess.Popen(["bash", NOTIFY_SH,
        f"⏰ MARVEEN: a Claude Code refresh token {when}-kor vegleg lejar. "
        f"Addig csinalj egy kezi /login-t a WSL-ben, kulonben minden ugynok kiesik."])
    with open(RT_WARN_STAMP, "w") as f:
        f.write(today)


def needs_refresh(oauth: dict) -> bool:
    expires_at_ms = oauth.get("expiresAt", 0)
    expires_at_s = expires_at_ms / 1000
    remaining = expires_at_s - time.time()
    if remaining < REFRESH_MARGIN_S:
        log(f"Token lejár: {remaining:.0f}s múlva (határ: {REFRESH_MARGIN_S}s) -- refresh szükséges")
        return True
    log(f"Token érvényes: {remaining:.0f}s múlva jár le -- nincs teendő")
    return False


def refresh(oauth: dict) -> dict:
    refresh_token = oauth.get("refreshToken")
    if not refresh_token:
        raise ValueError("Nincs refreshToken a credentials fájlban (a Claude Code invalid_grant miatt kiuritette) -- kezi /login kell")

    payload = json.dumps({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
    }).encode()

    req = urllib.request.Request(
        TOKEN_ENDPOINT,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "node/20.0.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def main():
    try:
        creds = load_creds()
    except Exception as e:
        log(f"HIBA: credentials nem olvasható: {e}")
        sys.exit(1)

    oauth = creds.get("claudeAiOauth", {})
    warn_refresh_token_expiry(oauth)
    if not needs_refresh(oauth):
        sys.exit(0)

    log("Refresh kísérlet...")
    try:
        result = refresh(oauth)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        log(f"HIBA: HTTP {e.code} -- {body}")
        sys.exit(1)
    except (urllib.error.URLError, OSError) as e:
        # DNS failure, timeout, connection refused -- hálózati hiba, nem auth hiba.
        # Exit 3 = network error (watchdog külön kezeli, hosszú cooldown).
        log(f"HIBA: hálózati hiba (DNS/timeout): {e}")
        sys.exit(3)
    except Exception as e:
        log(f"HIBA: {e}")
        sys.exit(1)

    if "access_token" not in result:
        log(f"HIBA: access_token hiányzik a válaszból: {result}")
        sys.exit(1)

    # Credentials frissítése
    oauth["accessToken"] = result["access_token"]
    if "refresh_token" in result:
        oauth["refreshToken"] = result["refresh_token"]
    if "expires_in" in result:
        oauth["expiresAt"] = int((time.time() + result["expires_in"]) * 1000)
    if result.get("refresh_token_expires_in"):
        oauth["refreshTokenExpiresAt"] = int((time.time() + int(result["refresh_token_expires_in"])) * 1000)

    creds["claudeAiOauth"] = oauth
    save_creds(creds)
    log("Token sikeresen megújítva")
    sys.exit(2)


if __name__ == "__main__":
    main()
