#!/usr/bin/env bash
# 0025: a refused `sudo c4-app` command leaves the files the application's running containers read
# as they were, on a stand-in demo host:
#
#   - Faito deployed with tests/fixtures/0025/mounted.yml (its gateway mounts ./content read-only),
#     content/page.txt v1: the gateway reads v1, mounted from /var/lib/c4-apps/faito/content (the
#     model's source and the container's);
#   - page.txt v2 and a refused compose.yml (a published port): `sudo c4-app up` and `pull` refused;
#     the staging directory's page.txt and compose.yml are the former ones, the gateway reads v1;
#   - the valid compose.yml back, page.txt still v2, `sudo c4-app register --themes themes` with
#     Hurura'a's theme: refused, the staging directory unchanged;
#   - `sudo c4-app up`: exits 0, the gateway reads v2.
#
#   bash tests/0025-refused-stage.stand-in.sh
#
# covers: demo/ register-app.sh registry.sh networks.sh tests/fixtures/0025/ tests/stand-in-host/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

FIXTURES=tests/fixtures/0025
STAGING=/var/lib/c4-apps/faito

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
send() { # <fixture file> [<name>]: as ~faito/faito/<name> (compose.yml), over ssh as faito
  stand_in_ssh -i faito "cat > ~/faito/${2:-compose.yml}" < "$1"
}
page() { # <version>: ~faito/faito/content/page.txt
  stand_in_ssh faito "mkdir -p ~/faito/content && printf '%s\n' $1 > ~/faito/content/page.txt"
}
staged_page() { stand_in_exec cat "$STAGING/content/page.txt" | tr -d '\r'; }
read_page() { stand_in_exec docker exec faito.gateway cat /srv/content/page.txt | tr -d '\r'; }
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual: $1, expected: $2"; return 1; }
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, faito), the shared stack deployed as c4-infra" stand_in_accounts faito

check "mounted.yml is sent as ~faito/faito/compose.yml, content/page.txt v1" \
  eval 'send "$FIXTURES/mounted.yml" && page v1'
as_faito up-v1.log "sudo c4-app up"
check "sudo c4-app up exits 0" exited_0 up-v1.log
check "the gateway reads v1" is "$(read_page)" v1
check "the model mounts $STAGING/content" \
  is "$(stand_in_exec jq -r '.services.gateway.volumes[0].source' /var/lib/c4-apps/.run.faito/model.json | tr -d '\r')" "$STAGING/content"
check "so does the container" \
  is "$(stand_in_exec docker inspect -f '{{range .Mounts}}{{.Source}}{{end}}' faito.gateway | tr -d '\r')" "$STAGING/content"
staged_compose=$(stand_in_exec cksum "$STAGING/compose.yml" | tr -d '\r')

check "refused.yml (a published port) is sent as compose.yml, content/page.txt v2" \
  eval 'send "$FIXTURES/refused.yml" && page v2'
as_faito up-refused.log "sudo c4-app up"
check "sudo c4-app up is refused" refused up-refused.log
check "it says why" says up-refused.log "c4-app: refused: service gateway: published ports (7080)"
check "the staging directory's page.txt is still v1" is "$(staged_page)" v1
check "its compose.yml is still the former one" is "$(stand_in_exec cksum "$STAGING/compose.yml" | tr -d '\r')" "$staged_compose"
check "the gateway still reads v1" is "$(read_page)" v1
as_faito pull-refused.log "sudo c4-app pull"
check "sudo c4-app pull is refused" refused pull-refused.log
check "it says why" says pull-refused.log "c4-app: refused: service gateway: published ports (7080)"
check "the staging directory's page.txt is still v1, after pull" is "$(staged_page)" v1

check "mounted.yml is sent back, page.txt still v2, Hurura'a's theme in ~faito/faito/themes/" \
  eval 'send "$FIXTURES/mounted.yml" && stand_in_ssh faito "mkdir -p ~/faito/themes/hururaa/login" && send "$FIXTURES/themes/hururaa/login/theme.properties" themes/hururaa/login/theme.properties'
as_faito register-refused.log "sudo c4-app register --themes themes"
check "sudo c4-app register --themes themes is refused" refused register-refused.log
check "it says why" says register-refused.log "theme hururaa is not faito's"
check "the staging directory's page.txt is still v1, after register" is "$(staged_page)" v1
check "the gateway still reads v1, after register" is "$(read_page)" v1

as_faito up-v2.log "sudo c4-app up"
check "with the valid compose.yml, sudo c4-app up exits 0" exited_0 up-v2.log
check "the staging directory's page.txt is v2" is "$(staged_page)" v2
check "the gateway reads v2" is "$(read_page)" v2
finish
