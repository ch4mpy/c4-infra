#!/usr/bin/env bash
# The demo host's side of the deployment: .github/workflows/deploy-demo.yml runs it over ssh, in
# ~/c4-infra, once the files of demo/deploy-files.txt and .env are there and the images pulled.
# Starts the stack or brings it up to date, reloads Caddy, prunes the old images and installs the
# nightly backup. Idempotent.
set -euo pipefail
# the stack's directory: compose reads COMPOSE_FILE (compose.yml:compose.demo.yml) from its .env
cd "$(dirname "$0")/.."

# What the applications register: their themes and their sites, in directories of the deploy user
# (a bind mount Docker creates would belong to root)
mkdir -p keycloak/themes caddy/apps
# --wait: fails, with the state printed, unless every service with a healthcheck reports healthy
# within the timeout
docker compose up -d --remove-orphans --wait --wait-timeout 300 || { docker compose ps; exit 1; }
# up -d leaves Caddy running when only its configuration changed: reload it (graceful; an invalid
# configuration fails the deployment while the previous one keeps serving). Its stdin is closed: the
# workflow sends this script's caller on ssh's stdin.
docker compose exec -T reverse-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile < /dev/null
docker image prune -f > /dev/null
docker compose ps

# Nightly backup (demo/backup.sh), idempotent: the line replaces the one of an earlier deployment
# (./backup.sh, before demo/ held the host's scripts). The "|| true" keep set -e / pipefail from
# aborting on an empty crontab (crontab -l and grep -v both return 1).
mkdir -p ~/backups
crontab_file=$(mktemp)
{ crontab -l 2> /dev/null || true; } | { grep -vE 'c4-infra && bash \./(demo/)?backup\.sh' || true; } > "$crontab_file"
echo '15 3 * * * cd ~/c4-infra && bash ./demo/backup.sh >> ~/backups/c4-infra-backup.log 2>&1' >> "$crontab_file"
crontab "$crontab_file"
rm -f "$crontab_file"
