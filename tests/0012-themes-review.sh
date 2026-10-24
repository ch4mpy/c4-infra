#!/usr/bin/env bash
# 0012: the forms of a theme.properties that bash and Java read differently (sdlc-verify's review,
# round 1, 2026-10-23), refused before any docker call as AC-1's (REQ-1, REQ-3), with a fake docker:
#
#   - a NUL byte before # (bash drops it and saw a comment; Java reads the key "\u0000#k" and
#     resolves its value);
#   - U+3000, U+2002 or U+1680 before # under LC_ALL=C.UTF-8, the locale demo/c4-app runs
#     register-app.sh in (its [:blank:] holds them; Java's blanks are the space, the tab and the
#     form feed only);
#
# and their must-not-fire twins: blanks (space, tab) before # still make a comment; U+3000 inside a
# value without ${ passes. A theme.properties the registering user can't read is refused too
# (register-app.sh), which NTFS doesn't let this test make.
#
#   bash tests/0012-themes-review.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh

export REGISTRY_FILE=$PWD/tests/fixtures/0012/registry.txt
export LC_ALL=C.UTF-8
INSTALLED=keycloak/themes
NAMES=(verif-env verif-unicode verif-escape verif-continued verif-case verif-crlf)

work=$(mktemp -d)
stub_path "$work/stubs" docker
remove_themes() {
  local name
  for name in "${NAMES[@]}"; do rm -rf "${INSTALLED:?}/$name"; done
}
trap 'remove_themes; rm -rf "$work"' EXIT
remove_themes

# register-app.sh --app verif-themes --themes <dir> with the fake docker: sets status, its output in
# $work/out, the docker calls in $work/docker.log
register_stubbed() {
  : > "$work/docker.log"
  STUB_LOG="$work/docker.log" PATH="$work/stubs:$PATH" \
    bash ./register-app.sh --app verif-themes --themes "$1" > "$work/out" 2>&1 < /dev/null
  status=$?
}
refused() {
  [ "$status" -ne 0 ] || { echo "exited 0:"; cat "$work/out"; return 1; }
}
says() { # <text>
  grep -qF -- "$1" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}
never_says() { # <text>
  ! grep -qF -- "$1" "$work/out" || { echo "output:"; cat "$work/out"; return 1; }
}
no_docker_call() {
  [ ! -s "$work/docker.log" ] || { echo "docker called:"; head -n 5 "$work/docker.log"; return 1; }
}
not_installed() { # <theme>
  [ ! -e "$INSTALLED/$1" ] || { echo "$INSTALLED/$1 is installed"; return 1; }
}

# A themes directory holding one login theme: <name> <content, printf's format>
theme() {
  local dir=$work/themes-$1
  rm -rf "$dir"
  mkdir -p "$dir/$1/login"
  # shellcheck disable=SC2059 # the content is a format: its octal escapes are the bytes written
  printf "$2" > "$dir/$1/login/theme.properties"
  echo "$dir"
}

refused_theme() { # <label> <name> <content> <what the refusal names>
  register_stubbed "$(theme "$2" "$3")"
  check "$1: refused" refused
  check "$1: names $4" says "$4"
  check "$1: nothing was registered" says "nothing was registered"
  check "$1: before any docker call" no_docker_call
  check "$1: $2 isn't installed" not_installed "$2"
}

refused_theme 'a NUL byte before #' verif-env \
  'parent=keycloak\n\000#k=${env.KC_DB_PASSWORD}\n' 'verif-env/login/theme.properties: a NUL byte'
refused_theme 'U+3000 before #' verif-unicode \
  'parent=keycloak\n\343\200\200#k=${env.KC_DB_PASSWORD}\n' 'verif-unicode/login/theme.properties:2: '
refused_theme 'U+2002 before #' verif-escape \
  'parent=keycloak\n\342\200\202#k=${env.KC_DB_PASSWORD}\n' 'verif-escape/login/theme.properties:2: '
refused_theme 'U+1680 before !' verif-continued \
  'parent=keycloak\n\341\232\200!k=${env.KC_DB_PASSWORD}\n' 'verif-continued/login/theme.properties:2: '

# The twins pass the theme check: the registration goes on (the fake docker is called)
passes_theme_check() { # <label> <name> <content>
  register_stubbed "$(theme "$2" "$3")"
  check "$1: no theme refusal" never_says "theme.properties"
  check "$1: the registration goes on (docker is called)" test -s "$work/docker.log"
}
passes_theme_check 'a space and a tab before # make a comment' verif-crlf \
  'parent=keycloak\n  \t# ${env.KC_DB_PASSWORD}\n'
passes_theme_check 'U+3000 inside a value without ${' verif-case \
  'parent=keycloak\nkcHtmlClass=login-pf\343\200\200x\n'

finish
