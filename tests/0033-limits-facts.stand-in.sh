#!/usr/bin/env bash
# 0033: the facts the backups' time limits are built on (plan, step 0), on a bare stand-in demo host
# (no account, no stack), as root; the database is compose.yml's image (keycloak-db's), its user
# fact-user, its table item held ACCESS EXCLUSIVE by a session of its own (psql, named holder):
#
#   (a) a dump through docker exec waits for that lock, its CLI cut by timeout (TERM, then KILL):
#       pg_dump still runs in the container (docker top), its session still waits (Lock);
#   (b) ps is in the stand-in; docker top -eo pid gives host PIDs whose environ root reads; PGAPPNAME,
#       passed by docker exec -e PGAPPNAME from the CLI's environment, is in the exec'd processes'
#       environment and is the application_name of pg_dump's, pg_restore's and psql's sessions;
#   (c) pg_terminate_backend of the sessions bearing the marker, as POSTGRES_USER on the local socket,
#       ends the waiting session within 2 s; kill -KILL of the marked PID of an exec'd pg_dump (its
#       parent outside the container) ends it within 2 s and its CLI exits, while its session still
#       waits; a TERMed pg_dump's session ends by itself; a session named pg_dump and the holder,
#       unmarked, are untouched. A pg_dump orphaned into the container's first process (postgres, its
#       sh parent killed): ended through its session, it exits 1 and nothing else changes; KILLed,
#       the server takes it for a crash of its own and ends every session (the holder's too);
#   (d) a throwaway container's tar, its PID 1, ignores the TERM its CLI proxies: timeout without
#       --kill-after waits; paused, with --kill-after=5, timeout returns 137 and the container stays;
#       docker rm -f of the cidfile's id removes it, running or paused, within 5 s;
#   (e) a stub for c4-app, run as the nightly runs it (timeout --kill-after=60 20 runuser … sudo -n,
#       vps-bootstrap.sh's rule pointed at it), holding a lock on fd 9: its item in the background (fd
#       9 closed) and waited for, its TERM trap runs within 2 s of the limit, the item is stopped, the
#       lock is free (the TERMs it gets are printed); its item in the foreground, no trap runs before
#       the nightly's timeout returns, and the item is still alive afterwards, holding the lock (how
#       and when that timeout returns is printed);
#   (f) a FIFO in place of a backup's file, served by a background job's redirection: whole at its
#       first opening, stalled at its second, through docker exec -i and docker run -i; a throwaway's
#       copy of 2 GiB paused at its start by a docker events watcher (filtered by the image's id; a
#       file it writes, polled): the window (the unpaused copy's duration) is at least 5 times the
#       pause's latency (both printed, with the bytes copied before the pause).
#
#   bash tests/0033-limits-facts.stand-in.sh
#
# covers: compose.yml tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

IMAGE=$(sed -n '/^  keycloak-db:/,/^  [a-z]/s/^    image: //p' compose.yml)
FACTS=/root/facts
trap stand_in_down EXIT

is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
# in the stand-in, as root, with $FACTS/lib.sh sourced: bash -c <script> with <args>
on_host() { # <script> [<arg>…]
  local script=$1
  shift
  stand_in_exec bash -c ". $FACTS/lib.sh; $script" sh "$@" | tr -d '\r'
}
image_there() {
  stand_in_exec docker image inspect "$IMAGE" > /dev/null 2>&1 \
    || stand_in_exec docker pull -q "$IMAGE" > /dev/null 2>&1 \
    || stand_in_load_image "$IMAGE"
}

# The stand-in's side: c4-app's constants as the plan has them, and the facts' helpers
LIB=$(cat <<'EOF'
FACTS=/root/facts
DUMP='exec pg_dump --lock-wait-timeout=120s -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" -Fc'
SESSIONS='maintenance=postgres
[ "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" != postgres ] || maintenance=template1
exec psql -X -q -At -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-postgres}" -d "$maintenance" -v marker="$1"'
THROWAWAY=(--rm --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE
  --cap-add FOWNER --cap-add FSETID --security-opt no-new-privileges --log-driver none)
IMG=$(cat "$FACTS/image-id" 2> /dev/null)
sql() { docker exec facts-db psql -X -U fact-user -d fact-db -Atc "$1"; }
named() { sql "select count(*) from pg_stat_activity where application_name = '$1'"; }
waiting() { sql "select count(*) from pg_stat_activity where application_name = '$1' and wait_event_type = 'Lock'"; }
# the host PIDs of facts-db's processes whose environment holds the entry PGAPPNAME=<marker>
marked() {
  local pid
  for pid in $(docker top facts-db -eo pid | tail -n +2); do
    grep -qzxF "PGAPPNAME=$1" "/proc/$pid/environ" 2> /dev/null && echo "$pid"
  done
}
comms() { local pid; for pid in "$@"; do cat "/proc/$pid/comm" 2> /dev/null; done | paste -sd' '; }
# the host PIDs of facts-db's processes named <comm>
running() { docker top facts-db -eo pid,comm | awk -v comm="$1" '$2 == comm { print $1 }'; }
# whether each PID's parent is facts-db's first process (postgres), or outside the container
parents() {
  local pid init
  init=$(docker inspect -f '{{.State.Pid}}' facts-db)
  for pid in "$@"; do
    if [ "$(ps -o ppid= -p "$pid" | tr -d ' ')" = "$init" ]; then echo "$(cat "/proc/$pid/comm"):postgres"; else echo "$(cat "/proc/$pid/comm"):other"; fi
  done | paste -sd' '
}
terminate() {
  echo "select count(*) filter (where pg_terminate_backend(pid)) from pg_stat_activity where application_name = :'marker';" \
    | docker exec -i facts-db sh -c "$SESSIONS" sh "$1"
}
within() { # <seconds> <command…>: until it succeeds, polled every 0.1 s
  local tries=$(($1 * 10))
  shift
  until "$@"; do
    tries=$((tries - 1))
    [ "$tries" -gt 0 ] || return 1
    sleep 0.1
  done
}
none_marked() { [ -z "$(marked "$1")" ]; }
no_session() { [ "$(named "$1")" = 0 ]; }
waits() { [ "$(waiting "$1")" = 1 ]; }
gone() { ! kill -0 "$1" 2> /dev/null; }
no_container() { ! docker inspect "$1" > /dev/null 2>&1; }
orphan_of() { [ "$(parents $(marked "$1"))" = pg_dump:postgres ]; }
# a dump marked <marker> (<script>: $DUMP, exec'd, by default) in the background, waiting for the lock;
# its CLI's PID in $FACTS/<marker>.cli
dump_marked() { # <marker> [<script>]
  PGAPPNAME=$1 docker exec -e PGAPPNAME facts-db sh -c "${2:-$DUMP}" > /dev/null 2>&1 &
  echo $! > "$FACTS/$1.cli"
  within 10 waits "$1"
}
# <fifo> <source>: whole at its first opening; at its second, all but its last 100 bytes, then held open
serve() {
  cat "$2" > "$1"
  while find /proc/[0-9]*/fd -lname "$1" 2> /dev/null | grep -q .; do sleep 0.1; done
  { head -c -100 "$2"; exec sleep 600; } > "$1"
}
EOF
)

check "the stand-in host starts" stand_in_up
check "$IMAGE (compose.yml's keycloak-db) is in the stand-in's Docker" image_there
check "$FACTS/lib.sh is written" eval \
  'stand_in_exec mkdir -p "$FACTS" && stand_in_exec -i sh -c "cat > $FACTS/lib.sh" <<< "$LIB" \
    && stand_in_exec sh -c "docker image inspect -f {{.Id}} $IMAGE > $FACTS/image-id"'
echo "# the stand-in's $(on_host 'docker version -f "Docker {{.Server.Version}}"; sudo -V | head -n 1; bash --version | head -n 1; runuser --version' | paste -sd, -)"
database_runs() {
  on_host 'umask 022
    head -c 16 /dev/urandom | od -An -tx1 | tr -d " \n" > "$FACTS/password"
    docker run -d --name facts-db -e POSTGRES_USER=fact-user -e POSTGRES_DB=fact-db \
      -e POSTGRES_PASSWORD_FILE=/run/secrets/password -v "$FACTS/password:/run/secrets/password:ro" "$1" > /dev/null
    within 60 docker exec facts-db pg_isready -q -h 127.0.0.1 || { docker logs --tail 10 facts-db; exit 1; }
    within 10 eval "sql \"select 1\" > /dev/null"' "$IMAGE"
}
check "a database runs (facts-db), POSTGRES_USER fact-user, POSTGRES_DB fact-db, its password in a file" database_runs
check "a table item holds r1 and r2, dumped to $FACTS/db.dump" \
  on_host 'sql "create table item (name text primary key); insert into item values ('\''r1'\''), ('\''r2'\'')" > /dev/null \
    && docker exec facts-db pg_dump -U fact-user -d fact-db -Fc > "$FACTS/db.dump"'
holder_holds() {
  on_host 'docker exec -d -e PGAPPNAME=holder facts-db psql -U fact-user -d fact-db -c "begin; lock table item in access exclusive mode; select pg_sleep(3600)" \
    && within 10 eval "[ \"\$(sql \"select wait_event from pg_stat_activity where application_name = '\''holder'\''\")\" = PgSleep ]"'
}
check "the holder (psql, named holder) holds item ACCESS EXCLUSIVE" holder_holds
check "a session named pg_dump runs pg_sleep (psql, exec'd without a marker)" \
  on_host 'docker exec -d -e PGAPPNAME=pg_dump facts-db psql -U fact-user -d fact-db -c "select pg_sleep(3600)" \
    && within 10 eval "[ \"\$(named pg_dump)\" = 1 ]"'
psqls() { on_host 'docker top facts-db -eo pid,comm | awk "\$2 == \"psql\" { print \$1 }" | LC_ALL=C sort | paste -sd" "'; }
the_psqls=$(psqls)
check "two psql run in facts-db: the holder's and pg_dump's namesake ($the_psqls)" eval '[[ $the_psqls =~ ^[0-9]+\ [0-9]+$ ]]'

# (a)
# the unmarked dumps of (a), ended once measured: their sessions, then their processes (exec'd)
end_unmarked() {
  on_host 'sql "select count(pg_terminate_backend(pid)) from pg_stat_activity where application_name = '\''pg_dump'\'' and wait_event_type = '\''Lock'\''" > /dev/null
    within 5 eval "[ \"\$(waiting pg_dump)\" = 0 ]" && within 5 eval "[ -z \"\$(running pg_dump)\" ]"'
}
for signal in TERM KILL; do
  expected=124
  [ "$signal" = TERM ] || expected=137
  code=$(on_host 'timeout --kill-after=5 -s "$1" 5 docker exec facts-db sh -c "$DUMP" > /dev/null 2>&1; echo $?' "$signal")
  check "(a) timeout -s $signal 5 ends the dump's docker exec CLI: $code" is "$code" "$expected"
  check "(a) once its CLI is ended, docker top facts-db still lists pg_dump" \
    on_host '[ -n "$(running pg_dump)" ]'
  check "(a) and its session still waits for the lock (named pg_dump, wait_event_type Lock)" \
    is "$(on_host 'waiting pg_dump')" 1
  check "(a) that pg_dump and its session ended (the test's cleanup)" end_unmarked
done

# (b)
check "(b) ps is in the stand-in" on_host 'command -v ps'
check "(b) docker top facts-db -eo pid gives host PIDs whose environ root reads" \
  on_host 'n=0; for pid in $(docker top facts-db -eo pid | tail -n +2); do head -c 1 "/proc/$pid/environ" > /dev/null || exit 1; n=$((n + 1)); done; [ "$n" -gt 0 ]'
marker() { echo "c4-app.fact.$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"; }
m1=$(marker)
check "(b) a dump marked $m1 (PGAPPNAME=… docker exec -e PGAPPNAME, sh -c 'exec pg_dump …') waits for the lock" \
  on_host 'dump_marked "$1"' "$m1"
m1_parents=$(on_host 'parents $(marked "$1")' "$m1")
check "(b) facts-db's processes whose environment holds PGAPPNAME=$m1, and their parent: $m1_parents" is "$m1_parents" "pg_dump:other"
check "(b) its session's application_name is the marker, waiting for the lock" is "$(on_host 'waiting "$1"' "$m1")" 1
m2=$(marker)
check "(b) a pg_restore --data-only -t item marked $m2 waits for the lock: its session bears the marker" \
  on_host 'PGAPPNAME=$1 docker exec -i -e PGAPPNAME facts-db pg_restore --data-only -t item -U fact-user -d fact-db < "$FACTS/db.dump" > /dev/null 2>&1 &
    within 10 waits "$1"' "$m2"
m3=$(marker)
check "(b) a psql marked $m3: its session's application_name is the marker" \
  is "$(on_host 'PGAPPNAME=$1 docker exec -e PGAPPNAME facts-db psql -X -U fact-user -d fact-db -Atc "select application_name from pg_stat_activity where pid = pg_backend_pid()"' "$m3")" "$m3"

# (c)
check "(c) pg_terminate_backend of the sessions bearing $m1, as POSTGRES_USER on the local socket, ends 1" \
  is "$(on_host 'terminate "$1"' "$m1")" 1
check "(c) its session is gone within 2 s" on_host 'within 2 no_session "$1"' "$m1"
echo "# (c) its pg_dump, once its session is ended: $(on_host 'if within 2 none_marked "$1"; then echo "ends by itself within 2 s"; else echo "still runs: $(comms $(marked "$1"))"; fi' "$m1")"
m4=$(marker)
check "(c) a dump marked $m4 waits for the lock" on_host 'dump_marked "$1"' "$m4"
check "(c) kill -KILL of the PID marked $m4 ($(on_host 'parents $(marked "$1")' "$m4")): none left within 2 s" \
  on_host 'marked "$1" | xargs -r kill -KILL; within 2 none_marked "$1"' "$m4"
check "(c) and its docker exec CLI exits within 2 s" on_host 'within 2 gone "$(cat "$FACTS/$1.cli")"' "$m4"
sleep 3
check "(c) 3 s later, the KILLed pg_dump's session still waits for the lock" is "$(on_host 'waiting "$1"' "$m4")" 1
check "(c) pg_terminate_backend of the sessions bearing $m4 ends it within 2 s" \
  on_host '[ "$(terminate "$1")" = 1 ] && within 2 no_session "$1"' "$m4"
m5=$(marker)
check "(c) a dump marked $m5 waits for the lock" on_host 'dump_marked "$1"' "$m5"
check "(c) kill -TERM of its marked PID: its session ends by itself within 2 s (pg_dump's cancel)" \
  on_host 'marked "$1" | xargs -r kill -TERM; within 2 no_session "$1"' "$m5"
on_host 'terminate "$1" > /dev/null; marked "$1" | xargs -r kill -KILL; within 2 no_session "$1"' "$m2"
check "(c) the holder and pg_dump's namesake keep their sessions" \
  is "$(on_host 'named holder; named pg_dump' | paste -sd' ')" "1 1"
check "(c) and their psql processes ($the_psqls)" is "$(psqls)" "$the_psqls"
NOT_EXECD='pg_dump --lock-wait-timeout=120s -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" -Fc'
# the sh of a dump marked <marker> (not exec'd) KILLed: its pg_dump orphaned into facts-db's first process
orphaned() { # <marker>
  on_host 'dump_marked "$1" "$2" || exit 1
    for pid in $(marked "$1"); do [ "$(cat "/proc/$pid/comm")" != sh ] || kill -KILL "$pid"; done
    within 2 orphan_of "$1"' "$1" "$NOT_EXECD"
}
m6=$(marker)
check "(c) a dump marked $m6, its sh KILLed: its pg_dump is orphaned into postgres" orphaned "$m6"
check "(c) its session ended: the orphan is gone within 2 s" \
  on_host '[ "$(terminate "$1")" = 1 ] && within 2 none_marked "$1"' "$m6"
check "(c) and the holder keeps its session; the server logged the orphan's end: $(on_host 'docker logs --tail 5 facts-db 2>&1 | grep -o "untracked child process.*"')" \
  eval 'is "$(on_host "named holder")" 1 && on_host "docker logs --tail 5 facts-db 2>&1 | grep -q \"untracked child process (PID [0-9]*) exited with exit code 1\""'
m7=$(marker)
check "(c) a dump marked $m7, its sh KILLed: its pg_dump is orphaned into postgres" orphaned "$m7"
check "(c) KILLed, that orphan ends every session of the server within 5 s, the holder's too" \
  on_host 'marked "$1" | xargs -r kill -KILL; within 5 eval "[ \"\$(named holder 2> /dev/null)\" = 0 ]"' "$m7"
echo "# (c) the server's log: $(on_host 'docker logs --tail 40 facts-db 2>&1 | grep -E "untracked child process|terminating any other|reinitializing" | cut -d" " -f4- | paste -sd"|" -')"
check "(c) the server is back within 30 s" on_host 'within 30 eval "sql \"select 1\" > /dev/null 2>&1"'

# (d)
# a throwaway's tar -tf - fed by a FIFO a background sleep holds open, paused once running if asked,
# under timeout <options>: 12 s later, timeout's status if it ended, and whether the container is there
throwaway_held() { # <name> run|pause <timeout option>…
  on_host 'name=$1 then=$2
    shift 2
    rm -f "$FACTS/$name.in" "$FACTS/$name.cid" "$FACTS/$name.status"
    mkfifo "$FACTS/$name.in"
    sleep 600 > "$FACTS/$name.in" &
    echo $! > "$FACTS/$name.writer"
    (timeout "$@" docker run -i --cidfile "$FACTS/$name.cid" "${THROWAWAY[@]}" --entrypoint tar "$IMG" -tf - \
      < "$FACTS/$name.in" > /dev/null 2>&1; echo $? > "$FACTS/$name.status") > /dev/null 2>&1 &
    within 4 eval "[ \"\$(docker inspect -f {{.State.Running}} \"\$(cat \"\$FACTS/\$name.cid\" 2> /dev/null)\" 2> /dev/null)\" = true ]"
    [ "$then" != pause ] || docker pause "$(cat "$FACTS/$name.cid")" > /dev/null
    sleep 12
    if [ -e "$FACTS/$name.status" ]; then echo "ended $(cat "$FACTS/$name.status")"; else echo "timeout waits"; fi
    docker inspect -f "{{.State.Status}}" "$(cat "$FACTS/$name.cid")" 2>&1' "$@" | paste -sd' '
}
removed() { # <name>: docker rm -f of its cidfile's id, the container gone within 5 s
  on_host 'id=$(cat "$FACTS/$1.cid")
    start=$(date +%s%N)
    docker rm -f "$id" > /dev/null || exit 1
    within 5 no_container "$id" || exit 1
    echo "# removed in $((($(date +%s%N) - start) / 1000000)) ms"
    kill "$(cat "$FACTS/$1.writer")" 2> /dev/null; true' "$1"
}
check "(d) timeout 5 around a throwaway's tar (PID 1), 12 s later: timeout waits, the container runs" \
  is "$(throwaway_held d1 run 5)" "timeout waits running"
check "(d) docker rm -f of its cidfile's id: gone within 5 s" removed d1
echo "# (d) that timeout, once the container is gone: $(on_host 'within 5 test -e "$FACTS/d1.status" && cat "$FACTS/d1.status"')"
check "(d) paused, timeout --kill-after=5 5 around it, 12 s later: ended 137, the container still paused" \
  is "$(throwaway_held d2 pause --kill-after=5 5)" "ended 137 paused"
check "(d) docker rm -f of the paused container's id: gone within 5 s" removed d2
echo "# (d) running, its CLI KILLed: $(throwaway_held d3 run -s KILL 5) (the daemon closes its stdin: tar ends, --rm removes it)"

# (e)
STUB=$(cat <<'EOF'
#!/bin/bash
# c4-app's stand-in for fact (e): its item, in the background (fd 9 closed) or the foreground
exec 9> /var/lib/fact-e.lock
flock -n 9 || exit 3
log=/root/fact-e.log
item=
stop() {
  echo "term $(date +%s)" >> "$log"
  trap 'echo "term again $(date +%s)" >> "$log"' TERM
  if [ -n "$item" ]; then
    kill -TERM "$item"
    wait "$item"
  fi
  sleep 2
  echo "end $(date +%s)" >> "$log"
  exit 143
}
trap stop TERM
if [ "$1" = background ]; then
  timeout --kill-after=5 600 sh -c 'echo $$ > /root/fact-e.item; exec sleep 600' 9>&- &
  item=$!
  wait "$item"
else
  timeout --kill-after=5 600 sh -c 'echo $$ > /root/fact-e.item; exec sleep 600'
fi
EOF
)
stub_installed() {
  stand_in_exec -i sh -c "cat > /usr/local/sbin/c4-app-stub && chmod 0755 /usr/local/sbin/c4-app-stub" <<< "$STUB" || return 1
  stand_in_exec -i bash -c 'sed -n "s|^%c4-apps ALL=(root) NOPASSWD: /usr/local/sbin/c4-app\$|&-stub|p" > /tmp/stub-sudoers
    [ -s /tmp/stub-sudoers ] && visudo -cf /tmp/stub-sudoers > /dev/null && install -m 0440 /tmp/stub-sudoers /etc/sudoers.d/stub' \
    < demo/vps-bootstrap.sh
}
check "(e) an account created --groups c4-apps" \
  on_host 'groupadd c4-apps && useradd --create-home --shell /bin/bash --groups c4-apps fact-app'
check "(e) the stub, and vps-bootstrap.sh's rule pointed at it" stub_installed
# the stub run as the nightly runs c4-app: <its exit status> <seconds from the start to the stub's
# trap, or none> <seconds from the start to timeout's return>; what runuser and sudo said in $FACTS/e.err
nightly_stub() { # background | foreground
  on_host 'rm -f /root/fact-e.log /root/fact-e.item
    start=$(date +%s)
    timeout --kill-after=60 20 runuser -u fact-app -- sudo -n /usr/local/sbin/c4-app-stub "$1" < /dev/null > "$FACTS/e.err" 2>&1
    code=$?
    took=$(($(date +%s) - start))
    term=$(sed -n "s/^term \([0-9]*\)$/\1/p" /root/fact-e.log 2> /dev/null | head -n 1)
    if [ -n "$term" ]; then echo "$code $((term - start)) $took"; else echo "$code none $took"; fi' "$1"
}
result=$(nightly_stub background)
check "(e) the item in the background: the stub's trap runs within 2 s of the limit (exit, trap, end: $result)" \
  eval '[[ $result =~ ^[0-9]+\ (20|21|22)\ [0-9]+$ ]]'
echo "# (e) the stub's log: $(on_host 'cat /root/fact-e.log' | paste -sd, -); runuser and sudo said: $(on_host 'tr "\n" " " < "$FACTS/e.err"')"
check "(e) its item (sleep, pid $(on_host 'cat /root/fact-e.item')) is stopped" \
  on_host 'within 5 gone "$(cat /root/fact-e.item)"'
check "(e) once the stub has ended, flock -n takes its lock" \
  on_host 'within 5 eval "! pgrep -x c4-app-stub > /dev/null" && flock -n /var/lib/fact-e.lock true'
result=$(nightly_stub foreground)
check "(e) the item in the foreground: no trap runs before the nightly's timeout returns (exit, trap, end: $result)" \
  eval '[[ $result =~ ^[0-9]+\ none\ [0-9]+$ ]]'
echo "# (e) runuser and sudo said: $(on_host 'tr "\n" " " < "$FACTS/e.err"'); the stub, afterwards: $(on_host 'if pgrep -x c4-app-stub > /dev/null; then echo "still runs"; else echo gone; fi')"
check "(e) its item (sleep, pid $(on_host 'cat /root/fact-e.item')) is still alive" on_host '! gone "$(cat /root/fact-e.item)"'
check "(e) and holds the lock: flock -n fails" on_host '! flock -n /var/lib/fact-e.lock true'
on_host 'kill "$(cat /root/fact-e.item)"; within 10 eval "flock -n /var/lib/fact-e.lock true"'

# (f)
# <fifo> <source> pg_restore|tar: the reader's status at the FIFO's first opening, then at its second, cut after 10 s
fifo_read() {
  on_host 'fifo=$1 source=$2
    case $3 in
      pg_restore) reader=(docker exec -i facts-db pg_restore -f /dev/null) ;;
      tar) reader=(docker run -i "${THROWAWAY[@]}" --entrypoint tar "$IMG" -tf -) ;;
    esac
    rm -f "$fifo"
    mkfifo "$fifo"
    serve "$fifo" "$source" &
    writer=$!
    "${reader[@]}" < "$fifo" > /dev/null 2>&1
    echo "first $?"
    timeout --kill-after=2 10 "${reader[@]}" < "$fifo" > /dev/null 2>&1
    echo "second $?"
    kill "$writer"' "$@" | paste -sd' '
}
check "(f) a FIFO served for db.dump, read by docker exec -i facts-db pg_restore -f /dev/null: whole, then stalled" \
  is "$(fifo_read "$FACTS/f.dump" "$FACTS/db.dump" pg_restore)" "first 0 second 124"
on_host 'running pg_restore | xargs -r kill -KILL'
check "(f) a tar of 2 files is written" \
  on_host 'mkdir -p "$FACTS/f-src" && echo a > "$FACTS/f-src/a" && head -c 65536 /dev/urandom > "$FACTS/f-src/b" && tar -C "$FACTS/f-src" -cf "$FACTS/f.src.tar" .'
tar_read=$(fifo_read "$FACTS/f.tar" "$FACTS/f.src.tar" tar)
check "(f) a FIFO served for it, read by a throwaway's tar -tf - (docker run -i): whole, then stalled ($tar_read)" \
  eval '[[ $tar_read =~ ^first\ 0\ second\ 1(24|37)$ ]]'
on_host 'db=$(docker inspect -f "{{.Id}}" facts-db); docker ps -aq --no-trunc | grep -vx "$db" | xargs -r docker rm -f > /dev/null; true'
check "(f) a volume holds 2 GiB of random bytes" \
  on_host 'docker volume create facts-f > /dev/null && docker run --rm -v facts-f:/data --entrypoint sh "$IMG" -c "head -c 2147483648 /dev/urandom > /data/big"'
# shellcheck disable=SC2016 # expanded in the stand-in
COPY='docker run --cidfile "$FACTS/$1.cid" "${THROWAWAY[@]}" --mount type=volume,src=facts-f,dst=/data --entrypoint tar "$IMG" --sparse --numeric-owner -cpf - -C /data .'
window=$(on_host 'rm -f "$FACTS/$1.cid"; start=$(date +%s%N); '"$COPY"' < /dev/null | wc -c; echo $((($(date +%s%N) - start) / 1000000))' full | paste -sd' ')
echo "# (f) the unpaused copy: $window (bytes, then ms)"
# the watcher: docker events into a file (--until alone would replay the past ones), polled every 0.05 s
paused=$(on_host 'rm -f "$FACTS/$1.cid" "$FACTS/paused" "$FACTS/copy.out" "$FACTS/events"
  docker events --filter event=start --filter type=container --filter image="$IMG" --format "{{.Actor.ID}}" > "$FACTS/events" 2> /dev/null &
  events=$!
  (until [ -s "$FACTS/events" ]; do sleep 0.05; done
    docker pause "$(head -n 1 "$FACTS/events")" && date +%s%N > "$FACTS/paused") > /dev/null 2>&1 &
  sleep 1
  start=$(date +%s%N)
  '"$COPY"' < /dev/null > "$FACTS/copy.out" 2> /dev/null &
  if within 10 test -s "$FACTS/paused"; then
    sleep 1
    before=$(stat -c %s "$FACTS/copy.out")
    sleep 2
    echo "$((($(cat "$FACTS/paused") - start) / 1000000)) $before $(stat -c %s "$FACTS/copy.out") $(docker inspect -f "{{.State.Status}}" "$(cat "$FACTS/$1.cid")")"
  else
    echo "none"
  fi
  docker rm -f "$(cat "$FACTS/$1.cid")" > /dev/null
  kill "$events"' paused | paste -sd' ')
echo "# (f) paused at its start: $paused (ms from docker run to the pause; the bytes copied 1 s later, then 3 s later; its state)"
read -r latency before after state <<< "$paused"
check "(f) the pause landed (${latency} ms) and held: no byte copied while paused ($before, then $after, $state)" \
  eval '[[ $latency =~ ^[0-9]+$ ]] && [ "$before" = "$after" ] && [ "$state" = paused ]'
check "(f) the window (${window#* } ms) is at least 5 times the pause's latency (${latency} ms)" \
  eval '[[ $latency =~ ^[0-9]+$ ]] && [ "${window#* }" -ge $((5 * latency)) ]'
finish
