#!/usr/bin/env bash
# Nightly backup of the shared Keycloak: its PostgreSQL database, dumped hot through the running
# container (users, organizations, clients and role mappings of every application's realm). The
# applications' databases and volumes are backed up by `sudo c4-app backup`, as each application's
# account, from root's cron at 03:45 (demo/c4-app, README.md "Backups").
#
# Runs on the host as the c4-infra account, from ~/c4-infra (demo/deploy.sh installs it in that
# account's crontab). Restore procedure in README.md.
set -euo pipefail
# the stack's directory, where compose finds its .env
cd "$(dirname "$0")/.."

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"
stamp="$(date +%Y%m%d-%H%M%S)"
install -d -m 0700 "$BACKUP_DIR"

# --before-upgrade (demo/deploy.sh, intent 0013): the dump taken before a new Keycloak image migrates
# the database, the way back; named out of the nightly rotation, kept until removed by hand
prefix=c4-infra-keycloak-db
[ "${1:-}" != --before-upgrade ] || prefix=c4-infra-keycloak-before-upgrade

docker compose exec -T keycloak-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$BACKUP_DIR/$prefix-$stamp.dump"

find "$BACKUP_DIR" -name 'c4-infra-keycloak-db-*.dump' -mtime +"$KEEP_DAYS" -delete
echo "backup $stamp written to $BACKUP_DIR/$prefix-$stamp.dump (nightly ones kept $KEEP_DAYS days)"
