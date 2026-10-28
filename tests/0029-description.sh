#!/usr/bin/env bash
# 0029: keycloak-image.properties, the description of the stack's Keycloak an application's tests
# read, says what keycloak/ builds:
#
#   - (a) its form: comments, blank lines and KEY=value lines whose values bash, Git Bash and Java's
#     properties read alike (no quote, space, $ or backslash), no CR;
#   - (b) sourced by bash, each value is its line's text;
#   - (c) its keys are KC_VERSION, KC_PUBLISHED_IMAGE and every ENV KC_* of keycloak/Dockerfile, with
#     the Dockerfile's values: each difference named, both ways, here and on copies (a feature
#     removed from the Dockerfile, another version in the description, an ENV added, a key added);
#   - (d) KC_PUBLISHED_IMAGE is ghcr.io/ch4mpy/c4-infra-keycloak:<KC_VERSION>-<12 hex of keycloak/'s
#     tree, as the working tree holds it>: a change of keycloak/ needs a new reference (another one
#     on a copy: named).
#
#   bash tests/0029-description.sh
#
# covers: keycloak/ keycloak-image.properties .github/workflows/ README.md docs/migration.md
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

DESCRIPTION=keycloak-image.properties
DOCKERFILE=keycloak/Dockerfile
REPOSITORY=ghcr.io/ch4mpy/c4-infra-keycloak

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

form() { # <description>: every line a comment, blank or KEY=value of the safe characters, no CR
  local bad
  bad=$(grep -nvE '^(#.*|[A-Z][A-Z0-9_]*=[A-Za-z0-9._,/:@+-]*|)$' "$1"; grep -n $'\r' "$1")
  [ -z "$bad" ] || { echo "lines:"; printf '%s\n' "$bad"; return 1; }
}
sourced_as_written() { # <description>: bash's value of each key is its line's text
  local line key value
  while IFS= read -r line; do
    key=${line%%=*} value=${line#*=}
    [ "$(bash -c 'set -a; . "./$1"; printf "%s" "${!2}"' _ "$1" "$key")" = "$value" ] \
      || { echo "$key: sourced as something else than '$value'"; return 1; }
  done < <(grep -E '^[A-Z]' "$1")
}
built() { # <Dockerfile>: KEY=value of its ARG KC_VERSION and ENV KC_* lines
  sed -nE 's/^ARG (KC_VERSION)=(.*)$/\1=\2/p; s/^ENV (KC_[A-Z0-9_]+)=(.*)$/\1=\2/p' "$1"
}
described() { # <description>: its KEY=value lines, KC_PUBLISHED_IMAGE aside
  grep -E '^[A-Z]' "$1" | grep -v '^KC_PUBLISHED_IMAGE='
}
same_settings() { # <Dockerfile> <description>: each key whose value differs, or that only one names
  local key in_dockerfile in_description differs=0
  for key in $({ built "$1"; described "$2"; } | cut -d= -f1 | LC_ALL=C sort -u); do
    in_dockerfile=$(built "$1" | grep "^$key=") in_description=$(described "$2" | grep "^$key=")
    if [ -z "$in_description" ]; then
      echo "$key: in $1, not in $2"
    elif [ -z "$in_dockerfile" ]; then
      echo "$key: in $2, not in $1"
    elif [ "$in_dockerfile" != "$in_description" ]; then
      echo "$key: $1 says ${in_dockerfile#*=}, $2 says ${in_description#*=}"
    else
      continue
    fi
    differs=1
  done
  return "$differs"
}
keycloak_tree() { # the 12 first hex of keycloak/'s tree as the working tree holds it; .git/objects untouched
  local tmp objects
  tmp=$(mktemp -d)
  mkdir "$tmp/objects"
  objects=$(git rev-parse --path-format=absolute --git-path objects)
  GIT_INDEX_FILE=$tmp/index GIT_OBJECT_DIRECTORY=$tmp/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$objects \
    git add -- keycloak \
    && GIT_INDEX_FILE=$tmp/index GIT_OBJECT_DIRECTORY=$tmp/objects GIT_ALTERNATE_OBJECT_DIRECTORIES=$objects \
      git write-tree --prefix=keycloak/ | cut -c1-12
  rm -rf "$tmp"
}
published_here() { # <description> <tree>: its KC_PUBLISHED_IMAGE is this keycloak/'s
  local expected named
  expected=$REPOSITORY:$(built "$DOCKERFILE" | sed -n 's/^KC_VERSION=//p')-$2
  named=$(sed -n 's/^KC_PUBLISHED_IMAGE=//p' "$1")
  [ "$named" = "$expected" ] || { echo "KC_PUBLISHED_IMAGE: $1 says $named, keycloak/ gives $expected"; return 1; }
}
refused_naming() { # <text> <command…>: the command fails, its output holding the text
  local output
  ! output=$("${@:2}" 2>&1) && grep -qF -- "$1" <<< "$output" || { echo "output:"; printf '%s\n' "$output"; return 1; }
}

check "(a) the description's lines are comments or KEY=value, no CR" form "$DESCRIPTION"
check "(b) sourced by bash, each value is its line's text" sourced_as_written "$DESCRIPTION"
check "(c) its settings are keycloak/Dockerfile's, both ways" same_settings "$DOCKERFILE" "$DESCRIPTION"
tree=$(keycloak_tree)
check "(d) keycloak/'s tree read ($tree)" grep -qE '^[0-9a-f]{12}$' <<< "$tree"
check "(d) KC_PUBLISHED_IMAGE is $REPOSITORY:<KC_VERSION>-$tree" published_here "$DESCRIPTION" "$tree"

# The differences named, on copies
sed 's/,cimd$//' "$DOCKERFILE" > "$work/feature-removed"
check "(c) a feature removed from the Dockerfile: named" \
  refused_naming "KC_FEATURES: $work/feature-removed says token-exchange-delegation,parameterized-scopes, $DESCRIPTION says token-exchange-delegation,parameterized-scopes,cimd" \
  same_settings "$work/feature-removed" "$DESCRIPTION"
sed 's/^KC_VERSION=.*/KC_VERSION=26.9.0/' "$DESCRIPTION" > "$work/other-version"
check "(c) another version in the description: named" \
  refused_naming "KC_VERSION: $DOCKERFILE says 26.8.1, $work/other-version says 26.9.0" same_settings "$DOCKERFILE" "$work/other-version"
{ cat "$DOCKERFILE"; echo 'ENV KC_LOG_LEVEL=info'; } > "$work/env-added"
check "(c) an ENV added to the Dockerfile: named" \
  refused_naming "KC_LOG_LEVEL: in $work/env-added, not in $DESCRIPTION" same_settings "$work/env-added" "$DESCRIPTION"
{ cat "$DESCRIPTION"; echo 'KC_LOG_LEVEL=info'; } > "$work/key-added"
check "(c) a key added to the description: named" \
  refused_naming "KC_LOG_LEVEL: in $work/key-added, not in $DOCKERFILE" same_settings "$DOCKERFILE" "$work/key-added"
check "(d) another tree: named" \
  refused_naming "keycloak/ gives $REPOSITORY:26.8.1-000000000000" published_here "$DESCRIPTION" 000000000000
printf 'KC_VERSION="26.8.1"\n' > "$work/quoted"
check "(a) a quoted value: refused" refused_naming 'KC_VERSION="26.8.1"' form "$work/quoted"
finish
