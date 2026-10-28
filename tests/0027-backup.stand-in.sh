#!/usr/bin/env bash
# 0027: `sudo c4-app backup` and `restore` on a stand-in demo host, a tmpfs of 20 GiB at
# /var/backups/c4-apps:
#
#   - AC-01: Faito deployed with tests/fixtures/0027/data.yml (db labelled postgres, files labelled
#     volumes, other declaring nothing), rows r1 r2 and a file a: the backup writes a new stamp with
#     db.dump (pg_restore reads it) and files.files_data.tar (it lists a), names faito_cache as not
#     backed up; pg_isready answers throughout, faito.db isn't restarted, faito.files is and runs;
#     the modes are 0750 and 0640 root:faito, Faito's account reads its backup and can't delete it;
#   - AC-02: r3 and a file b added; `restore <stamp>` without --yes refused, nothing changed; with
#     --yes, the rows and files are the backup's (b gone), faito.db not restarted, the three
#     containers running, and a newer stamp holds the state before (r3 in its dump, b in its tar);
#     `restore` alone lists both stamps; a restore that fails once it has begun (a stamp planted with
#     db.dump cut short) starts the containers again and names the backup of the state before, which
#     restores them;
#   - AC-04: relabelled.yml in ~faito/faito/, not deployed, then refused.yml refused by up: each
#     backup holds the items that run, and /var/lib/c4-apps/faito/ and .run.faito/ stay as they were;
#   - AC-05: label-rsync.yml, then label-injection.yml ('postgres;id') deployed: the backup is
#     refused, naming the service and the value, nothing written;
#   - AC-07: slow-up.yml's up running, a backup waits for it, saying so, its stamp no earlier than
#     up's end;
#   - AC-08: the tmpfs remounted at 4 GiB, under the floor: the backup is refused, naming the free
#     space and the floor, the earlier stamps kept, no .partial left, the containers running; so is
#     `restore <stamp> --yes`, the containers still running.
#
#   bash tests/0027-backup.stand-in.sh
#
# covers: demo/ registry.sh networks.sh tests/fixtures/0027/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0027
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
send() { # <fixture file>: as ~faito/faito/compose.yml, over ssh as faito
  stand_in_ssh -i faito "cat > ~/faito/compose.yml" < "$1"
}
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
on_host() { # <script> [<arg>…]: bash -c <script> in the stand-in, as root
  local script=$1
  shift
  stand_in_exec bash -c "$script" sh "$@" | tr -d '\r'
}
sql() { on_host 'docker exec faito.db psql -U fixture-user -d fixture-db -Atc "$1"' "$1"; }
started() { on_host 'docker inspect -f "{{.State.StartedAt}}" "$1"' "$1"; }
runs() { # <container>…
  local name
  for name in "$@"; do
    is "$name $(on_host 'docker inspect -f "{{.State.Running}}" "$1"' "$name")" "$name true" || return 1
  done
}
# what the backup directory holds, every entry
entries() { on_host 'ls -1A "$1"' "$BACKUPS"; }
stamps() { entries | grep -E '^[0-9]{8}-[0-9]{6}$'; }
latest() { stamps | LC_ALL=C sort | tail -n 1; }
holds() { # <stamp> <files…>
  is "$(on_host 'ls -1A "$1"' "$BACKUPS/$1" | LC_ALL=C sort | paste -sd' ')" "${*:2}"
}
rows() { sql "select string_agg(name, ',' order by name) from item"; }
files() { on_host 'docker exec faito.files ls -1A /srv' | paste -sd' '; }
changed() { sql "insert into item values ('r3')" && on_host 'docker exec faito.files sh -c "echo b > /srv/b"'; }
# what root's compose mounts and runs, staged by c4-app up: every file, with its checksum
staged() { on_host 'cd /var/lib/c4-apps && find faito .run.faito -type f -exec cksum {} + | LC_ALL=C sort'; }

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito
check "a tmpfs of 20 GiB at $BACKUP_ROOT" \
  on_host 'install -d -m 0755 "$1" && mount -t tmpfs -o size=20g,mode=0755 tmpfs "$1"' "$BACKUP_ROOT"

# AC-01
check "data.yml is sent as ~faito/faito/compose.yml" send "$FIXTURES/data.yml"
as_faito up.log "sudo c4-app up"
check "sudo c4-app up exits 0" exited_0 up.log
check "rows r1 and r2 in faito.db" sql "create table item (name text primary key); insert into item values ('r1'), ('r2')"
check "a file a in faito.files' volume" on_host 'docker exec faito.files sh -c "echo a > /srv/a"'
db_started=$(started faito.db)
files_started=$(started faito.files)
# pg_isready every 0.2 s, in the stand-in, until /root/ready.stop
on_host 'rm -f /root/ready.log /root/ready.stop
  while [ ! -e /root/ready.stop ]; do
    if docker exec faito.db pg_isready -q -h 127.0.0.1; then echo ok; else echo KO; fi >> /root/ready.log
    sleep 0.2
  done' &
ready_loop=$!
sleep 2
as_faito backup.log "sudo c4-app backup"
on_host 'touch /root/ready.stop'
wait "$ready_loop"
check "sudo c4-app backup exits 0" exited_0 backup.log
first=$(latest)
check "it writes a new stamp ($first)" test -n "$first"
check "it says so, naming db.dump and files.files_data.tar" \
  eval 'says backup.log "c4-app: backup $first of faito: db.dump (" && says backup.log "), files.files_data.tar ("'
check "the stamp holds db.dump and files.files_data.tar only" holds "$first" db.dump files.files_data.tar
check "pg_restore --list reads db.dump: the table item" \
  on_host 'docker exec -i faito.db pg_restore --list < "$1/db.dump" | grep -q "TABLE public item"' "$BACKUPS/$first"
check "files.files_data.tar lists a" on_host 'tar -tf "$1/files.files_data.tar" | grep -qx "./a"' "$BACKUPS/$first"
check "pg_isready answered throughout the backup (no KO, some ok)" \
  is "$(on_host 'grep -c KO /root/ready.log; grep -c ok /root/ready.log | sed "s/^[1-9][0-9]*$/some/"' | paste -sd' ')" "0 some"
check "faito.db wasn't restarted" is "$(started faito.db)" "$db_started"
check "faito.files was restarted" test "$(started faito.files)" != "$files_started"
check "faito.files, faito.db and faito.other run" runs faito.files faito.db faito.other
check "faito_cache is named as not backed up" says backup.log "c4-app: not backed up: faito_cache"
check "$BACKUPS and the stamp: 0750 root:faito; its files 0640 root:faito" \
  is "$(on_host 'cd "$1" && stat -c "%a %U:%G" . "$2" "$2/db.dump" "$2/files.files_data.tar"' "$BACKUPS" "$first" | paste -sd' ')" \
  "750 root:faito 750 root:faito 640 root:faito 640 root:faito"
check "Faito's account reads its backup" stand_in_ssh faito "cat $BACKUPS/$first/db.dump $BACKUPS/$first/files.files_data.tar > /dev/null"
check "Faito's account can't delete it" eval \
  '! stand_in_ssh faito "rm -f $BACKUPS/$first/db.dump $BACKUPS/$first/files.files_data.tar; rm -rf $BACKUPS/$first" && holds "$first" db.dump files.files_data.tar'

# AC-02
check "r3 is added to faito.db, b to faito.files' volume" changed
check "the rows are r1,r2,r3, the files a b" is "$(rows) $(files)" "r1,r2,r3 a b"
before="$(entries | paste -sd' ') $(started faito.db) $(started faito.files)"
as_faito restore-unconfirmed.log "sudo c4-app restore $first"
check "sudo c4-app restore $first, without --yes, is refused" refused restore-unconfirmed.log
check "it says how" says restore-unconfirmed.log "sudo c4-app restore $first --yes"
check "it changed nothing: the rows, the files, the backups, the containers" \
  is "$(rows) $(files) $(entries | paste -sd' ') $(started faito.db) $(started faito.files)" "r1,r2,r3 a b $before"
db_started=$(started faito.db)
as_faito restore.log "sudo c4-app restore $first --yes"
check "sudo c4-app restore $first --yes exits 0" exited_0 restore.log
check "the rows are the backup's: r1,r2" is "$(rows)" r1,r2
check "the files are the backup's: a, b gone" is "$(files)" a
check "faito.db wasn't restarted" is "$(started faito.db)" "$db_started"
check "faito.db, faito.files and faito.other run" runs faito.db faito.files faito.other
safety=$(latest)
check "a newer stamp ($safety) holds the state before: r3 in its dump" eval \
  '[[ $safety > $first ]] && on_host "docker exec -i faito.db pg_restore -a -f - < \"\$1/db.dump\" | grep -qx r3" "$BACKUPS/$safety"'
check "and b in its tar" on_host 'tar -tf "$1/files.files_data.tar" | grep -qx ./b' "$BACKUPS/$safety"
check "it says so" says restore.log "c4-app: backup $first of faito restored; the state before it is backup $safety"
as_faito restore-list.log "sudo c4-app restore"
check "sudo c4-app restore alone lists both stamps" \
  eval 'exited_0 restore-list.log && says restore-list.log "  $first  " && says restore-list.log "  $safety  "'
broken=$(on_host 'date -u -d "1 hour ago" +%Y%m%d-%H%M%S')
check "a backup $broken planted, $first's with db.dump cut short" \
  on_host 'cp -a "$1/$2" "$1/$3" && truncate -s 100 "$1/$3/db.dump"' "$BACKUPS" "$first" "$broken"
as_faito restore-broken.log "sudo c4-app restore $broken --yes"
check "its restore fails" refused restore-broken.log
before_broken=$(latest)
check "it names the backup of the state before ($before_broken)" \
  says restore-broken.log "the state before it is backup $before_broken (sudo c4-app restore $before_broken --yes)"
check "faito.db, faito.files and faito.other run again" runs faito.db faito.files faito.other
as_faito restore-back.log "sudo c4-app restore $before_broken --yes"
check "restoring that backup puts the rows and files back: r1,r2 a" \
  eval 'exited_0 restore-back.log && is "$(rows) $(files)" "r1,r2 a"'
on_host 'rm -rf "$1/$2"' "$BACKUPS" "$broken"

# AC-04
check "relabelled.yml is sent as compose.yml, not deployed" send "$FIXTURES/relabelled.yml"
before=$(staged)
as_faito backup-relabelled.log "sudo c4-app backup"
check "the backup exits 0" exited_0 backup-relabelled.log
second=$(latest)
check "it holds what runs: db.dump, files.files_data.tar ($second)" \
  eval '[ "$second" != "$first" ] && holds "$second" db.dump files.files_data.tar'
check "/var/lib/c4-apps/faito/ and .run.faito/ are as they were" is "$(staged)" "$before"
check "refused.yml (a published port) is sent as compose.yml" send "$FIXTURES/refused.yml"
as_faito up-refused.log "sudo c4-app up"
check "sudo c4-app up is refused" refused up-refused.log
check "it says why" says up-refused.log "c4-app: refused: service other: published ports (7080)"
before=$(staged)
as_faito backup-refused.log "sudo c4-app backup"
check "the backup exits 0" exited_0 backup-refused.log
third=$(latest)
check "it holds what runs: db.dump, files.files_data.tar ($third)" \
  eval '[ "$third" != "$second" ] && holds "$third" db.dump files.files_data.tar'
check "/var/lib/c4-apps/faito/ and .run.faito/ are as they were, after the refused up" is "$(staged)" "$before"

# AC-05
refuses_label() { # <fixture> <log> <message>
  local before
  send "$FIXTURES/$1" || return 1
  as_faito "up-$2" "sudo c4-app up"
  exited_0 "up-$2" || return 1
  before=$(entries)
  as_faito "$2" "sudo c4-app backup"
  refused "$2" && says "$2" "$3" && is "$(entries)" "$before"
}
check "label-rsync.yml deployed: the backup refused, naming service files and rsync, nothing written" \
  refuses_label label-rsync.yml backup-rsync.log "c4-app: service files: c4-infra.backup 'rsync': postgres or volumes"
check "label-injection.yml deployed: the backup refused, naming service files and postgres;id, nothing written" \
  refuses_label label-injection.yml backup-injection.log "c4-app: service files: c4-infra.backup 'postgres\;id': postgres or volumes"

# AC-07
check "slow-up.yml is sent as compose.yml" send "$FIXTURES/slow-up.yml"
stand_in_ssh faito 'sudo c4-app up > ~/up-slow.log 2>&1; echo $? > ~/up-slow.status; date -u +%Y%m%d-%H%M%S > ~/up-slow.end' &
slow_up=$!
# up holds the lock once it creates faito.slow, 15 s before it is healthy
for _ in $(seq 120); do
  on_host 'docker inspect faito.slow > /dev/null 2>&1' && break
  sleep 0.5
done
as_faito backup-waits.log "sudo c4-app backup"
wait "$slow_up"
check "sudo c4-app up of slow-up.yml exits 0" is "$(on_host 'cat /home/faito/up-slow.status')" 0
check "the backup, started meanwhile, exits 0" exited_0 backup-waits.log
check "it says it waits" says backup-waits.log "c4-app: waiting for another c4-app command of faito (600 s at most)"
up_end=$(on_host 'cat /home/faito/up-slow.end')
check "its stamp ($(latest)) is no earlier than up's end ($up_end)" eval '[[ ! "$(latest)" < "$up_end" ]]'
check "data.yml is deployed again" eval 'send "$FIXTURES/data.yml" && as_faito up-again.log "sudo c4-app up" && exited_0 up-again.log'

# AC-08
check "the tmpfs remounted at 4 GiB" on_host 'mount -o remount,size=4g "$1"' "$BACKUP_ROOT"
before=$(entries)
files_started=$(started faito.files)
as_faito backup-floor.log "sudo c4-app backup"
check "the backup is refused" refused backup-floor.log
check "it names the free space and the floor" \
  eval 'says backup-floor.log "GiB free on $BACKUP_ROOT, under the floor of 5.0GiB"'
check "the earlier stamps stay, no .partial left" is "$(entries)" "$before"
check "faito.files wasn't stopped, and the containers run" \
  eval 'is "$(started faito.files)" "$files_started" && runs faito.db faito.files faito.other'
as_faito restore-floor.log "sudo c4-app restore $first --yes"
check "sudo c4-app restore $first --yes is refused" refused restore-floor.log
check "it names the free space and the floor" \
  eval 'says restore-floor.log "GiB free on $BACKUP_ROOT, under the floor of 5.0GiB"'
check "faito.files wasn't stopped, and the containers run, after the restore" \
  eval 'is "$(started faito.files)" "$files_started" && runs faito.db faito.files faito.other'
check "the tmpfs remounted at 20 GiB" on_host 'mount -o remount,size=20g "$1"' "$BACKUP_ROOT"
finish
