#!/bin/bash
# Marketing agent startup script
INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_DIR="$INSTALL_DIR/agents/marketing"
SESSION="agent-marketing"

if [ -f "$INSTALL_DIR/.env" ]; then
  _oauth="$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$INSTALL_DIR/.env" | head -1 | cut -d= -f2-)"
  [ -n "$_oauth" ] && export CLAUDE_CODE_OAUTH_TOKEN="$_oauth"
  _api_key="$(grep -E '^ANTHROPIC_API_KEY=' "$INSTALL_DIR/.env" | head -1 | cut -d= -f2-)"
  [ -n "$_api_key" ] && export ANTHROPIC_API_KEY="$_api_key"
  unset _oauth _api_key
fi

export PATH="/home/userzoltan/.bun/bin:/home/userzoltan/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
CLAUDE="$(command -v claude)"
TMUX_BIN="$(command -v tmux)"

[ -z "$CLAUDE" ] && echo "ERROR: claude not found" >&2 && exit 1
[ -z "$TMUX_BIN" ] && echo "ERROR: tmux not found" >&2 && exit 1

$TMUX_BIN kill-session -t "$SESSION" 2>/dev/null

ENCODED_DIR="${AGENT_DIR//\//-}"
PROJECTS_ROOT="$HOME/.claude/projects"
LOOP_LOG="/home/userzoltan/marveen/store/marketing-loop.log"

# Onujraindito wrapper: CONTINUE_FLAG dinamikusan szamitodik minden
# iteracioban, hogy a lezart --continue session ne okozzon hibas ujrainditast.
# FAIL_COUNT: ha 3x egymás után nem nullás exit code, töröljük a --continue flaget
# (megvédés az ismételten hibás/túl hosszú context-ből való végtelen újraindítástól).
$TMUX_BIN new-session -d -s "$SESSION" -c "$AGENT_DIR" \
  "FAIL_COUNT=0
  while true; do
    if [ -d \"$PROJECTS_ROOT/$ENCODED_DIR\" ] && [ \$FAIL_COUNT -lt 3 ]; then CF='--continue '; else CF=''; fi
    $CLAUDE \${CF}--dangerously-skip-permissions --model claude-sonnet-4-6
    EC=\$?
    echo \"\$(date -Iseconds) exited ec=\$EC fail_count=\$FAIL_COUNT\" >> \"$LOOP_LOG\"
    if [ \$EC -ne 0 ]; then
      FAIL_COUNT=\$((FAIL_COUNT + 1))
    else
      FAIL_COUNT=0
    fi
    sleep 30
  done"

echo "Marketing agent started in tmux session: $SESSION"
echo "Attach with: tmux attach -t $SESSION"

# Auto-elfogad first-run dialogusokat (bypass permissions, trust folder, resume dialog)
for i in $(seq 1 20); do
  sleep 1
  pane=$($TMUX_BIN capture-pane -t "$SESSION" -p 2>/dev/null || true)
  case "$pane" in
    *"Bypass Permissions mode"*"Yes, I accept"*)
      $TMUX_BIN send-keys -t "$SESSION" "2" Enter
      sleep 1
      ;;
    *"Do you trust the files in this folder?"*)
      $TMUX_BIN send-keys -t "$SESSION" "1" Enter
      sleep 1
      ;;
    *"Resume from summary"*|*"Resume full session"*)
      $TMUX_BIN send-keys -t "$SESSION" "" Enter
      sleep 2
      ;;
    *"bypass permissions on"*|*"? for shortcuts"*)
      echo "Marketing agent session ready."
      break
      ;;
  esac
done

exit 0
