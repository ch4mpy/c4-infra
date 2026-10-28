#!/usr/bin/env bash
# 0033: a dump or a restore step cut by its time limit is stopped where it runs, on a stand-in demo
# host (accounts faito and hururaa, a tmpfs of 20 GiB at /var/backups/c4-apps), the limits read from
# /etc/c4-app/limits (ITEM_TIMEOUT=15, RESTORE_TIMEOUT=15). Each command a cut should end runs under the
# test's bound (the limit plus 90 s); what the code before the fix leaves is then cleaned up
# (tests/fixtures/0033/devices.sh), after the case's checks:
#
#   - IV-05: a group-writable limits file, ITEM_TIMEOUT=0, then ITEM_TIMEOUT=$(touch /tmp/limits-ran):
#     each refuses the backup, naming the file; nothing is written, /tmp/limits-ran doesn't exist;
#   - AC-01: Faito (data.yml) with a session of its own, psql named pg_dump, holding ACCESS EXCLUSIVE on
#     item: the backup exits 1 within 75 s, saying db.dump didn't end within 15 s and what it stopped;
#     faito.db runs no pg_dump, its database holds Faito's session only, Faito's psql runs; no stamp,
#     no .partial, nothing holds Faito's lock; once that session has ended, the next backup doesn't
#     wait and exits 0;
#   - AC-06: across AC-01's cut, Hurura'a's containers (StartedAt) and its own session named pg_dump
#     (its pid) are unchanged;
#   - AC-04: a copy of a backup whose db.dump is a FIFO opened but never written: its restore exits 1
#     within 75 s, naming reading db.dump whole and 15 s; faito.db runs no pg_restore; the rows, the
#     files, the backups (no safety backup) and the StartedAt of faito.files and faito.other unchanged;
#   - a copy whose db.dump is whole at its first opening and stalls at its second (RQ-02, restoring a
#     dump): its restore exits 1 within 75 s, naming restoring db.dump into faito.db and 15 s; no
#     pg_restore and no session of it left; faito.files and faito.other stopped, faito.db runs;
#     restoring the safety backup it names, then sudo c4-app up, bring the rows, the files and the
#     containers back.
#
#   bash tests/0033-dump-limits.stand-in.sh
#
# covers: demo/ registry.sh networks.sh tests/fixtures/0027/ tests/fixtures/0033/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0027
BACKUP_ROOT=/var/backups/c4-apps
BACKUPS=$BACKUP_ROOT/faito
LIMITS=/etc/c4-app/limits
LIMIT=15
BOUND=$((LIMIT + 90))
WITHIN=$((LIMIT + 60))

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

as() { # <account> <log> <command>: over ssh, its output into $work/<log>, its exit status into $status
  stand_in_ssh "$1" "$3" > "$work/$2" 2>&1
  status=$?
}
# <account> <log> <command>: the same, KILLed after $BOUND s; its duration into $took (the stand-in's clock)
as_bounded() {
  local start
  start=$(on_host 'date +%s')
  # shellcheck disable=SC2046 # the ssh command line: no space but between its words
  stand_in_exec timeout -s KILL "$BOUND" $(stand_in_ssh_command "$1") "$1@127.0.0.1" "$3" > "$work/$2" 2>&1
  status=$?
  took=$(($(on_host 'date +%s') - start))
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
doesnt_say() { # <log> <text>
  ! grep -qF -- "$2" "$work/$1" || { echo "output:"; tail -n 20 "$work/$1"; return 1; }
}
# the bounded command exited 1 within the limit plus 60 s
cut_in_time() { # <log>
  [ "$status" -eq 1 ] && [ "$took" -le "$WITHIN" ] \
    || { echo "exit $status after $took s (bound $BOUND s):"; tail -n 20 "$work/$1"; return 1; }
}
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
on_host() { # <script> [<arg>…]: bash -c <script> in the stand-in, as root, the devices sourced
  local script=$1
  shift
  stand_in_exec bash -c ". /root/devices.sh 2> /dev/null; $script" sh "$@" | tr -d '\r'
}
sql() { on_host 'docker exec "$1" psql -X -U fixture-user -d fixture-db -Atc "$2"' "${2:-faito.db}" "$1"; }
started() { on_host 'docker inspect -f "{{.State.StartedAt}}" "$1"' "$1"; }
state() { # <container>…: running or not, each
  local name
  for name in "$@"; do
    echo "$name $(on_host 'docker inspect -f "{{.State.Running}}" "$1"' "$name")"
  done | paste -sd' '
}
entries() { on_host 'ls -1A "$1" 2> /dev/null' "$BACKUPS" | paste -sd' '; }
stamps() { on_host 'ls -1A "$1"' "$BACKUPS" | grep -E '^[0-9]{8}-[0-9]{6}$'; }
latest() { stamps | LC_ALL=C sort | tail -n 1; }
rows() { sql "select string_agg(name, ',' order by name) from item"; }
files() { on_host 'docker exec faito.files ls -1A /srv' | paste -sd' '; }
# faito.db's processes named <comm>
in_faito_db() { on_host 'docker top faito.db -eo pid,comm | awk -v comm="$1" '\''$2 == comm { print $1 }'\''' "$1"; }
# the sessions of fixture-db on faito.db, but this query's: their pids
sessions() { sql "select coalesce(string_agg(pid::text, ' ' order by pid), '') from pg_stat_activity where datname = 'fixture-db' and pid <> pg_backend_pid()"; }
limits() { # <mode> <line>…: $LIMITS, root's, with that mode
  on_host 'mode=$1 file=$2
    shift 2
    install -d -m 0755 -o root -g root "${file%/*}" && printf "%s\n" "$@" > "$file" && chown root:root "$file" && chmod "$mode" "$file"' \
    "$1" "$LIMITS" "${@:2}"
}
copy_of() { # <stamp> <new stamp>: a copy of that backup
  on_host 'cp -a "$1/$2" "$1/$3"' "$BACKUPS" "$1" "$2"
}
freed() { on_host 'free_faito'; }
# RQ-04: nothing holds Faito's lock once the cut command has ended (the processes holding it named)
lock_free() {
  on_host 'flock -n /var/lib/c4-apps/.faito.lock true' && return 0
  echo "held by: $(on_host 'for pid in $(find /proc/[0-9]*/fd -lname /var/lib/c4-apps/.faito.lock 2> /dev/null | cut -d/ -f3 | sort -u); do cat "/proc/$pid/comm"; done' | paste -sd' ')"
  return 1
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito, hururaa), the shared stack deployed as c4-infra" stand_in_accounts faito hururaa
check "a tmpfs of 20 GiB at $BACKUP_ROOT" \
  on_host 'install -d -m 0755 "$1" && mount -t tmpfs -o size=20g,mode=0755 tmpfs "$1"' "$BACKUP_ROOT"
check "the test's devices are in the stand-in (/root/devices.sh)" \
  eval 'stand_in_exec -i sh -c "cat > /root/devices.sh" < tests/fixtures/0033/devices.sh'

# Hurura'a, with a session of its own named pg_dump
deployed() { # <account> <fixture>: sent as ~<account>/<account>/compose.yml, then sudo c4-app up
  stand_in_ssh -i "$1" "cat > ~/$1/compose.yml" < "$FIXTURES/$2" || return 1
  as "$1" "up-$1.log" "sudo c4-app up"
  exited_0 "up-$1.log"
}
check "Hurura'a deployed with hururaa.yml" deployed hururaa hururaa.yml
check "a row r1 in hururaa.db" sql "create table item (name text primary key); insert into item values ('r1')" hururaa.db
check "a session of Hurura'a's own, named pg_dump, runs pg_sleep" \
  on_host 'docker exec -d -e PGAPPNAME=pg_dump hururaa.db psql -U fixture-user -d fixture-db -c "select pg_sleep(3600)"'
hururaa_session() { sql "select coalesce(string_agg(pid::text, ' '), '') from pg_stat_activity where application_name = 'pg_dump'" hururaa.db; }
for _ in $(seq 50); do [ -n "$(hururaa_session)" ] && break; sleep 0.2; done
hururaa_pid=$(hururaa_session)
check "its session ($hururaa_pid)" eval '[[ $hururaa_pid =~ ^[0-9]+$ ]]'
hururaa_state() { echo "$(started hururaa.db) $(started hururaa.files) session $(hururaa_session)"; }

# Faito
check "data.yml is deployed as Faito's" deployed faito data.yml
check "rows r1 and r2 in faito.db" sql "create table item (name text primary key); insert into item values ('r1'), ('r2')"
check "a file a in faito.files' volume" on_host 'docker exec faito.files sh -c "echo a > /srv/a"'

# IV-05
refuses_limits() { # <log> <what it says> <mode> <line>
  local before
  before=$(entries)
  limits "$3" "$4" || return 1
  as faito "$1" "sudo c4-app backup"
  refused "$1" && says "$1" "$2" && is "$(entries)" "$before"
}
check "a group-writable $LIMITS (0664): the backup refused, naming it, nothing written" \
  refuses_limits limits-mode.log "c4-app: $LIMITS" 0664 "ITEM_TIMEOUT=$LIMIT"
check "ITEM_TIMEOUT=0: the backup refused, naming the file and the line, nothing written" \
  refuses_limits limits-zero.log "c4-app: $LIMITS, line 1: 'ITEM_TIMEOUT=0'" 0644 "ITEM_TIMEOUT=0"
# shellcheck disable=SC2016 # the very text the file holds
check "ITEM_TIMEOUT=\$(touch /tmp/limits-ran): the backup refused, naming the file and the line, nothing written" \
  refuses_limits limits-shell.log "c4-app: $LIMITS, line 1: " 0644 'ITEM_TIMEOUT=$(touch /tmp/limits-ran)'
check "and /tmp/limits-ran doesn't exist" on_host '[ ! -e /tmp/limits-ran ]'
check "$LIMITS: ITEM_TIMEOUT=$LIMIT, RESTORE_TIMEOUT=$LIMIT (0644 root:root)" \
  limits 0644 "# the tests' limits" "ITEM_TIMEOUT=$LIMIT" "RESTORE_TIMEOUT=$LIMIT"
as faito backup.log "sudo c4-app backup"
check "sudo c4-app backup exits 0" exited_0 backup.log
good=$(latest)
check "it writes a stamp ($good): db.dump and files.files_data.tar" \
  is "$(on_host 'ls -1A "$1"' "$BACKUPS/$good" | LC_ALL=C sort | paste -sd' ')" "db.dump files.files_data.tar"

# AC-01, AC-06
check "a session of Faito's own (psql, named pg_dump) holds item ACCESS EXCLUSIVE" \
  on_host 'docker exec -d -e PGAPPNAME=pg_dump faito.db psql -U fixture-user -d fixture-db -c "begin; lock table item in access exclusive mode; select pg_sleep(3600)"'
holder_session() { sql "select coalesce(string_agg(pid::text, ' '), '') from pg_stat_activity where application_name = 'pg_dump' and wait_event = 'PgSleep'"; }
for _ in $(seq 50); do [ -n "$(holder_session)" ] && break; sleep 0.2; done
holder=$(holder_session)
holder_psql=$(in_faito_db psql)
check "its session ($holder) and its psql ($holder_psql)" eval '[[ $holder =~ ^[0-9]+$ && $holder_psql =~ ^[0-9]+$ ]]'
hururaa_before=$(hururaa_state)
before=$(entries)
as_bounded faito backup-cut.log "sudo c4-app backup"
check "sudo c4-app backup exits 1 within $WITHIN s ($took s)" cut_in_time backup-cut.log
check "it says db.dump didn't end within $LIMIT s, and what it stopped" \
  says backup-cut.log "c4-app: db.dump didn't end within $LIMIT s: stopped ("
check "faito.db runs no pg_dump" is "$(in_faito_db pg_dump)" ""
check "fixture-db holds Faito's own session only ($holder)" is "$(sessions)" "$holder"
check "Faito's psql still runs ($holder_psql)" is "$(in_faito_db psql)" "$holder_psql"
check "no stamp, no .partial: the backups as they were" is "$(entries)" "$before"
check "Hurura'a's containers (StartedAt) and its session named pg_dump are as they were" is "$(hururaa_state)" "$hururaa_before"
check "nothing holds Faito's lock" lock_free
freed
check "Faito's session ends" sql "select pg_terminate_backend($holder)"
for _ in $(seq 50); do [ -z "$(in_faito_db psql)" ] && break; sleep 0.2; done
as faito backup-next.log "sudo c4-app backup"
check "the next backup exits 0" exited_0 backup-next.log
check "it doesn't wait for another c4-app command" doesnt_say backup-next.log "waiting for another"

# AC-04
never=$(on_host 'date -u -d "1 hour ago" +%Y%m%d-%H%M%S')
check "a copy of backup $good ($never), its db.dump a FIFO opened but never written" \
  eval 'copy_of "$good" "$never" && on_host "fifo held \"\$1\" db.dump" "$BACKUPS/$never"'
before="$(rows) $(files) $(entries) $(started faito.files) $(started faito.other)"
as_bounded faito restore-never.log "sudo c4-app restore $never --yes"
check "its restore exits 1 within $WITHIN s ($took s)" cut_in_time restore-never.log
check "the FIFO was opened (the device worked)" on_host '[ -e /root/opened ]'
check "it says reading db.dump whole didn't end within $LIMIT s, and what it stopped" \
  says restore-never.log "c4-app: restore of backup $never: reading db.dump whole didn't end within $LIMIT s: stopped ("
check "faito.db runs no pg_restore" is "$(in_faito_db pg_restore)" ""
check "nothing changed: the rows, the files, the backups (no safety backup), faito.files' and faito.other's StartedAt" \
  is "$(rows) $(files) $(entries) $(started faito.files) $(started faito.other)" "$before"
check "nothing holds Faito's lock" lock_free
freed
on_host 'rm -rf "$1/$2"' "$BACKUPS" "$never"

# RQ-02: a dump's restore cut
stalls=$(on_host 'date -u -d "2 hours ago" +%Y%m%d-%H%M%S')
check "a copy of backup $good ($stalls), its db.dump whole at its first opening, stalled at its second" \
  eval 'copy_of "$good" "$stalls" && on_host "fifo served \"\$1\" db.dump" "$BACKUPS/$stalls"'
as_bounded faito restore-stalls.log "sudo c4-app restore $stalls --yes"
check "its restore exits 1 within $WITHIN s ($took s)" cut_in_time restore-stalls.log
check "db.dump was opened twice (the device worked)" on_host '[ -e /root/served ]'
check "it says restoring db.dump into faito.db didn't end within $LIMIT s, and what it stopped" \
  says restore-stalls.log "c4-app: restore of backup $stalls: restoring db.dump into faito.db didn't end within $LIMIT s: stopped ("
check "faito.db runs no pg_restore" is "$(in_faito_db pg_restore)" ""
check "fixture-db holds no session" is "$(sessions)" ""
check "faito.files and faito.other stay stopped, faito.db runs" \
  is "$(state faito.files faito.other faito.db)" "faito.files false faito.other false faito.db true"
safety=$(latest)
check "it names the safety backup ($safety) and how to put it back" \
  says restore-stalls.log "sudo c4-app restore $safety --yes, then sudo c4-app up"
check "nothing holds Faito's lock" lock_free
freed
on_host 'docker stop faito.files faito.other > /dev/null'
as faito restore-back.log "sudo c4-app restore $safety --yes"
check "sudo c4-app restore $safety --yes exits 0" exited_0 restore-back.log
as faito up-back.log "sudo c4-app up"
check "then sudo c4-app up: the rows r1,r2 and the file a are back, the three containers run" \
  eval 'exited_0 up-back.log && is "$(rows) $(files) $(state faito.db faito.files faito.other)" "r1,r2 a faito.db true faito.files true faito.other true"'
on_host 'rm -rf "$1/$2"' "$BACKUPS" "$stalls"
finish
