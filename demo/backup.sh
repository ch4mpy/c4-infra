#!/usr/bin/env bash
# Nightly backup of the shared Keycloak: its PostgreSQL database, dumped hot through the running
# container (users, organizations, clients and role mappings of every application's realm). Each
# application backs up its own databases.
#
# Runs on the host as the deploy user, from ~/c4-infra (demo/deploy.sh installs it in that
# user's crontab). Restore procedure in README.md.
set -euo pipefail
# the stack's directory, where compose finds its .env
cd "$(dirname "$0")/.."

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"
stamp="$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$BACKUP_DIR"

docker compose exec -T keycloak-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$BACKUP_DIR/c4-infra-keycloak-db-$stamp.dump"

find "$BACKUP_DIR" -name 'c4-infra-keycloak-db-*.dump' -mtime +"$KEEP_DAYS" -delete
echo "backup $stamp written to $BACKUP_DIR (keeping $KEEP_DAYS days)"
