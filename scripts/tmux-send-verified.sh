#!/bin/bash
# tmux-send-verified.sh SESSION "prompt szoveg"
# Prompt kuldese egy Claude Code tmux sessionbe ugy, hogy az indulas igazolt.
#
# Kilepesi kodok:
#   0 = a prompt elindult (a pane "esc to interrupt"-ot mutatott kuldes utan)
#   1 = nem indult el (az input torolve, hogy ne maradjon beragadt szoveg)
#   2 = a session mar dolgozik, nem kuldtunk semmit
#   3 = a session nem letezik
#
# Miert kell: a `tmux send-keys "szoveg" Enter` egy hivasban gyors beillesztesnek
# latszik, az Enter sortoreskent landol es a prompt elkuldetlenul ul az input
# boxban (2026-10-08/09: a job scan tartalek inditasa igy bukott el, ketszer
# beirva). Ezert: -l literal szoveg, kulon Enter, es polloljuk az indulast.

SESSION="$1"
TEXT="$2"
[ -z "$SESSION" ] || [ -z "$TEXT" ] && { echo "hasznalat: $0 SESSION \"szoveg\"" >&2; exit 64; }

tmux has-session -t "=$SESSION" 2>/dev/null || exit 3

# Egyszerre csak egy kuldo irhat ugyanabba a sessionbe (enforcer + watchdog
# ugyanabban a percben futhat).
exec 9>"/tmp/tmux-send-verified-${SESSION}.lock"
flock -w 60 9 || exit 1

is_busy() {
    tmux capture-pane -t "=$SESSION:" -p 2>/dev/null | tail -6 | grep -q "esc to interrupt"
}

# Van-e valodi (nem halvany javaslat/placeholder) szoveg az input sorban?
has_stuck_input() {
    local line
    line=$(tmux capture-pane -t "=$SESSION:" -ep 2>/dev/null | grep -a "❯" | tail -1)
    [ -z "$line" ] && return 1
    # Halvany (dim, ESC[2m) szoveg = Claude Code javaslat, nem beragadt input
    printf '%s' "$line" | grep -aq $'\x1b\[2m' && return 1
    local plain
    plain=$(printf '%s' "$line" | sed $'s/\x1b\\[[0-9;]*m//g' | sed $'s/\xc2\xa0//g' | sed 's/^[[:space:]]*❯//' | tr -d '[:space:]')
    [ -n "$plain" ]
}

clear_input() {
    # Dupla Escape urit, de CSAK ha tenyleg van szoveg: ures inputnal a dupla
    # Escape a visszatekero dialogot nyitna meg.
    if has_stuck_input; then
        tmux send-keys -t "=$SESSION:" Escape
        sleep 0.5
        tmux send-keys -t "=$SESSION:" Escape
        sleep 1.5
    fi
}

wait_busy() {
    local i
    for i in $(seq 1 "$1"); do
        is_busy && return 0
        sleep 1
    done
    return 1
}

is_busy && exit 2

clear_input

tmux send-keys -t "=$SESSION:" -l "$TEXT"
sleep 0.7
tmux send-keys -t "=$SESSION:" Enter
wait_busy 10 && exit 0

# Egy potlo Enter (pl. a session meg toltott)
tmux send-keys -t "=$SESSION:" Enter
wait_busy 15 && exit 0

clear_input
exit 1
