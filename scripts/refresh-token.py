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
import json, sys, time, urllib.request, urllib.error, os, shutil

CREDS_FILE  = os.path.expanduser("~/.claude/.credentials.json")
TOKEN_ENDPOINT = "https://platform.claude.com/v1/oauth/token"
CLIENT_ID   = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
REFRESH_MARGIN_S = 1800  # 30 perc


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
        raise ValueError("Nincs refreshToken a credentials fájlban")

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

    creds["claudeAiOauth"] = oauth
    save_creds(creds)
    log("Token sikeresen megújítva")
    sys.exit(2)


if __name__ == "__main__":
    main()
