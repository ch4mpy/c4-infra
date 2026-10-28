#!/usr/bin/env bash
# 0003: the compose base and its two overrides (RQ-05, RQ-09): `docker compose config` of dev
# (COMPOSE_FILE of .env, as up.sh runs it) and of the demo host (compose.yml + compose.demo.yml, with
# the dummy values of tests/fixtures/0003/demo.env). The image versions are written once, in the
# base, and an upgrade there shows in both (AC-05); dev publishes every port on 127.0.0.1, the demo
# host 80 and 443 only (AC-10); what the demo host doesn't expose stays dev's (RQ-02).
#
#   bash tests/0003-compose.sh
#
# covers: compose.yml compose.dev.yml compose.demo.yml env.sh keycloak/ rabbitmq/ reverse-proxy/
# covers: grafana-lgtm/ tests/fixtures/0003/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

DEMO_ENV=tests/fixtures/0003/demo.env
# the ports 0001 publishes in dev (its RQ-01)
DEV_PORTS='1025 15672 3000 4317 4318 443 5672 80 8025'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

dev_config() { docker compose config --format json; }
demo_config() { docker compose -f compose.yml -f compose.demo.yml --env-file "$DEMO_ENV" config --format json; }

dev_config > "$work/dev.json" 2> "$work/dev.err"
check "dev: docker compose config succeeds (COMPOSE_FILE of .env)" test -s "$work/dev.json"
demo_config > "$work/demo.json" 2> "$work/demo.err"
check "demo: docker compose config succeeds" test -s "$work/demo.json"

images() { # <config file>: "<service> <image>", one per line, sorted
  jq -r '.services | to_entries[] | "\(.key) \(.value.image)"' "$1" | LC_ALL=C sort
}

same_images() {
  local dev demo
  # Keycloak's (and keycloak-import's) is KC_IMAGE in both, the proxy's PROXY_IMAGE (0013): built here,
  # pulled from GHCR on the demo host
  dev=$(images "$work/dev.json" | grep -vE '^(keycloak(-import)?|reverse-proxy) ')
  demo=$(images "$work/demo.json" | grep -vE '^(keycloak(-import)?|reverse-proxy) ')
  [ "$dev" = "$demo" ] && [ -n "$dev" ] || { echo "dev:"; echo "$dev"; echo "demo:"; echo "$demo"; return 1; }
}

no_image_in_overrides() {
  ! grep -n 'image:' compose.dev.yml compose.demo.yml
}

no_ports_in_base() {
  ! grep -n 'ports:' compose.yml
}

keycloak_image_is() { # <config file> <image>
  [ "$(jq -r '.services.keycloak.image' "$1")" = "$2" ] || { echo "keycloak: $(jq -r '.services.keycloak.image' "$1")"; return 1; }
}

published() { # <config file>: "<published> <host_ip or none>", one per line
  jq -r '.services[] | (.ports // [])[] | "\(.published) \(.host_ip // "none")"' "$1"
}

all_on_loopback() {
  local others
  others=$(published "$work/dev.json" | grep -v ' 127\.0\.0\.1$')
  [ -z "$others" ] || { echo "not on 127.0.0.1:"; echo "$others"; return 1; }
}

ports_are() { # <config file> <ports, sorted as strings, space-separated>
  local ports
  ports=$(published "$1" | awk '{ print $1 }' | LC_ALL=C sort | paste -sd' ' -)
  [ "$ports" = "$2" ] || { echo "published: $ports"; return 1; }
}

demo_publishes_proxy_only() {
  local services
  services=$(jq -r '.services | to_entries[] | select((.value.ports // []) | length > 0) | .key' "$work/demo.json")
  [ "$services" = reverse-proxy ] || { echo "services publishing ports: $services"; return 1; }
}

value_is() { # <config file> <jq path> <value>
  [ "$(jq -r "$2" "$1")" = "$3" ] || { echo "$2: $(jq -r "$2" "$1")"; return 1; }
}

mounts() { # <config file> <service>: the targets of its volumes
  jq -r --arg s "$2" '.services[$s].volumes[]?.target' "$1"
}

lacks_mount() { # <config file> <service> <target>
  ! mounts "$1" "$2" | grep -qxF -- "$3" || { echo "$2 mounts $3"; return 1; }
}

has_mount() { # <config file> <service> <target>
  mounts "$1" "$2" | grep -qxF -- "$3" || { echo "$2 mounts:"; mounts "$1" "$2"; return 1; }
}

# RQ-05: the versions once, in the base
check "every shared image is the same in dev and on the demo host" same_images
check "no image: in compose.dev.yml nor compose.demo.yml" no_image_in_overrides
check "dev: Keycloak is the image built here, c4-infra/keycloak" keycloak_image_is "$work/dev.json" c4-infra/keycloak
check "dev: Keycloak is built from keycloak/" test "$(jq -r '.services.keycloak.build.context // empty' "$work/dev.json")" != ""
check "demo: Keycloak is KC_IMAGE, pulled" keycloak_image_is "$work/demo.json" ghcr.io/ch4mpy/c4-infra-keycloak:000000000000
# 0012: the master realm's one-shot import runs the very Keycloak that serves the database
import_image_is_keycloaks() { # <config file>
  jq -e '.services["keycloak-import"].image == .services.keycloak.image' "$1" > /dev/null \
    || { jq -r '"keycloak-import: \(.services["keycloak-import"].image), keycloak: \(.services.keycloak.image)"' "$1"; return 1; }
}
check "0012, dev: keycloak-import runs Keycloak's image" import_image_is_keycloaks "$work/dev.json"
check "0012, dev: keycloak-import is built from keycloak/ too" \
  test "$(jq -r '.services["keycloak-import"].build.context // empty' "$work/dev.json")" = "$(jq -r '.services.keycloak.build.context' "$work/dev.json")"
check "0012, demo: keycloak-import runs Keycloak's image" import_image_is_keycloaks "$work/demo.json"
check "demo: nothing is built" test -z "$(jq -r '.services[].build // empty' "$work/demo.json")"
check "0013, dev: the proxy is the image built here, c4-infra/reverse-proxy" value_is "$work/dev.json" '.services["reverse-proxy"].image' c4-infra/reverse-proxy
check "0013, dev: the proxy is built from reverse-proxy/" test "$(jq -r '.services["reverse-proxy"].build.context // empty' "$work/dev.json")" != ""
check "0013, demo: the proxy is PROXY_IMAGE, pulled" value_is "$work/demo.json" '.services["reverse-proxy"].image' ghcr.io/ch4mpy/c4-infra-reverse-proxy:000000000000

# RQ-09, AC-10
check "no ports: in compose.yml" no_ports_in_base
check "dev: every published port is on 127.0.0.1" all_on_loopback
check "dev: the nine ports of 0001" ports_are "$work/dev.json" "$DEV_PORTS"
check "demo: exactly 80 and 443 published" ports_are "$work/demo.json" '443 80'
check "demo: by the proxy only" demo_publishes_proxy_only

# INFRA_ENV picks the proxy's rules
check "dev: Caddy's INFRA_ENV is dev" value_is "$work/dev.json" '.services["reverse-proxy"].environment.INFRA_ENV' dev
check "demo: Caddy's INFRA_ENV is demo" value_is "$work/demo.json" '.services["reverse-proxy"].environment.INFRA_ENV' demo
check "dev: Caddy has the dev certificates" has_mount "$work/dev.json" reverse-proxy /certs
check "demo: Caddy has no dev certificate" lacks_mount "$work/demo.json" reverse-proxy /certs
# (0007) Mailpit asks for its credentials itself, and the issuer's name is Caddy's on each
# application's network (compose.apps.yml, tests/0007-dev.sh), no longer on c4-infra
check "demo: Mailpit asks for its UI credentials (MP_UI_AUTH)" \
  value_is "$work/demo.json" '.services.mailpit.environment.MP_UI_AUTH' demo:dummy
check "demo: Caddy has no alias on c4-infra" \
  value_is "$work/demo.json" '.services["reverse-proxy"].networks.default.aliases // [] | length' 0

# RQ-02: dev's additions stay dev's
check "dev: RabbitMQ's management plugin enabled" has_mount "$work/dev.json" rabbitmq /etc/rabbitmq/enabled_plugins
check "demo: no RabbitMQ management plugin" lacks_mount "$work/demo.json" rabbitmq /etc/rabbitmq/enabled_plugins
check "demo: no RabbitMQ management configuration" lacks_mount "$work/demo.json" rabbitmq /etc/rabbitmq/conf.d/20-c4-infra.conf
check "demo: Grafana's anonymous access off" \
  value_is "$work/demo.json" '.services["grafana-lgtm"].environment.GF_AUTH_ANONYMOUS_ENABLED' false
check "dev: Mailpit's UI without TLS" value_is "$work/dev.json" '.services.mailpit.environment.MP_UI_TLS_CERT // "none"' none

# AC-05: an image version changed in compose.yml only shows in both configurations
mkdir -p "$work/copy"
cp compose.yml compose.dev.yml compose.demo.yml "$DEMO_ENV" "$work/copy/"
sed -i 's|axllent/mailpit:v1.31.0|axllent/mailpit:v0.0.0-test|' "$work/copy/compose.yml"
check "AC-05: the copy's compose.yml names v0.0.0-test" grep -q 'axllent/mailpit:v0.0.0-test' "$work/copy/compose.yml"
for override in dev demo; do
  (cd "$work/copy" && docker compose -f compose.yml -f "compose.$override.yml" --env-file demo.env config --format json) \
    > "$work/copy-$override.json" 2> /dev/null
  check "AC-05: $override's configuration shows axllent/mailpit:v0.0.0-test" \
    value_is "$work/copy-$override.json" .services.mailpit.image axllent/mailpit:v0.0.0-test
done
finish
