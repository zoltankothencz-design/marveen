#!/usr/bin/env python3
"""
tg-bridge.py -- Telegram <-> Marveen hid
Tmux inject + notify.sh log polling + session restart context injection
"""
import datetime, json, os, re, subprocess, sys, tempfile, time, urllib.request, urllib.parse

TOKEN      = open('/home/userzoltan/marveen/.env').read().split('TELEGRAM_BOT_TOKEN=')[1].split()[0]
ALLOWED    = '7397490330'
OFFSET     = '/home/userzoltan/marveen/store/tg-bridge-offset'
LOG        = '/home/userzoltan/marveen/store/tg-bridge.log'
LOG_NOTIFY = '/home/userzoltan/marveen/store/notify.log'
INSTALL    = '/home/userzoltan/marveen'
TMUX       = '/usr/bin/tmux'
DASH_TOKEN_FILE = '/home/userzoltan/marveen/store/.dashboard-token'
SCHED_DIR      = '/home/userzoltan/.claude/scheduled-tasks'
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

def tg_api_post(method, payload):
    """JSON POST to Telegram Bot API."""
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f'https://api.telegram.org/bot{TOKEN}/{method}',
        data=data, headers={'Content-Type': 'application/json'}, method='POST'
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())

def _dash_api(method, path, data=None):
    """Dashboard API hivas."""
    token = open(DASH_TOKEN_FILE).read().strip()
    payload = json.dumps(data).encode() if data is not None else b''
    headers = {'Content-Type': 'application/json', 'Authorization': f'Bearer {token}'}
    req = urllib.request.Request(
        f'http://localhost:3420{path}',
        data=payload if method != 'GET' else None,
        headers=headers, method=method
    )
    with urllib.request.urlopen(req, timeout=5) as r:
        return json.loads(r.read())

def _tg_confirm(chat_id, text):
    """Rovid megerosito uzenet Telegramra."""
    try:
        tg_api_post('sendMessage', {'chat_id': chat_id, 'text': text})
    except Exception as e:
        log(f'tg_confirm hiba: {e}')

def _forward_callback(cq_data, targets):
    """Callback tovabbitasa inter-agent uzenetkent."""
    try:
        for t in targets:
            _dash_api('POST', '/api/messages', {
                'from': 'tg-bridge', 'to': t,
                'content': f'[TELEGRAM CALLBACK] {cq_data}'
            })
        log(f'CALLBACK tovabbitva ({", ".join(targets)}): {cq_data}')
    except Exception as e:
        log(f'CALLBACK tovabbitas hiba: {e}')

def _kanban_done(chat, card_id):
    try:
        _dash_api('PUT', f'/api/kanban/{card_id}', {'status': 'done'})
        _tg_confirm(chat, '✅ Kész jelölve.')
        log(f'KANBAN DONE: {card_id}')
    except Exception as e:
        log(f'kanban_done hiba: {e}')
        _tg_confirm(chat, f'⚠️ Nem sikerült jelölni: {e}')

def _kanban_holnapra(chat, card_id):
    try:
        tomorrow = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
        _dash_api('PUT', f'/api/kanban/{card_id}', {'due_date': tomorrow})
        _tg_confirm(chat, f'📅 Holnapra tolva ({tomorrow}).')
        log(f'KANBAN HOLNAPRA: {card_id} -> {tomorrow}')
    except Exception as e:
        log(f'kanban_holnapra hiba: {e}')
        _tg_confirm(chat, f'⚠️ Halasztás sikertelen: {e}')

def _reminder_done(chat, sched_name):
    try:
        _dash_api('PUT', f'/api/schedules/{sched_name}', {'enabled': False})
        # Disable all snooze copies ({sched_name}-snz*)
        try:
            all_scheds = _dash_api('GET', '/api/schedules')
            prefix = sched_name + '-snz'
            for s in (all_scheds if isinstance(all_scheds, list) else []):
                name = s.get('name', '')
                if name.startswith(prefix) and s.get('enabled', False):
                    _dash_api('PUT', f'/api/schedules/{name}', {'enabled': False})
                    log(f'REMINDER DONE snz: {name}')
        except Exception as e2:
            log(f'snz disable hiba: {e2}')
        _tg_confirm(chat, '✅ Rendben, az emlékeztető le van állítva.')
        log(f'REMINDER DONE: {sched_name}')
    except Exception as e:
        log(f'reminder_done hiba: {e}')
        _tg_confirm(chat, f'⚠️ Emlékeztető leállítása sikertelen: {e}')

def _reminder_snooze(chat, sched_name):
    try:
        sched_dir = f'{SCHED_DIR}/{sched_name}'
        config = json.loads(open(f'{sched_dir}/task-config.json').read())
        skill_raw = open(f'{sched_dir}/SKILL.md').read()
        # YAML frontmatter kiszedese
        if skill_raw.startswith('---'):
            parts = skill_raw.split('---', 2)
            prompt = parts[2].strip() if len(parts) >= 3 else skill_raw.strip()
        else:
            prompt = skill_raw.strip()
        now = datetime.datetime.now()
        snooze_dt = now + datetime.timedelta(hours=1)
        cron = f'{snooze_dt.minute} {snooze_dt.hour} {snooze_dt.day} {snooze_dt.month} *'
        snooze_name = f'{sched_name[:40]}-snz{int(now.timestamp()) % 100000}'
        # One-shot: append self-disable instruction to prompt
        self_disable = (
            f'\n\nEGYSZERI EMLEKEZTETO: Miutan elkuldted az uzenetet Telegramon, '
            f'AZONNAL tiltsd le ezt a schedule-t:\n'
            f'curl -s -X PUT "http://localhost:3420/api/schedules/{snooze_name}" '
            f'-H "Content-Type: application/json" '
            f'-H "Authorization: Bearer $(cat /home/userzoltan/marveen/store/.dashboard-token)" '
            f'-d \'{{"enabled": false}}\''
        )
        _dash_api('POST', '/api/schedules', {
            'name': snooze_name,
            'description': f'Egyszeri halasztas: {sched_name}',
            'prompt': prompt + self_disable,
            'schedule': cron,
            'agent': config.get('agent', 'marveen'),
            'type': config.get('type', 'task'),
        })
        _tg_confirm(chat, f'⏳ Rendben, {snooze_dt.strftime("%H:%M")}-kor emlékeztetlek.')
        log(f'REMINDER SNOOZE: {sched_name} -> {cron} ({snooze_name})')
    except Exception as e:
        log(f'reminder_snooze hiba: {e}')
        _tg_confirm(chat, f'⚠️ Halasztás sikertelen: {e}')

def handle_callback(cq):
    """Feldolgozza a Telegram callback_query-t (inline gomb nyomas)."""
    cq_id     = cq['id']
    cq_data   = cq.get('data', '')
    cq_msg    = cq.get('message', {})
    cq_chat   = str(cq_msg.get('chat', {}).get('id', ''))
    cq_msg_id = cq_msg.get('message_id')

    if cq_chat != ALLOWED:
        return

    log(f'CALLBACK: {cq_data}')

    # 1. answerCallbackQuery azonnal (10mp-es ablak)
    try:
        tg_api_post('answerCallbackQuery', {'callback_query_id': cq_id})
    except Exception as e:
        log(f'answerCallbackQuery hiba: {e}')

    # 2. Gombok eltavolitasa (ketszeri nyomas megakadalyozasa)
    try:
        tg_api_post('editMessageReplyMarkup', {
            'chat_id': cq_chat, 'message_id': cq_msg_id,
            'reply_markup': {'inline_keyboard': []}
        })
    except Exception as e:
        log(f'editMessageReplyMarkup hiba: {e}')

    # 3. Routing: action:type:id format
    parts  = cq_data.split(':', 2)
    action = parts[0] if len(parts) > 0 else ''
    ctype  = parts[1] if len(parts) > 1 else ''
    cid    = parts[2] if len(parts) > 2 else ''

    if action in ('approve', 'reject', 'later'):
        _forward_callback(cq_data, ['marveen', 'job-hunter'])
    elif action == 'done' and ctype == 'kanban':
        _kanban_done(cq_chat, cid)
    elif action == 'holnapra' and ctype == 'kanban':
        _kanban_holnapra(cq_chat, cid)
    elif action == 'done' and ctype == 'rem':
        _reminder_done(cq_chat, cid)
    elif action == 'snooze' and ctype == 'rem':
        _reminder_snooze(cq_chat, cid)
    else:
        _forward_callback(cq_data, ['marveen'])

def tg_send_direct(text):
    """Direkt Telegram uzenet Zoltannak Bot API POST-tal (nem notify.sh)."""
    try:
        data = json.dumps({'chat_id': ALLOWED, 'text': text}).encode()
        req = urllib.request.Request(
            f'https://api.telegram.org/bot{TOKEN}/sendMessage',
            data=data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        log(f'tg_send_direct hiba: {e}')
        return None

WHISPER_PYTHON = '/home/userzoltan/.whisper-venv/bin/python3'
STT_SCRIPT    = '/home/userzoltan/marveen/scripts/stt.py'
TG_IMAGES_DIR = '/home/userzoltan/marveen/store/tg-images'

def download_photo(file_id):
    """Telegram kep letoltese helyi fajlba, visszaadja az elerhesi utat."""
    try:
        os.makedirs(TG_IMAGES_DIR, exist_ok=True)
        info = tg_get('getFile', file_id=file_id)
        file_path = info['result']['file_path']
        ext = os.path.splitext(file_path)[1] or '.jpg'
        dl_url = f'https://api.telegram.org/file/bot{TOKEN}/{file_path}'
        local_path = os.path.join(TG_IMAGES_DIR, f'{time.strftime("%Y%m%d-%H%M%S")}{ext}')
        urllib.request.urlretrieve(dl_url, local_path)
        return local_path
    except Exception as e:
        log(f'KEP LETOLTES HIBA: {e}')
        return None

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

# --- Session readiness check (pane-state.ts logika alapjan) ---
# Idle: "bypass permissions on" VAGY "? for shortcuts" lathato a pane-ben
# Busy: "esc to interrupt" VAGY spinner glyph-ok jelen vannak
_IDLE_FOOTER_RX = re.compile(r'bypass permissions on|\? for shortcuts')
_BUSY_RX        = re.compile(r'esc to interrupt|[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]')

def _capture_pane(session):
    try:
        r = subprocess.run(
            [TMUX, 'capture-pane', '-t', session, '-p'],
            capture_output=True, text=True, timeout=5
        )
        return r.stdout if r.returncode == 0 else None
    except Exception:
        return None

def _is_session_ready(session, max_wait=60):
    """Double-sample idle check, max_wait masodpercig var. Visszater True/False."""
    deadline = time.monotonic() + max_wait
    while time.monotonic() < deadline:
        pane = _capture_pane(session)
        if pane and not _BUSY_RX.search(pane) and _IDLE_FOOTER_RX.search(pane):
            # Elso sample idle -- dupla megerosites 300ms utan
            time.sleep(0.3)
            pane2 = _capture_pane(session)
            if pane2 and _IDLE_FOOTER_RX.search(pane2) and not _BUSY_RX.search(pane2):
                return True
        time.sleep(3)
    return False

def _inject_to_session(session, inject):
    """Tmux send-keys injektalas. Raise ha a session nem elerheto."""
    subprocess.run([TMUX, 'send-keys', '-t', session, '-l', inject], timeout=10)
    time.sleep(0.7)
    subprocess.run([TMUX, 'send-keys', '-t', session, 'Enter'], timeout=5)

def _wait_for_reply(log_before, wait_secs=90):
    """Varakozas notify.log novekedesere. Visszaadja a valaszt vagy None-t."""
    for _ in range(wait_secs // 2):
        time.sleep(2)
        try:
            size = os.path.getsize(LOG_NOTIFY)
            if size > log_before:
                with open(LOG_NOTIFY) as f:
                    lines = f.readlines()
                last = lines[-1].strip() if lines else ''
                if '|' in last:
                    return last.split('|', 1)[1]
        except Exception:
            pass
    return None

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

    # Readiness check: varunk amig a session idle, max 60 mp
    if not _is_session_ready(session, max_wait=60):
        log('Session nem idle 60 mp utan -- injektalas mindenkeppen megprobaljuk')

    # 1. kisérlet
    _inject_to_session(session, inject)
    reply = _wait_for_reply(log_before, wait_secs=90)
    if reply:
        save_to_history(user_msg, reply)
        return reply

    # 2. kisérlet (retry) -- ha az inject nem jutott be vagy Marveen lassan indult
    log('Nincs valasz 90 mp utan -- retry (2. injektalas)...')
    try:
        log_before2 = os.path.getsize(LOG_NOTIFY)
    except Exception:
        log_before2 = log_before
    _inject_to_session(session, inject)
    reply = _wait_for_reply(log_before2, wait_secs=90)
    if reply:
        save_to_history(user_msg, reply)
        return reply

    # Mindket kisérlet meghiusult -- Zoltant direkt ertesitjuk
    log('Mindket kisérlet meghiusult -- direkt Telegram ertesites Zoltannak')
    short = single[:80] + ('...' if len(single) > 80 else '')
    tg_send_direct(
        f'⚠️ Marveen nem valaszolt idoben (2x90mp). Az uzeneted elveszett:\n"{short}"\n\nKerem probald ujra.'
    )
    return 'Nincs valasz 90 masodpercen belul (retry utan sem). Ertesites kuldve.'

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

    _net_errors = 0

    while True:
        try:
            off = int(open(OFFSET).read().strip())
            d = tg_get('getUpdates', offset=off, limit=5, timeout=0)
            for u in d.get('result', []):
                uid = u['update_id']
                open(OFFSET, 'w').write(str(uid + 1))

                # Inline gomb visszajelzes kezelese
                cq = u.get('callback_query')
                if cq:
                    handle_callback(cq)
                    continue

                msg  = u.get('message', {})
                chat = str(msg.get('chat', {}).get('id', ''))
                text = msg.get('text', '').strip()
                voice = msg.get('voice') or msg.get('audio')
                photo = msg.get('photo')
                user = msg.get('from', {}).get('first_name', 'User')

                if voice and chat == ALLOWED:
                    log(f'HANG: {user} hanguzenet ({voice.get("duration", "?")}s)')
                    transcribed = transcribe_voice(voice['file_id'])
                    if transcribed:
                        text = '[TELEGRAM HANG - atirt hanguzenet, elirás lehetseges] ' + transcribed
                        log(f'HANG->SZOVEG: {text[:80]}')
                    else:
                        log('HANG: atiras sikertelen, kihagyva')
                        continue

                if photo and chat == ALLOWED:
                    largest = photo[-1]
                    log(f'KEP: {user} kepet kuldott')
                    img_path = download_photo(largest['file_id'])
                    if img_path:
                        cap = msg.get('caption', '').strip()
                        text = f'[TELEGRAM KEP: {img_path}]' + (f' [FELIRAT: {cap}]' if cap else '')
                        log(f'KEP LETOLTVE: {img_path}')
                    else:
                        log('KEP: letoltes sikertelen, kihagyva')
                        continue

                if not text or chat != ALLOWED:
                    continue

                log(f'IN: {user}: {text[:60]}')
                reply = ask_marveen(text)
                log(f'OUT: {reply[:80]}')
            _net_errors = 0
        except KeyboardInterrupt:
            break
        except Exception as e:
            err_str = str(e).lower()
            is_net_err = any(x in err_str for x in ('unreachable', 'timed out', 'timeout', 'connection', 'ssl'))
            if is_net_err:
                _net_errors += 1
                if _net_errors == 1:
                    log(f'HALOZATI HIBA -- DNS flush kiserlet')
                    subprocess.run(['resolvectl', 'flush-caches'], capture_output=True, timeout=5)
                wait = min(60 * _net_errors, 300)
                log(f'HALOZATI HIBA #{_net_errors}: {e} -- {wait}s varakozas')
                time.sleep(wait)
                continue
            else:
                _net_errors = 0
                log(f'ERR: {e}')

        time.sleep(5)

main()
