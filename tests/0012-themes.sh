#!/usr/bin/env bash
# 0012: a registered theme can't bring the shared Keycloak's environment into a page (RQ-01 to
# RQ-04), on the workstation:
#
#   - AC-01, AC-02: with a fake docker (tests/lib/stubs.sh), register-app.sh refuses, before any docker
#     call and naming the file and its line, a theme whose theme.properties holds `${` once read as
#     Java reads it: ${env.KC_DB_PASSWORD}; \u0024{…}; \$\{…}; `$` and `{` joined by a continuation
#     line; the same in a CRLF file; ${java.version} in an email theme; a file named
#     Theme.Properties. None of them is installed in keycloak/themes/.
#   - AC-05: on the dev stack, the fixture application verif-themes (tests/fixtures/0012/registry.txt)
#     registers its realm and two themes that pass: verif-ok (a commented ${…}, a comment ending
#     with a backslash, an even number of backslashes before a line's end, ${msg(…)} and {0} in its
#     template and its messages) and verif-tickee (Tickee's theme, without its images): both
#     installed as they are, and the realm's login page shows verif-ok's message.
#
# A theme's links (AC-03) are tested on the stand-in host (tests/0012-themes.stand-in.sh): Git Bash
# doesn't make them here. The realm, the themes and the network this test creates are removed by a
# trap, whatever happens.
#
#   bash tests/0012-themes.sh
#
# covers: up.sh env.sh compose.yml compose.dev.yml caddy/ keycloak/ keycloak-import/ reverse-proxy/
# covers: certs/ register-app.sh registry.sh registry.txt routes.sh networks.sh
# covers: registration-account.sh tlds-alpha-by-domain.txt tests/fixtures/0012/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh
source tests/lib/keycloak.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0012/registry.txt
FIXTURE=tests/fixtures/0012
INSTALLED=keycloak/themes
NAMES=(verif-ok verif-tickee verif-env verif-unicode verif-escape verif-continued verif-crlf verif-sysprop verif-case)
# account-console requires PKCE (the challenge is RFC 7636's example)
LOGIN_PAGE="https://host.docker.internal/auth/realms/verif-themes/protocol/openid-connect/auth?client_id=account-console&response_type=code&scope=openid&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&redirect_uri=https%3A%2F%2Fhost.docker.internal%2Fauth%2Frealms%2Fverif-themes%2Faccount%2F"

work=$(mktemp -d)
stub_path "$work/stubs" docker
new_network=false
docker network inspect c4-infra.verif-themes > /dev/null 2>&1 || new_network=true
remove_fixture() {
  local name
  kc_registration delete realms/verif-themes > /dev/null 2>&1
  for name in "${NAMES[@]}"; do rm -rf "${INSTALLED:?}/$name"; done
}
cleanup() {
  remove_fixture
  ! $new_network || bash networks.sh remove verif-themes > /dev/null
  rm -rf "$work"
}
trap cleanup EXIT
remove_fixture

# register-app.sh --app verif-themes <option…> with the fake docker first in PATH: sets status, its
# output in $work/out, the docker calls in $work/docker.log
register_stubbed() {
  : > "$work/docker.log"
  STUB_LOG="$work/docker.log" PATH="$work/stubs:$PATH" \
    bash ./register-app.sh --app verif-themes "$@" > "$work/out" 2>&1 < /dev/null
  status=$?
}
refused() {
  [ "$status" -ne 0 ] || { echo "exited 0:"; cat "$work/out"; return 1; }
}
says() { # <text>
  grep -qF -- "$1" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}
no_docker_call() {
  [ ! -s "$work/docker.log" ] || { echo "docker called:"; head -n 5 "$work/docker.log"; return 1; }
}
not_installed() { # <theme>
  [ ! -e "$INSTALLED/$1" ] || { echo "$INSTALLED/$1 is installed"; return 1; }
}

# A themes directory holding one theme: <name> <type> <file name> <content, printf's format>
theme() {
  local dir=$work/themes-$1
  rm -rf "$dir"
  mkdir -p "$dir/$1/$2"
  # shellcheck disable=SC2059 # the content is a format: its \n, \r and \\ are the bytes written
  printf "$4" > "$dir/$1/$2/$3"
  echo "$dir"
}

refused_theme() { # <label> <name> <type> <file name> <content> <line>
  register_stubbed --themes "$(theme "$2" "$3" "$4" "$5")"
  check "$1: refused" refused
  check "$1: names $2/$3/$4:$6" says "$2/$3/$4:$6: "
  check "$1: nothing was registered" says "nothing was registered"
  check "$1: before any docker call" no_docker_call
  check "$1: $2 isn't installed" not_installed "$2"
}

# AC-01
refused_theme 'AC-01: ${env.KC_DB_PASSWORD}' verif-env login theme.properties \
  'parent=keycloak\nkcHtmlClass=login-pf ${env.KC_DB_PASSWORD}\n' 2
# AC-02: what Java's Properties decodes, or joins, into ${
refused_theme 'AC-02: \u0024{…}' verif-unicode login theme.properties \
  'parent=keycloak\nkcHtmlClass=\\u0024{env.KC_DB_PASSWORD}\n' 2
refused_theme 'AC-02: \$\{…}' verif-escape login theme.properties \
  'parent=keycloak\nkcHtmlClass=\\$\\{env.KC_DB_PASSWORD}\n' 2
refused_theme 'AC-02: $ and { joined by a continuation' verif-continued login theme.properties \
  'parent=keycloak\nkcHtmlClass=login-pf $\\\n    {env.KC_DB_PASSWORD}\n' 2
refused_theme 'AC-02: the same, CRLF' verif-crlf login theme.properties \
  'parent=keycloak\r\nkcHtmlClass=login-pf $\\\r\n    {env.KC_DB_PASSWORD}\r\n' 2
refused_theme 'AC-02: ${java.version} in an email theme' verif-sysprop email theme.properties \
  'parent=base\nsubject=${java.version}\n' 2
refused_theme 'AC-02: Theme.Properties' verif-case login Theme.Properties \
  'parent=keycloak\nkcHtmlClass=${env.KC_DB_PASSWORD}\n' 2

# AC-05: the themes that pass, on the dev stack
bash register-app.sh --app verif-themes --realm "$FIXTURE/verif-themes-realm.json" \
  --themes "$FIXTURE/themes" > "$work/register.out" 2>&1 < /dev/null
status=$?
registered() {
  [ "$status" -eq 0 ] || { echo "exit $status:"; cat "$work/register.out"; return 1; }
}
installed_as_is() { # <theme>
  diff -r "$FIXTURE/themes/$1" "$INSTALLED/$1"
}
check "AC-05: verif-themes registers its realm, verif-ok and verif-tickee" registered
check "AC-05: verif-ok is installed as it is" installed_as_is verif-ok
check "AC-05: verif-tickee (Tickee's theme) is installed as it is" installed_as_is verif-tickee
shows_message() {
  local page
  page=$(curl --ssl-no-revoke --cacert certs/ca.crt -s "$LOGIN_PAGE")
  grep -qF 'Theme verif-ok, argument 0012' <<< "$page" || { echo "the login page:"; head -c 600 <<< "$page"; return 1; }
}
check "AC-05: the realm's login page shows verif-ok's message" shows_message

finish
