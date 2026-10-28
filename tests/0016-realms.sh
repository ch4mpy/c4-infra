#!/usr/bin/env bash
# 0016: the three simulated providers' realms on the dev stack (keycloak-import/simulated-*-realm.json):
#
#   - AC-01: they exist; keycloak-import run again skips each ("already exists. Import skipped"), and
#     the other realms are as they were;
#   - AC-02: each one's discovery names its issuer https://host.docker.internal/auth/realms/<name>;
#   - AC-07: registration, password reset and brute-force protection off; their users are PA-05's;
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
  for realm in $(kc_admin get realms --fields realm 2> /dev/null | jq -r '.[].realm' | grep -v '^simulated-' | sort); do
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
    | jq -r '.[] | "\(.username) \(.email // "-") \(.attributes.is_private_email[0] // "-")"' | sort | paste -sd' ' -
}
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
finish
