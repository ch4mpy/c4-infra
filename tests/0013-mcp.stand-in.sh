#!/usr/bin/env bash
# 0013: an application's MCP server on a stand-in demo host (AC-6, AC-13, REQ-7, REQ-15):
#
#   - the accounts and the shared stack as docs/demo-setup.md prepares them (stand_in_accounts turu);
#     the probe image (tests/fixtures/0007/probe/: an echo, curl) built in the stand-in's daemon;
#   - Turu (tests/fixtures/0013/turu/: its MCP server turu.mcp on 9080, on c4-infra.turu; a realm
#     turu whose client verif-mcp may exchange the tokens issued for it), rsynced to ~turu/turu/ with
#     its key, with examples/routes/turu.routes; registered (sudo c4-app register --realm
#     turu-realm.json --proxy turu.routes) and started (sudo c4-app up; no pull: the probe is local);
#   - AC-6: its site names its MCP origin, turu-mcp.c4-soft.com, which Caddy serves (HTTP to HTTPS)
#     and from which it reaches turu.mcp:9080;
#   - AC-13: from turu.mcp, through http://keycloak:8080/auth, a token issued for the public issuer
#     (https://infra.c4-soft.com/auth/realms/turu) is exchanged for another, of the same issuer.
#
# The stand-in serves no HTTPS (Let's Encrypt is kept out): the MCP origin's headers are checked by
# tests/0003-demo-edge.sh, on a throwaway Caddy with its own certificates.
#
#   bash tests/0013-mcp.stand-in.sh      (bash tests/run.sh --all runs it)
#
# As tests/0007-isolation.stand-in.sh: the images are this machine's, loaded into the stand-in; the
# fixture's client secrets are dev values ("secret"), sent on stdin.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stand-in-host.sh

STACK=/home/c4-infra/c4-infra
UPLOAD=/root/apps-0013/turu
PROBE=c4-test/probe
ISSUER=https://infra.c4-soft.com/auth/realms/turu
TOKEN=http://keycloak:8080/auth/realms/turu/protocol/openid-connect/token

umask 077
work=$(mktemp -d)
trap 'stand_in_down; rm -rf "$work"' EXIT

# <log> <account> <command>: over ssh as <account>, its output into $work/<log>, its exit status
# into $status
as() {
  local log=$1
  stand_in_ssh "$2" "$3" > "$work/$log" 2>&1
  status=$?
}
exited_0() { # <log>
  [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 25 "$work/$1"; return 1; }
}
running() { # <container>
  [ "$(stand_in_exec docker inspect -f '{{.State.Running}}' "$1" 2> /dev/null | tr -d '\r')" = true ] \
    || { echo "$1 doesn't run"; return 1; }
}
# Turu's files into $UPLOAD, then rsynced to ~turu/turu/ with its key
upload() {
  stand_in_exec rm -rf "$UPLOAD"
  stand_in_exec mkdir -p "$UPLOAD" || return 1
  (cd tests/fixtures/0013/turu && tar -cf - .) | stand_in_exec -i tar -xf - --no-same-owner -C "$UPLOAD" || return 1
  stand_in_exec -i sh -c 'cat > "$1"' sh "$UPLOAD/turu.routes" < examples/routes/turu.routes || return 1
  stand_in_exec bash -c 'cd "$1" && rsync -az --delete -e "$2" ./ "turu@127.0.0.1:~/turu/"' \
    sh "$UPLOAD" "$(stand_in_ssh_command turu)"
}
site_names() { # <line>
  stand_in_exec grep -qxF -- "$1" "$STACK/caddy/apps/turu.caddy" || { stand_in_exec cat "$STACK/caddy/apps/turu.caddy"; return 1; }
}
# A POST to Keycloak's token endpoint from turu.mcp, the form on stdin: the response
token_from_mcp() {
  stand_in_exec -i docker exec -i turu.mcp curl -s --max-time 20 -d @- "$TOKEN"
}
# Payload of a JWT, padding restored
claims() {
  local payload
  payload=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  while [ $((${#payload} % 4)) -ne 0 ]; do payload="${payload}="; done
  printf '%s' "$payload" | base64 -d
}

check "the stand-in host starts" stand_in_up
check "the accounts (c4-infra, turu), the shared stack deployed as c4-infra" stand_in_accounts turu
build_probe() {
  (cd tests/fixtures/0007/probe && tar -cf - .) | stand_in_exec -i docker build -q -t "$PROBE" - > /dev/null
}
check "the probe image is built in the stand-in" build_probe

check "Turu's files are rsynced to ~turu/turu/ with its key" upload
as register.log turu "sudo c4-app register --realm turu-realm.json --proxy turu.routes"
check "Turu registers (sudo c4-app register: its realm, its routes file)" exited_0 register.log
as up.log turu "sudo c4-app up"
check "Turu starts (sudo c4-app up)" exited_0 up.log
check "turu.mcp runs" running turu.mcp

# AC-6
check "AC-6: Turu's site names its MCP origin, turu-mcp.c4-soft.com" site_names 'turu-mcp.c4-soft.com {'
check "AC-6: which reaches http://turu.mcp:9080" site_names $'\t\t\treverse_proxy http://turu.mcp:9080'
check "AC-6: Caddy serves turu-mcp.c4-soft.com (HTTP to HTTPS)" \
  stand_in_exec sh -c 'curl -s -o /dev/null -w "%{http_code} %{redirect_url}" -H "Host: turu-mcp.c4-soft.com" http://127.0.0.1/mcp | grep -qx "308 https://turu-mcp.c4-soft.com/mcp"'
caddy_reaches_mcp() {
  local answer
  answer=$(stand_in_exec docker exec c4-infra.reverse-proxy wget -qO- http://turu.mcp:9080/mcp | tr -d '\r')
  [ "$answer" = turu.mcp ] || { echo "answer: ${answer:-none}"; return 1; }
}
check "AC-6: Caddy reaches turu.mcp:9080 (its answer)" caddy_reaches_mcp

# AC-13
printf 'grant_type=client_credentials&client_id=verif-subject&client_secret=secret' | token_from_mcp > "$work/subject.json"
subject=$(jq -r '.access_token // empty' "$work/subject.json" | tr -d '\r')
check "AC-13: from turu.mcp, through http://keycloak:8080/auth, a token ($(jq -c '.error // "ok"' "$work/subject.json"))" test -n "$subject"
check "AC-13: issued for the public issuer ($ISSUER)" test "$(claims "$subject" | jq -r .iss | tr -d '\r')" = "$ISSUER"
printf 'grant_type=urn:ietf:params:oauth:grant-type:token-exchange&client_id=verif-mcp&client_secret=secret&subject_token=%s&subject_token_type=urn:ietf:params:oauth:token-type:access_token' "$subject" \
  | token_from_mcp > "$work/exchanged.json"
exchanged=$(jq -r '.access_token // empty' "$work/exchanged.json" | tr -d '\r')
check "AC-13: exchanged there by verif-mcp ($(jq -c '.error_description // .error // "ok"' "$work/exchanged.json"))" test -n "$exchanged"
check "AC-13: the exchanged token's issuer is the public one" test "$(claims "$exchanged" | jq -r .iss | tr -d '\r')" = "$ISSUER"
finish
