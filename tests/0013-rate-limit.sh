#!/usr/bin/env bash
# 0013: the proxy limits a realm's client registration endpoint to 10 requests a minute per client
# address, 429 beyond, and nothing else (AC-14, RQ-16), on the dev stack:
#
#   - from this workstation, 11 anonymous registrations of realm master within the minute: the first
#     10 answered by Keycloak (403, its Trusted Hosts policy), the 11th by the proxy (429);
#   - meanwhile, the same address's request to the realm's discovery document is answered (200);
#   - from another address, a throwaway container on the shared services' network c4-infra, a
#     registration is answered by Keycloak (403), not 429.
#
#   bash tests/0013-rate-limit.sh
#
# Needs the dev stack running (up.sh); the throwaway container is removed whatever happens.
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ reverse-proxy/ keycloak/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

BASE=https://host.docker.internal
REGISTRATION=/auth/realms/master/clients-registrations/openid-connect
PROBE=c4-infra.0013-rate-limit
trap 'docker rm -f "$PROBE" > /dev/null 2>&1' EXIT
docker rm -f "$PROBE" > /dev/null 2>&1

register() { # the status of one anonymous registration, from this workstation
  kc_curl -o /dev/null -w '%{http_code}' -X POST \
    -H 'Content-Type: application/json' -d '{"redirect_uris":["https://example.org/callback"]}' "$BASE$REGISTRATION"
}

statuses=()
for _ in $(seq 1 11); do statuses+=("$(register)"); done
first_ten=$(printf '%s\n' "${statuses[@]:0:10}" | sort -u | paste -sd' ' -)
check "AC-14: the first 10 registrations of the minute reach Keycloak ($first_ten)" test "$first_ten" = 403
check "AC-14: the 11th gets 429 from the proxy (${statuses[10]})" test "${statuses[10]}" = 429
discovery=$(kc_curl -o /dev/null -w '%{http_code}' "$BASE/auth/realms/master/.well-known/openid-configuration")
check "AC-14: the same address's other requests to Keycloak are answered ($discovery)" test "$discovery" = 200

# Another address: a container on c4-infra, reaching the proxy by its network address, under the
# shared host's name
proxy_address=$(docker inspect -f '{{(index .NetworkSettings.Networks "c4-infra").IPAddress}}' c4-infra.reverse-proxy | tr -d '\r')
other=$(MSYS_NO_PATHCONV=1 docker run --rm --name "$PROBE" --network c4-infra --add-host "host.docker.internal:$proxy_address" \
  caddy:2.11.4-alpine wget -q -S -O /dev/null --no-check-certificate --header 'Content-Type: application/json' \
  --post-data '{"redirect_uris":["https://example.org/callback"]}' "$BASE$REGISTRATION" 2>&1 \
  | sed -n 's|^ *HTTP/[0-9.]* \([0-9]*\).*|\1|p' | tail -n 1)
check "AC-14: another address isn't limited ($other from $proxy_address's network)" test "$other" = 403

finish
