#!/usr/bin/env bash
# 0027: the facts the applications' backups are built on (plan, step 1), on a bare stand-in demo host
# (no account, no stack), as root, root's docker compose running a `config --format json` model as
# c4-app does; the database's image is compose.yml's (keycloak-db):
#
#   (a) a service whose labels set com.docker.compose.project and .service, and a volume whose labels
#       set the project: the container and the volume carry compose's own (-p, the service's name);
#   (b) `docker compose -p <p> stop`, then `start`, run from an empty directory: they act on the
#       project, and start honours depends_on (second starts once first is healthy); whether
#       `start --wait` exists is printed (E7);
#   (c) a hot `pg_dump -Fc` through docker exec, as a user with a hyphen, a session open, the password
#       in a file (the local socket is trusted); `DROP … WITH (FORCE)` and `CREATE … OWNER` from psql
#       variables on stdin, then `pg_restore --exit-on-error`: exit 0, the dump's rows (E4, E7);
#   (d) a cold copy of a named volume through E4's throwaway container (the database's image id,
#       --pull never, --network none, --read-only, --cap-drop ALL plus CHOWN DAC_OVERRIDE FOWNER
#       FSETID, no-new-privileges, --log-driver none), emptied and restored: its owners, modes, links
#       (not followed), hard links, fifo, empty directory, odd names and contents are the same; without
#       any one of the four capabilities, they aren't (MKNOD isn't needed: a fifo isn't a device);
#   (e) a tmpfs at /var/backups/c4-apps: `df -P -B1` gives its free space and size, 20 GiB, then 4 GiB
#       once remounted, its files kept; root's redirections write there; `df -P --output` is refused
#       (E6, E11); the stand-in's own disk is printed;
#   (f) `getent group c4-apps` lists an account created `--groups c4-apps`; `runuser -u <it> -- sudo -n
#       <stub>`, with no terminal and vps-bootstrap.sh's rule pointed at the stub, runs it as root
#       with SUDO_USER=<it> (E2).
#
#   bash tests/0027-backup-facts.stand-in.sh
#
# covers: tests/fixtures/0027/facts/ compose.yml tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0027/facts
FACTS=/root/facts
IMAGE=$(sed -n '/^  keycloak-db:/,/^  [a-z]/s/^    image: //p' compose.yml)
DATA=facts-d_data
BACKUPS=/var/backups/c4-apps
GIB=1073741824
trap stand_in_down EXIT

is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
# in the stand-in, as root: bash -c <script> with <args>; -i passes stdin, which the caller redirects
on_host() { # [-i] <script> [<arg>…]
  local options=() script
  if [ "$1" = -i ]; then
    options=(-i)
    shift
  fi
  script=$1
  shift
  stand_in_exec "${options[@]}" bash -c "$script" sh "$@" | tr -d '\r'
}
# the stand-in's own Docker pulls the image a deployment would; else this machine's copy
image_there() {
  stand_in_exec docker image inspect "$IMAGE" > /dev/null 2>&1 \
    || stand_in_exec docker pull -q "$IMAGE" > /dev/null 2>&1 \
    || stand_in_load_image "$IMAGE"
}
# root's compose on the model of <fixture>, read with config --format json, as c4-app runs it
compose_model() { # <project> <fixture>
  on_host 'cd "$4" && FACTS_IMAGE=$3 docker compose --project-directory "$4" -p "$1" -f "$2" config --format json > "$1.json" 2> "$1.log" \
    && docker compose --project-directory "$4" -p "$1" -f "$1.json" --env-file /dev/null up -d --wait > "$1.log" 2>&1 \
    || { tail -n 10 "$1.log"; exit 1; }' "$1" "$2" "$IMAGE" "$FACTS"
}

check "the stand-in host starts" stand_in_up
check "$IMAGE (compose.yml's keycloak-db) is in the stand-in's Docker" image_there
check "the fixtures are copied to $FACTS" eval \
  'stand_in_exec mkdir -p "$FACTS" /root/empty && tar -C "$FIXTURES" -cf - . | stand_in_exec -i tar -C "$FACTS" -xf - --no-same-owner'
echo "# the stand-in's $(on_host 'docker version -f "Docker {{.Server.Version}}"; docker compose version' | paste -sd, -)"

# (a)
check "(a) root's compose runs labels.yml's model as the project facts-a" compose_model facts-a labels.yml
check "(a) the model keeps the file's labels" \
  is "$(on_host 'jq -c ".services.forged.labels, .volumes.data.labels" "$1"' "$FACTS/facts-a.json" | paste -sd' ')" \
  '{"com.docker.compose.project":"other","com.docker.compose.service":"x"} {"com.docker.compose.project":"other"}'
check "(a) the container carries compose's project and service labels: facts-a forged" \
  is "$(on_host 'docker inspect -f "{{index .Config.Labels \"com.docker.compose.project\"}} {{index .Config.Labels \"com.docker.compose.service\"}}" facts-a-forged-1')" \
  "facts-a forged"
check "(a) the volume carries compose's project label: facts-a" \
  is "$(on_host 'docker volume inspect -f "{{index .Labels \"com.docker.compose.project\"}}" facts-a_data')" facts-a
check "(a) no container and no volume carries the project label other" \
  is "$(on_host 'docker ps -aq --filter label=com.docker.compose.project=other; docker volume ls -q --filter label=com.docker.compose.project=other')" ""

# (b)
statuses() { on_host 'docker inspect -f "{{.State.Status}}" facts-b-first-1 facts-b-second-1' | paste -sd' '; }
started() { on_host 'date -d "$(docker inspect -f "{{.State.StartedAt}}" "$1")" +%s' "$1"; }
check "(b) root's compose runs order.yml's model as the project facts-b" compose_model facts-b order.yml
check "(b) docker compose -p facts-b stop, from an empty directory, exits 0" \
  on_host 'cd /root/empty && docker compose -p facts-b stop > /dev/null 2>&1'
check "(b) it stopped both containers" is "$(statuses)" "exited exited"
check "(b) docker compose -p facts-b start, from an empty directory, exits 0" \
  on_host 'cd /root/empty && docker compose -p facts-b start > /dev/null 2>&1'
check "(b) both containers run" is "$(statuses)" "running running"
check "(b) second started once first was healthy (5 s after its start): depends_on honoured" \
  test "$(($(started facts-b-second-1) - $(started facts-b-first-1)))" -ge 4
echo "# (b) docker compose start --wait, on this compose: $(on_host 'cd /root/empty && docker compose -p facts-b start --wait 2>&1 | head -n 1; echo "exit ${PIPESTATUS[0]}"' | paste -sd' ')"

# (c)
DUMP='pg_dump -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" -Fc'
RECREATE='db=${POSTGRES_DB:-${POSTGRES_USER:-postgres}}
psql -q -v ON_ERROR_STOP=1 -U "${POSTGRES_USER:-postgres}" -d postgres -v db="$db" -v owner="${POSTGRES_USER:-postgres}"'
RESTORE='pg_restore --exit-on-error -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}"'
sql() { # <query>: its rows, as fact-user on fact-db
  on_host 'docker exec facts-db psql -U fact-user -d fact-db -Atc "$1"' "$1"
}
sessions() { sql "select count(*) from pg_stat_activity where datname = 'fact-db' and pid <> pg_backend_pid()"; }
session_open() {
  stand_in_exec docker exec -d facts-db psql -U fact-user -d fact-db -c 'select pg_sleep(600)' && sleep 1 && is "$(sessions)" 1
}
database_runs() {
  on_host 'umask 022
    head -c 16 /dev/urandom | od -An -tx1 | tr -d " \n" > "$2/password"
    docker run -d --name facts-db -e POSTGRES_USER=fact-user -e POSTGRES_DB=fact-db \
      -e POSTGRES_PASSWORD_FILE=/run/secrets/password -v "$2/password:/run/secrets/password:ro" "$1" > /dev/null
    for _ in $(seq 60); do
      docker exec facts-db pg_isready -q -h 127.0.0.1 && exit 0
      sleep 1
    done
    docker logs --tail 10 facts-db; exit 1' "$IMAGE" "$FACTS"
}
check "(c) a database runs, POSTGRES_USER fact-user, POSTGRES_DB fact-db, its password in a file" database_runs
check "(c) a table item holds r1 and r2" sql "create table item (name text primary key); insert into item values ('r1'), ('r2')"
check "(c) a session holds fact-db open" session_open
check "(c) the hot dump, through docker exec into root's file, exits 0" \
  on_host 'docker exec facts-db sh -c "$1" > "$2/db.dump"' "$DUMP" "$FACTS"
check "(c) pg_restore --list reads it: the table item" \
  on_host 'docker exec -i facts-db pg_restore --list < "$1/db.dump" | grep -q "TABLE public item"' "$FACTS"
check "(c) r3 is added after the dump" sql "insert into item values ('r3')"
check "(c) DROP … WITH (FORCE) and CREATE … OWNER, from psql variables on stdin, exit 0, the session open" \
  on_host 'printf "%s\n" "DROP DATABASE :\"db\" WITH (FORCE);" "CREATE DATABASE :\"db\" OWNER :\"owner\";" \
    | docker exec -i facts-db sh -c "$1"' "$RECREATE"
check "(c) the session was ended" is "$(sessions)" 0
check "(c) pg_restore --exit-on-error of the dump, on stdin, exits 0" \
  on_host 'docker exec -i facts-db sh -c "$1" < "$2/db.dump"' "$RESTORE" "$FACTS"
check "(c) the rows are the dump's: r1,r2" is "$(sql "select string_agg(name, ',' order by name) from item")" r1,r2
check "(c) fact-user owns the database and the table" \
  is "$(sql "select pg_get_userbyid(datdba) from pg_database where datname = 'fact-db'; select tableowner from pg_tables where tablename = 'item'" | paste -sd' ')" \
  "fact-user fact-user"

# (d)
# the volume's entries (name, owner, group, mode, type, links, target), then its files' checksums
LISTING='cd /data && find . -printf "%P|%U|%G|%m|%y|%n|%l\0" | LC_ALL=C sort -z | tr "\0" "\n"
  find . -type f -exec sha256sum {} + | LC_ALL=C sort'
listing() { on_host 'docker run --rm -v "$1:/data:ro" --entrypoint bash "$2" -c "$3"' "$DATA" "$IMAGE" "$LISTING"; }
filled() {
  on_host -i 'docker volume rm -f "$1" > /dev/null && docker volume create "$1" > /dev/null \
    && docker run --rm -i -v "$1:/data" --entrypoint bash "$2" -s' "$DATA" "$IMAGE" < "$FIXTURES/fill-volume.sh"
}
holds() { # <listing line>…
  local listed line
  listed=$(listing)
  for line in "$@"; do
    grep -qxF -- "$line" <<< "$listed" || { echo "no line $line in:"; echo "$listed"; return 1; }
  done
}
# E4's copy out, then the volume emptied and the copy put back, with these capabilities: create
# <status>, restore <status>, same or different
round_trip() { # <capability>…
  local before after
  before=$(listing)
  on_host 'data=$1 database=$2 facts=$3
    shift 3
    options=(--rm --pull never --network none --read-only --cap-drop ALL)
    for cap in "$@"; do options+=(--cap-add "$cap"); done
    options+=(--security-opt no-new-privileges --log-driver none --mount "type=volume,src=$data,dst=/data")
    image=$(docker inspect -f "{{.Image}}" "$database")
    docker run "${options[@]}" --entrypoint tar "$image" --numeric-owner -cpf - -C /data . > "$facts/data.tar" 2> /dev/null < /dev/null
    echo "create $?"
    docker run -i "${options[@]}" --entrypoint sh "$image" -c "find /data -mindepth 1 -delete && tar --numeric-owner -xpf - -C /data" \
      < "$facts/data.tar" > /dev/null 2>&1
    echo "restore $?"' "$DATA" facts-db "$FACTS" "$@" | paste -sd' '
  after=$(listing)
  if [ "$before" = "$after" ]; then echo same; else echo different; fi
}
FOUR=(CHOWN DAC_OVERRIDE FOWNER FSETID)
check "(d) a volume holds owners 999 and 70, modes 0700 and 2755, links, a hard-link pair, a fifo, odd names" eval \
  'filled && holds "|999|70|751|d|5|" "pg|999|999|700|d|2|" "shared|70|70|2755|d|2|" "empty|0|0|755|d|2|" \
    "relative-link|0|0|777|l|1|pg/file" "absolute-link|0|0|777|l|1|/etc/passwd" "hard-1|0|0|644|f|2|" \
    "hard-2|0|0|644|f|2|" "fifo|0|0|644|p|1|" "with space|0|0|644|f|1|" "-dash|0|0|644|f|1|" "new"'
check "(d) with ${FOUR[*]}: copied, emptied and restored, the same" is "$(round_trip "${FOUR[@]}" | paste -sd' ')" "create 0 restore 0 same"
for cap in "${FOUR[@]}"; do
  without=()
  for other in "${FOUR[@]}"; do [ "$other" = "$cap" ] || without+=("$other"); done
  result=$(filled > /dev/null && round_trip "${without[@]}" | paste -sd' ')
  check "(d) without $cap: not the same ($result)" test "$result" != "create 0 restore 0 same"
done
check "(d) the volume, filled again, restored with ${FOUR[*]}: the same" \
  is "$(filled > /dev/null && round_trip "${FOUR[@]}" | paste -sd' ')" "create 0 restore 0 same"

# (e)
free_and_size() { on_host 'df -P -B1 "$1" | awk "NR == 2 { print \$4, \$2 }"' "$BACKUPS"; }
echo "# (e) the stand-in's own disk, df -P -B1 /var/backups: $(on_host 'df -P -B1 /var/backups | awk "NR == 2 { print \"free \" \$4 \", size \" \$2 }"')"
check "(e) a tmpfs of 20 GiB is mounted at $BACKUPS" \
  on_host 'install -d -m 0755 "$1" && mount -t tmpfs -o size=20g,mode=0755 tmpfs "$1"' "$BACKUPS"
check "(e) df -P -B1: free $((20 * GIB)), size $((20 * GIB))" is "$(free_and_size)" "$((20 * GIB)) $((20 * GIB))"
check "(e) df -P --output is refused (-P and --output exclude each other)" \
  eval '! on_host "df -P -B1 --output=avail,size \"\$1\" > /dev/null 2>&1" "$BACKUPS"'
check "(e) root's redirection writes 1 MiB there" \
  on_host 'head -c 1048576 /dev/zero > "$1/probe" && [ "$(stat -c %s "$1/probe")" -eq 1048576 ]' "$BACKUPS"
check "(e) remounted at 4 GiB" on_host 'mount -o remount,size=4g "$1"' "$BACKUPS"
check "(e) df -P -B1: size $((4 * GIB)), free that less 1 MiB, under 5 GiB" \
  is "$(free_and_size)" "$((4 * GIB - 1048576)) $((4 * GIB))"
check "(e) the file written before is still there" on_host 'test -s "$1/probe"' "$BACKUPS"
on_host 'umount "$1"' "$BACKUPS"

# (f)
check "(f) an account created --groups c4-apps" \
  on_host 'groupadd c4-apps && useradd --create-home --shell /bin/bash --groups c4-apps fact-app'
check "(f) getent group c4-apps lists it" is "$(on_host 'getent group c4-apps | cut -d: -f4')" fact-app
check "(f) vps-bootstrap.sh's rule, pointed at a stub" on_host -i '
  printf "%s\n" "#!/bin/sh" "echo \"SUDO_USER=\$SUDO_USER uid=\$(id -u) \$(tty)\"" > /usr/local/sbin/c4-app-stub
  chmod 0755 /usr/local/sbin/c4-app-stub
  sed -n "s|^%c4-apps ALL=(root) NOPASSWD: /usr/local/sbin/c4-app\$|&-stub|p" > /tmp/stub-sudoers
  [ -s /tmp/stub-sudoers ] && visudo -cf /tmp/stub-sudoers > /dev/null && install -m 0440 /tmp/stub-sudoers /etc/sudoers.d/stub' \
  < demo/vps-bootstrap.sh
check "(f) runuser -u fact-app -- sudo -n, with no terminal: as root, SUDO_USER=fact-app" \
  is "$(on_host 'runuser -u fact-app -- sudo -n /usr/local/sbin/c4-app-stub < /dev/null')" "SUDO_USER=fact-app uid=0 not a tty"
finish
