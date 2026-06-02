#!/usr/bin/env python3
"""
tg-bridge.py -- Telegram <-> Marveen hid
Tmux inject + notify.sh log polling + session restart context injection
"""
import json, os, subprocess, sys, tempfile, time, urllib.request, urllib.parse

TOKEN      = open('/home/userzoltan/marveen/.env').read().split('TELEGRAM_BOT_TOKEN=')[1].split()[0]
ALLOWED    = '7397490330'
OFFSET     = '/home/userzoltan/marveen/store/tg-bridge-offset'
LOG        = '/home/userzoltan/marveen/store/tg-bridge.log'
LOG_NOTIFY = '/home/userzoltan/marveen/store/notify.log'
INSTALL    = '/home/userzoltan/marveen'
TMUX       = '/usr/bin/tmux'
HISTORY_FILE         = '/home/userzoltan/marveen/store/conversation-history.json'
SESSION_CREATED_FILE = '/home/userzoltan/marveen/store/tg-bridge-session-ts'

def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    open(LOG, 'a').write(line + '\n')

def tg_get(method, **params):
    qs = '&'.join(f'{k}={urllib.parse.quote(str(v))}' for k, v in params.items())
    url = f'https://api.telegram.org/bot{TOKEN}/{method}?{qs}'
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read())

WHISPER_PYTHON = '/home/userzoltan/.whisper-venv/bin/python3'
STT_SCRIPT    = '/home/userzoltan/marveen/scripts/stt.py'

def transcribe_voice(file_id):
    """Telegram hanguzenet letoltese es helyi Whisper atirasa."""
    ogg_path = None
    wav_path = None
    try:
        info = tg_get('getFile', file_id=file_id)
        file_path = info['result']['file_path']
        dl_url = f'https://api.telegram.org/file/bot{TOKEN}/{file_path}'
        with tempfile.NamedTemporaryFile(suffix='.ogg', delete=False, dir='/tmp') as f:
            ogg_path = f.name
        urllib.request.urlretrieve(dl_url, ogg_path)
        wav_path = ogg_path.replace('.ogg', '.wav')
        subprocess.run(
            ['ffmpeg', '-i', ogg_path, '-ar', '16000', '-ac', '1', wav_path, '-y', '-loglevel', 'error'],
            check=True, timeout=60
        )
        result = subprocess.run(
            [WHISPER_PYTHON, STT_SCRIPT, wav_path],
            capture_output=True, text=True, timeout=180
        )
        if result.returncode != 0:
            log(f'STT HIBA: {result.stderr.strip()}')
            return None
        text = result.stdout.strip()
        log(f'STT OK: {text[:80]}')
        return text if text else None
    except Exception as e:
        log(f'STT KIVETEL: {e}')
        return None
    finally:
        for p in [ogg_path, wav_path]:
            if p:
                try:
                    os.unlink(p)
                except Exception:
                    pass

# --- Conversation history & restart context ---

def save_to_history(user_msg, response):
    """Elmenti a valtast a gordulo history fajlba (max 20 bejegyzes)."""
    history = []
    try:
        with open(HISTORY_FILE, encoding='utf-8') as f:
            history = json.load(f)
    except Exception:
        pass
    history.append({
        'ts': time.strftime('%Y-%m-%d %H:%M'),
        'user': user_msg[:500],
        'marveen': response[:500]
    })
    history = history[-20:]
    try:
        with open(HISTORY_FILE, 'w', encoding='utf-8') as f:
            json.dump(history, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log(f'HISTORY MENTES HIBA: {e}')

def build_restart_context():
    """Visszaadja az utolso 5 valtast kontextuskent session restart utan."""
    try:
        with open(HISTORY_FILE, encoding='utf-8') as f:
            history = json.load(f)
        if not history:
            return ''
        last = history[-5:]
        lines = [f"  [{h['ts']}] Zoltan: {h['user']}\n  Marveen: {h['marveen']}" for h in last]
        block = '[ELOZO BESZELGETES - session ujraindult, ez a kontextus folytatáshoz]\n'
        block += '\n'.join(lines)
        block += '\n[/ELOZO BESZELGETES]\n\n'
        return block
    except Exception:
        return ''

def get_session_created():
    """Visszaadja a marveen-channels tmux session letrehozasi timestampjet."""
    try:
        r = subprocess.run(
            [TMUX, 'display-message', '-t', 'marveen-channels', '-p', '#{session_created}'],
            capture_output=True, text=True, timeout=5
        )
        return r.stdout.strip() if r.returncode == 0 else ''
    except Exception:
        return ''

def check_restart_context():
    """Ha a session ujraindult az elozo uzenet ota, visszaadja a kontextust."""
    current_ts = get_session_created()
    if not current_ts:
        return ''
    stored_ts = ''
    try:
        stored_ts = open(SESSION_CREATED_FILE).read().strip()
    except Exception:
        pass
    try:
        with open(SESSION_CREATED_FILE, 'w') as f:
            f.write(current_ts)
    except Exception:
        pass
    if stored_ts and stored_ts != current_ts:
        log(f'SESSION UJRAINDULT (ts: {stored_ts} -> {current_ts}) - kontextus injektalas')
        return build_restart_context()
    return ''

# --- Fo uzenetkuldő ---

def ask_marveen(user_msg):
    session = 'marveen-channels'
    single = user_msg.replace('\n', ' ')

    # Restart detektálás: ha a session ujraindult, elozmeny injektalunk
    context_prefix = check_restart_context()
    if context_prefix:
        log('Kontextus prefix injektalva session restart utan')

    inject = (context_prefix +
              f'[TELEGRAM UZENET - Zoltan irja]: {single}'
              f' [FONTOS: a teljes valaszodat kizarolag a notify.sh-val kuld:'
              f' bash /home/userzoltan/marveen/scripts/notify.sh "valasz".'
              f' NE hasznalj mas csatornat.]')

    log_before = 0
    try:
        log_before = os.path.getsize(LOG_NOTIFY)
    except Exception:
        pass

    subprocess.run([TMUX, 'send-keys', '-t', session, '-l', inject], timeout=10)
    time.sleep(0.7)
    subprocess.run([TMUX, 'send-keys', '-t', session, 'Enter'], timeout=5)

    # Varakozas Marveen valaszara (max 90 masodperc)
    for _ in range(45):
        time.sleep(2)
        try:
            size = os.path.getsize(LOG_NOTIFY)
            if size > log_before:
                with open(LOG_NOTIFY) as f:
                    lines = f.readlines()
                last = lines[-1].strip() if lines else ''
                if '|' in last:
                    reply = last.split('|', 1)[1]
                    save_to_history(user_msg, reply)
                    return reply
        except Exception:
            pass
    return 'Nincs valasz 90 masodpercen belul.'

def main():
    if not os.path.exists(OFFSET):
        try:
            d = tg_get('getUpdates', limit=1, offset=-1)
            updates = d.get('result', [])
            off = updates[-1]['update_id'] + 1 if updates else 0
        except Exception:
            off = 0
        open(OFFSET, 'w').write(str(off))
        log(f'Start offset: {off}')

    # Session timestamp inicializalas induласkor
    current_ts = get_session_created()
    if current_ts:
        try:
            with open(SESSION_CREATED_FILE, 'w') as f:
                f.write(current_ts)
        except Exception:
            pass

    log('=== TG-BRIDGE INDUL ===')

    while True:
        try:
            off = int(open(OFFSET).read().strip())
            d = tg_get('getUpdates', offset=off, limit=5, timeout=0)
            for u in d.get('result', []):
                uid = u['update_id']
                open(OFFSET, 'w').write(str(uid + 1))

                msg  = u.get('message', {})
                chat = str(msg.get('chat', {}).get('id', ''))
                text = msg.get('text', '').strip()
                voice = msg.get('voice') or msg.get('audio')
                user = msg.get('from', {}).get('first_name', 'User')

                if voice and chat == ALLOWED:
                    log(f'HANG: {user} hanguzenet ({voice.get("duration", "?")}s)')
                    transcribed = transcribe_voice(voice['file_id'])
                    if transcribed:
                        text = transcribed
                        log(f'HANG->SZOVEG: {text[:80]}')
                    else:
                        log('HANG: atiras sikertelen, kihagyva')
                        continue

                if not text or chat != ALLOWED:
                    continue

                log(f'IN: {user}: {text[:60]}')
                reply = ask_marveen(text)
                log(f'OUT: {reply[:80]}')
        except KeyboardInterrupt:
            break
        except Exception as e:
            log(f'ERR: {e}')

        time.sleep(5)

main()
