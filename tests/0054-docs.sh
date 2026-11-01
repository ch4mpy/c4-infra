#!/usr/bin/env bash
# 0054: README states what the stack's Keycloak does with a client metadata document at a private
# address until the upgrade to Keycloak 27.x, and the note can't outlive its reason. While
# KC_VERSION of keycloak-image.properties is below 27:
#
#   - (AC-09) "Keycloak in an application's tests" says the published image carries no refusal of
#     private addresses, that from 27.x the refusal is the realm's cimd-allow-private-use-addresses,
#     and that an application's private-address test proves nothing of the stack;
#   - (AC-10) the cimd checks of "What an application provides" state the accepted risk: an
#     unauthenticated client, a trusted domain resolving to the host's private networks, on dev and
#     on the demo host, what the fetch exposes, the free precaution, accepted on 2026-11-01 until the
#     upgrade to Keycloak 27.0, taken up end of January or early February 2027 (release planned for
#     29 January 2027), a realm opting into cimd taking that risk, and what stays after 27.0.
#
#   - (RQ-10) once KC_VERSION is 27 or later, README holding the note's marker fails, naming 0054
#     and what the upgrade's intent owes; (AC-12) on copies of README: at 27.0.0 without the note it
#     passes and with the marker inserted it fails, naming 0054 and what is owed; at 26.8.1, README
#     as it is passes.
#
#   bash tests/0054-docs.sh
#
# covers: README.md keycloak-image.properties
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

README=README.md
DESCRIPTION=keycloak-image.properties
PROVIDES_SECTION='What an application provides'
TESTS_SECTION="Keycloak in an application's tests"
CIMD_ITEM='client policies that fetch client metadata documents'
NOTE_MARKER='accepted risk (intent 0054)'
FIRST_MAJOR_WITHOUT_THE_RISK=27

RISK_TERMS=("$NOTE_MARKER" 'unauthenticated client' 'trusted domain' 'private networks'
  'dev and on the demo host' 'blind TCP/TLS probe' 'valid for the trusted name and trusted by Keycloak'
  'at most a connection attempt' 'exact host names' 'a zone whose DNS the realm'"'"'s owner alone controls'
  '`*.nip.io`' '`*.github.io`' '2026-11-01' 'Keycloak 27.0' 'end of January or early February 2027'
  '29 January 2027' 'A realm that opts into `cimd` takes that risk' 'narrows, it doesn'"'"'t close'
  '`jwks_uri`' 'DNS rebinding')
IMAGE_TERMS=('carries no refusal of private addresses' 'cimd-allow-private-use-addresses'
  'proves nothing of the stack')
OWED_TERMS=('cimd-allow-private-use-addresses off' "RQ-17" 'facts test on Keycloak 27'
  "0054's AC-09 and AC-10")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

section_lines() { # <readme> <heading>
  sed -n "/^### $2\$/,/^### /p" "$1"
}

section() { # <readme> <heading>: the section's text on one line, its line breaks read as spaces
  section_lines "$1" "$2" | tr '\n' ' ' | tr -s ' '
}

cimd_item() { # <readme>: the cimd checks' item of "What an application provides", on one line
  section_lines "$1" "$PROVIDES_SECTION" | awk -v item="$CIMD_ITEM" '
    index($0, item) { inside = 1; print; next }
    inside && /^(  )?- / { exit }
    inside { print }' | tr '\n' ' ' | tr -s ' '
}

names_every_term() { # <text's label> <text> <term…>
  local label=$1 text=$2 term missing=()
  shift 2
  [ -n "${text// /}" ] || { echo "README has no $label"; return 1; }
  for term in "$@"; do
    grep -qF -- "$term" <<< "$text" || missing+=("'$term'")
  done
  [ ${#missing[@]} -eq 0 ] || { echo "$label doesn't name ${missing[*]}"; return 1; }
}

kc_major() { # <description>
  local version
  version=$(sed -n 's/^KC_VERSION=//p' "$1" | tr -d '\r')
  [[ ${version%%.*} =~ ^[0-9]+$ ]] || { echo "$1: KC_VERSION '$version' isn't a version" >&2; return 1; }
  echo "${version%%.*}"
}

no_risk_left_after_upgrade() { # <readme> <description>
  local major
  major=$(kc_major "$2") || return 1
  if [ "$major" -ge "$FIRST_MAJOR_WITHOUT_THE_RISK" ] && grep -qF -- "$NOTE_MARKER" "$1"; then
    echo "0054: Keycloak's major version is $major and README still holds '$NOTE_MARKER', the" \
      "note of a client metadata document fetched from a private address. The Keycloak upgrade's" \
      "intent owes: cimd-allow-private-use-addresses off in every client-id-metadata-document" \
      "executor of the stack's realms; 0013's RQ-17 check refusing an export that sets it to a" \
      "value Keycloak reads as true; a facts test on Keycloak 27 proving the refusal; README's" \
      "residual risks in place of the note and of its pointer from 'Reachable from an" \
      "application's network'; and retiring 0054's AC-09 and AC-10 notes and their checks in" \
      "tests/0054-docs.sh"
    return 1
  fi
}

without_the_note() { # <readme>: README without the note's items, from the marker's to the cimd item's end
  awk -v item="$CIMD_ITEM" -v marker="$NOTE_MARKER" '
    index($0, item) { cimd = 1 }
    cimd && /^    - / && index($0, marker) { dropping = 1 }
    /^(  )?- / && !index($0, item) { cimd = 0; dropping = 0 }
    !dropping { print }' "$1"
}

copy_at() { # <KC_VERSION> <dir> <readme source command…>: README from the command, the description at that version
  local version=$1 dir=$2
  shift 2
  mkdir -p "$dir"
  "$@" > "$dir/README.md"
  sed "s/^KC_VERSION=.*/KC_VERSION=$version/" "$DESCRIPTION" > "$dir/$DESCRIPTION"
}

with_the_marker_inserted() { # <readme>: README without the note, the marker inserted under the cimd item
  without_the_note "$1" | awk -v item="$CIMD_ITEM" -v marker="$NOTE_MARKER" '
    { print } index($0, item) { print "    - an " marker ", inserted by tests/0054-docs.sh;" }'
}

refused_naming_0054() { # <dir>
  local output term missing=()
  if output=$(no_risk_left_after_upgrade "$1/README.md" "$1/$DESCRIPTION"); then
    echo "passed"
    return 1
  fi
  for term in 0054 "${OWED_TERMS[@]}"; do
    grep -qF -- "$term" <<< "$output" || missing+=("'$term'")
  done
  [ ${#missing[@]} -eq 0 ] || { echo "refused without naming ${missing[*]}: $output"; return 1; }
}

note_absent() { # <readme>
  ! grep -qF -- "$NOTE_MARKER" "$1" || { echo "$1 still holds '$NOTE_MARKER'"; return 1; }
}

if major=$(kc_major "$DESCRIPTION") && [ "$major" -lt "$FIRST_MAJOR_WITHOUT_THE_RISK" ]; then
  check "(AC-09) README's tests section says the published image carries no refusal of private addresses" \
    names_every_term "'$TESTS_SECTION'" "$(section "$README" "$TESTS_SECTION")" "${IMAGE_TERMS[@]}"
  check "(AC-10) README states the accepted risk in the cimd checks' item" \
    names_every_term "the cimd checks' item of '$PROVIDES_SECTION'" "$(cimd_item "$README")" "${RISK_TERMS[@]}"
else
  echo "skip - (AC-09, AC-10) Keycloak's major version is ${major:-unread}: the notes are the upgrade's to retire"
fi
check "(RQ-10) README holds no accepted-risk note once Keycloak is $FIRST_MAJOR_WITHOUT_THE_RISK or later" \
  no_risk_left_after_upgrade "$README" "$DESCRIPTION"

copy_at 27.0.0 "$work/27-without" without_the_note "$README"
check "(AC-12) a copy at 27.0.0 without the note holds no marker" note_absent "$work/27-without/README.md"
check "(AC-12) a copy at 27.0.0 without the note passes" \
  no_risk_left_after_upgrade "$work/27-without/README.md" "$work/27-without/$DESCRIPTION"
copy_at 27.0.0 "$work/27-inserted" with_the_marker_inserted "$README"
check "(AC-12) the same copy with the marker inserted is refused, naming 0054 and what is owed" \
  refused_naming_0054 "$work/27-inserted"
copy_at 26.8.1 "$work/26" cat "$README"
check "(AC-12) README as it is, at 26.8.1, passes" \
  no_risk_left_after_upgrade "$work/26/README.md" "$work/26/$DESCRIPTION"
finish
