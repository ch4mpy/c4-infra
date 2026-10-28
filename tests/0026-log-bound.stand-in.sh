#!/usr/bin/env bash
# 0026: on a stand-in demo host, every container an application starts through `sudo c4-app up`
# keeps a bounded log, the stack's own, whatever its compose file says (AC-01 to AC-05, AC-08):
#
#   - the accounts and the shared stack as docs/demo-setup.md prepares them (stand_in_accounts
#     faito); AC-05: each container of the project c4-infra has json-file 10m × 3;
#   - AC-02: tests/fixtures/0026/logging-*.yml (json-file without options, none, local with
#     options), each sent as ~faito/faito/compose.yml: `sudo c4-app up` and `pull` refused, naming the
#     service and the key, nothing started, no container of the project faito;
#   - AC-03: $BEFORE's c4-app (main's head before this change) installed, talker.yml comes up
#     unbounded (LogConfig's Config {}); the stack's demo/deploy.sh run again as c4-infra installs
#     this one (`c4-app installed`); `sudo c4-app up` with the same files: new containers, json-file
#     10m × 3 in their LogConfig and in the model, equal to c4-infra.keycloak's;
#   - AC-01: the talker's 60 MiB: its log files at most 3, each at most 10 MB (one entry over at
#     most); `docker logs` ends on its last line and lacks its first;
#   - AC-04: as c4-infra, `docker logs --tail 1 faito.talker` and, from ~,
#     `docker compose -p faito logs --tail 1 --no-log-prefix talker` show its last line;
#   - `sudo c4-app down`, then `up`: the containers bounded from their creation;
#   - AC-08: faito outside the docker group, `sudo -l` listing c4-app only, no container's bind mount
#     under /var/lib/docker nor of the Docker socket.
#
#   bash tests/0026-log-bound.stand-in.sh      (bash tests/run.sh --all runs it)
#
# The fixtures' image is the stand-in's caddy (the shared reverse proxy's).
#
# covers: demo/ compose.yml compose.demo.yml tests/fixtures/0026/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0026
# main's head at the plan's step 0: its c4-app refuses logging with the allowlist's line, and bounds nothing
BEFORE=75d2809
MODEL=/var/lib/c4-apps/.run.faito/model.json
BOUND='{"Type":"json-file","Config":{"max-file":"3","max-size":"10m"}}'
UNBOUNDED='{"Type":"json-file","Config":{}}'
REFUSAL='c4-app: refused: service talker: logging: the demo host bounds every container'"'"'s logs (README, "Accounts")'
FIRST_LINE='faito.talker: first line'
LAST_LINE='faito.talker: last line'
# Docker reads max-size 10m as 10 MB
MAX_SIZE=$((10 * 1000 * 1000))
# a json-file entry of the talker's 1 KiB lines, with its JSON, is under 2 KiB
ENTRY=2048

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

as() { # <log> <account> <command>: over ssh, its output into $work/<log>, its exit status into $status
  stand_in_ssh "$2" "$3" > "$work/$1" 2>&1
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
ends_with() { # <log> <line>
  [ "$(tail -n 1 "$work/$1" | tr -d '\r')" = "$2" ] || { echo "output:"; tail -n 5 "$work/$1"; return 1; }
}
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}
send() { # <fixture file>: as ~faito/faito/compose.yml, over ssh as faito
  stand_in_ssh -i faito "cat > ~/faito/compose.yml" < "$1"
}
no_container() {
  local found
  found=$(stand_in_exec docker ps -aq --filter label=com.docker.compose.project=faito | tr -d '\r')
  [ -z "$found" ] || { echo "containers of the project faito: $found"; return 1; }
}
id_of() { stand_in_exec docker inspect -f '{{.Id}}' "$1" 2> /dev/null | tr -d '\r'; }
log_config() { stand_in_exec docker inspect -f '{{json .HostConfig.LogConfig}}' "$1" 2> /dev/null | tr -d '\r'; }
log_configs_are() { # <expected> <container>…
  local expected=$1 container actual wrong=0
  shift
  for container in "$@"; do
    actual=$(log_config "$container")
    [ "$actual" = "$expected" ] || { echo "$container: $actual"; wrong=1; }
  done
  return "$wrong"
}
printed() { # the talker printed its last line (120 s at most)
  local i
  for i in $(seq 120); do
    [ "$(stand_in_exec sh -c 'docker logs --tail 1 faito.talker 2>&1' | tr -d '\r')" = "$LAST_LINE" ] && return 0
    sleep 1
  done
  echo "its last line: $(stand_in_exec sh -c 'docker logs --tail 1 faito.talker 2>&1' | head -c 200)"
  return 1
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito

# AC-05 on the stand-in
mapfile -t stack < <(stand_in_exec docker ps -a --filter label=com.docker.compose.project=c4-infra --format '{{.Names}}' | tr -d '\r' | LC_ALL=C sort)
check "AC-05: the stack's containers are listed (${#stack[@]})" test "${#stack[@]}" -ge 6
check "AC-05: each has json-file 10m × 3 (${stack[*]})" log_configs_are "$BOUND" "${stack[@]}"
check "AC-05: c4-infra.keycloak's is that bound" is "$(log_config c4-infra.keycloak)" "$BOUND"

# AC-02
for file in logging-json-file.yml logging-none.yml logging-local.yml; do
  check "$file is sent as ~faito/faito/compose.yml" send "$FIXTURES/$file"
  as "$file-up.log" faito "sudo c4-app up"
  check "AC-02: $file: sudo c4-app up is refused" refused "$file-up.log"
  check "AC-02: $file: it says \"$REFUSAL\"" says "$file-up.log" "$REFUSAL"
  check "AC-02: $file: and that nothing was started" says "$file-up.log" "nothing was started"
  check "AC-02: $file: no container of the project faito exists" no_container
  as "$file-pull.log" faito "sudo c4-app pull"
  check "AC-02: $file: sudo c4-app pull is refused" refused "$file-pull.log"
  check "AC-02: $file: it says \"$REFUSAL\"" says "$file-pull.log" "$REFUSAL"
done

# AC-03: the application's containers started by the former c4-app, unbounded
git show "$BEFORE:demo/c4-app" > "$work/c4-app-before" 2> "$work/git-show.log"
check "$BEFORE's demo/c4-app is read" test -s "$work/c4-app-before"
check "it is installed as /usr/local/sbin/c4-app" eval \
  'stand_in_exec -i sh -c "cat > /root/c4-app-before" < "$work/c4-app-before" && stand_in_exec install -o root -g root -m 0755 /root/c4-app-before /usr/local/sbin/c4-app'
check "talker.yml is sent as ~faito/faito/compose.yml" send "$FIXTURES/talker.yml"
as up-before.log faito "sudo c4-app up"
check "AC-03: with $BEFORE's c4-app, sudo c4-app up exits 0" exited_0 up-before.log
check "AC-03: faito.gateway and faito.talker are unbounded ($UNBOUNDED)" log_configs_are "$UNBOUNDED" faito.gateway faito.talker
gateway_before=$(id_of faito.gateway)
talker_before=$(id_of faito.talker)

as deploy.log c4-infra "cd ~/c4-infra && bash ./demo/deploy.sh < /dev/null"
check "AC-03: the stack's demo/deploy.sh, run again as c4-infra, exits 0" exited_0 deploy.log
check "AC-03: it installs this c4-app" says deploy.log "c4-app installed"
as up-after.log faito "sudo c4-app up"
check "AC-03: with the same files, sudo c4-app up exits 0" exited_0 up-after.log
check "AC-03: faito.gateway is a new container" eval '[ -n "$gateway_before" ] && [ "$(id_of faito.gateway)" != "$gateway_before" ]'
check "AC-03: so is faito.talker" eval '[ -n "$talker_before" ] && [ "$(id_of faito.talker)" != "$talker_before" ]'
check "AC-01: faito.gateway and faito.talker have json-file 10m × 3, c4-infra.keycloak's" \
  log_configs_are "$(log_config c4-infra.keycloak)" faito.gateway faito.talker
check "AC-01: that bound is the stack's ($BOUND)" log_configs_are "$BOUND" faito.gateway faito.talker
model_bound=$(stand_in_exec jq -cS '[.services[].logging] | unique' "$MODEL" | tr -d '\r')
check "AC-01: the model gives every service json-file 10m × 3 ($MODEL)" \
  is "$model_bound" '[{"driver":"json-file","options":{"max-file":"3","max-size":"10m"}}]'

# AC-01: what 60 MiB leave on disk
check "AC-01: the talker printed its 60 MiB and its last line" printed
log_path=$(stand_in_exec docker inspect -f '{{.LogPath}}' faito.talker | tr -d '\r')
stand_in_exec sh -c 'stat -c "%s %n" "$1"*' sh "$log_path" | tr -d '\r' > "$work/log-files"
echo "# its log files: $(awk '{ printf "%s%s", sep, $1; sep = ", " }' "$work/log-files") bytes"
at_most_3_files() {
  local count
  count=$(wc -l < "$work/log-files")
  [ "$count" -ge 1 ] && [ "$count" -le 3 ] || { cat "$work/log-files"; return 1; }
}
check "AC-01: at most 3 log files" at_most_3_files
check "AC-01: each at most 10 MB (one entry over at most)" \
  awk -v max=$((MAX_SIZE + ENTRY)) '$1 > max { print; bad = 1 } END { exit bad }' "$work/log-files"
check "AC-01: docker logs ends on its last line" \
  is "$(stand_in_exec sh -c 'docker logs faito.talker 2>&1 | tail -n 1' | tr -d '\r')" "$LAST_LINE"
check "AC-01: and lacks its first" \
  eval '[ "$(stand_in_exec sh -c "docker logs faito.talker 2>&1 | head -n 1" | tr -d "\r")" != "$FIRST_LINE" ]'

# AC-04
as logs.log c4-infra "docker logs --tail 1 faito.talker"
check "AC-04: as c4-infra, docker logs --tail 1 faito.talker shows its last line" ends_with logs.log "$LAST_LINE"
as compose-logs.log c4-infra "cd ~ && docker compose -p faito logs --tail 1 --no-log-prefix talker"
check "AC-04: so does docker compose -p faito logs --tail 1 --no-log-prefix talker, from ~" ends_with compose-logs.log "$LAST_LINE"

# bounded from their creation
as down.log faito "sudo c4-app down"
check "sudo c4-app down exits 0" exited_0 down.log
check "and removes the project faito's containers" no_container
as up-again.log faito "sudo c4-app up"
check "sudo c4-app up exits 0" exited_0 up-again.log
check "AC-01: the new containers have json-file 10m × 3 from their creation" log_configs_are "$BOUND" faito.gateway faito.talker

# AC-08
groups=$(stand_in_exec id -nG faito | tr -d '\r')
check "AC-08: faito is outside the docker group ($groups)" eval '[[ " $groups " != *" docker "* ]]'
as sudo-l.log faito "sudo -l"
only_c4_app() {
  local rules
  rules=$(sed -n '/may run the following commands/,$p' "$work/sudo-l.log" | tail -n +2 | sed '/^[[:space:]]*$/d')
  [ "$(printf '%s\n' "$rules" | tr -d '\r')" = "    (root) NOPASSWD: /usr/local/sbin/c4-app" ] || { cat "$work/sudo-l.log"; return 1; }
}
check "AC-08: sudo -l lists c4-app only" only_c4_app
stand_in_exec sh -c 'docker ps -aq | xargs -r docker inspect -f "{{.Name}}{{range .Mounts}}{{if eq .Type \"bind\"}} {{.Source}}{{end}}{{end}}"' \
  | tr -d '\r' > "$work/binds"
check "AC-08: the bind mounts of the stand-in's containers are read ($(wc -l < "$work/binds") containers)" test -s "$work/binds"
check "AC-08: none under /var/lib/docker nor of the Docker socket" \
  awk '{ for (i = 2; i <= NF; i++) if ($i ~ /^\/var\/lib\/docker(\/|$)/ || $i ~ /docker\.sock$/) { print; bad = 1 } } END { exit bad }' "$work/binds"
finish
