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
fi

export PATH="/home/userzoltan/.bun/bin:/home/userzoltan/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
CLAUDE="$(command -v claude)"
TMUX_BIN="$(command -v tmux)"

[ -z "$CLAUDE" ] && echo "ERROR: claude not found" >&2 && exit 1

$TMUX_BIN kill-session -t "$SESSION" 2>/dev/null

ENCODED_DIR="${AGENT_DIR//\//-}"
PROJECTS_ROOT="$HOME/.claude/projects"
CONTINUE_FLAG=""
[ -d "$PROJECTS_ROOT/$ENCODED_DIR" ] && CONTINUE_FLAG="--continue "

$TMUX_BIN new-session -d -s "$SESSION" -c "$AGENT_DIR" \
  "$CLAUDE ${CONTINUE_FLAG}--dangerously-skip-permissions --model claude-sonnet-4-6"

echo "Marketing agent started in tmux session: $SESSION"
echo "Attach with: tmux attach -t $SESSION"
