#!/usr/bin/env bash
# 0007: on a stand-in demo host, `sudo c4-app up` refuses a compose project that leaves the
# application's isolation, before any container starts (AC-8, REQ-9):
#
#   - the accounts and the shared stack as docs/demo-setup.md prepares them (stand_in_accounts faito);
#   - each file of tests/fixtures/0007/hostile/ but valid.yml, sent as ~faito/faito/compose.yml over
#     ssh as faito: sudo c4-app up exits non-zero, its output names the service, network or volume
#     and the rule, no container of the project faito exists, and no network c4-infra.faito either;
#   - valid.yml (its network c4-infra.faito and one of the project's own, an alias and a container
#     name under faito., an exposed port, a volume of its own, a bind mount inside its directory)
#     starts: faito.gateway runs, on those two networks;
#   - the model compose starts is the one checked: root's, in a directory faito can't write; a
#     symbolic link swapped into ~faito/faito/ afterwards is refused at the next up, and the running
#     container is unchanged.
#
#   bash tests/0007-compose-check.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0002-accounts.stand-in.sh: the Keycloak image is the one up.sh builds here, loaded into
# the stand-in; the fixtures' image is the stand-in's caddy (the shared reverse proxy's).
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0007/hostile
STAGING=/var/lib/c4-apps/faito
# what each refusal says (c4-app: refused: <this>)
declare -A REFUSAL=(
  [network-mode.yml]='service gateway: network_mode container:c4-infra.keycloak'
  [service-keycloak.yml]='service keycloak: named after a shared service'
  [alias-keycloak.yml]='service gateway: alias keycloak on network c4-infra.faito, outside faito.'
  [alias-hururaa-gateway.yml]='service gateway: alias hururaa.gateway on network c4-infra.faito, outside faito.'
  [container-name-hururaa.yml]='service gateway: container_name hururaa.gateway, outside faito.'
  [network-hururaa.yml]='network c4-infra.hururaa: external, and not c4-infra.faito'
  [ports.yml]='service gateway: published ports (7080)'
  [privileged.yml]='service gateway: privileged'
  [docker-socket.yml]="service gateway: a bind mount of /var/run/docker.sock, outside $STAGING/"
  [host-path.yml]="service gateway: a bind mount of /home/hururaa/hururaa, outside $STAGING/"
  [cap-add.yml]='service gateway: cap_add NET_ADMIN'
  [pid-host.yml]='service gateway: pid host'
  [devices.yml]='service gateway: devices'
  [external-volume.yml]='volume data: external (hururaa_rest_api_data)'
  [volume-bind-driver.yml]='volume data: driver_opts'
  [build-outside.yml]="service gateway: build context /var/lib/c4-apps/hururaa, outside $STAGING/"
  # review round 1 (2026-10-22): the escapes that passed the former denylist, now the allowlist's
  [use-api-socket.yml]='service gateway: use_api_socket is not allowed'
  [post-start-privileged.yml]='service gateway: post_start is not allowed'
  [provider.yml]='service helper: provider is not allowed'
  [seccomp-file.yml]="service gateway: security_opt seccomp=$STAGING/compose.yml (only no-new-privileges)"
  [service-dotted-name.yml]='service faito.gateway: its name is outside a-z 0-9 _ -'
  [build-network.yml]='service gateway: build.network is not allowed'
  [build-ssh.yml]='service gateway: build.ssh is not allowed'
  [build-dockerfile-dotdot.yml]="service gateway: Dockerfile ../../c4-app.model.json resolves outside $STAGING/"
  [bind-rw.yml]="service gateway: a read-write bind mount of $STAGING/compose.yml"
  [bind-staging-root.yml]="service gateway: a bind mount of the staging root $STAGING itself"
  [deploy-devices.yml]='service gateway: deploy reserves host devices'
)

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

# <log> <command>: over ssh as faito, its output into $work/<log>, its exit status into $status
as_faito() {
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
no_container() {
  local found
  found=$(stand_in_exec docker ps -aq --filter label=com.docker.compose.project=faito | tr -d '\r')
  [ -z "$found" ] || { echo "containers of the project faito: $found"; return 1; }
}
no_network() {
  ! stand_in_exec docker network inspect c4-infra.faito > /dev/null 2>&1 || { echo "c4-infra.faito exists"; return 1; }
}
send() { # <fixture file> [<name>]: as ~faito/faito/<name> (compose.yml), over ssh as faito
  stand_in_ssh -i faito "cat > ~/faito/${2:-compose.yml}" < "$1"
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito

for file in "${!REFUSAL[@]}"; do
  check "$file is sent as ~faito/faito/compose.yml" send "$FIXTURES/$file"
  as_faito "$file.log" "sudo c4-app up"
  check "$file: sudo c4-app up is refused" refused "$file.log"
  check "$file: it says \"${REFUSAL[$file]}\"" says "$file.log" "c4-app: refused: ${REFUSAL[$file]}"
  check "$file: and that nothing was started" says "$file.log" "nothing was started"
  check "$file: no container of the project faito exists" no_container
done
check "no refusal created c4-infra.faito" no_network

# a project that keeps to its isolation starts
check "valid.yml is sent as ~faito/faito/compose.yml" send "$FIXTURES/valid.yml"
as_faito valid.log "sudo c4-app up"
check "valid.yml: sudo c4-app up exits 0" exited_0 valid.log
check "valid.yml: faito.gateway runs" \
  test "$(stand_in_exec docker inspect -f '{{.State.Running}}' faito.gateway 2> /dev/null | tr -d '\r')" = true
networks=$(stand_in_exec docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' faito.gateway | tr -d '\r')
check "valid.yml: faito.gateway is on c4-infra.faito and faito_internal only ($networks)" \
  test "$networks" = 'c4-infra.faito faito_internal '

# the model compose started is the one checked: root's, in the root-only snapshot directory, outside
# anything a container may mount (review round 1, 2026-10-22, finding 4: the model left the staging
# tree, which the application's own containers can mount, for /var/lib/c4-apps/.run.<app>/)
SNAP=/var/lib/c4-apps/.run.faito
model_mode=$(stand_in_exec stat -c '%U:%G %a' "$SNAP/model.json" | tr -d '\r')
check "the model root's compose ran is root's, in the snapshot directory ($model_mode)" test "$model_mode" = 'root:root 640'
snap_mode=$(stand_in_exec stat -c '%U:%G %a' "$SNAP" | tr -d '\r')
check "the snapshot directory is root-only ($snap_mode)" test "$snap_mode" = 'root:root 700'
check "no model file is left in the staging tree (faito's containers mount it)" \
  stand_in_exec test ! -e "$STAGING/.c4-app.model.json"
check "the snapshot directory is outside the staging tree (no bind mount can reach it)" \
  bash -c 'case "$1" in "$2"/*) exit 1 ;; *) exit 0 ;; esac' sh "$SNAP" "$STAGING"
as_faito write-staging.log "touch $STAGING/x"
check "faito can't write the staging directory" refused write-staging.log
as_faito read-snap.log "cat $SNAP/model.json"
check "faito can't even read the root-only snapshot" refused read-snap.log
started=$(stand_in_exec docker inspect -f '{{.Id}} {{.State.StartedAt}}' faito.gateway | tr -d '\r')
check "a hostile file (privileged.yml) is sent next to compose.yml, as hostile.yml" send "$FIXTURES/privileged.yml" hostile.yml
as_faito swap.log "rm ~/faito/compose.yml && ln -s hostile.yml ~/faito/compose.yml && sudo c4-app up"
check "compose.yml swapped for a link to it: sudo c4-app up is refused" refused swap.log
check "it says the link is refused" says swap.log "holds a symbolic link or a special file, refused: compose.yml"
check "faito.gateway is the same container, still running ($started)" \
  test "$(stand_in_exec docker inspect -f '{{.Id}} {{.State.StartedAt}}' faito.gateway | tr -d '\r')" = "$started"
check "and it isn't privileged" \
  test "$(stand_in_exec docker inspect -f '{{.HostConfig.Privileged}}' faito.gateway | tr -d '\r')" = false
finish
