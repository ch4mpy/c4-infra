#!/usr/bin/env bash
# 0003: the shared Caddy configuration, caddy/, holds in both environments with every example
# application's site (REQ-1, AC-9): `caddy validate` in throwaway containers of the stack's Caddy
# image, with the sites routes.sh generates in a temporary apps/ directory.
#
#   bash tests/0003-caddy-config.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

# the reverse proxy's image (compose.yml), built by up.sh: Caddy with the rate-limit module the Caddyfile uses (intent 0013)
CADDY_IMAGE=c4-infra/reverse-proxy

# the docker CLI of Windows wants a Windows path for a bind mount
host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# caddy validate of caddy/Caddyfile, with <apps dir> as its apps/ and the given docker run options
validate() { # <apps dir> [docker run option…]
  local apps=$1
  shift
  MSYS_NO_PATHCONV=1 docker run --rm "$@" \
    -v "$(host_path "$PWD/caddy"):/etc/caddy:ro" -v "$(host_path "$apps"):/etc/caddy/apps:ro" \
    "$CADDY_IMAGE" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1 | tail -n 3
  return "${PIPESTATUS[0]}"
}

fails() { # <command…>: exits non-zero
  if "$@" > "$work/fails.out" 2>&1; then
    echo "exited 0:"
    cat "$work/fails.out"
    return 1
  fi
}

generated() { # <apps dir> <app> <env>
  bash routes.sh generate "examples/routes/$2.routes" "$2" "$3" > "$1/$2.caddy"
}

DEV=(-e INFRA_ENV=dev -e INFRA_HOST=host.docker.internal -v "$(host_path "$PWD/certs"):/certs:ro")
# the demo host's .env holds Mailpit's hash, a bcrypt hash (here of a random password, read by caddy
# on its stdin); Caddy no longer reads it since intent 0007 (Mailpit asks for its credentials
# itself, MP_UI_AUTH), and its configuration validates with it set
MAILPIT_UI_PASSWORD_HASH=$(openssl rand -hex 16 | docker run --rm -i "$CADDY_IMAGE" caddy hash-password)
export MAILPIT_UI_PASSWORD_HASH
DEMO=(-e INFRA_ENV=demo -e INFRA_HOST=infra.c4-soft.com -e MAILPIT_UI_PASSWORD_HASH)

mkdir -p "$work/none" "$work/dev" "$work/demo" "$work/broken"
check "dev: valid without any application" validate "$work/none" "${DEV[@]}"
check "demo: valid without any application" validate "$work/none" "${DEMO[@]}"

for app in faito hururaa turu; do
  check "dev: $app's site generates" generated "$work/dev" "$app" dev
done
check "dev: valid with Faito's, Hurura'a's and Turu's sites" validate "$work/dev" "${DEV[@]}"

for app in faito hururaa turu; do
  check "demo: $app's site generates" generated "$work/demo" "$app" demo
done
check "demo: valid with Faito's, Hurura'a's and Turu's sites (its MCP origin, intent 0013)" validate "$work/demo" "${DEMO[@]}"

# the sites are read: a broken one makes the configuration invalid
printf 'broken.dev.localhost {\n\timport no-such-snippet\n}\n' > "$work/broken/broken.caddy"
check "dev: a broken site in apps/ is refused" fails validate "$work/broken" "${DEV[@]}"
# no environment, no proxy (fail fast rather than a proxy with neither dev's nor the demo's rules)
check "INFRA_ENV missing: refused" fails validate "$work/none" -e INFRA_HOST=host.docker.internal
finish
