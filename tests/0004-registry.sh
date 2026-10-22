#!/usr/bin/env bash
# 0004: the application registry, registry.txt, read by registry.sh.
#
#   bash tests/0004-registry.sh [registry|scripts|docs]...   (every part by default)
#
#   registry   registry.sh on registry.txt and on the fixtures of tests/fixtures/0004/: the four
#              entries (AC-6), the duplicates and the malformed lines `check` refuses (AC-3), `next`
#              (AC-4), `entry` and `upstream` as their output contract says (plan, REQ-3)
#   scripts    up.sh and register-app.sh with fake docker, getent and powershell.exe (answering
#              127.0.0.1, so that up.sh's resolution check passes): a registry with a duplicate stops
#              both (AC-3, REQ-4), an application missing from it is refused (AC-1), before any
#              docker call
#   docs       the README's "Port registry" section points to registry.txt and holds no table of
#              numbers (AC-7); docs/migration.md states the registry's contract
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/stubs.sh

FIXTURES=$PWD/tests/fixtures/0004
TICKEE_LINE='^3 +tickee +tickee,brasserie,tenant2,tenant3 +tickee-api +tickee +tickee\.dev\.localhost +tickee\.c4-soft\.com$'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Runs <command…> with REGISTRY_FILE=<file> (registry.txt when empty): sets `status`, and leaves
# its stdout and stderr in $work/out and $work/err
run_with() { # <registry file> <command…>
  local file=$1
  shift
  REGISTRY_FILE=$file "$@" > "$work/out" 2> "$work/err"
  status=$?
}

exited() { # <status>
  [ "$status" -eq "$1" ] || { echo "exited $status, not $1; stderr:"; cat "$work/err"; return 1; }
}

says() { # <text>: stderr holds the text
  grep -qF -- "$1" "$work/err" || { echo "stderr:"; cat "$work/err"; return 1; }
}

prints() { # <text>: stdout is exactly the text (and a final new line)
  [ "$(cat "$work/out")" = "$1" ] || { echo "stdout:"; cat "$work/out"; return 1; }
}

prints_nothing() {
  [ ! -s "$work/out" ] || { echo "stdout:"; cat "$work/out"; return 1; }
}

# "<fields> <app>" for each entry of registry.txt
entries() {
  grep -vE '^[[:space:]]*(#|$)' registry.txt | awk '{ print NF, $2 }'
}

has_entry() { # <app>: one line of seven fields
  [ "$(entries | grep -c " $1$")" -eq 1 ] && entries | grep -qx "7 $1" \
    || { echo "entries (fields, name):"; entries; return 1; }
}

refused() { # <fixture> <text…>: check exits 1, saying each text
  local fixture=$1 text
  shift
  run_with "$FIXTURES/$fixture" bash registry.sh check
  check "$fixture: check exits 1" exited 1
  for text in "$@"; do
    check "$fixture: check says \"$text\"" says "$text"
  done
}

upstream_is() { # <role> <env> <url>
  run_with "" bash registry.sh upstream faito "$1" "$2"
  check "upstream faito $1 $2 is $3" prints "$3"
  check "upstream faito $1 $2 exits 0" exited 0
}

part_registry() {
  # AC-6
  run_with "" bash registry.sh check
  check "entries: check passes on registry.txt" exited 0
  check "entries: check prints nothing" prints_nothing
  check "entries: four entries" test "$(entries | wc -l)" -eq 4
  for app in turu hururaa tickee faito; do
    check "entries: $app has one entry of seven fields" has_entry "$app"
  done
  check "entries: Tickee's line" grep -qE "$TICKEE_LINE" registry.txt
  run_with "" bash registry.sh entry tickee
  check "entry tickee exits 0" exited 0
  check "entry tickee: n=3" grep -qx 'n=3' "$work/out"
  check "entry tickee: realms=tickee,brasserie,tenant2,tenant3" grep -qx 'realms=tickee,brasserie,tenant2,tenant3' "$work/out"
  check "entry tickee: rabbitmq_user=tickee-api" grep -qx 'rabbitmq_user=tickee-api' "$work/out"
  check "entry tickee: themes=tickee" grep -qx 'themes=tickee' "$work/out"
  check "entry tickee: dev_host=tickee.dev.localhost" grep -qx 'dev_host=tickee.dev.localhost' "$work/out"
  check "entry tickee: demo_host=tickee.c4-soft.com" grep -qx 'demo_host=tickee.c4-soft.com' "$work/out"

  # AC-3, at the source: check names both entries of a duplicate
  refused duplicate-number.txt 'number 4: faito (line 5) and verif (line 6)'
  refused duplicate-realm.txt 'realm public-facing: hururaa (line 3) and verif (line 6)'
  refused duplicate-theme.txt 'theme tickee: tickee (line 4) and verif (line 6)'
  refused bad-fields.txt 'bad-fields.txt:2: 6 columns, 7 expected' \
    "bad-fields.txt:3: number '39' is not between 1 and 38" \
    "bad-fields.txt:4: host name 'verif2.dev.localhost:14080' is not a host name"
  refused reserved-name.txt 'reserved-name.txt:6: keycloak-db is reserved for the shared stack'

  # AC-4
  run_with "$FIXTURES/taken-1-4.txt" bash registry.sh next
  check "next, 1 to 4 taken: prints 5" prints 5
  check "next, 1 to 4 taken: exits 0" exited 0
  run_with "$FIXTURES/taken-1-2-4.txt" bash registry.sh next
  check "next, 1, 2 and 4 taken: prints 3" prints 3
  check "next, 1, 2 and 4 taken: exits 0" exited 0

  # entry's output contract
  run_with "" bash registry.sh entry faito
  check "entry faito prints the eight fields" prints "$(printf '%s\n' n=4 prefix=14 app=faito realms=faito \
    rabbitmq_user=faito-api themes= dev_host=faito.dev.localhost demo_host=faito.c4-soft.com)"
  check "entry faito exits 0" exited 0
  run_with "" bash registry.sh entry verif
  check "entry verif prints nothing on stdout" prints_nothing
  check "entry verif exits 1" exited 1
  check "entry verif names registry.txt" says registry.txt
  check "entry verif names bash registry.sh next" says 'bash registry.sh next'
  run_with "$FIXTURES/duplicate-number.txt" bash registry.sh entry faito
  check "entry faito, two entries numbered 4: exits 2" exited 2
  check "entry faito, two entries numbered 4: prints nothing on stdout" prints_nothing
  check "entry faito, two entries numbered 4: says why" says 'number 4: faito (line 5) and verif (line 6)'

  # upstream (REQ-3): the derivation table
  upstream_is gateway dev https://host.docker.internal:14080
  upstream_is mcp dev https://host.docker.internal:14280
  upstream_is fr dev http://host.docker.internal:14200
  upstream_is ui dev http://host.docker.internal:14200
  upstream_is en dev http://host.docker.internal:14205
  upstream_is gateway demo http://faito.gateway:7080
  upstream_is fr demo http://faito.frontend:80
  upstream_is ui demo http://faito.frontend:80
  upstream_is en demo http://faito.frontend:80
  run_with "" bash registry.sh upstream faito mcp demo
  check "upstream faito mcp demo exits 2" exited 2
  check "upstream faito mcp demo prints nothing on stdout" prints_nothing
  check "upstream faito mcp demo names the README section" \
    says "README.md, 'What an application's deployment does'"
  run_with "" bash registry.sh upstream faito admin dev
  check "upstream faito admin dev (unknown role) exits 1" exited 1
  run_with "" bash registry.sh upstream verif gateway dev
  check "upstream verif gateway dev (unknown application) exits 1" exited 1
}

# Runs <command…> as run_with does, with the fakes of $work/stubs first in PATH: their docker
# appends each call to $work/docker.log
run_stubbed() { # <registry file> <command…>
  local file=$1
  shift
  : > "$work/docker.log"
  STUB_LOG="$work/docker.log" STUB_ADDRESS=127.0.0.1 PATH="$work/stubs:$PATH" run_with "$file" "$@"
}

exited_non_zero() {
  [ "$status" -ne 0 ] || { echo "exited 0; stderr:"; cat "$work/err"; return 1; }
}

called_no_docker() {
  [ ! -s "$work/docker.log" ] || { echo "called:"; head -n 5 "$work/docker.log"; return 1; }
}

stopped() { # <label> <both entries>: the last run exited ≠ 0, naming both entries, before any docker call
  local label=$1 both=$2
  check "$label: exits non-zero" exited_non_zero
  check "$label: names both entries ($both)" says "$both"
  check "$label: no docker call" called_no_docker
}

part_scripts() {
  stub_path "$work/stubs" docker getent powershell.exe

  # AC-3
  run_stubbed "$FIXTURES/duplicate-number.txt" bash ./up.sh
  stopped "duplicate number, up.sh" 'number 4: faito (line 5) and verif (line 6)'
  run_stubbed "$FIXTURES/duplicate-realm.txt" bash ./up.sh
  stopped "duplicate realm, up.sh" 'realm public-facing: hururaa (line 3) and verif (line 6)'
  run_stubbed "$FIXTURES/duplicate-theme.txt" bash ./up.sh
  stopped "duplicate theme, up.sh" 'theme tickee: tickee (line 4) and verif (line 6)'

  # REQ-4: register-app.sh as well, for an application of the registry
  run_stubbed "$FIXTURES/duplicate-realm.txt" bash ./register-app.sh --app faito
  stopped "duplicate realm, register-app.sh --app faito" 'realm public-facing: hururaa (line 3) and verif (line 6)'

  # AC-1
  run_stubbed "" bash ./register-app.sh --app verif
  check "unknown app: register-app.sh --app verif exits non-zero" exited_non_zero
  check "unknown app: its message names registry.txt" says registry.txt
  check "unknown app: its message names bash registry.sh next" says 'bash registry.sh next'
  check "unknown app: no docker call" called_no_docker
}

# The README's "Port registry" section, up to the next heading
port_registry_section() {
  awk '/^### Port registry$/ { on = 1; next } on && /^#/ { exit } on' README.md
}

holds() { # <text> <file or "-" for stdin>
  grep -qF -- "$1" "$2" || { echo "not found: $1"; return 1; }
}

no_table_of_numbers() {
  local rows
  rows=$(port_registry_section | grep -E '^\| *[0-9]+ *\| *[a-z]')
  [ -z "$rows" ] || { echo "table rows:"; printf '%s\n' "$rows"; return 1; }
}

part_docs() {
  local section
  section=$(port_registry_section)
  check "README: the Port registry section is there" test -n "$section"
  check "README: the section names registry.txt" holds registry.txt - <<< "$section"
  check "README: the section names bash registry.sh next" holds 'bash registry.sh next' - <<< "$section"
  check "README: the section holds no table of numbers" no_table_of_numbers
  check "migration.md names bash registry.sh next" holds 'bash registry.sh next' docs/migration.md
  check "migration.md gives the columns" holds 'n app realms rabbitmq-user themes dev-host demo-host' docs/migration.md
}

[ $# -gt 0 ] || set -- registry scripts docs
for part in "$@"; do
  case "$part" in
    registry | scripts | docs)
      echo "# $part"
      "part_$part"
      ;;
    *)
      echo "Unknown part: $part (registry, scripts or docs)" >&2
      exit 2
      ;;
  esac
done
finish
