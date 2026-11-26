#!/usr/bin/env bash
# Runs ON THE VPS (as the site user) after every push to `draft`.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.local/node/bin:$PATH"   # site-user Node + PM2 (non-interactive SSH has a bare PATH)
git fetch --prune origin draft
git reset --hard origin/draft          # .env, uploads, logs are untracked -> untouched
php database/migrate.php                # apply new database/migrations/*.sql (backs up DB first)
php database/register_apk.php           # publish APKs committed in releases/app/ to Admin → Mobile App
if command -v pm2 >/dev/null 2>&1; then
  pm2 startOrRestart ecosystem.config.cjs --update-env && pm2 save
fi
echo "deployed $(git rev-parse --short HEAD)"
