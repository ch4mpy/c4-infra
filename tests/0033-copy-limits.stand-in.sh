#!/usr/bin/env bash
# 0033: a volume's copy, a refill or a nightly run cut by its time limit stops its throwaway container,
# on a stand-in demo host (account faito, a tmpfs of 20 GiB at /var/backups/c4-apps), the limits read
# from /etc/c4-app/limits. Each command a cut should end runs under the test's bound (the limit plus
# 90 s); what the code before the fix leaves is then cleaned up (tests/fixtures/0033/devices.sh),
# after the case's checks:
#
#   - AC-03 (ITEM_TIMEOUT=15, RESTORE_TIMEOUT=15): a copy of a backup whose files.files_data.tar is
#     whole at its first opening and stalls at its second: its restore exits 1 within 75 s, naming
#     refilling faito_files_data and 15 s; no throwaway left; faito.files and faito.other stopped,
#     faito.db runs; restoring the safety backup it names, then sudo c4-app up, bring the rows, the
#     files and the containers back;
#   - AC-02: 2 GiB in faito.files' volume, the copy's container paused at its start by a watcher (the
#     pause checked): the backup exits 1 within 75 s, naming files.files_data.tar and 15 s; no
#     container labelled c4-infra.c4-app, the paused one gone; faito.files runs; the backups as they
#     were; nothing holds Faito's lock; the next backup doesn't wait and exits 0;
#   - AC-05 (NIGHTLY_TIMEOUT=30, ITEM_TIMEOUT=600): the copy paused again, root's c4-app nightly ends
#     within 90 s; Faito's backup.log holds the cut's line, then == exit 124: stopped after 30 s;
#     Faito's containers run, no throwaway and no .partial left, nothing holds Faito's lock; the next
#     backup doesn't wait.
#
#   bash tests/0033-copy-limits.stand-in.sh
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
NIGHTLY=30

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

as() { # <account> <log> <command>: over ssh, its output into $work/<log>, its exit status into $status
  stand_in_ssh "$1" "$3" > "$work/$2" 2>&1
  status=$?
}
# <limit> <log> <command>: as faito over ssh, KILLed after <limit> + 90 s; its duration into $took
as_bounded() {
  local start
  start=$(on_host 'date +%s')
  # shellcheck disable=SC2046 # the ssh command line: no space but between its words
  stand_in_exec timeout -s KILL "$(($1 + 90))" $(stand_in_ssh_command faito) faito@127.0.0.1 "$3" > "$work/$2" 2>&1
  status=$?
  took=$(($(on_host 'date +%s') - start))
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
# the bounded command exited <status> within <seconds>
ended() { # <log> <status> <seconds>
  [ "$status" -eq "$2" ] && [ "$took" -le "$3" ] \
    || { echo "exit $status after $took s:"; tail -n 20 "$work/$1"; return 1; }
}
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
on_host() { # <script> [<arg>…]: bash -c <script> in the stand-in, as root, the devices sourced
  local script=$1
  shift
  stand_in_exec bash -c ". /root/devices.sh 2> /dev/null; $script" sh "$@" | tr -d '\r'
}
sql() { on_host 'docker exec faito.db psql -X -U fixture-user -d fixture-db -Atc "$1"' "$1"; }
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
limits() { # <line>…: $LIMITS, root's, 0644
  on_host 'file=$1
    shift
    install -d -m 0755 -o root -g root "${file%/*}" && printf "%s\n" "$@" > "$file" && chown root:root "$file" && chmod 0644 "$file"' \
    "$LIMITS" "$@"
}
# RQ-04: nothing holds Faito's lock once the cut command has ended (the processes holding it named)
lock_free() {
  on_host 'flock -n /var/lib/c4-apps/.faito.lock true' && return 0
  echo "held by: $(on_host 'for pid in $(find /proc/[0-9]*/fd -lname /var/lib/c4-apps/.faito.lock 2> /dev/null | cut -d/ -f3 | sort -u); do cat "/proc/$pid/comm"; done' | paste -sd' ')"
  return 1
}
no_throwaway() { is "$(on_host 'throwaways' | paste -sd' ')" ""; }
freed() { on_host 'free_faito'; }
# the 2 GiB out of the volume (into faito.files' own layer), or back: a mv, never a c4-app command
big_out() { on_host 'docker exec faito.files sh -c "[ ! -e /srv/big ] || mv /srv/big /tmp/big"'; }
big_in() { on_host 'docker exec faito.files sh -c "[ ! -e /tmp/big ] || mv /tmp/big /srv/big; [ -e /srv/big ]"'; }

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito
check "a tmpfs of 20 GiB at $BACKUP_ROOT" \
  on_host 'install -d -m 0755 "$1" && mount -t tmpfs -o size=20g,mode=0755 tmpfs "$1"' "$BACKUP_ROOT"
check "the test's devices are in the stand-in (/root/devices.sh)" \
  eval 'stand_in_exec -i sh -c "cat > /root/devices.sh" < tests/fixtures/0033/devices.sh'
check "data.yml is sent as ~faito/faito/compose.yml" \
  eval 'stand_in_ssh -i faito "cat > ~/faito/compose.yml" < "$FIXTURES/data.yml"'
as faito up.log "sudo c4-app up"
check "sudo c4-app up exits 0" exited_0 up.log
check "rows r1 and r2 in faito.db" sql "create table item (name text primary key); insert into item values ('r1'), ('r2')"
check "a file a in faito.files' volume" on_host 'docker exec faito.files sh -c "echo a > /srv/a"'
check "$LIMITS: ITEM_TIMEOUT=$LIMIT, RESTORE_TIMEOUT=$LIMIT" limits "ITEM_TIMEOUT=$LIMIT" "RESTORE_TIMEOUT=$LIMIT"
as faito backup.log "sudo c4-app backup"
check "sudo c4-app backup exits 0" exited_0 backup.log
good=$(latest)
check "it writes a stamp ($good): db.dump and files.files_data.tar" \
  is "$(on_host 'ls -1A "$1"' "$BACKUPS/$good" | LC_ALL=C sort | paste -sd' ')" "db.dump files.files_data.tar"

# AC-03
stalls=$(on_host 'date -u -d "1 hour ago" +%Y%m%d-%H%M%S')
check "a copy of backup $good ($stalls), its files.files_data.tar whole at its first opening, stalled at its second" \
  on_host 'cp -a "$1/$2" "$1/$3" && fifo served "$1/$3" files.files_data.tar' "$BACKUPS" "$good" "$stalls"
as_bounded "$LIMIT" restore-stalls.log "sudo c4-app restore $stalls --yes"
check "its restore exits 1 within $((LIMIT + 60)) s ($took s)" ended restore-stalls.log 1 $((LIMIT + 60))
check "files.files_data.tar was opened twice (the device worked)" on_host '[ -e /root/served ]'
check "it says refilling faito_files_data didn't end within $LIMIT s, and what it stopped" \
  says restore-stalls.log "c4-app: restore of backup $stalls: refilling faito_files_data didn't end within $LIMIT s: stopped ("
check "no throwaway container is left" no_throwaway
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

# AC-02
check "2 GiB of random bytes in faito.files' volume" \
  on_host 'docker exec faito.files dd if=/dev/urandom of=/srv/big bs=1M count=2048 2> /dev/null && [ "$(docker exec faito.files stat -c %s /srv/big)" = 2147483648 ]'
before=$(entries)
on_host 'watch_throwaway'
as_bounded "$LIMIT" backup-paused.log "sudo c4-app backup"
paused=$(on_host 'cat /root/paused 2> /dev/null; unwatch')
check "the copy's container was paused at its start (the device worked: $paused)" eval '[[ $paused =~ ^[0-9a-f]{64}$ ]]'
check "the backup exits 1 within $((LIMIT + 60)) s ($took s)" ended backup-paused.log 1 $((LIMIT + 60))
check "it says files.files_data.tar didn't end within $LIMIT s, and what it stopped" \
  says backup-paused.log "c4-app: files.files_data.tar didn't end within $LIMIT s: stopped ("
check "no container is labelled c4-infra.c4-app" is "$(on_host 'docker ps -aq --filter label=c4-infra.c4-app')" ""
check "the paused one is gone" on_host '! docker inspect "$1" > /dev/null 2>&1' "$paused"
check "faito.files runs again" is "$(state faito.files)" "faito.files true"
check "the backups are as they were" is "$(entries)" "$before"
check "nothing holds Faito's lock" lock_free
big_out
as_bounded "$LIMIT" backup-next.log "sudo c4-app backup"
check "the next backup exits 0" ended backup-next.log 0 $((LIMIT + 60))
check "it doesn't wait for another c4-app command" doesnt_say backup-next.log "waiting for another"
freed
check "the 2 GiB back in faito.files' volume" big_in

# AC-05
check "$LIMITS: NIGHTLY_TIMEOUT=$NIGHTLY, ITEM_TIMEOUT=600, RESTORE_TIMEOUT=$LIMIT" \
  limits "NIGHTLY_TIMEOUT=$NIGHTLY" "ITEM_TIMEOUT=600" "RESTORE_TIMEOUT=$LIMIT"
before=$(entries)
on_host 'watch_throwaway'
start=$(on_host 'date +%s')
on_host 'timeout -s KILL "$1" /usr/local/sbin/c4-app nightly' $((NIGHTLY + 90)) > "$work/nightly.log" 2>&1
took=$(($(on_host 'date +%s') - start))
paused=$(on_host 'cat /root/paused 2> /dev/null; unwatch')
check "the copy's container was paused at its start (the device worked: $paused)" eval '[[ $paused =~ ^[0-9a-f]{64}$ ]]'
check "root's c4-app nightly ends within $((NIGHTLY + 60)) s ($took s)" test "$took" -le $((NIGHTLY + 60))
night=$(on_host 'cat "$1/backup.log"' "$BACKUPS" | tr -d '\r')
check "Faito's backup.log holds the cut's line, then == exit 124: stopped after $NIGHTLY s" \
  eval '[[ $night == *"c4-app: stopped by a signal during files.files_data.tar: stopped ("*"== exit 124: stopped after $NIGHTLY s" ]] || { echo "$night" | tail -n 8; false; }'
check "Faito's containers run" \
  is "$(state faito.db faito.files faito.other)" "faito.db true faito.files true faito.other true"
check "no throwaway container is left" no_throwaway
check "no .partial: the backups as they were" is "$(entries | sed 's/ \{0,1\}backup.log//')" "$(sed 's/ \{0,1\}backup.log//' <<< "$before")"
check "nothing holds Faito's lock" lock_free
big_out
as_bounded "$LIMIT" backup-after.log "sudo c4-app backup"
check "the next backup exits 0" ended backup-after.log 0 $((LIMIT + 60))
check "it doesn't wait for another c4-app command" doesnt_say backup-after.log "waiting for another"
freed
finish
