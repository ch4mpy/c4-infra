#!/usr/bin/env bash
# 0035: the stand-in host's Caddy runs the demo host's configuration but its certificates (RQ-02,
# RQ-04): `caddy adapt` of caddy/Caddyfile with INFRA_ENV=demo and Faito's generated site, in
# throwaway containers of the stack's Caddy image, mounted as the demo host mounts it, then as the
# stand-in does (tests/stand-in-host/compose.no-acme.yml: caddy-env/ over env/, the stack's env/
# beside it):
#
#   - both adapt;
#   - their JSON is the same once apps.tls and apps.pki are left out;
#   - the stand-in's one automation policy issues from the internal authority, which installs its root
#     nowhere; the demo host's configuration has no internal issuer.
#
#   bash tests/0035-stand-in-proxy.sh
#
# covers: tests/stand-in-host/ caddy/ reverse-proxy/ routes.sh registry.sh registry.txt examples/routes/
# covers: compose.yml
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

CADDY_IMAGE=c4-infra/reverse-proxy

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

adapt() { # <output> [docker run option…]: caddy adapt of the demo configuration, Faito's site in apps/
  local output=$1
  shift
  MSYS_NO_PATHCONV=1 docker run --rm -e INFRA_ENV=demo -e INFRA_HOST=infra.c4-soft.com \
    -v "$(host_path "$PWD/caddy"):/etc/caddy:ro" -v "$(host_path "$work/apps"):/etc/caddy/apps:ro" "$@" \
    "$CADDY_IMAGE" caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile > "$output" 2> "$output.err" \
    || { tail -n 5 "$output.err"; return 1; }
}
same_but_certificates() {
  diff <(jq -S 'del(.apps.tls, .apps.pki)' < "$work/host.json") <(jq -S 'del(.apps.tls, .apps.pki)' < "$work/stand-in.json")
}
is() { # <file> <jq filter> <expected, compact JSON>
  local actual
  actual=$(jq -c "$2" < "$1" | tr -d '\r')
  [ "$actual" = "$3" ] || { echo "$2: $actual"; return 1; }
}

faito_site() { bash routes.sh generate examples/routes/faito.routes faito demo > "$work/apps/faito.caddy"; }

mkdir "$work/apps"
check "Faito's site generates" faito_site
check "the demo host's configuration adapts" adapt "$work/host.json"
check "the stand-in's adapts" adapt "$work/stand-in.json" \
  -v "$(host_path "$PWD/tests/stand-in-host/caddy-env"):/etc/caddy/env:ro" \
  -v "$(host_path "$PWD/caddy/env"):/etc/caddy-stack-env:ro"
check "both are the same, apps.tls and apps.pki aside" same_but_certificates
check "the stand-in's one automation policy issues from the internal authority" \
  is "$work/stand-in.json" .apps.tls.automation.policies '[{"issuers":[{"module":"internal"}]}]'
check "whose root is installed nowhere" \
  is "$work/stand-in.json" .apps.pki.certificate_authorities.local.install_trust false
check "the demo host's configuration has no internal issuer" \
  is "$work/host.json" '[.. | objects | select(.module? == "internal")] | length' 0
finish
