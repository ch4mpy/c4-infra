#!/usr/bin/env bash
# 0013: the facts the stack's Keycloak 26.8.1 and its proxy are built on, checked in a throwaway
# Keycloak of the stack's image (start-dev on a file database, no published port) and in the proxy's
# image:
#
#   (a) its built-in themes are the ones no registry entry may claim (registry.sh,
#       REGISTRY_KEYCLOAK_THEMES), and the healthcheck compiled into the image answers;
#   (b) it starts with token-exchange-delegation and parameterized-scopes (preview) and cimd
#       (experimental), nothing else;
#   (c) its client-id-metadata-document executor has the settings register-app.sh reads:
#       cimd-allow-http-scheme (a boolean) and cimd-allow-permitted-domains (a list), exported as a
#       boolean and a list; a realm whose domains aren't a list is refused;
#   (d) it reads the http setting as Jackson does: "TRUE" and 1 let it fetch a client's metadata over
#       http, false doesn't;
#   (e) it permits a host equal to a domain, or ending with what follows "*.": "*." lets it fetch from
#       any host written with a final dot, "*" from none, a named domain from that domain only;
#   (f) the proxy's image has the rate_limit handler the Caddyfile uses.
#
# A fetch is seen in Keycloak's log ("UnknownHostException: <host>": the throwaway resolves no
# example host), a refusal by its absence.
#
#   bash tests/0013-keycloak-facts.sh
#
# Needs the images c4-infra/keycloak and c4-infra/reverse-proxy (up.sh builds them). The throwaway
# container is removed whatever happens.
#
# covers: keycloak/ reverse-proxy/ registry.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh
source ./registry.sh

IMAGE=c4-infra/keycloak
PROXY_IMAGE=c4-infra/reverse-proxy
NAME=c4-infra.0013-facts
SERVER=http://localhost:8080/auth
export MSYS_NO_PATHCONV=1

host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

umask 077
work=$(mktemp -d)
trap 'docker rm -f "$NAME" > /dev/null 2>&1; rm -rf "$work"' EXIT
docker rm -f "$NAME" > /dev/null 2>&1

KC_CLI_PASSWORD=$(openssl rand -hex 16)
export KC_CLI_PASSWORD
printf '%s\n' KC_BOOTSTRAP_ADMIN_USERNAME=admin "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD" > "$work/admin.env"

admin() { # <kcadm args…>: as the throwaway's administrator, the request's JSON on stdin
  docker exec -i -e KC_CLI_PASSWORD "$NAME" /opt/keycloak/bin/kcadm.sh "$@" \
    --no-config --server "$SERVER" --realm master --user admin 2> "$work/admin.err"
}

# (a)
mkdir -p "$work/lib"
container=$(docker create "$IMAGE")
docker cp "$container:/opt/keycloak/lib/lib/main" "$(host_path "$work/lib")" > /dev/null
docker rm "$container" > /dev/null
builtin=$(for jar in "$work"/lib/main/*.jar; do
  unzip -p "$jar" META-INF/keycloak-themes.json 2> /dev/null | jq -r '.themes[]?.name' 2> /dev/null
done | tr -d '\r' | LC_ALL=C sort -u | paste -sd' ' -)
reserved=$(printf '%s\n' "${REGISTRY_KEYCLOAK_THEMES[@]}" | LC_ALL=C sort | paste -sd' ' -)
check "(a) the built-in themes ($builtin) are registry.sh's reserved ones ($reserved)" test "$builtin" = "$reserved"

docker run -d --name "$NAME" --env-file "$(host_path "$work/admin.env")" "$IMAGE" start-dev --db=dev-file > /dev/null
check "(a) the throwaway answers the image's healthcheck" kc_throwaway_ready "$NAME"

# (b)
log=$(docker logs "$NAME" 2>&1 | tr -d '\r')
check "(b) Keycloak 26.8.1" grep -qF "Keycloak 26.8.1 on JVM" <<< "$log"
check "(b) preview: parameterized-scopes, token-exchange-delegation" \
  test "$(kc_features Preview "$log")" = "parameterized-scopes:v1,token-exchange-delegation:v1"
check "(b) experimental: cimd alone" test "$(kc_features Experimental "$log")" = "cimd:v1"

# (c)
executor=$(admin get serverinfo < /dev/null | jq -c '[.componentTypes[][] | select(.id == "client-id-metadata-document")
  | .properties[] | select(.name | startswith("cimd-allow-")) | {(.name): .type}] | add')
check "(c) the executor's settings: cimd-allow-http-scheme a boolean, cimd-allow-permitted-domains a list ($executor)" \
  test "$executor" = '{"cimd-allow-http-scheme":"boolean","cimd-allow-permitted-domains":"MultivaluedString"}'

# A realm whose CIMD policy applies to client IDs of the given schemes and domains, its executor
# configured with the given JSON (the domains are the condition's too)
cimd_realm() { # <realm> <schemes JSON> <executor configuration JSON>
  jq -n --arg realm "$1" --argjson schemes "$2" --argjson executor "$3" '{
    realm: $realm, enabled: true,
    clientProfiles: { profiles: [ { name: "cimd", executors: [ { executor: "client-id-metadata-document", configuration: $executor } ] } ] },
    clientPolicies: { policies: [ { name: "cimd", enabled: true, profiles: [ "cimd" ],
      conditions: [ { condition: "client-id-uri", configuration: { "client-id-uri-scheme": $schemes,
        "client-id-uri-allow-permitted-domains": ($executor["cimd-allow-permitted-domains"] // []) } } ] } ] }
  }' | admin create realms -f - > /dev/null
}
exported() { # <realm> <jq filter>: the value in the realm's partial export
  admin create "realms/$1/partial-export" -o < /dev/null | jq -c "$2"
}
cimd_realm facts-export '["https"]' '{"cimd-allow-http-scheme":true,"cimd-allow-permitted-domains":["*.example.org"]}'
check "(c) exported as a boolean and a list" \
  test "$(exported facts-export '.clientProfiles.profiles[0].executors[0].configuration')" = '{"cimd-allow-http-scheme":true,"cimd-allow-permitted-domains":["*.example.org"]}'
refused_import() { # <realm> <executor configuration JSON>
  ! cimd_realm "$1" '["https"]' "$2" || { echo "imported"; return 1; }
}
check '(c) domains as a string ("*") are refused at import' refused_import facts-string '{"cimd-allow-permitted-domains":"*"}'
check '(c) domains as a "##"-joined string are refused at import' refused_import facts-joined '{"cimd-allow-permitted-domains":"a.example##*"}'

# An authorization request of the client <client_id> to <realm>, from inside the throwaway (its
# image has no curl)
authorize() { # <realm> <client_id>
  local id
  id=$(jq -rn --arg v "$2" '$v | @uri')
  docker exec "$NAME" bash -c 'exec 3<> /dev/tcp/localhost/8080
    printf "GET /auth/realms/%s/protocol/openid-connect/auth?client_id=%s&redirect_uri=%s&response_type=code&scope=openid HTTP/1.0\r\nHost: localhost\r\n\r\n" "$1" "$2" "$2" >&3
    cat <&3 > /dev/null' sh "$1" "$id"
}
fetched() { # <realm> <client_id> <host>: Keycloak tried to fetch the client's metadata from <host>
  authorize "$1" "$2"
  docker logs "$NAME" 2>&1 | grep -qF "UnknownHostException: $3:" || { echo "no fetch from $3"; return 1; }
}
not_fetched() { # <realm> <client_id> <host>
  authorize "$1" "$2"
  ! docker logs "$NAME" 2>&1 | grep -qF "UnknownHostException: $3:" || { echo "fetched from $3"; return 1; }
}

# (d)
cimd_realm facts-http-upper '["http","https"]' '{"cimd-allow-http-scheme":"TRUE","cimd-allow-permitted-domains":["http-upper.example"]}'
check '(d) "TRUE": fetched over http' fetched facts-http-upper http://http-upper.example/cimd http-upper.example
cimd_realm facts-http-one '["http","https"]' '{"cimd-allow-http-scheme":1,"cimd-allow-permitted-domains":["http-one.example"]}'
check '(d) 1: fetched over http' fetched facts-http-one http://http-one.example/cimd http-one.example
cimd_realm facts-http-off '["http","https"]' '{"cimd-allow-http-scheme":false,"cimd-allow-permitted-domains":["http-off.example"]}'
check "(d) false: not fetched over http" not_fetched facts-http-off http://http-off.example/cimd http-off.example
check "(d) false: fetched over https" fetched facts-http-off https://http-off.example/cimd http-off.example

# (e)
cimd_realm facts-star-dot '["https"]' '{"cimd-allow-permitted-domains":["*."]}'
check '(e) "*.": fetched from any host written with a final dot' fetched facts-star-dot https://star-dot.example./cimd star-dot.example.
cimd_realm facts-star '["https"]' '{"cimd-allow-permitted-domains":["*"]}'
check '(e) "*": not fetched from a host' not_fetched facts-star https://star.example/cimd star.example
check '(e) "*": nor from one written with a final dot' not_fetched facts-star https://star.example./cimd star.example.
cimd_realm facts-named '["https"]' '{"cimd-allow-permitted-domains":["named.example"]}'
check "(e) a named domain: fetched from it" fetched facts-named https://named.example/cimd named.example
check "(e) a named domain: not from another" not_fetched facts-named https://other.example/cimd other.example

# (f)
check "(f) the proxy's image has http.handlers.rate_limit" \
  bash -c 'docker run --rm "$1" caddy list-modules 2> /dev/null | tr -d "\r" | grep -qx http.handlers.rate_limit' sh "$PROXY_IMAGE"
finish
