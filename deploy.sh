#!/usr/bin/env bash
# Runs ON THE VPS (as the site user) after every push to `draft`.
set -euo pipefail
cd "$(dirname "$0")"
git fetch --prune origin draft
git reset --hard origin/draft          # .env, uploads, logs are untracked -> untouched
if command -v pm2 >/dev/null 2>&1; then
  pm2 startOrRestart ecosystem.config.cjs --update-env && pm2 save
fi
echo "deployed $(git rev-parse --short HEAD)"
