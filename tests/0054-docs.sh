#!/usr/bin/env bash
# 0054: README states what the stack's Keycloak does with a client metadata document at a private
# address until the upgrade to Keycloak 27.x, and the note can't outlive its reason:
#
#   - (AC-09) "Keycloak in an application's tests" says the published image carries no refusal of
#     private addresses, that from 27.x the refusal is the realm's cimd-allow-private-use-addresses,
#     and that an application's private-address test proves nothing of the stack;
#   - (AC-10) beside the cimd checks of "What an application provides", the accepted risk: an
#     unauthenticated client, a trusted domain resolving to the host's private networks, on dev and
#     on the demo host, accepted on 2026-11-01 until the upgrade to Keycloak 27.0, taken up end of
#     January or early February 2027 (release planned for 29 January 2027);
#   - (RQ-10) once KC_VERSION of keycloak-image.properties is 27 or later, README stating the
#     accepted risk fails, naming 0054 and what the upgrade's intent owes; on a copy of README that
#     states it, with KC_VERSION=27.0.0 (fails, naming 0054) and 26.8.1 (passes) (AC-12).
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
ACCEPTED_RISK='accepted risk'

RISK_TERMS=("$ACCEPTED_RISK" 'unauthenticated client' 'trusted domain' 'private networks'
  'dev and on the demo host' '2026-11-01' 'Keycloak 27.0' 'end of January or early February 2027'
  '29 January 2027')
IMAGE_TERMS=('carries no refusal of private addresses' 'cimd-allow-private-use-addresses'
  'proves nothing of the stack')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

section() { # <readme> <heading>: the section's text on one line, its line breaks read as spaces
  sed -n "/^### $2\$/,/^### /p" "$1" | tr '\n' ' ' | tr -s ' '
}

names_every_term() { # <readme> <heading> <term…>
  local readme=$1 heading=$2 text term missing=()
  shift 2
  text=$(section "$readme" "$heading")
  [ -n "$text" ] || { echo "$readme has no section '### $heading'"; return 1; }
  for term in "$@"; do
    grep -qF -- "$term" <<< "$text" || missing+=("'$term'")
  done
  [ ${#missing[@]} -eq 0 ] || { echo "'$heading' doesn't name ${missing[*]}"; return 1; }
}

no_risk_left_after_upgrade() { # <readme> <description>
  local version major
  version=$(sed -n 's/^KC_VERSION=//p' "$2" | tr -d '\r')
  major=${version%%.*}
  [[ $major =~ ^[0-9]+$ ]] || { echo "$2: KC_VERSION '$version' isn't a version"; return 1; }
  if [ "$major" -ge 27 ] && grep -qF -- "$ACCEPTED_RISK" <<< "$(section "$1" "$PROVIDES_SECTION")"; then
    echo "0054: Keycloak is $version and README's '$PROVIDES_SECTION' still states the accepted risk" \
      "of a client metadata document fetched from a private address. The Keycloak upgrade's intent owes:" \
      "cimd-allow-private-use-addresses off in every client-id-metadata-document executor of the" \
      "stack's realms, 0013's RQ-17 check refusing an export that sets it to a value Keycloak reads" \
      "as true, and README's residual risks in place of the accepted-risk note"
    return 1
  fi
}

copy_stating_the_risk() { # <KC_VERSION> <dir>: README with the accepted risk, and the description at that version
  mkdir -p "$2"
  sed "/^### $PROVIDES_SECTION\$/a\\
Until Keycloak 27.0, an $ACCEPTED_RISK." "$README" > "$2/README.md"
  sed "s/^KC_VERSION=.*/KC_VERSION=$1/" "$DESCRIPTION" > "$2/$DESCRIPTION"
}

refused_naming_0054() { # <dir>
  local output
  if output=$(no_risk_left_after_upgrade "$1/README.md" "$1/$DESCRIPTION"); then
    echo "passed"
    return 1
  fi
  grep -qF '0054' <<< "$output" || { echo "refused without naming 0054: $output"; return 1; }
}

check "(AC-09) README's tests section says the published image carries no refusal of private addresses" \
  names_every_term "$README" "$TESTS_SECTION" "${IMAGE_TERMS[@]}"
check "(AC-10) README states the accepted risk beside the cimd checks" \
  names_every_term "$README" "$PROVIDES_SECTION" "${RISK_TERMS[@]}"
check "(RQ-10) README states no accepted risk once Keycloak is 27 or later" \
  no_risk_left_after_upgrade "$README" "$DESCRIPTION"

copy_stating_the_risk 27.0.0 "$work/27"
check "(AC-12) a copy at 27.0.0 still stating the risk is refused, naming 0054" refused_naming_0054 "$work/27"
copy_stating_the_risk 26.8.1 "$work/26"
check "(AC-12) a copy at 26.8.1 stating the risk passes" \
  no_risk_left_after_upgrade "$work/26/README.md" "$work/26/$DESCRIPTION"
finish
