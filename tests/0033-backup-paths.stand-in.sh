#!/usr/bin/env bash
# 0033: the three backup paths 0027's review round only read, on a stand-in demo host (account faito, a
# tmpfs of 20 GiB at /var/backups/c4-apps):
#
#   - AC-07: no-volume.yml (bare, labelled volumes, mounts a tmpfs and no named volume): the backup is
#     refused, naming service bare, and changes nothing (the backups, every container's StartedAt); a
#     restore of an earlier backup is refused the same way, and changes nothing (the rows, the files
#     too);
#   - AC-08: shared-volume.yml (db, labelled postgres, and files, labelled volumes, both mount shared):
#     the backup holds exactly db.dump, files.files_data.tar and files.shared.tar; faito.db and
#     faito.files were restarted (StartedAt) and run; once the rows and both volumes' files change, the
#     restore brings them back, every container running;
#   - AC-09: layers.yml (l1, l2, l3, each healthy 5 s after its start, l2 service_healthy on l1, l3 on
#     l2): after a restore, l2 started at least 4 s after l1 and l3 at least 4 s after l2, each of them
#     restarted and running.
#
#   bash tests/0033-backup-paths.stand-in.sh
#
# covers: demo/ registry.sh networks.sh tests/fixtures/0027/ tests/fixtures/0033/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

BACKUP_ROOT=/var/backups/c4-apps
BACKUPS=$BACKUP_ROOT/faito

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

as_faito() { # <log> <command>: over ssh as faito, its output into $work/<log>, its exit status into $status
  stand_in_ssh faito "$2" > "$work/$1" 2>&1
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
deployed() { # <fixture>: sent as ~faito/faito/compose.yml, then sudo c4-app up
  stand_in_ssh -i faito "cat > ~/faito/compose.yml" < "$1" || return 1
  as_faito "up-${1##*/}.log" "sudo c4-app up"
  exited_0 "up-${1##*/}.log"
}
sql() { on_host 'docker exec faito.db psql -X -U fixture-user -d fixture-db -Atc "$1"' "$1"; }
rows() { sql "select string_agg(name, ',' order by name) from item"; }
listed() { on_host 'docker exec faito.files ls -1A "$1"' "$1" | paste -sd' '; }
# each container's name and StartedAt, the start in seconds
starts() { on_host 'docker ps -aq --filter label=com.docker.compose.project=faito | xargs -r docker inspect -f "{{.Name}} {{.State.StartedAt}}" | LC_ALL=C sort'; }
started_s() { on_host 'date -d "$(docker inspect -f "{{.State.StartedAt}}" "$1")" +%s' "$1"; }
runs() { # <container>…
  local name
  for name in "$@"; do
    is "$name $(on_host 'docker inspect -f "{{.State.Running}}" "$1"' "$name")" "$name true" || return 1
  done
}
entries() { on_host 'ls -1A "$1"' "$BACKUPS" | paste -sd' '; }
stamps() { on_host 'ls -1A "$1"' "$BACKUPS" | grep -E '^[0-9]{8}-[0-9]{6}$'; }
latest() { stamps | LC_ALL=C sort | tail -n 1; }
holds() { # <stamp> <files…>
  is "$(on_host 'ls -1A "$1"' "$BACKUPS/$1" | LC_ALL=C sort | paste -sd' ')" "${*:2}"
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito
check "a tmpfs of 20 GiB at $BACKUP_ROOT" \
  on_host 'install -d -m 0755 "$1" && mount -t tmpfs -o size=20g,mode=0755 tmpfs "$1"' "$BACKUP_ROOT"
check "data.yml is deployed as Faito's" deployed tests/fixtures/0027/data.yml
check "rows r1 and r2 in faito.db" sql "create table item (name text primary key); insert into item values ('r1'), ('r2')"
check "a file a in faito.files' volume" on_host 'docker exec faito.files sh -c "echo a > /srv/a"'
as_faito backup.log "sudo c4-app backup"
check "sudo c4-app backup exits 0" exited_0 backup.log
first=$(latest)

# AC-07
check "no-volume.yml is deployed (bare, labelled volumes, a tmpfs, no named volume)" deployed tests/fixtures/0033/no-volume.yml
NO_VOLUME="c4-app: service bare is declared volumes but mounts no named volume of faito: refused"
before="$(entries) $(starts)"
as_faito backup-bare.log "sudo c4-app backup"
check "sudo c4-app backup is refused, naming service bare" eval 'refused backup-bare.log && says backup-bare.log "$NO_VOLUME"'
check "nothing changed: the backups, every container's StartedAt" is "$(entries) $(starts)" "$before"
before="$(rows) $(listed /srv) $(entries) $(starts)"
as_faito restore-bare.log "sudo c4-app restore $first --yes"
check "sudo c4-app restore $first --yes is refused the same way" eval 'refused restore-bare.log && says restore-bare.log "$NO_VOLUME"'
check "nothing changed: the rows, the files, the backups, every container's StartedAt" \
  is "$(rows) $(listed /srv) $(entries) $(starts)" "$before"

# AC-08
check "shared-volume.yml is deployed (db and files both mount shared)" deployed tests/fixtures/0033/shared-volume.yml
check "a file s in shared" on_host 'docker exec faito.files sh -c "echo s > /shared/s"'
db_started=$(started_s faito.db)
files_started=$(started_s faito.files)
sleep 1
as_faito backup-shared.log "sudo c4-app backup"
check "sudo c4-app backup exits 0" exited_0 backup-shared.log
shared=$(latest)
check "its stamp ($shared) holds exactly db.dump, files.files_data.tar and files.shared.tar" \
  holds "$shared" db.dump files.files_data.tar files.shared.tar
check "faito.db and faito.files were restarted, and run" \
  eval '[ "$(started_s faito.db)" != "$db_started" ] && [ "$(started_s faito.files)" != "$files_started" ] && runs faito.db faito.files'
check "r3 added, b in files_data, t in shared" \
  eval 'sql "insert into item values ('\''r3'\'')" && on_host "docker exec faito.files sh -c \"echo b > /srv/b && echo t > /shared/t\""'
as_faito restore-shared.log "sudo c4-app restore $shared --yes"
check "sudo c4-app restore $shared --yes exits 0" exited_0 restore-shared.log
check "the rows (r1,r2), files_data's files (a) and shared's (s) are the backup's" \
  is "$(rows) $(listed /srv) $(listed /shared)" "r1,r2 a s"
check "faito.db and faito.files run" runs faito.db faito.files

# AC-09
check "layers.yml is deployed (l1, l2 on l1 healthy, l3 on l2 healthy)" deployed tests/fixtures/0033/layers.yml
as_faito backup-layers.log "sudo c4-app backup"
check "sudo c4-app backup exits 0" exited_0 backup-layers.log
layers=$(latest)
l1=$(started_s faito.l1) l2=$(started_s faito.l2) l3=$(started_s faito.l3)
as_faito restore-layers.log "sudo c4-app restore $layers --yes"
check "sudo c4-app restore $layers --yes exits 0" exited_0 restore-layers.log
l1_again=$(started_s faito.l1) l2_again=$(started_s faito.l2) l3_again=$(started_s faito.l3)
check "each of l1, l2, l3 was restarted ($l1 $l2 $l3, then $l1_again $l2_again $l3_again)" \
  eval '[ "$l1_again" -gt "$l1" ] && [ "$l2_again" -gt "$l2" ] && [ "$l3_again" -gt "$l3" ]'
check "l2 started at least 4 s after l1 ($((l2_again - l1_again)) s), l3 at least 4 s after l2 ($((l3_again - l2_again)) s)" \
  eval '[ $((l2_again - l1_again)) -ge 4 ] && [ $((l3_again - l2_again)) -ge 4 ]'
check "every container runs" runs faito.db faito.files faito.other faito.l1 faito.l2 faito.l3
finish
