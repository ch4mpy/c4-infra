#!/usr/bin/env bash
# 0016: the simulated providers' login themes (keycloak/stack-themes/, a theme JAR in the stack's
# Keycloak image), AC-07:
#
#   - on the dev stack, each simulated realm's login page, and an error page of its flow (a redirect
#     URI the shared client refuses), shows its banner: "Simulated <provider> — c4-infra test
#     provider. Never type your real <provider> password.";
#   - the three themes, copied under the names of a fixture application (tests/fixtures/0016/), pass
#     register-app.sh's theme checks (intent 0012): with a fake docker, the registration goes past
#     them (docker is called), no theme refused. The copies it installs in keycloak/themes/ are
#     removed by a trap.
#
#   bash tests/0016-themes.sh
#
# Needs the dev stack, its Keycloak image built from this keycloak/ (bash up.sh).
#
# covers: keycloak/ keycloak-import/ register-app.sh tests/fixtures/0016/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh
source tests/lib/keycloak.sh

BASE=https://host.docker.internal
INSTALLED=keycloak/themes

work=$(mktemp -d)
cleanup() {
  rm -rf "$INSTALLED/verif-copy-google" "$INSTALLED/verif-copy-facebook" "$INSTALLED/verif-copy-apple" "$work"
}
trap cleanup EXIT

page() { # <realm> <redirect_uri>: the page of an authorization request of the shared client, in $work/page.html
  kc_curl -o "$work/page.html" -w '%{http_code}' -G --data-urlencode client_id=any-application \
    --data-urlencode response_type=code --data-urlencode scope=openid --data-urlencode "redirect_uri=$2" \
    "$BASE/auth/realms/$1/protocol/openid-connect/auth"
}
banner() { # <provider>
  grep -qF "c4-infra test provider. Never type your real $1 password." "$work/page.html" \
    && grep -qF "Simulated $1" "$work/page.html" \
    || { echo "page:"; grep -o 'kc-header-wrapper[^<]*<[^<]*' "$work/page.html" | head -n 3; return 1; }
}
for provider in Google Facebook Apple; do
  realm=simulated-${provider,,}
  status=$(page "$realm" "$BASE/auth/realms/some-app/broker/${provider,,}/endpoint")
  check "AC-07: $realm's login page (200, $status)" test "$status" = 200
  check "AC-07: it shows the banner" banner "$provider"
  check "AC-07: in its own stylesheet" grep -qF "/login/$realm/css/simulated.css" "$work/page.html"
  status=$(page "$realm" https://evil.test/callback)
  check "AC-07: $realm's error page, a refused redirect URI (400, $status)" test "$status" = 400
  check "AC-07: it shows the banner too" banner "$provider"
done

# The stack themes through register-app.sh's checks, as an application's themes
mkdir -p "$work/themes" "$work/stubs"
for provider in google facebook apple; do
  cp -R "keycloak/stack-themes/theme/simulated-$provider" "$work/themes/verif-copy-$provider"
done
stub_path "$work/stubs" docker
: > "$work/docker.log"
REGISTRY_FILE=$PWD/tests/fixtures/0016/registry.txt STUB_LOG="$work/docker.log" PATH="$work/stubs:$PATH" \
  bash ./register-app.sh --app verif-social --themes "$work/themes" > "$work/register.out" 2>&1 < /dev/null
check "AC-07: no stack theme is refused by register-app.sh's checks" \
  eval '! grep -n "refused" "$work/register.out"'
check "AC-07: the registration goes past them (docker is called)" test -s "$work/docker.log"
finish
