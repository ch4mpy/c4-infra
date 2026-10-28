#!/usr/bin/env bash
# 0005: in dev, Keycloak caches no theme, and a registration installs a new or changed theme without
# restarting it: the login page shows the change on reload, and another application's realm keeps
# answering (AC-01, AC-02, AC-04); with INFRA_ENV=demo, a changed theme restarts Keycloak once and an
# unchanged one doesn't (AC-03, AC-04).
#
#   bash tests/0005-themes.sh
#
# Registers the fixture application verif-theme (tests/fixtures/0005/registry.txt): its realm, whose
# login theme is verif-theme, and that theme, its login page printing a stamp each registration
# changes. The INFRA_ENV=demo part restarts the dev Keycloak once. Never runs up.sh nor docker
# compose up; .env is put back by a trap, the realm and the theme removed, whatever happens.
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ keycloak/ keycloak-import/ reverse-proxy/
# covers: certs/ register-app.sh registry.sh registry.txt routes.sh networks.sh
# covers: registration-account.sh tlds-alpha-by-domain.txt tests/fixtures/0005/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0005/registry.txt
FIXTURE=tests/fixtures/0005
INSTALLED=keycloak/themes/verif-theme
BASE=https://host.docker.internal/auth/realms
# account-console, a client every realm has, requires PKCE: without a challenge Keycloak redirects
# rather than render the login page (the challenge is RFC 7636's example)
LOGIN_PAGE="$BASE/verif-theme/protocol/openid-connect/auth?client_id=account-console&response_type=code&scope=openid&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fhost.docker.internal%2Fauth%2Frealms%2Fverif-theme%2Faccount%2F"
OTHER_REALM="$BASE/faito/.well-known/openid-configuration"

work=$(mktemp -d)
cp .env "$work/env"
# verif-theme's network (0007: each registration makes sure of it), when this test creates it
new_network=false
docker network inspect c4-infra.verif-theme > /dev/null 2>&1 || new_network=true
remove_fixture() {
  kc_admin delete realms/verif-theme > /dev/null 2>&1
  rm -rf "$INSTALLED"
}
cleanup() {
  touch "$work/poll.stop"
  [ -z "${poller:-}" ] || wait "$poller" 2> /dev/null
  cp "$work/env" .env
  kc_wait_healthy > /dev/null
  remove_fixture
  # after .env is back: compose.apps.yml is rewritten for its INFRA_ENV
  ! $new_network || bash networks.sh remove verif-theme > /dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# a previous run's leftovers: the first registration installs a theme Keycloak has never seen
remove_fixture

set_env() { # <dev|demo>: INFRA_ENV in .env
  sed -i "s/^INFRA_ENV=.*/INFRA_ENV=$1/" .env
  grep -qx "INFRA_ENV=$1" .env
}

# The fixture theme, with its login page's stamp, in $work/themes/
stamp() { # <stamp>
  rm -rf "$work/themes"
  mkdir -p "$work/themes"
  cp -r "$FIXTURE/themes/verif-theme" "$work/themes/"
  sed -i "s/@STAMP@/$1/" "$work/themes/verif-theme/login/login.ftl"
}

# register-app.sh --app verif-theme <option…>, its output in $work/register.out
register() {
  bash register-app.sh --app verif-theme "$@" > "$work/register.out" 2>&1 || { cat "$work/register.out"; return 1; }
}

said() { # <line>: register-app.sh printed that line
  grep -qxF -- "$1" "$work/register.out" || { echo "register-app.sh printed:"; cat "$work/register.out"; return 1; }
}

never_said() { # <text>
  ! grep -qF -- "$1" "$work/register.out" || { echo "register-app.sh printed:"; cat "$work/register.out"; return 1; }
}

times_said() { # <count> <text>
  [ "$(grep -cF -- "$2" "$work/register.out")" = "$1" ] || { echo "register-app.sh printed:"; cat "$work/register.out"; return 1; }
}

fetch() { # <url> <file>: the body into <file>, the headers into <file>.headers; prints the status
  curl --ssl-no-revoke --cacert certs/ca.crt -s -D "$2.headers.raw" -o "$2" -w '%{http_code}' "$1"
  tr -d '\r' < "$2.headers.raw" > "$2.headers"
}

page_shows() { # <stamp>: the login page of realm verif-theme, as a reload gets it, holds it
  local status
  status=$(fetch "$LOGIN_PAGE" "$work/page")
  grep -qF "VERIF-STAMP-$1<" "$work/page" || { echo "status $status, page:"; head -c 800 "$work/page"; echo; return 1; }
}

# The stylesheet the login page links: served, and not kept by browsers for days (RQ-01)
stylesheet_not_kept() {
  local resources status max_age
  resources=$(sed -n 's/.*RESOURCES=\([^<]*\)<.*/\1/p' "$work/page")
  [ -n "$resources" ] || { echo "no resources path in the page"; return 1; }
  status=$(fetch "https://host.docker.internal$resources/css/verif.css" "$work/css")
  [ "$status" = 200 ] || { echo "$resources/css/verif.css: status $status"; return 1; }
  max_age=$(grep -i '^cache-control:' "$work/css.headers" | grep -oiE 'max-age=[0-9]+' | cut -d= -f2)
  if [ -n "$max_age" ] && [ "$max_age" -ge 86400 ]; then
    echo "$resources/css/verif.css: $(grep -i '^cache-control:' "$work/css.headers")"
    return 1
  fi
}

# Another application's realm, every 0.2 s until $work/poll.stop exists: each status in $work/poll.codes
poll_other_realm() {
  local code
  while [ ! -f "$work/poll.stop" ]; do
    code=$(curl --ssl-no-revoke --cacert certs/ca.crt -s -o /dev/null --max-time 5 -w '%{http_code}' "$OTHER_REALM")
    echo "$code" >> "$work/poll.codes"
    sleep 0.2
  done
}

polled_only_200() {
  local count
  count=$(wc -l < "$work/poll.codes" 2> /dev/null || echo 0)
  [ "$count" -gt 0 ] || { echo "no answer recorded"; return 1; }
  ! grep -vqx 200 "$work/poll.codes" || { echo "$count answers, not 200:"; grep -vx 200 "$work/poll.codes" | LC_ALL=C sort | uniq -c; return 1; }
}

unchanged_since() { # <start time>
  [ "$(kc_started_at)" = "$1" ] || { echo "started at $1, now at $(kc_started_at)"; return 1; }
}

changed_since() { # <start time>
  [ "$(kc_started_at)" != "$1" ] || { echo "still started at $1"; return 1; }
}

# AC-04's setting: dev, with Caddy as the proxy
check "INFRA_ENV=dev in .env" set_env dev
check "the reverse proxy is the stack's Caddy (c4-infra/reverse-proxy, intent 0013)" \
  bash -c "docker inspect -f '{{.Config.Image}}' c4-infra.reverse-proxy | grep -qx 'c4-infra/reverse-proxy'"
check "Keycloak is healthy" kc_wait_healthy 60
started=$(kc_started_at)

# dev, a new theme (AC-01, AC-04)
stamp A
check "dev: verif-theme registers, with its realm and theme (stamp A)" register --realm "$FIXTURE/verif-theme-realm.json" --themes "$work/themes"
check "dev: the theme is installed" diff -r "$work/themes/verif-theme" "$INSTALLED"
check "dev: the message says to reload the login page" said "Theme verif-theme installed: reload the login page (Keycloak doesn't cache themes in dev)"
check "dev: no restart announced" never_said "Restarting Keycloak"
check "dev: the login page shows stamp A" page_shows A
check "dev: Keycloak wasn't restarted by a new theme (same start time)" unchanged_since "$started"
check "dev: the theme's stylesheet isn't kept by browsers for days" stylesheet_not_kept

# dev, a changed template, while another application's realm is polled (AC-01, AC-02, AC-04)
check "dev: realm faito answers before the change" test "$(curl --ssl-no-revoke --cacert certs/ca.crt -s -o /dev/null -w '%{http_code}' "$OTHER_REALM")" = 200
poll_other_realm &
poller=$!
stamp B
check "dev: verif-theme registers its changed theme (stamp B)" register --themes "$work/themes"
check "dev: the message says to reload the login page" said "Theme verif-theme installed: reload the login page (Keycloak doesn't cache themes in dev)"
check "dev: no restart announced" never_said "Restarting Keycloak"
check "dev: the login page shows stamp B on reload" page_shows B
sleep 2
touch "$work/poll.stop"
wait "$poller"
poller=""
check "dev: Keycloak wasn't restarted (same start time)" unchanged_since "$started"
check "dev: realm faito answered 200 throughout ($(wc -l < "$work/poll.codes" | tr -d ' ') requests)" polled_only_200

# INFRA_ENV=demo: a changed theme restarts Keycloak, once; an unchanged one doesn't (AC-03, AC-04)
check "INFRA_ENV=demo in .env" set_env demo
stamp C
check "demo: verif-theme registers its changed theme (stamp C)" register --themes "$work/themes"
check "demo: the theme is installed" said "Theme verif-theme installed"
check "demo: one restart announced" times_said 1 "Restarting Keycloak"
check "demo: Keycloak was restarted (new start time)" changed_since "$started"
check "demo: Keycloak is healthy again" kc_wait_healthy
check "demo: the login page shows stamp C" page_shows C
started=$(kc_started_at)
check "demo: verif-theme registers its unchanged theme (stamp C)" register --themes "$work/themes"
check "demo: nothing installed" never_said "Theme verif-theme installed"
check "demo: no restart announced" never_said "Restarting Keycloak"
check "demo: Keycloak wasn't restarted (same start time)" unchanged_since "$started"

# back to INFRA_ENV=dev: a changed theme restarts nothing (AC-04)
check "INFRA_ENV=dev in .env" set_env dev
stamp D
check "dev: verif-theme registers its changed theme (stamp D)" register --themes "$work/themes"
check "dev: no restart announced" never_said "Restarting Keycloak"
check "dev: the login page shows stamp D on reload" page_shows D
check "dev: Keycloak wasn't restarted (same start time)" unchanged_since "$started"
finish
