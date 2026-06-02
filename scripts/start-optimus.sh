#!/bin/bash
# Optimus agent startup script
# Rendszermernok/full-stack fejleszto agent

INSTALL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_DIR="$INSTALL_DIR/agents/engineer"
SESSION="agent-engineer"

if [ -f "$INSTALL_DIR/.env" ]; then
  _oauth="$(grep -E '^CLAUDE_CODE_OAUTH_TOKEN=' "$INSTALL_DIR/.env" | head -1 | cut -d= -f2-)"
  [ -n "$_oauth" ] && export CLAUDE_CODE_OAUTH_TOKEN="$_oauth"
  _api_key="$(grep -E '^ANTHROPIC_API_KEY=' "$INSTALL_DIR/.env" | head -1 | cut -d= -f2-)"
  [ -n "$_api_key" ] && export ANTHROPIC_API_KEY="$_api_key"
  unset _oauth _api_key
fi

export PATH="/opt/homebrew/bin:$HOME/.bun/bin:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
CLAUDE="$(command -v claude)"
TMUX_BIN="$(command -v tmux)"

[ -z "$CLAUDE" ] && echo "ERROR: claude not found" >&2 && exit 1
[ -z "$TMUX_BIN" ] && echo "ERROR: tmux not found" >&2 && exit 1

$TMUX_BIN kill-session -t "$SESSION" 2>/dev/null

ENCODED_DIR="${AGENT_DIR//\//-}"
PROJECTS_ROOT="$HOME/.claude/projects"
if [ -d "$PROJECTS_ROOT/$ENCODED_DIR" ]; then
  CONTINUE_FLAG="--continue "
else
  CONTINUE_FLAG=""
fi

$TMUX_BIN new-session -d -s "$SESSION" -c "$AGENT_DIR" \
  "$CLAUDE ${CONTINUE_FLAG}--dangerously-skip-permissions --model claude-sonnet-4-6"

echo "Optimus agent started in tmux session: $SESSION"
echo "Attach with: tmux attach -t $SESSION"

for i in $(seq 1 12); do
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
    *">"*|*"claude"*)
      echo "Optimus session ready."
      break
      ;;
  esac
done

exit 0
