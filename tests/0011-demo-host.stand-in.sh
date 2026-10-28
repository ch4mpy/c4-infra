#!/usr/bin/env bash
# 0011: on a stand-in demo host, what `sudo c4-app` does with a project's compose file:
#
#   - AC-08: the six values of tests/fixtures/0011/six-values.env, read by registry.sh's dotenv_value
#     and by the host's docker compose, are alike (a guard: no fix, spec PA-02);
#   - AC-01: tests/fixtures/0011/build.yml (a service with build: .) is refused by `sudo c4-app up` and
#     `pull`, with RQ-01's message, naming the service; up starts nothing and creates no c4-infra.faito;
#   - AC-09: with a refused INFRA_HOST in the stack's .env, c4-app's own check doesn't read it
#     (networks.sh ensure, which adds the proxy's alias, still does: up stops there);
#   - AC-04: 0007's valid.yml started, then compose.yml replaced by tests/fixtures/0011/down-hook.yml
#     (a provider, hook.sh, staged by the earlier up): `sudo c4-app down` exits 0, the project's
#     containers and its network faito_internal are gone, its volume faito_cache and c4-infra.faito
#     stay, and the provider didn't run (no hook-ran next to it).
#
#   bash tests/0011-demo-host.stand-in.sh
#
# The stack's .env is restored right after AC-09's run.
#
# covers: demo/ registry.sh networks.sh compose.yml compose.demo.yml tests/fixtures/0011/
# covers: tests/fixtures/0007/hostile/valid.yml tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0011
STAGING=/var/lib/c4-apps/faito
BUILD_REFUSAL="c4-app: refused: service gateway: build: the demo host runs the images the application's CI pushes to a registry"

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
doesnt_say() { # <log> <text>
  ! grep -nF -- "$2" "$work/$1"
}
send() { # <fixture file> [<name>]: as ~faito/faito/<name> (compose.yml), over ssh as faito
  stand_in_ssh -i faito "cat > ~/faito/${2:-compose.yml}" < "$1"
}
containers() { stand_in_exec docker ps -aq --filter label=com.docker.compose.project=faito | tr -d '\r'; }
no_container() {
  [ -z "$(containers)" ] || { echo "containers of the project faito: $(containers)"; return 1; }
}
network_exists() { stand_in_exec docker network inspect "$1" > /dev/null 2>&1; }

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito

# AC-08: the same six values, by dotenv_value and by the host's compose
stand_in_ssh -i c4-infra "mkdir -p ~/0011 && cat > ~/0011/six-values.env" < "$FIXTURES/six-values.env"
stand_in_ssh c4-infra 'cd ~/0011 && printf "services:\n  s:\n    image: busybox\n    environment:\n" > six.yml &&
  for key in A B C D E F; do printf "      %s: \${%s}\n" "$key" "$key" >> six.yml; done &&
  docker compose --env-file six-values.env -f six.yml config --format json \
    | jq -r ".services.s.environment | to_entries[] | \"\(.key)=[\(.value)]\"" > compose.read &&
  source ~/c4-infra/registry.sh &&
  for key in A B C D E F; do printf "%s=[%s]\n" "$key" "$(dotenv_value six-values.env "$key")"; done > dotenv.read' \
  > "$work/six.log" 2>&1
alike() {
  local compose dotenv
  compose=$(stand_in_exec cat /home/c4-infra/0011/compose.read)
  dotenv=$(stand_in_exec cat /home/c4-infra/0011/dotenv.read)
  [ -n "$compose" ] && [ "$compose" = "$dotenv" ] \
    || { echo "compose: $compose"; echo "dotenv_value: $dotenv"; cat "$work/six.log"; return 1; }
}
check "AC-08: the six values, read by dotenv_value and by the host's docker compose, are alike" alike

# AC-01: a service that builds, refused by up and by pull
check "build.yml is sent as ~faito/faito/compose.yml" send "$FIXTURES/build.yml"
as_faito build-up.log "sudo c4-app up"
check "AC-01: build.yml: sudo c4-app up is refused" refused build-up.log
check "AC-01: it says \"$BUILD_REFUSAL\"" says build-up.log "$BUILD_REFUSAL"
check "AC-01: and that nothing was started" says build-up.log "nothing was started"
check "AC-01: no container of the project faito exists" no_container
check "AC-01: no network c4-infra.faito was created" eval '! network_exists c4-infra.faito'
as_faito build-pull.log "sudo c4-app pull"
check "AC-01: build.yml: sudo c4-app pull is refused" refused build-pull.log
check "AC-01: it says \"$BUILD_REFUSAL\"" says build-pull.log "$BUILD_REFUSAL"

# AC-09: a refused INFRA_HOST (an unbalanced quote) in the stack's .env, which c4-app's check no
# longer reads; restored at once
check "0007's valid.yml is sent as ~faito/faito/compose.yml" send tests/fixtures/0007/hostile/valid.yml
stand_in_ssh c4-infra "cd ~/c4-infra && cp -p .env .env.0011 && sed -i \"s/^INFRA_HOST=/INFRA_HOST='/\" .env"
as_faito infra-host.log "sudo c4-app up"
stand_in_ssh c4-infra "cd ~/c4-infra && mv -f .env.0011 .env"
check "AC-09: a refused INFRA_HOST: c4-app's check doesn't read it" \
  doesnt_say infra-host.log "c4-app: INFRA_HOST of /home/c4-infra/c4-infra/.env can't be read"
check "AC-09: (networks.sh ensure, which adds the proxy's alias, refuses it)" \
  says infra-host.log "INFRA_HOST of /home/c4-infra/c4-infra/.env is refused"

# AC-04: a project started, then its compose.yml replaced by a refused one with a provider staged
# beside it: down stops the project by its name, reading no file
check "hook.sh is sent next to compose.yml, executable" send "$FIXTURES/hook.sh" hook.sh
stand_in_ssh faito "chmod 755 ~/faito/hook.sh"
as_faito valid-up.log "sudo c4-app up"
check "AC-04: valid.yml: sudo c4-app up exits 0" exited_0 valid-up.log
check "AC-04: faito.gateway runs" test "$(stand_in_exec docker inspect -f '{{.State.Running}}' faito.gateway | tr -d '\r')" = true
check "AC-04: hook.sh is staged ($STAGING/hook.sh)" stand_in_exec test -x "$STAGING/hook.sh"
check "down-hook.yml replaces ~faito/faito/compose.yml" send "$FIXTURES/down-hook.yml"
as_faito down.log "sudo c4-app down"
check "AC-04: sudo c4-app down exits 0" exited_0 down.log
check "AC-04: no container of the project faito is left" no_container
check "AC-04: its network faito_internal is gone" eval '! network_exists faito_internal'
check "AC-04: its volume faito_cache stays" stand_in_exec docker volume inspect faito_cache
check "AC-04: c4-infra.faito stays (networks.sh's, not the project's)" network_exists c4-infra.faito
check "AC-04: the provider of the new file didn't run (no $STAGING/hook-ran)" \
  eval "! stand_in_exec test -e $STAGING/hook-ran"
finish
