#!/usr/bin/env bash
# 0016: the facts the simulated providers are built on, in a throwaway Keycloak of the stack's image
# (start-dev on a file database; its port published on 127.0.0.1, its front-end URL there, and the
# network alias keycloak for the back channel, as on the stack's networks):
#
#   (a) a theme JAR in /opt/keycloak/providers/ serves its login theme, and an application's folder
#       theme in /opt/keycloak/themes/ is still served beside it;
#   (b) a user without an e-mail address is refused under the default user profile ("Account is not
#       fully set up": the address is required of users), and logs in once the profile makes the
#       address optional;
#   (c) the user attributes picture and is_private_email, once the user profile declares them,
#       reach the ID token and the user info through attribute mappers;
#   (d) a client without the profile scope gets no name in its ID token;
#   (e) a realm brokers another realm of the same Keycloak as an OpenID Connect provider, its
#       authorization URL on the front-end URL and its token, user info and keys URLs on
#       http://keycloak:8080 (the back channel), the provider's issuer checked: a browser flow
#       (curl, its cookies) signs in through it, and the brokering realm holds the brokered user;
#   (f) a client whose redirect URIs are https://infra.test/auth/realms/* accepts a broker endpoint
#       of a realm of that host, and refuses another host, another path, http, and a path climbing
#       out with ..
#
#   bash tests/0016-keycloak-facts.sh
#
# Needs the image c4-infra/keycloak (up.sh builds it). The throwaway is removed whatever happens.
#
# covers: keycloak/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/docker-preflight.sh
mapfile -t C4_LABELS < <(docker_labels c4-infra)
source tests/lib/keycloak.sh

IMAGE=c4-infra/keycloak
NAME=c4-infra.0016-facts
NETWORK=c4-infra-0016-facts
PORT=48416
FRONT=http://127.0.0.1:$PORT/auth
SERVER=http://localhost:8080/auth
export MSYS_NO_PATHCONV=1

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

umask 022
work=$(mktemp -d)
cleanup() {
  docker rm -f -v "$NAME" > /dev/null 2>&1
  docker network rm "$NETWORK" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
docker rm -f -v "$NAME" > /dev/null 2>&1
docker network rm "$NETWORK" > /dev/null 2>&1

KC_CLI_PASSWORD=$(openssl rand -hex 16)
export KC_CLI_PASSWORD
printf '%s\n' KC_BOOTSTRAP_ADMIN_USERNAME=admin "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD" > "$work/admin.env"
chmod 600 "$work/admin.env"
admin() { # <kcadm args…>: as the throwaway's administrator, the request's JSON on stdin
  docker exec -i -e KC_CLI_PASSWORD "$NAME" /opt/keycloak/bin/kcadm.sh "$@" \
    --no-config --server "$SERVER" --realm master --user admin 2>> "$work/admin.err"
}

# (a) a theme JAR, built with the image's jar tool, and a folder theme
mkdir -p "$work/jar/META-INF" "$work/jar/theme/facts-jar/login/messages" "$work/providers" \
  "$work/themes/facts-folder/login/messages"
printf '{"themes":[{"name":"facts-jar","types":["login"]}]}\n' > "$work/jar/META-INF/keycloak-themes.json"
printf 'parent=keycloak.v2\n' > "$work/jar/theme/facts-jar/login/theme.properties"
printf 'loginAccountTitle=Facts JAR theme\n' > "$work/jar/theme/facts-jar/login/messages/messages_en.properties"
printf 'parent=keycloak.v2\n' > "$work/themes/facts-folder/login/theme.properties"
printf 'loginAccountTitle=Facts folder theme\n' > "$work/themes/facts-folder/login/messages/messages_en.properties"
docker run "${C4_LABELS[@]}" --rm --user 0 --entrypoint java -v "$(host_path "$work"):/w" "$IMAGE" \
  -m jdk.jartool/sun.tools.jar.Main --create --file /w/providers/facts-themes.jar -C /w/jar . > "$work/jar.log" 2>&1
check "(a) the theme JAR is built with the image's java" test -s "$work/providers/facts-themes.jar"

docker network create "${C4_LABELS[@]}" "$NETWORK" > /dev/null
docker run "${C4_LABELS[@]}" -d --name "$NAME" --network "$NETWORK" --network-alias keycloak -p "127.0.0.1:$PORT:8080" \
  --env-file "$(host_path "$work/admin.env")" \
  -v "$(host_path "$work/providers"):/opt/keycloak/providers:ro" -v "$(host_path "$work/themes"):/opt/keycloak/themes:ro" \
  "$IMAGE" start-dev --db=dev-file "--hostname=$FRONT" > /dev/null
check "(a) the throwaway answers its readiness probe" kc_throwaway_ready "$NAME"

realm() { # <JSON>: a realm created from it
  admin create realms -f - <<< "$1" > /dev/null
}
login_page() { # <realm>: its login page, through the account client
  curl -s -L -c "$(host_path "$work/page.jar")" -b "$(host_path "$work/page.jar")" -G \
    --data-urlencode client_id=account --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode "redirect_uri=$FRONT/realms/$1/account/" \
    "$FRONT/realms/$1/protocol/openid-connect/auth" > "$work/page.html"
}
page_holds() { grep -qF -- "$1" "$work/page.html" || { echo "page:"; head -c 600 "$work/page.html"; return 1; }; }
realm '{"realm":"facts-jar","enabled":true,"loginTheme":"facts-jar"}'
realm '{"realm":"facts-folder","enabled":true,"loginTheme":"facts-folder"}'
login_page facts-jar
check "(a) the JAR's login theme is served (its message)" page_holds "Facts JAR theme"
login_page facts-folder
check "(a) a folder theme beside it is served too (its message)" page_holds "Facts folder theme"

# (b), (c), (d): realm sim, a public client with direct grants for the tokens, the user profile
# declaring picture and is_private_email, a client scope mapping them, a client without profile
realm "$(jq -n --arg port "$PORT" '{
  realm: "sim", enabled: true,
  clients: [
    { clientId: "sim-direct", publicClient: true, directAccessGrantsEnabled: true, standardFlowEnabled: false,
      defaultClientScopes: ["basic", "profile", "email"] },
    { clientId: "sim-no-profile", publicClient: true, directAccessGrantsEnabled: true, standardFlowEnabled: false,
      defaultClientScopes: ["basic", "email"], optionalClientScopes: [] },
    { clientId: "broker", secret: "facts-broker-secret", publicClient: false, standardFlowEnabled: true,
      directAccessGrantsEnabled: false, redirectUris: ["http://127.0.0.1:\($port)/auth/realms/*"],
      defaultClientScopes: ["basic", "profile", "email"] },
    { clientId: "redirects", secret: "facts-redirects-secret", publicClient: false, standardFlowEnabled: true,
      redirectUris: ["https://infra.test/auth/realms/*"] } ],
  users: [
    { username: "with-address", enabled: true, email: "with-address@sim.test", emailVerified: true,
      firstName: "With", lastName: "Address",
      credentials: [ { type: "password", value: "with-address-password", temporary: false } ] },
    { username: "no-address", enabled: true, firstName: "No", lastName: "Address",
      credentials: [ { type: "password", value: "no-address-password", temporary: false } ] } ]
}')"
# the claims' scope, created once the realm has its built-in scopes, as a default of two clients
admin create client-scopes -r sim -f - > /dev/null <<'JSON'
{"name": "sim-claims", "protocol": "openid-connect", "attributes": {"include.in.token.scope": "false"},
 "protocolMappers": [
  {"name": "picture", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-attribute-mapper",
   "config": {"user.attribute": "picture", "claim.name": "picture", "jsonType.label": "String",
              "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true"}},
  {"name": "is_private_email", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-attribute-mapper",
   "config": {"user.attribute": "is_private_email", "claim.name": "is_private_email", "jsonType.label": "boolean",
              "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true"}}]}
JSON
scope_id=$(admin get client-scopes -r sim | jq -r '.[] | select(.name == "sim-claims") | .id')
for client in sim-direct broker; do
  client_id=$(admin get clients -r sim -q "clientId=$client" --fields id | jq -r '.[0].id')
  admin update "clients/$client_id/default-client-scopes/$scope_id" -r sim < /dev/null > /dev/null
done
token() { # <client> <user> <password>: the token response, in $work/token.json
  curl -s -o "$(host_path "$work/token.json")" -w '%{http_code}' -d grant_type=password -d "client_id=$1" -d "username=$2" \
    -d "password=$3" -d scope=openid "$FRONT/realms/sim/protocol/openid-connect/token"
}
refused_not_set_up() {
  [ "$(token sim-direct no-address no-address-password)" = 400 ] && grep -qF 'Account is not fully set up' "$work/token.json" \
    || { cat "$work/token.json"; return 1; }
}
check "(b) a user without an address, under the default user profile: refused, not fully set up" refused_not_set_up
user_profile() {
  admin get realms/sim/users/profile | jq '(.attributes[] | select(.name == "email")) |= del(.required) | .attributes += [
    { name: "picture", displayName: "Picture", permissions: { view: ["admin", "user"], edit: ["admin"] }, multivalued: false },
    { name: "is_private_email", displayName: "Private e-mail", permissions: { view: ["admin", "user"], edit: ["admin"] }, multivalued: false } ]' \
    | admin update realms/sim/users/profile -f - > /dev/null
}
check "(b), (c) the user profile of sim: the address optional, picture and is_private_email declared" user_profile
# the attributes, set once declared (-s: kcadm merges them into the user; a partial JSON would clear
# its address and names)
with_address=$(admin get users -r sim -q username=with-address --fields id | jq -r '.[0].id')
admin update "users/$with_address" -r sim -s 'attributes.picture=["https://sim.test/with-address.png"]' \
  -s 'attributes.is_private_email=["true"]' < /dev/null > /dev/null

check "(b) the address optional: the user without one logs in (a direct grant: 200)" test "$(token sim-direct no-address no-address-password)" = 200
check "(b) its ID token has no email claim" eval 'kc_claims "$(jq -r .id_token < "$work/token.json")" | jq -e "has(\"email\") | not" > /dev/null'
check "(c) with-address logs in" test "$(token sim-direct with-address with-address-password)" = 200
id_claims=$(kc_claims "$(jq -r .id_token < "$work/token.json")")
check "(c) its ID token holds picture" test "$(jq -r .picture <<< "$id_claims")" = https://sim.test/with-address.png
check "(c) and is_private_email, a boolean" test "$(jq -c .is_private_email <<< "$id_claims")" = true
userinfo=$(curl -s -H "Authorization: Bearer $(jq -r .access_token < "$work/token.json")" "$FRONT/realms/sim/protocol/openid-connect/userinfo")
check "(c) the user info holds both" test "$(jq -c '[.picture, .is_private_email]' <<< "$userinfo")" = '["https://sim.test/with-address.png",true]'
check "(d) a client without the profile scope logs in" test "$(token sim-no-profile with-address with-address-password)" = 200
check "(d) its ID token has no name" eval 'kc_claims "$(jq -r .id_token < "$work/token.json")" | jq -e "(has(\"name\") or has(\"given_name\") or has(\"family_name\")) | not" > /dev/null'
check "(d) but the address" test "$(kc_claims "$(jq -r .id_token < "$work/token.json")" | jq -r .email)" = with-address@sim.test

# (e) realm app brokers sim: the authorization URL on the front end, the rest on the back channel
realm "$(jq -n --arg front "$FRONT" '{
  realm: "app", enabled: true,
  identityProviders: [ { alias: "google", providerId: "oidc", enabled: true, trustEmail: false,
    config: { issuer: "\($front)/realms/sim", clientId: "broker", clientSecret: "facts-broker-secret",
      clientAuthMethod: "client_secret_post", authorizationUrl: "\($front)/realms/sim/protocol/openid-connect/auth",
      tokenUrl: "http://keycloak:8080/auth/realms/sim/protocol/openid-connect/token",
      userInfoUrl: "http://keycloak:8080/auth/realms/sim/protocol/openid-connect/userinfo",
      jwksUrl: "http://keycloak:8080/auth/realms/sim/protocol/openid-connect/certs", useJwksUrl: "true",
      validateSignature: "true", defaultScope: "openid profile email", syncMode: "IMPORT" } } ],
  clients: [ { clientId: "app-web", publicClient: true, standardFlowEnabled: true,
    redirectUris: ["http://127.0.0.1:9/callback"] } ]
}')"

# The browser: follows redirects itself (keeping the cookies) until a page, or the client's callback
browse() { # <url> [curl option…]: the last page in $work/page.html, the callback URL in $work/callback
  local url=$1 status location i
  shift
  : > "$work/callback"
  for ((i = 0; i < 15; i++)); do
    status=$(curl -s -c "$(host_path "$work/browser.jar")" -b "$(host_path "$work/browser.jar")" \
      -D "$(host_path "$work/browse.h")" -o "$(host_path "$work/page.html")" -w '%{http_code}' "$@" "$url")
    set --
    case "$status" in
      30?)
        location=$(sed -n 's/^[Ll]ocation: //p' "$work/browse.h" | tr -d '\r')
        case "$location" in
          http://127.0.0.1:9/callback*) printf '%s' "$location" > "$work/callback"; return 0 ;;
          /*) location=${FRONT%/auth}$location ;;
        esac
        url=$location
        ;;
      *) return 0 ;;
    esac
  done
  echo "too many redirects"
  return 1
}
form_action() { grep -o 'action="[^"]*"' "$work/page.html" | head -n 1 | sed 's/^action="//; s/"$//; s/&amp;/\&/g'; }

browse "$FRONT/realms/app/protocol/openid-connect/auth?client_id=app-web&response_type=code&scope=openid&redirect_uri=http%3A%2F%2F127.0.0.1%3A9%2Fcallback&kc_idp_hint=google"
check "(e) the brokering realm sends the browser to sim's login page" page_holds 'kc-form-login'
action=$(form_action)
check "(e) whose form posts to sim ($action)" eval '[[ $action == "$FRONT/realms/sim/login-actions/authenticate"* ]]'
browse "$action" -d username=with-address -d password=with-address-password -d credentialId=
callback_reached() { [ -s "$work/callback" ] || { echo "no callback; page:"; sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$work/page.html"; grep -o 'kc-feedback-text">[^<]*' "$work/page.html"; docker logs --tail 5 "$NAME" 2>&1 | cut -c1-300; return 1; }; }
check "(e) signed in through sim, back to the client's callback with a code" callback_reached
brokered=$(admin get users -r app -q username=with-address --fields id,email,firstName | jq -c '.[0]')
check "(e) realm app holds the brokered user ($brokered)" test "$(jq -r .email <<< "$brokered")" = with-address@sim.test
identities=$(admin get "users/$(jq -r .id <<< "$brokered")/federated-identity" -r app | jq -r '.[].identityProvider')
check "(e) linked to the provider google ($identities)" test "$identities" = google
issuer=$(curl -s "$FRONT/realms/sim/.well-known/openid-configuration" | jq -r .issuer)
check "(e) sim's issuer is the one the provider checks ($issuer)" test "$issuer" = "$FRONT/realms/sim"

# (f) redirect URIs: a pattern on the infra host's realms
authorization_status() { # <redirect_uri>
  curl -s -o "$(host_path "$work/authorization.html")" -w '%{http_code}' -G \
    --data-urlencode client_id=redirects --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode "redirect_uri=$1" "$FRONT/realms/sim/protocol/openid-connect/auth"
}
check "(f) a broker endpoint of a realm of the infra host: accepted (200)" \
  test "$(authorization_status https://infra.test/auth/realms/someapp/broker/google/endpoint)" = 200
for uri in https://evil.test/auth/realms/someapp/broker/google/endpoint https://infra.test/other \
  http://infra.test/auth/realms/someapp/broker/google/endpoint https://infra.test/auth/realms/../../other; do
  check "(f) $uri: refused (400)" test "$(authorization_status "$uri")" = 400
done
finish
