#!/usr/bin/env bash
# 0027: an application's backups touch nothing of another's, and the nightly run backs up each, on a
# stand-in demo host (accounts faito, hururaa, turu and tickee, a tmpfs of 20 GiB at
# /var/backups/c4-apps):
#
#   - AC-03: Hurura'a (B) deployed with tests/fixtures/0027/hururaa.yml, a row and a file, backed up;
#     Faito (A) with forged.yml, whose service and volume are labelled with B's project: compose
#     labels them faito; A's backup and restore leave B's containers running (StartedAt), B's rows,
#     files and backups as they were; A's account can't list B's backup directory; A's restore
#     refuses B's stamp, /var/backups/c4-apps/hururaa/<stamp>, ../hururaa/<stamp> and ..;
#   - AC-06: Turu deployed with turu.yml (nothing declared), Tickee never deployed; a stamp 8 days old
#     and one 6 days old planted in Faito's backups; /etc/cron.d/c4-apps-backup (vps-bootstrap.sh)
#     0644, at 03:45, its command run as root: Faito and Hurura'a get a new stamp each, Turu's log
#     says it declares nothing, Tickee's that it has no container, each log 0640 root:<app>; the
#     stamp 8 days old is removed, the 6 days old kept; an application's `sudo c4-app nightly` is
#     refused.
#
#   bash tests/0027-isolation.stand-in.sh
#
# covers: demo/ registry.sh networks.sh tests/fixtures/0027/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0027
BACKUP_ROOT=/var/backups/c4-apps
CRON=/etc/cron.d/c4-apps-backup

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

as() { # <account> <log> <command>: over ssh, its output into $work/<log>, its exit status into $status
  stand_in_ssh "$1" "$3" > "$work/$2" 2>&1
  status=$?
}
refused() { # <log>
  [ "$status" -ne 0 ] || { echo "exited 0:"; tail -n 20 "$work/$1"; return 1; }
}
exited_0() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 20 "$work/$1"; return 1; }
}
says() { # <log> <text>
  grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 20 "$work/$1"; return 1; }
}
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
on_host() { # <script> [<arg>…]: bash -c <script> in the stand-in, as root
  local script=$1
  shift
  stand_in_exec bash -c "$script" sh "$@" | tr -d '\r'
}
deployed() { # <account> <fixture>: sent as ~<account>/<account>/compose.yml, then sudo c4-app up
  stand_in_ssh -i "$1" "cat > ~/$1/compose.yml" < "$FIXTURES/$2" || return 1
  as "$1" "up-$1.log" "sudo c4-app up"
  exited_0 "up-$1.log"
}
stamps() { on_host 'ls -1A "$1"' "$BACKUP_ROOT/$1" | grep -E '^[0-9]{8}-[0-9]{6}$'; }
latest() { stamps "$1" | LC_ALL=C sort | tail -n 1; }
# Hurura'a's state: its containers' starts, its rows, its files, its backups (every entry, each file's checksum)
hururaa_state() {
  on_host 'docker inspect -f "{{.Name}} {{.State.StartedAt}}" hururaa.db hururaa.files
    docker exec hururaa.db psql -U fixture-user -d fixture-db -Atc "select string_agg(name, '\'','\'' order by name) from item"
    docker exec hururaa.files ls -1A /srv
    cd "$1" && find . -printf "%P %y %m %U %G %s\n" | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort' \
    "$BACKUP_ROOT/hururaa"
}
# the com.docker.compose.project label of a container and of a volume
labels() { # <container> <volume>
  on_host 'docker inspect -f "{{index .Config.Labels \"com.docker.compose.project\"}}" "$1"
    docker volume inspect -f "{{index .Labels \"com.docker.compose.project\"}}" "$2"' "$1" "$2" | paste -sd' '
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito, hururaa, turu, tickee), the shared stack deployed as c4-infra" \
  stand_in_accounts faito hururaa turu tickee
check "a tmpfs of 20 GiB at $BACKUP_ROOT" \
  on_host 'install -d -m 0755 "$1" && mount -t tmpfs -o size=20g,mode=0755 tmpfs "$1"' "$BACKUP_ROOT"

# AC-03
check "Hurura'a deployed with hururaa.yml" deployed hururaa hururaa.yml
check "a row r1 in hururaa.db, a file h in hururaa.files' volume" \
  on_host 'docker exec hururaa.db psql -q -U fixture-user -d fixture-db -c "create table item (name text primary key); insert into item values ('\''r1'\'')" \
    && docker exec hururaa.files sh -c "echo h > /srv/h"'
as hururaa backup-hururaa.log "sudo c4-app backup"
check "Hurura'a's backup exits 0" exited_0 backup-hururaa.log
hururaa_stamp=$(latest hururaa)
check "it writes a stamp ($hururaa_stamp)" test -n "$hururaa_stamp"
check "Faito deployed with forged.yml (its service and volume labelled with Hurura'a's project)" deployed faito forged.yml
check "compose labels faito.files and faito_files_data faito's, not hururaa's" \
  is "$(labels faito.files faito_files_data)" "faito faito"
check "a file a in faito.files' volume" on_host 'docker exec faito.files sh -c "echo a > /srv/a"'
before=$(hururaa_state)
as faito backup-faito.log "sudo c4-app backup"
check "Faito's backup exits 0" exited_0 backup-faito.log
faito_stamp=$(latest faito)
check "it holds faito's volume only: files.files_data.tar ($faito_stamp)" \
  is "$(on_host 'ls -1A "$1"' "$BACKUP_ROOT/faito/$faito_stamp" | paste -sd' ')" files.files_data.tar
check "Hurura'a's containers, rows, files and backups are as they were" is "$(hururaa_state)" "$before"
check "a file b in faito.files' volume" on_host 'docker exec faito.files sh -c "echo b > /srv/b"'
as faito restore-faito.log "sudo c4-app restore $faito_stamp --yes"
check "Faito's restore exits 0" exited_0 restore-faito.log
check "Faito's files are its backup's: a" is "$(on_host 'docker exec faito.files ls -1A /srv' | paste -sd' ')" a
check "Hurura'a's containers, rows, files and backups are as they were, after Faito's restore" \
  is "$(hururaa_state)" "$before"
as faito ls-hururaa.log "ls $BACKUP_ROOT/hururaa/"
check "Faito's account can't list $BACKUP_ROOT/hururaa/" refused ls-hururaa.log
for wanted in "$hururaa_stamp" "$BACKUP_ROOT/hururaa/$hururaa_stamp" "../hururaa/$hururaa_stamp" ..; do
  as faito restore-refused.log "sudo c4-app restore '$wanted' --yes"
  check "Faito's restore of $wanted is refused, saying there is no such backup of faito" \
    eval 'refused restore-refused.log && says restore-refused.log "c4-app: no backup " && says restore-refused.log " of faito"'
done
check "Hurura'a's containers, rows, files and backups are as they were, after the refused restores" \
  is "$(hururaa_state)" "$before"

# AC-06
check "Turu deployed with turu.yml (nothing declared)" deployed turu turu.yml
old=$(on_host 'date -u -d "8 days ago" +%Y%m%d-%H%M%S')
recent=$(on_host 'date -u -d "6 days ago" +%Y%m%d-%H%M%S')
check "stamps 8 days old ($old) and 6 days old ($recent) planted in Faito's backups" \
  on_host 'install -d -m 0750 -o root -g faito "$1/$2" "$1/$3"' "$BACKUP_ROOT/faito" "$old" "$recent"
check "$CRON is 0644 root:root, at 03:45, as root: /usr/local/sbin/c4-app nightly" \
  is "$(on_host 'stat -c "%a %U:%G" "$1" && grep -v "^#" "$1"' "$CRON" | paste -sd' ')" \
  "644 root:root 45 3 * * * root /usr/local/sbin/c4-app nightly"
faito_before=$(latest faito)
hururaa_before=$(latest hururaa)
check "its command, run as root, exits 0" on_host "$(on_host 'sed -n "s/^45 3 \* \* \* root //p" "$1"' "$CRON")"
check "Faito gets a new stamp" eval '[[ $(latest faito) > $faito_before ]]'
check "Hurura'a gets a new stamp" eval '[[ $(latest hururaa) > $hururaa_before ]]'
log() { on_host 'cat "$1/$2/backup.log"' "$BACKUP_ROOT" "$1"; }
check "Faito's log names its backup, between a dated header and its exit status" \
  eval '[[ $(log faito) == "== "*" nightly backup of faito"*"c4-app: backup $(latest faito) of faito: "*"== exit 0" ]]'
check "Turu's log says it declares nothing" eval 'log turu | grep -qF "c4-app: turu declares no data to back up"'
check "Tickee's log says it has no container" eval 'log tickee | grep -qF "c4-app: tickee has no container"'
check "each log is 0640 root:<app>" \
  is "$(on_host 'cd "$1" && stat -c "%a %U:%G" faito/backup.log hururaa/backup.log turu/backup.log tickee/backup.log' "$BACKUP_ROOT" | paste -sd' ')" \
  "640 root:faito 640 root:hururaa 640 root:turu 640 root:tickee"
check "the stamp 8 days old is removed, the 6 days old kept" \
  eval 'stamps faito > "$work/stamps" && ! grep -qx "$old" "$work/stamps" && grep -qx "$recent" "$work/stamps"'
as faito nightly-faito.log "sudo c4-app nightly"
check "Faito's sudo c4-app nightly is refused" refused nightly-faito.log
check "it says it is root's cron's" says nightly-faito.log "c4-app: nightly is root's cron's"
finish
