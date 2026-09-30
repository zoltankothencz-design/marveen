#!/usr/bin/env python3
# Utemezett feladatok kezbesites-ellenorzese (2026-09-27).
# A dashboard a task_runs-ba irja, ha elkuldott egy feladatot egy agens tmux-sessionjebe,
# de azt nem ellenorzi, hogy a prompt tenyleg bekerult-e az agens transzkriptjebe.
# 2026-09-27-en az igaming ket feladata igy veszett el csendben. Ez a szkript 10 percenkent:
#   - a 8-90 perce elkuldott feladatokat megkeresi az agens transzkriptjeben (marker + idobelyeg),
#   - ha nincs meg es a session nem dolgozik: egyszer ujrakuldi (vagy ha a sorban beragadt, Entert nyom),
#   - ha az ujrakuldes utan 15 perccel sincs meg: egyszer riaszt Telegramon.
# Heartbeat tipusu feladatot nem kuld ujra (30 percenkent ugyis jon), csak naploz.
# Hasznalat: task-delivery-check.py [--dry]
import glob, json, os, sqlite3, subprocess, sys, time
from datetime import datetime, timezone

HOME = os.path.expanduser('~')
M = f'{HOME}/marveen'
DB = f'{M}/store/claudeclaw.db'
STATE = f'{M}/store/task-delivery-state.json'
LOG = f'{M}/store/task-delivery-check.log'
TASKS = f'{HOME}/.claude/scheduled-tasks'
PROJECTS = f'{HOME}/.claude/projects'
TMUX = '/usr/bin/tmux'
DRY = '--dry' in sys.argv
MIN_AGE, MAX_AGE = 8 * 60, 90 * 60          # masodperc
BUSY_GRACE, RETRY_WAIT = 60 * 60, 15 * 60


def log(msg):
    line = f'{datetime.now().isoformat(timespec="seconds")} {"DRY " if DRY else ""}{msg}'
    print(line)
    if not DRY:
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(line + '\n')


def notify(msg):
    log(f'NOTIFY: {msg}')
    if not DRY:
        subprocess.run(['bash', f'{M}/scripts/notify.sh', msg], timeout=60)


def tmux(*args):
    return subprocess.run([TMUX, *args], capture_output=True, text=True, timeout=10)


def session_for(agent):
    return 'marveen-channels' if agent == 'marveen' else f'agent-{agent}'


def project_dir(agent):
    cwd = M if agent == 'marveen' else f'{M}/agents/{agent}'
    return os.path.join(PROJECTS, cwd.replace('/', '-'))


def task_type(name):
    try:
        return json.load(open(f'{TASKS}/{name}/task-config.json')).get('type', 'task')
    except Exception:
        return 'task'


def marker(name, ttype):
    return f'[Heartbeat: {name}]' if ttype == 'heartbeat' else f'[Utemezett feladat: {name}]'


def delivered(agent, mark, since_s):
    """Van-e a markert tartalmazo user-uzenet az agens transzkriptjeben since_s ota."""
    since_iso = datetime.fromtimestamp(since_s - 10, timezone.utc).strftime('%Y-%m-%dT%H:%M:%S')
    for f in glob.glob(os.path.join(project_dir(agent), '*.jsonl')):
        if os.path.getmtime(f) < since_s - 60:
            continue
        with open(f, encoding='utf-8', errors='replace') as fh:
            for line in fh:
                if mark not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if d.get('type') == 'user' and d.get('timestamp', '')[:19] >= since_iso:
                    return True
    return False


def pane(session):
    r = tmux('capture-pane', '-p', '-t', session)
    return r.stdout if r.returncode == 0 else None


def resend(session, name, mark):
    p = pane(session)
    if p is None:
        return f'session {session} nem fut'
    tail = '\n'.join(p.rstrip().splitlines()[-15:])
    if mark in tail:
        # a prompt ott all a beviteli sorban, csak nem ment el
        if not DRY:
            tmux('send-keys', '-t', session, 'Enter')
        return 'beragadt prompt, Enter elkuldve'
    text = (f'{mark} (ujrakuldes: az utemezett kuldes nem jutott el hozzad) '
            f'Hajtsd vegre pontosan a leiras szerint: {TASKS}/{name}/SKILL.md')
    if not DRY:
        tmux('send-keys', '-t', session, '-l', text)
        # Poll until the text appears in the pane before submitting.
        # send-keys -l throughput is ~1KB/s for long prompts; 0.8s is not
        # enough for a multi-line SKILL.md path prompt. Max wait: 5s.
        for _ in range(10):
            time.sleep(0.5)
            p2 = pane(session)
            if p2 and mark in '\n'.join(p2.rstrip().splitlines()[-15:]):
                break
        tmux('send-keys', '-t', session, 'Enter')
    return 'ujrakuldve'


def main():
    now = time.time()
    try:
        state = json.load(open(STATE))
    except Exception:
        state = {}
    con = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
    rows = con.execute('SELECT id, name, agent, ts FROM task_runs WHERE ts BETWEEN ? AND ?',
                       (int((now - MAX_AGE) * 1000), int((now - MIN_AGE) * 1000))).fetchall()
    con.close()
    for rid, name, agent, ts in rows:
        key = str(rid)
        st = state.get(key, {})
        if st.get('final'):
            continue
        sent = ts / 1000
        ttype = task_type(name)
        mark = marker(name, ttype)
        session = session_for(agent)
        if delivered(agent, mark, sent):
            if st.get('retried'):
                log(f'OK az ujrakuldes utan: {name} ({agent})')
            state[key] = {'final': 'ok', 'ts': sent}
            continue
        if ttype == 'heartbeat':
            log(f'MISS heartbeat nem jutott el: {name} ({agent}), nem kuldom ujra')
            state[key] = {'final': 'miss-heartbeat', 'ts': sent}
            continue
        p = pane(session) or ''
        busy = 'esc to interrupt' in p
        if not st.get('retried'):
            if busy and now - sent < BUSY_GRACE:
                continue  # dolgozik, a sorban allo prompt kesobb kerul be
            res = resend(session, name, mark)
            log(f'RESEND {name} ({agent}, kuldve {datetime.fromtimestamp(sent):%H:%M}): {res}')
            notify(f'Marveen: a(z) "{name}" feladat ({agent}) nem jutott el az agenshez, {res}.')
            state[key] = {'retried': now, 'ts': sent}
            if res.startswith('session'):
                state[key]['final'] = 'no-session'
        elif now - st['retried'] > RETRY_WAIT:
            notify(f'HIBA: a(z) "{name}" feladat ({agent}) az ujrakuldes utan sem futott le. Kezi ellenorzes kell.')
            state[key] = {**st, 'final': 'failed'}
    # 2 napnal regebbi bejegyzesek torlese
    state = {k: v for k, v in state.items() if now - v.get('ts', now) < 2 * 86400}
    if not DRY:
        tmp = STATE + '.tmp'
        json.dump(state, open(tmp, 'w'))
        os.replace(tmp, STATE)


if __name__ == '__main__':
    main()
