#!/usr/bin/env bash
# 0016: the three simulated providers' realms on the dev stack (keycloak-import/simulated-*-realm.json):
#
#   - AC-01: they exist; keycloak-import run again skips each ("already exists. Import skipped"), and
#     the other realms are as they were;
#   - AC-02: each one's discovery names its issuer https://host.docker.internal/auth/realms/<name>;
#   - AC-07: registration, password reset and brute-force protection off; their users are PA-05's;
#     no required action enabled, so that a visitor signed in as a public account can't change its
#     password nor add a second factor: an authorization request asking for one (kc_action), signed
#     in, comes back to the redirect URI with a code, no form; and no account role (an imported user
#     gets none): the account console's token of a public account reads no session of the visitors
#     signed in as it (their addresses and browsers), the account API refusing it;
#   - AC-04 (its refusal): the shared client any-application accepts a broker endpoint of a realm of
#     the infra host (the login page, 200), and refuses another host, another path, http and a path
#     climbing out with .. (400);
#   - AC-05 (its refusal): the registration account may not read them (403).
#
#   bash tests/0016-realms.sh
#
# Needs the dev stack (bash up.sh). Changes nothing: keycloak-import imports nothing that exists.
#
# covers: keycloak-import/ compose.yml compose.dev.yml registration-account.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

BASE=https://host.docker.internal
REALMS=(simulated-google simulated-facebook simulated-apple)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# the realms but the simulated ones, with what tells a change: their id and their users' count
others() {
  local realm
  for realm in $(kc_admin get realms --fields realm 2> /dev/null | jq -r '.[].realm' | grep -v '^simulated-' | LC_ALL=C sort); do
    printf '%s %s %s\n' "$realm" "$(kc_admin get "realms/$realm" --fields id 2> /dev/null | jq -r .id)" \
      "$(kc_admin get users/count -r "$realm" 2> /dev/null)"
  done
}
before=$(others)
check "AC-01: the other realms are listed ($(wc -l <<< "$before") of them)" test -n "$before"

docker start -a c4-infra.keycloak-import > "$work/import.log" 2>&1
for realm in "${REALMS[@]}"; do
  check "AC-01: keycloak-import run again: realm $realm already exists, skipped" \
    grep -qF "Realm '$realm' already exists. Import skipped" "$work/import.log"
done
check "AC-01: the other realms are as they were" test "$(others)" = "$before"

for realm in "${REALMS[@]}"; do
  issuer=$(kc_curl "$BASE/auth/realms/$realm/.well-known/openid-configuration" | jq -r .issuer)
  check "AC-02: $realm's issuer ($issuer)" test "$issuer" = "$BASE/auth/realms/$realm"
  settings=$(kc_admin get "realms/$realm" --fields registrationAllowed,resetPasswordAllowed,bruteForceProtected 2> /dev/null \
    | jq -c '[.registrationAllowed, .resetPasswordAllowed, .bruteForceProtected]')
  check "AC-07: $realm: registration, password reset and brute-force protection off ($settings)" \
    test "$settings" = '[false,false,false]'
done

users() { # <realm>: "<username> <email or -> <is_private_email or ->" per user, sorted
  kc_admin get users -r "$1" 2> /dev/null \
    | jq -r '.[] | "\(.username) \(.email // "-") \(.attributes.is_private_email[0] // "-")"' | LC_ALL=C sort | paste -sd' ' -
}
for realm in "${REALMS[@]}"; do
  enabled=$(kc_admin get authentication/required-actions -r "$realm" 2> /dev/null | jq -r '[.[] | select(.enabled) | .alias] | join(",")')
  check "AC-07: $realm: no required action enabled (${enabled:-none})" test -z "$enabled"
done
check "AC-07: simulated-google's users" test "$(users simulated-google)" = \
  'alice alice@simulated-google.test - bob bob@simulated-google.test -'
check "AC-07: simulated-facebook's users, carol without an address" test "$(users simulated-facebook)" = \
  'alice alice@simulated-facebook.test - bob bob@simulated-facebook.test - carol - -'
check "AC-07: simulated-apple's users, relay on a private relay address" test "$(users simulated-apple)" = \
  'alice alice@simulated-apple.test false bob bob@simulated-apple.test false relay x7k2p9qr4m@privaterelay.simulated-apple.test true'

authorization_status() { # <realm> <redirect_uri>
  kc_curl -o /dev/null -w '%{http_code}' -G --data-urlencode client_id=any-application --data-urlencode response_type=code \
    --data-urlencode scope=openid --data-urlencode "redirect_uri=$2" "$BASE/auth/realms/$1/protocol/openid-connect/auth"
}
for realm in "${REALMS[@]}"; do
  check "AC-04: $realm: a broker endpoint of a realm of the infra host: the login page (200)" \
    test "$(authorization_status "$realm" "$BASE/auth/realms/some-app/broker/google/endpoint")" = 200
  for uri in https://evil.test/auth/realms/some-app/broker/google/endpoint "$BASE/other" \
    "http://host.docker.internal/auth/realms/some-app/broker/google/endpoint" "$BASE/auth/realms/../../other"; do
    check "AC-04: $realm: $uri refused (400)" test "$(authorization_status "$realm" "$uri")" = 400
  done
  refused_to_registrations() {
    ! kc_registration get "realms/$1/roles" > "$work/registration.out" 2>&1 \
      && grep -qF 'HTTP 403' "$work/registration.out" || { cat "$work/registration.out"; return 1; }
  }
  check "AC-05: $realm: the registration account may not read it (403)" refused_to_registrations "$realm"
done
# A browser asking for a required action once signed in (Application Initiated Action): it follows
# the redirects (its cookies kept) until a page, or the broker endpoint it was given
ENDPOINT=$BASE/auth/realms/some-app/broker/google/endpoint
browse() { # <url> [curl option…]: the last page in $work/page.html, the endpoint reached in $work/reached
  local url=$1 status location i
  shift
  : > "$work/reached"
  for ((i = 0; i < 15; i++)); do
    status=$(kc_curl -c "$work/jar" -b "$work/jar" -D "$work/h" -o "$work/page.html" -w '%{http_code}' "$@" "$url")
    set --
    case "$status" in
      30?)
        location=$(sed -n 's/^[Ll]ocation: //p' "$work/h" | tr -d '\r')
        case "$location" in
          "$ENDPOINT"*) printf '%s' "$location" > "$work/reached"; return 0 ;;
          /*) location=$BASE$location ;;
        esac
        url=$location
        ;;
      *) return 0 ;;
    esac
  done
}
no_form_for() { # <kc_action>: alice signs in to simulated-google asking for it, and comes back with a code
  local action
  rm -f "$work/jar"
  browse "$BASE/auth/realms/simulated-google/protocol/openid-connect/auth?client_id=any-application&response_type=code&scope=openid&redirect_uri=$(jq -rn --arg v "$ENDPOINT" '$v | @uri')&kc_action=$1"
  action=$(grep -o 'action="[^"]*"' "$work/page.html" | head -n 1 | sed 's/^action="//; s/"$//; s/&amp;/\&/g')
  [ -n "$action" ] || { echo "no login form"; return 1; }
  browse "$action" -d username=alice -d password=alice-password -d credentialId=
  grep -q '[?&]code=' "$work/reached" \
    || { echo "not back with a code: $(sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$work/page.html" | head -n 1)"; return 1; }
}
for kc_action in UPDATE_PASSWORD CONFIGURE_TOTP webauthn-register; do
  check "AC-07: alice signed in asking for $kc_action: back with a code, no form" no_form_for "$kc_action"
done

# alice's token of the account console (its browser flow, PKCE), then the account API's devices
devices_refused() { # <realm>
  local base=$BASE/auth/realms/$1 redirect verifier challenge action location code token status
  redirect=$base/account/
  verifier=$(openssl rand -hex 32)
  challenge=$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')
  rm -f "$work/jar"
  kc_curl -c "$work/jar" -b "$work/jar" -o "$work/page.html" -G --data-urlencode client_id=account-console \
    --data-urlencode "redirect_uri=$redirect" --data-urlencode response_type=code --data-urlencode scope=openid \
    --data-urlencode "code_challenge=$challenge" --data-urlencode code_challenge_method=S256 "$base/protocol/openid-connect/auth"
  action=$(grep -o 'action="[^"]*"' "$work/page.html" | head -n 1 | sed 's/^action="//; s/"$//; s/&amp;/\&/g')
  location=$(kc_curl -c "$work/jar" -b "$work/jar" -o /dev/null -D - -d username=alice -d password=alice-password \
    -d credentialId= "$action" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
  code=$(sed -n 's/.*[?&]code=\([^&]*\).*/\1/p' <<< "$location")
  [ -n "$code" ] || { echo "alice didn't sign in to the account console: $location"; return 1; }
  token=$(kc_curl -d grant_type=authorization_code -d client_id=account-console -d "code=$code" -d "code_verifier=$verifier" \
    --data-urlencode "redirect_uri=$redirect" "$base/protocol/openid-connect/token" | jq -r '.access_token // empty')
  [ -n "$token" ] || { echo "no token"; return 1; }
  status=$(kc_curl -o "$work/devices" -w '%{http_code}' -H "Authorization: Bearer $token" -H 'Accept: application/json' \
    "$base/account/sessions/devices")
  [ "$status" = 401 ] || [ "$status" = 403 ] || { echo "status $status: $(head -c 200 "$work/devices")"; return 1; }
}
for realm in "${REALMS[@]}"; do
  check "AC-07: $realm: alice's account console token reads no visitor's session (refused)" devices_refused "$realm"
done
finish
