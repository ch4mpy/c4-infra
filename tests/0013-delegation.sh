#!/usr/bin/env bash
# 0013: the delegation Turu's agents rely on, on the shared Keycloak (AC-03, AC-04, RQ-05, RQ-06), in
# dev: the fixture application verif-delegation (tests/fixtures/0013/registry.txt) registers its realm,
# Turu's own export with ids of its own (tests/fixtures/0013/verif-delegation-realm.json), then the
# checks 1 to 4 of Turu's keycloak/check-agent-delegation.sh run against it:
#
#   1. the agent client's login (authorization code with PKCE, consent) asking the scope
#      delegation:client:<actor> gives a token for the MCP server carrying may_act, which names the
#      actor;
#   2. without that scope, no may_act, and the delegated exchange is refused;
#   3. the actor's delegated exchange gives an access token whose act names the actor (AC-03);
#   4. a standard exchange of a token carrying may_act is refused;
#
# and AC-04: once the realm's FGAP v2 delegate permission is removed, the request of 3 (a new login
# asking the same scope, its may_act naming the actor) gets no delegated token.
#
#   bash tests/0013-delegation.sh
#
# Needs the dev stack running (up.sh). The realm and the network this test creates are removed
# whatever happens. Dev values only: the fixture's users and clients have the secret "secret".
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0013/registry.txt
FIXTURE=tests/fixtures/0013
SERVER=https://host.docker.internal
REALM=$SERVER/auth/realms/verif-delegation
OIDC=$REALM/protocol/openid-connect
REDIRECT=http://127.0.0.1/callback
AGENT=turu-agent-dev
ACTOR=turu-agent-dev-actor
SECRET=secret

work=$(mktemp -d)
new_network=false
docker network inspect c4-infra.verif-delegation > /dev/null 2>&1 || new_network=true
remove_fixture() {
  kc_registration delete realms/verif-delegation > /dev/null 2>&1
}
cleanup() {
  remove_fixture
  ! $new_network || bash networks.sh remove verif-delegation > /dev/null
  rm -rf "$work"
}
trap cleanup EXIT
remove_fixture

curl_ca() { curl --ssl-no-revoke --cacert certs/ca.crt -s "$@"; }
# Payload of a JWT, padding restored
claims() {
  local payload
  payload=$(printf '%s' "$1" | cut -d. -f2 | tr '_-' '/+')
  while [ $((${#payload} % 4)) -ne 0 ]; do payload="${payload}="; done
  printf '%s' "$payload" | base64 -d
}
absolute() { case "$1" in /*) echo "$SERVER$1" ;; *) echo "$1" ;; esac; }

# The agent's login by the browser flow: username then password, the agency asked when it is, the
# consent. Prints the token response.
agent_login() { # <user> <scope>
  local jar="$work/cookies" page="$work/page" headers="$work/headers" verifier challenge action location code
  rm -f "$jar"
  verifier=$(head -c 48 /dev/urandom | base64 | tr -d '=+/\n' | cut -c1-64)
  challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
  curl_ca -c "$jar" -b "$jar" -o "$page" -G "$OIDC/auth" --data-urlencode "client_id=$AGENT" \
    --data-urlencode response_type=code --data-urlencode "redirect_uri=$REDIRECT" --data-urlencode "scope=$2" \
    --data-urlencode "code_challenge=$challenge" --data-urlencode code_challenge_method=S256 --data-urlencode state=check
  location=""
  for _ in 1 2 3 4 5 6; do
    action=$(grep -o 'action="[^"]*"' "$page" | head -1 | sed 's/action="//; s/"$//; s/&amp;/\&/g')
    [ -n "$action" ] || break
    action=$(absolute "$action")
    local data=()
    if grep -q 'id="kc-form-login"' "$page"; then
      data=(--data-urlencode "username=$1" --data-urlencode "password=$SECRET")
    elif grep -q 'name="kc.org"' "$page"; then
      data=(--data-urlencode "kc.org=uri")
    elif grep -q 'name="accept"' "$page"; then
      data=(--data-urlencode "code=$(grep -o 'name="code" value="[^"]*"' "$page" | sed 's/.*value="//; s/"$//')" --data-urlencode accept=yes)
    else
      break
    fi
    curl_ca -c "$jar" -b "$jar" -D "$headers" -o "$page" "${data[@]}" "$action"
    location=$(grep -i '^location:' "$headers" | tr -d '\r' | sed 's/^[Ll]ocation: //')
    if [ -n "$location" ]; then
      case "$location" in "$REDIRECT"*) break ;; esac
      curl_ca -c "$jar" -b "$jar" -o "$page" "$(absolute "$location")"
      location=""
    fi
  done
  code=$(printf '%s' "$location" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
  [ -n "$code" ] || return 1
  curl_ca -d grant_type=authorization_code -d "client_id=$AGENT" -d "code=$code" -d "redirect_uri=$REDIRECT" \
    -d "code_verifier=$verifier" "$OIDC/token"
}
client_token() { # <client>
  curl_ca -d grant_type=client_credentials -d "client_id=$1" -d "client_secret=$SECRET" "$OIDC/token" | jq -r .access_token | tr -d '\r'
}
delegated_exchange() { # <client> <subject token> <actor token>
  curl_ca -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange -d "client_id=$1" -d "client_secret=$SECRET" \
    -d "subject_token=$2" -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
    -d "actor_token=$3" -d actor_token_type=urn:ietf:params:oauth:token-type:access_token "$OIDC/token"
}

register() {
  bash register-app.sh --app verif-delegation --realm "$FIXTURE/verif-delegation-realm.json" > "$work/register.log" 2>&1 \
    || { tail -n 10 "$work/register.log"; return 1; }
}
check "verif-delegation registers its realm (Turu's export, ids of its own)" register

# 1
agent_token=$(agent_login uri.accountant "openid delegation:client:$ACTOR" | jq -r '.access_token // empty' | tr -d '\r')
check "1: the agent's login, asking delegation:client:$ACTOR, gives a token" test -n "$agent_token"
agent_claims=$(claims "$agent_token")
check "1: its may_act names $ACTOR" test "$(jq -r '.may_act.client_id' <<< "$agent_claims" | tr -d '\r')" = "$ACTOR"
check "1: its audience is the MCP server" bash -c 'jq -e ".aud | index(\"turu-mcp\")" > /dev/null' <<< "$agent_claims"

# 2
plain=$(agent_login uri.accountant openid | jq -r '.access_token // empty' | tr -d '\r')
actor_token=$(client_token "$ACTOR")
check "2: without the delegation scope, a token" test -n "$plain"
check "2: without may_act" test -z "$(claims "$plain" | jq -r '.may_act // empty' | tr -d '\r')"
check "2: and the delegated exchange is refused" \
  test -z "$(delegated_exchange "$ACTOR" "$plain" "$actor_token" | jq -r '.access_token // empty' | tr -d '\r')"

# 3 (AC-03)
exchanged=$(delegated_exchange "$ACTOR" "$agent_token" "$actor_token")
delegated=$(jq -r '.access_token // empty' <<< "$exchanged" | tr -d '\r')
check "AC-03: the actor's delegated exchange gives a token ($(jq -c '.error // "ok"' <<< "$exchanged"))" test -n "$delegated"
delegated_claims=$(claims "$delegated")
check "AC-03: its act names the actor" test "$(jq -r '.act.client_id' <<< "$delegated_claims" | tr -d '\r')" = "$ACTOR"
check "AC-03: its subject is the user's" \
  test "$(jq -r .sub <<< "$delegated_claims" | tr -d '\r')" = "$(jq -r .sub <<< "$agent_claims" | tr -d '\r')"
check "AC-03: no refresh token" test -z "$(jq -r '.refresh_token // empty' <<< "$exchanged" | tr -d '\r')"

# 4
standard=$(curl_ca -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange -d "client_id=$ACTOR" -d "client_secret=$SECRET" \
  -d "subject_token=$agent_token" -d subject_token_type=urn:ietf:params:oauth:token-type:access_token -d audience=turu-api "$OIDC/token")
check "4: a standard exchange of a token carrying may_act is refused" test -z "$(jq -r '.access_token // empty' <<< "$standard" | tr -d '\r')"

# AC-04: 1 and 3's requests again, once the realm holds no delegate permission. Keycloak checks it at
# the login (measured on 26.8.1): the token then carries neither the delegation scope nor may_act.
remove_delegate_permission() {
  local permissions id
  permissions=clients/$(kc_registration get clients -r verif-delegation -q clientId=admin-permissions --fields id \
    | jq -r '.[0].id')/authz/resource-server/permission
  id=$(kc_registration get "$permissions" -r verif-delegation | jq -r '.[] | select(.name == "agents-delegate") | .id')
  [ -n "$id" ] || { echo "no permission agents-delegate"; return 1; }
  kc_registration delete "$permissions/$id" -r verif-delegation
}
check "AC-04: the realm's delegate permission (agents-delegate) is removed" remove_delegate_permission
agent_token=$(agent_login uri.accountant "openid delegation:client:$ACTOR" | jq -r '.access_token // empty' | tr -d '\r')
agent_claims=$(claims "$agent_token")
check "AC-04: the agent's login, asking delegation:client:$ACTOR, gives a token" test -n "$agent_token"
check "AC-04: without delegation:client:$ACTOR among its scopes ($(jq -r .scope <<< "$agent_claims" | tr -d '\r'))" \
  jq -e --arg scope "delegation:client:$ACTOR" '.scope | split(" ") | index($scope) == null' <<< "$agent_claims"
check "AC-04: nor may_act" test -z "$(jq -r '.may_act // empty' <<< "$agent_claims" | tr -d '\r')"
actor_token=$(client_token "$ACTOR")
exchanged=$(delegated_exchange "$ACTOR" "$agent_token" "$actor_token")
check "AC-04: the actor's delegated exchange is refused ($(jq -c '.error_description // "granted"' <<< "$exchanged"))" \
  test -z "$(jq -r '.access_token // empty' <<< "$exchanged" | tr -d '\r')"

finish
