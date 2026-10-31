#!/usr/bin/env bash
# 0048: the landing page in dev, https://host.docker.internal/, as the fixture application
# verif-landing (tests/fixtures/0048/) registers its realm, its site and its accounts:
#
#   - AC-01: the shared services' links, then the application's name linked to its dev host, its users
#     (username, dev password, groups) and its groups (their realm roles, then their client roles as
#     <client>:<role>, sorted), the simulated providers' users with their passwords; the realm's
#     passwords unchanged (each user still signs in with the one its export gives);
#   - AC-06: the group named a&b<c shows escaped, never as markup;
#   - RQ-05: the page's content security policy allows no script, and it isn't to be indexed;
#   - AC-10: a user added to a group after the registration leaves the page as it was, until the next
#     registration with --accounts, which shows it;
#   - AC-04: a registration without --accounts keeps the list; one with a file of comments only empties
#     it, the application's link staying.
#
#   bash tests/0048-landing-page.sh
#
# Needs the dev stack running (up.sh), from the checkout the proxy mounts (the page it serves is that
# checkout's caddy/html). The realm, the site and the network this test creates are removed whatever
# happens, and the page written again.
#
# covers: register-app.sh registry.sh routes.sh networks.sh registration-account.sh caddy/
# covers: keycloak-import/ tests/fixtures/0048/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0048/registry.txt
FIXTURE=tests/fixtures/0048
APP=verif-landing
HOST=host.docker.internal

work=$(mktemp -d)
new_network=false
docker network inspect "c4-infra.$APP" > /dev/null 2>&1 || new_network=true
remove_fixture() {
  kc_registration delete "realms/$APP" > /dev/null 2>&1
  rm -f "caddy/apps/$APP.caddy" "caddy/apps/$APP.accounts"
}
cleanup() {
  remove_fixture
  ! $new_network || bash networks.sh remove "$APP" > /dev/null
  MSYS_NO_PATHCONV=1 docker exec c4-infra.reverse-proxy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile > /dev/null 2>&1
  bash register-app.sh --index-only
  rm -rf "$work"
}
trap cleanup EXIT
remove_fixture

register() { # [register-app.sh option…]: verif-landing's realm and site, and the options given
  bash register-app.sh --app "$APP" --realm "$FIXTURE/$APP-realm.json" --proxy "$FIXTURE/$APP.routes" "$@" \
    > "$work/register.log" 2>&1 || { cat "$work/register.log"; return 1; }
}

fetch() { # <path>: the proxy's answer, its headers (no \r) and body in $work
  curl --ssl-no-revoke --cacert certs/ca.crt -s --resolve "$HOST:443:127.0.0.1" -D "$work/headers.raw" \
    -o "$work/body" -w '%{http_code}' "https://$HOST$1" > "$work/code"
  tr -d '\r' < "$work/headers.raw" > "$work/headers"
}

page_holds() { # <text>
  grep -qF -- "$1" "$work/body" || { echo "page:"; cat "$work/body"; return 1; }
}

page_lacks() { # <text>
  ! grep -qF -- "$1" "$work/body" || { echo "page holds it:"; grep -F -- "$1" "$work/body"; return 1; }
}

header_is() { # <name> <value>
  grep -qix -- "$1: $2" "$work/headers" || { echo "headers:"; cat "$work/headers"; return 1; }
}

signs_in() { # <user> <password>: a password grant of the realm's admin-cli
  local code
  code=$(curl --ssl-no-revoke --cacert certs/ca.crt -s -o /dev/null -w '%{http_code}' --resolve "$HOST:443:127.0.0.1" \
    -d grant_type=password -d client_id=admin-cli --data-urlencode "username=$1" --data-urlencode "password=$2" \
    "https://$HOST/auth/realms/$APP/protocol/openid-connect/token")
  [ "$code" = 200 ] || { echo "token endpoint: $code"; return 1; }
}

user_id() { # <username>
  kc_registration get users -r "$APP" -q "username=$1" -q exact=true --fields id --format csv --noquotes | tr -d '\r'
}

group_id() { # <name>
  kc_registration get groups -r "$APP" -q "search=$1" -q exact=true --fields id --format csv --noquotes | tr -d '\r' | head -n 1
}

# AC-01, AC-06, RQ-05
check "verif-landing registers its realm, its site and its accounts" register --accounts "$FIXTURE/$APP.accounts"
check "the registration says it read the accounts" grep -qF "Landing page: $APP's accounts, 2" "$work/register.log"
fetch /
check "/: 200" test "$(cat "$work/code")" = 200
check "RQ-05: its policy allows no script, form, frame nor fetch" header_is Content-Security-Policy \
  "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
check "RQ-05: it isn't to be indexed (header)" header_is X-Robots-Tag noindex
check "RQ-05: nor (meta)" page_holds '<meta name="robots" content="noindex">'
check "AC-01: the shared services first" page_holds '<li><a href="/auth/admin/">Keycloak</a></li>'
check "AC-01: the application, linked to its dev host" page_holds "<h2><a href=\"https://$APP.dev.localhost/\">$APP</a></h2>"
check "AC-01: ann, her dev password and her group" page_holds '<li><code>ann</code> <code>ann-password</code> [managers]</li>'
check "AC-01, AC-06: bob, no dev password (-), his group escaped" page_holds '<li><code>bob</code> [a&amp;b&lt;c]</li>'
check "AC-01: managers, its realm role then its client roles, sorted" \
  page_holds '<li><code>managers</code> [manager, verif-landing-api:read, verif-landing-api:write]</li>'
check "AC-06: a&b<c escaped, its role" page_holds '<li><code>a&amp;b&lt;c</code> [worker]</li>'
check "AC-06: never as markup" page_lacks 'a&b<c'
check "AC-01: the simulated providers' users, with their public passwords in dev" \
  page_holds '<li><code>alice</code> <code>alice-password</code></li>'
check "AC-01: ann still signs in with her export's password" signs_in ann ann-password
check "AC-01: bob too" signs_in bob bob-password

# AC-10
ann=$(user_id ann)
spare=$(group_id spare)
check "AC-10: ann added to group spare in Keycloak" \
  kc_registration update "users/$ann/groups/$spare" -r "$APP" -s "realm=$APP" -s "userId=$ann" -s "groupId=$spare" -n
check "AC-10: a registration without --accounts writes the page again" register
fetch /
check "AC-10: the page doesn't follow it" page_holds '<li><code>ann</code> <code>ann-password</code> [managers]</li>'
check "AC-10: the next registration with --accounts" register --accounts "$FIXTURE/$APP.accounts"
fetch /
check "AC-10: shows it" page_holds '<li><code>ann</code> <code>ann-password</code> [managers, spare]</li>'

# AC-04
check "AC-04: a registration without --accounts" register
fetch /
check "AC-04: keeps the list" page_holds '<li><code>ann</code>'
printf '%s\n' '# no account' > "$work/none.accounts"
check "AC-04: a registration with a file of comments only" register --accounts "$work/none.accounts"
fetch /
check "AC-04: keeps the application's link" page_holds "<h2><a href=\"https://$APP.dev.localhost/\">$APP</a></h2>"
check "AC-04: lists no account" page_lacks '<code>ann</code>'
finish
