#!/usr/bin/env bash
# Syncs local Gibraltar iGaming Dashboard files to GitHub repo and pushes via SSH.
# Run after build-open-roles.py or career scan to auto-deploy updates to Vercel.

set -e

LOCAL_DIR="/home/userzoltan/marveen/agents/engineer/projects/gibraltar-igaming-dashboard"
REPO_DIR="/home/userzoltan/marveen/agents/engineer/projects/Igaming-Salary-dashboard-repo"
LOG_PREFIX="[sync-dashboard]"
TOKEN=$(cat /home/userzoltan/marveen/store/.dashboard-token)

echo "$LOG_PREFIX Starting sync at $(date '+%Y-%m-%d %H:%M:%S')"

# 1. Pull latest from GitHub (gracefully handle ff-only conflicts from GH Actions commits)
cd "$REPO_DIR"
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git pull --rebase origin main 2>&1

# 2. Copy data and frontend files
cp "$LOCAL_DIR/open-roles.json"    "$REPO_DIR/open-roles.json"
cp "$LOCAL_DIR/career-scan.json"   "$REPO_DIR/career-scan.json"
cp "$LOCAL_DIR/salary-data.json"   "$REPO_DIR/salary-data.json"
cp "$LOCAL_DIR/app.js"             "$REPO_DIR/app.js"
cp "$LOCAL_DIR/index.html"         "$REPO_DIR/index.html"
cp "$LOCAL_DIR/style.css"          "$REPO_DIR/style.css"
cp "$LOCAL_DIR/base.css"           "$REPO_DIR/base.css"

# Copy scraper source so GH Actions can run it
rsync -a --delete --exclude='__pycache__' "$LOCAL_DIR/salary-scraper/" "$REPO_DIR/salary-scraper/"
# Copy GitHub Actions workflow (use rsync to avoid directory nesting issues)
mkdir -p "$REPO_DIR/.github/workflows"
rsync -a "$LOCAL_DIR/.github/workflows/" "$REPO_DIR/.github/workflows/"
# Copy Vercel serverless API and config
mkdir -p "$REPO_DIR/api"
rsync -a "$LOCAL_DIR/api/" "$REPO_DIR/api/"
# vercel.json intentionally not synced (removed, Vercel detects api/ dir automatically)

echo "$LOG_PREFIX Files copied."

# 3. Export companies list from local API (used by GH Actions scraper for company career pages)
curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:3420/api/companies?active=true" \
  > "$REPO_DIR/companies.json"
echo "$LOG_PREFIX companies.json exported."

# 4. Write last-sync metadata (read by the frontend badge)
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
HUMAN_DATE=$(TZ='Europe/Budapest' date '+%-d %B %Y, %H:%M')
# Preserve signal_count from previous last-sync.json if GH Actions wrote it
PREV_SIGNAL_COUNT=$(python3 -c "import json,sys; d=json.load(open('$REPO_DIR/last-sync.json')) if __import__('pathlib').Path('$REPO_DIR/last-sync.json').exists() else {}; print(d.get('signal_count',''))" 2>/dev/null || echo "")
cat > "$REPO_DIR/last-sync.json" << ENDJSON
{"timestamp":"$TIMESTAMP","human":"$HUMAN_DATE","signal_count":${PREV_SIGNAL_COUNT:-null}}
ENDJSON
echo "$LOG_PREFIX last-sync.json written: $TIMESTAMP"

# 5. Commit only if there are changes
cd "$REPO_DIR"
git add -A
if git diff --cached --quiet; then
  echo "$LOG_PREFIX No changes to commit, skipping push."
  exit 0
fi

COMMIT_MSG="Auto-sync: data + frontend update $(TZ='Europe/Budapest' date '+%Y-%m-%d %H:%M')"
git commit -m "$COMMIT_MSG"
echo "$LOG_PREFIX Committed: $COMMIT_MSG"

# 6. Push via SSH
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git push origin main 2>&1
echo "$LOG_PREFIX Push complete. Vercel will auto-deploy."
