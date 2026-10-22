#!/usr/bin/env bash
# The demo host's side of the deployment: .github/workflows/deploy-demo.yml runs it over ssh, as the
# shared stack's account c4-infra, in ~/c4-infra, once the files of demo/deploy-files.txt and .env
# are there and the images pulled. Installs the applications' command (c4-app), starts the stack or
# brings it up to date, reloads Caddy, makes sure of the registration account, prunes the old images
# and installs the nightly backup. Idempotent.
set -euo pipefail
# the stack's directory: compose reads COMPOSE_FILE (compose.yml:compose.demo.yml) from its .env
cd "$(dirname "$0")/.."

# The one command the applications' accounts run as root (sudo c4-app, demo/c4-app), installed
# root-owned when it changed. The c4-infra account's only sudo rule (demo/vps-bootstrap.sh) is this
# exact command line, from /home/c4-infra/c4-infra; the stand-in tests run it as root.
if ! cmp -s demo/c4-app /usr/local/sbin/c4-app; then
  sudo -n /usr/bin/install -o root -g root -m 0755 "$PWD/demo/c4-app" /usr/local/sbin/c4-app
  echo "c4-app installed (/usr/local/sbin/c4-app)"
fi

# What the applications register: their themes and their sites, in directories of the c4-infra
# account (a bind mount Docker creates would belong to root)
mkdir -p keycloak/themes caddy/apps
# compose.apps.yml (COMPOSE_FILE): the shared services stay on each registered application's network
# when compose recreates them (intent 0007)
bash ./networks.sh compose-file
# --wait: fails, with the state printed, unless every service with a healthcheck reports healthy
# within the timeout
docker compose up -d --remove-orphans --wait --wait-timeout 300 || { docker compose ps; exit 1; }
# up -d leaves Caddy running when only its configuration changed: reload it (graceful; an invalid
# configuration fails the deployment while the previous one keeps serving). Its stdin is closed: the
# workflow sends this script's caller on ssh's stdin.
docker compose exec -T reverse-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile < /dev/null
# The account registrations log in as: created when missing, its secret set to .env's (a rotation),
# the registry's realms granted to it. An administrator is only needed then: the bootstrap one of
# .env while it works, else KC_SETUP_ADMIN_USERNAME / KC_SETUP_ADMIN_PASSWORD, which the workflow
# exports from the secrets of the demo environment when they are set (docs/demo-setup.md).
bash ./registration-account.sh ensure < /dev/null
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
