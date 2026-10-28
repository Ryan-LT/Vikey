#!/bin/zsh
# Builds site/dist and deploys it to Cloudflare Pages (project "vikey", domain vikey.app).
set -e
cd "$(dirname "$0")/../.."
python3 site/build.py
set -a; . ~/.secrets/cloudflare_dedicated; set +a
npx --yes wrangler@latest pages deploy site/dist --project-name vikey --branch main --commit-dirty=true | tail -2
