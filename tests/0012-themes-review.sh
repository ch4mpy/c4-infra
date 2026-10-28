#!/usr/bin/env bash
# 0012: the forms of a theme.properties that bash and Java read differently (sdlc-verify's review,
# round 1, 2026-10-23), refused before any docker call as AC-01's (RQ-01, RQ-03), with a fake docker:
#
#   - a NUL byte before # (bash drops it and saw a comment; Java reads the key "\u0000#k" and
#     resolves its value);
#   - U+3000, U+2002 or U+1680 before # under LC_ALL=C.UTF-8, the locale demo/c4-app runs
#     register-app.sh in (its [:blank:] holds them; Java's blanks are the space, the tab and the
#     form feed only);
#   - invalid UTF-8 (Keycloak then reads the file as ISO-8859-1) before a $ and a { joined by a
#     continuation, which bash read its own way under C.UTF-8 (the security review, round 1);
#   - since spec v2 (the engineer's decision, 2026-10-24), any byte outside printable ASCII, the tab,
#     CR, LF and the form feed, without ${ too: U+3000 inside a value, UTF-8's é, a DEL in a comment;
#
# and their must-not-fire twins: blanks (space, tab) before # still make a comment; the tab, the form
# feed and CRLF pass; a character beyond ASCII written as an escape (backslash, u00e9) passes. A
# theme.properties the registering user can't read is refused too (register-app.sh), which NTFS
# doesn't let this test make.
#
#   bash tests/0012-themes-review.sh
#
# covers: register-app.sh registry.sh registry.txt routes.sh networks.sh registration-account.sh
# covers: tlds-alpha-by-domain.txt keycloak/ tests/fixtures/0012/
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
# Security review (round 1): invalid UTF-8, which Keycloak reads as ISO-8859-1, before a $ and a { that
# a continuation joins (found by comparing this check with Java's PropertyResourceBundle on 24,000
# generated files; under C.UTF-8, bash read it otherwise and let it through)
refused_theme 'invalid UTF-8 before a continued ${' verif-crlf \
  '\303\\###0024=env.X}\\:$\\\n{\302\2400024\\t:\n' 'verif-crlf/login/theme.properties:1: '

# The twins pass the theme check: the registration goes on (the fake docker is called)
passes_theme_check() { # <label> <name> <content>
  register_stubbed "$(theme "$2" "$3")"
  check "$1: no theme refusal" never_says "theme.properties"
  check "$1: the registration goes on (docker is called)" test -s "$work/docker.log"
}
passes_theme_check 'a space and a tab before # make a comment' verif-crlf \
  'parent=keycloak\n  \t# ${env.KC_DB_PASSWORD}\n'
passes_theme_check 'the tab, the form feed and CRLF' verif-case \
  'parent=keycloak\r\nkcHtmlClass=login-pf\tx\fy\r\n'
passes_theme_check 'a character beyond ASCII written as an escape' verif-unicode \
  'parent=keycloak\nkcLogoText=Caf\134u00e9\n'

# Spec v2: a byte outside printable ASCII, the tab, CR, LF and the form feed, wherever it is
refused_theme 'v2: U+3000 inside a value without ${' verif-escape \
  'parent=keycloak\nkcHtmlClass=login-pf\343\200\200x\n' 'verif-escape/login/theme.properties:2: a byte outside printable ASCII'
refused_theme "v2: UTF-8's é in a value" verif-continued \
  'parent=keycloak\nkcLogoText=Caf\303\251\n' 'verif-continued/login/theme.properties:2: a byte outside printable ASCII'
refused_theme 'v2: a DEL in a comment' verif-env \
  'parent=keycloak\n# a comment \177\n' 'verif-env/login/theme.properties:2: a byte outside printable ASCII'

# Review of PR #3 (D-4): after a continued line that holds nothing yet, Java still starts a logical
# line, and a # or ! line is a comment (JDK 27's PropertyResourceBundle reads neither as a key);
# another line is read from there
passes_theme_check 'a continued empty line, then a # line: a comment' verif-case \
  'parent=keycloak\n\134\n# see ${env.KC_DB_PASSWORD}\n'
passes_theme_check 'blanks and a continued empty line, then a ! line: a comment' verif-crlf \
  'parent=keycloak\n  \134\n! see ${env.KC_DB_PASSWORD}\n'
refused_theme 'a continued empty line, then a ${' verif-env \
  'parent=keycloak\n\134\nk=${env.KC_DB_PASSWORD}\n' 'verif-env/login/theme.properties:3: '

# Review of PR #3 (D-1): a theme that find can't walk all of (a directory it can't read) is refused,
# not taken as clean: here a find that prints what it finds, then fails as on such a directory
mkdir -p "$work/find-fails"
printf '#!/usr/bin/env bash\n"%s" "$@"\necho "find: a directory: Permission denied" >&2\nexit 1\n' "$(command -v find)" \
  > "$work/find-fails/find"
chmod +x "$work/find-fails/find"
PATH="$work/find-fails:$PATH" refused_theme 'a walk find can'\''t finish' verif-continued \
  'parent=keycloak\n' "verif-continued: find couldn't walk all of it"

finish
