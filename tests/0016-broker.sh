#!/usr/bin/env bash
# 0016: an application's realm brokers the simulated providers, on the dev stack (AC-03, AC-04,
# AC-05): the fixture application verif-social (tests/fixtures/0016/registry.txt) registers two realms,
# verif-social-a and verif-social-b, each declaring the three simulated providers as oidc (aliases
# google, facebook, apple) with their shared client any-application, the authorization URL on the
# infra host and the token, user info and keys on http://keycloak:8080. Then a browser (curl, its
# cookies) signs in through each provider in each realm: kc_idp_hint, the simulated provider's login
# form, back to the realm's broker endpoint, the realm's first-broker-login form when the claims lack
# what its user profile requires (an address, a name), and back to the client's callback with a code:
#
#   - verif-social-a: Google's alice (her names, address and picture), Facebook's carol (no address:
#     the form asks for one), Apple's relay (a private relay address, is_private_email, no name: the
#     form asks for it);
#   - verif-social-b: Google's bob, Facebook's alice, Apple's alice (no name: the form asks for it);
#   - AC-05: each simulated realm, as an export of its settings and clients and the list of its users
#     sees it, is the same before the registration and after the six sign-ins.
#
#   bash tests/0016-broker.sh
#
# Needs the dev stack (bash up.sh). The two realms and verif-social's network are removed by a trap,
# whatever happens.
#
# covers: keycloak-import/ keycloak/ register-app.sh registry.sh networks.sh registration-account.sh
# covers: tests/fixtures/0016/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0016/registry.txt
FIXTURE=tests/fixtures/0016
BASE=https://host.docker.internal
CALLBACK=https://verif-social.dev.localhost/callback

work=$(mktemp -d)
new_network=false
docker network inspect c4-infra.verif-social > /dev/null 2>&1 || new_network=true
remove_fixture() {
  kc_registration delete realms/verif-social-a > /dev/null 2>&1
  kc_registration delete realms/verif-social-b > /dev/null 2>&1
}
cleanup() {
  remove_fixture
  ! $new_network || bash networks.sh remove verif-social > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
remove_fixture

# The simulated realms as an export of their settings and clients, and the list of their users, see them
simulated_realms() {
  local realm
  for realm in simulated-google simulated-facebook simulated-apple; do
    kc_admin create "realms/$realm/partial-export" -q exportClients=true -q exportGroupsAndRoles=true -o 2> /dev/null | jq -S .
    kc_admin get users -r "$realm" 2> /dev/null \
      | jq -S 'map({username, email, emailVerified, firstName, lastName, enabled, attributes, createdTimestamp})'
  done
}
before=$(simulated_realms)
check "AC-05: the simulated realms are read before the registration" test -n "$before"

bash register-app.sh --app verif-social --realm "$FIXTURE/verif-social-a-realm.json" \
  --realm "$FIXTURE/verif-social-b-realm.json" > "$work/register.out" 2>&1 < /dev/null
status=$?
registered() { [ "$status" -eq 0 ] || { echo "exit $status:"; tail -n 20 "$work/register.out"; return 1; }; }
check "verif-social registers its realms verif-social-a and verif-social-b" registered

# The browser: follows the redirects itself (its cookies kept) until a page, or the client's callback
browse() { # <url> [curl option…]: the last page in $work/page.html, the callback URL in $work/callback
  local url=$1 status location i
  shift
  : > "$work/callback"
  for ((i = 0; i < 20; i++)); do
    status=$(kc_curl -c "$work/browser.jar" -b "$work/browser.jar" -D "$work/browse.h" -o "$work/page.html" \
      -w '%{http_code}' "$@" "$url")
    set --
    case "$status" in
      30?)
        location=$(sed -n 's/^[Ll]ocation: //p' "$work/browse.h" | tr -d '\r')
        case "$location" in
          "$CALLBACK"*) printf '%s' "$location" > "$work/callback"; return 0 ;;
          /*) location=$BASE$location ;;
        esac
        url=$location
        ;;
      *) return 0 ;;
    esac
  done
  echo "too many redirects"
}
form_action() { grep -o 'action="[^"]*"' "$work/page.html" | head -n 1 | sed 's/^action="//; s/"$//; s/&amp;/\&/g'; }
page_title() { sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$work/page.html" | head -n 1; }
field() { # <name>: the value the page's form holds for it (keycloak.v2 writes an input on several lines)
  tr '\n' ' ' < "$work/page.html" | grep -o "<input[^>]*name=\"$1\"[^>]*>" | head -n 1 \
    | sed -n 's/.*value="\([^"]*\)".*/\1/p'
}

# <realm> <alias> <user> [<email> <first name> <last name>, for the first-broker-login form; empty:
# what the form holds; its username, <user>-<alias> when the claims give none (Apple's)]: sets asked
# (the realm's form was shown) and leaves the callback in $work/callback
sign_in() {
  local action username
  asked=false
  rm -f "$work/browser.jar"
  browse "$BASE/auth/realms/$1/protocol/openid-connect/auth?client_id=verif-web&response_type=code&scope=openid&redirect_uri=$(jq -rn --arg v "$CALLBACK" '$v | @uri')&kc_idp_hint=$2"
  action=$(form_action)
  [[ $action == "$BASE/auth/realms/simulated-$2/login-actions/authenticate"* ]] \
    || { echo "not the simulated $2's login page: $(page_title)"; return 1; }
  browse "$action" -d "username=$3" -d "password=$3-password" -d credentialId=
  if [ ! -s "$work/callback" ] && grep -q 'name="firstName"' "$work/page.html"; then
    asked=true
    username=$(field username)
    browse "$(form_action)" -d "username=${username:-$3-$2}" -d "email=${4:-$(field email)}" \
      -d "firstName=${5:-$(field firstName)}" -d "lastName=${6:-$(field lastName)}"
  fi
  [ -s "$work/callback" ] || { echo "no callback: $(page_title)"; grep -o 'kc-feedback-text">[^<]*' "$work/page.html" | head -n 2; return 1; }
  grep -q '[?&]code=' "$work/callback" || { echo "callback without a code: $(cat "$work/callback")"; return 1; }
}
# sign_in, outside check's subshell (asked must reach the caller): its output in $work/sign.out
signs_in() { # <sign_in's arguments…>
  sign_in "$@" > "$work/sign.out" 2>&1
  sign_status=$?
}
signed_in() { [ "$sign_status" -eq 0 ] || { cat "$work/sign.out"; return 1; }; }
user() { # <realm> <email>: the brokered user, its federated identities' aliases added
  local found id
  found=$(kc_admin get users -r "$1" -q "email=$2" -q exact=true 2> /dev/null | jq -c '.[0] // empty')
  [ -n "$found" ] || return 0
  id=$(jq -r .id <<< "$found")
  jq -c --argjson idps "$(kc_admin get "users/$id/federated-identity" -r "$1" 2> /dev/null | jq -c 'map(.identityProvider)')" \
    '{email, firstName, lastName, picture: .attributes.picture[0], is_private_email: .attributes.is_private_email[0], idps: $idps}' <<< "$found"
}
is() { # <actual> <expected>
  [ "$1" = "$2" ] || { echo "actual:   $1"; echo "expected: $2"; return 1; }
}

signs_in verif-social-a google alice
check "AC-03, verif-social-a: Google's alice signs in" signed_in
check "AC-03: no form asked (her claims hold an address and her names)" test "$asked" = false
check "AC-03: verif-social-a holds her, her names, address and picture, linked to google" \
  is "$(user verif-social-a alice@simulated-google.test)" \
  '{"email":"alice@simulated-google.test","firstName":"Alice","lastName":"Martin","picture":"https://pictures.simulated-google.test/alice.png","is_private_email":null,"idps":["google"]}'

signs_in verif-social-a facebook carol carol@verif-social.test Carol Petit
check "AC-03, verif-social-a: Facebook's carol, who has no address, signs in" signed_in
check "AC-03: the realm's form asked for the address the claims lack" test "$asked" = true
check "AC-03: verif-social-a holds her, the address typed, her names from Facebook, linked to facebook" \
  is "$(user verif-social-a carol@verif-social.test)" \
  '{"email":"carol@verif-social.test","firstName":"Carol","lastName":"Petit","picture":null,"is_private_email":null,"idps":["facebook"]}'

signs_in verif-social-a apple relay '' Dan Relay
check "AC-03, verif-social-a: Apple's relay signs in" signed_in
check "AC-03: the realm's form asked for the name Apple doesn't give" test "$asked" = true
relay=$(user verif-social-a x7k2p9qr4m@privaterelay.simulated-apple.test)
check "AC-03: verif-social-a holds the relay address, is_private_email true, linked to apple" \
  is "$(jq -c '{email, is_private_email, idps}' <<< "$relay")" \
  '{"email":"x7k2p9qr4m@privaterelay.simulated-apple.test","is_private_email":"true","idps":["apple"]}'

signs_in verif-social-b google bob
check "AC-04, verif-social-b: Google's bob signs in through the same shared client" signed_in
check "AC-04: verif-social-b holds him, linked to google" \
  is "$(user verif-social-b bob@simulated-google.test | jq -c '{email, firstName, idps}')" \
  '{"email":"bob@simulated-google.test","firstName":"Bob","idps":["google"]}'
signs_in verif-social-b facebook alice
check "AC-04, verif-social-b: Facebook's alice signs in" signed_in
check "AC-04: no form asked (her address and names from Facebook)" test "$asked" = false
check "AC-04: verif-social-b holds her, linked to facebook" \
  is "$(user verif-social-b alice@simulated-facebook.test | jq -c '{email, firstName, lastName, idps}')" \
  '{"email":"alice@simulated-facebook.test","firstName":"Alice","lastName":"Martin","idps":["facebook"]}'
signs_in verif-social-b apple alice '' Alice Apple
check "AC-04, verif-social-b: Apple's alice signs in" signed_in
check "AC-04: the realm's form asked for her name" test "$asked" = true
check "AC-04: verif-social-b holds her, is_private_email false, linked to apple" \
  is "$(user verif-social-b alice@simulated-apple.test | jq -c '{email, is_private_email, idps}')" \
  '{"email":"alice@simulated-apple.test","is_private_email":"false","idps":["apple"]}'

check "AC-05: the simulated realms are as they were before the registration and the sign-ins" \
  test "$(simulated_realms)" = "$before"
finish
