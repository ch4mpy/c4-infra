#!/usr/bin/env bash
# 0029: keycloak-image.properties, the description of the stack's Keycloak an application's tests
# read, says what keycloak/ builds:
#
#   - (a) its form: comments, blank lines and KEY=value lines whose values bash, Git Bash and Java's
#     properties read alike (no quote, space, $ or backslash), no CR; on copies, each refused naming
#     its one changed line alone: a CR before LF, a CR ending the last line, a CR inside a comment, a
#     space in a value, a lowercase key, a quoted value;
#   - (b) sourced by bash, each value is its line's text;
#   - (c) its keys are KC_VERSION, KC_PUBLISHED_IMAGE and every ENV KC_* of keycloak/Dockerfile, with
#     the Dockerfile's values: each difference named, both ways, here and on copies (a feature
#     removed from the Dockerfile, another version in the description, an ENV added, a key added);
#   - (d) KC_PUBLISHED_IMAGE is ghcr.io/ch4mpy/c4-infra-keycloak:<KC_VERSION>-<12 hex of keycloak/'s
#     tree, as the working tree holds it>: a change of keycloak/ needs a new reference (another one
#     on a copy: named);
#   - (e) the workflow's "Compute the images" block, run as it is: when keycloak/ is HEAD's, the
#     version reference it publishes is KC_PUBLISHED_IMAGE, beside the tree's; a description naming
#     another one stops it, ::error:: naming both (on copies);
#   - (f) the README's "Keycloak in an application's tests" holds a dated changelog entry for that
#     tag: a change of keycloak/ without its entry fails (a README copy without it: named);
#   - (g) the section names the description, start-dev and KC_DB=dev-file; docs/migration.md
#     points to it;
#   - (h) its bullet on a change names the generated admin client's sentence, and the changelog
#     entry of each version change (another version than the entry below it, or the oldest) holds
#     "Generated admin client:" (on copies: an entry of another version without it, named; one of
#     the same version without it, not named).
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
  local bad cr=$'\r'
  # cr outside $(…), where Git Bash drops it; -U: Git Bash's grep strips a CR before LF without it
  bad=$(grep -nvE '^(#.*|[A-Z][A-Z0-9_]*=[A-Za-z0-9._,/:@+-]*|)$' "$1"; grep -nU "$cr" "$1")
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
env_lines_read() { # <Dockerfile>: every ENV line is one KC_*=value, which built reads
  local other
  other=$(grep -nE '^[[:space:]]*ENV[[:space:]]' "$1" | grep -vE '^[0-9]+:ENV KC_[A-Z0-9_]+=[^[:space:]]*$')
  [ -z "$other" ] || { echo "ENV lines of another form:"; printf '%s\n' "$other"; return 1; }
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
compute_block() { # the commands of the workflow's "Compute the images" step
  awk '/- name: Compute the images/ { step = 1 } step && /run: \|/ { block = 1; next }
    block && /^[[:space:]]*$/ { exit } block { sub(/^ {10}/, ""); print }' .github/workflows/deploy-demo.yml
}
computed() { # <dir>: the block run there (its keycloak/Dockerfile and keycloak-image.properties, this repository's HEAD), its outputs in <dir>/output
  local block
  block=$(compute_block)
  (cd "$1" && GIT_DIR=$git_dir GITHUB_OUTPUT=$1/output REGISTRY=ghcr.io GITHUB_REPOSITORY_OWNER=ch4mpy bash -c "$block")
}
output() { sed -n "s/^$2=//p" "$1/output"; }
section() { # <README>: its "Keycloak in an application's tests" section
  awk '/^### Keycloak in an application.s tests$/ { inside = 1; next } inside && /^##/ { exit } inside' "$1"
}
changelog_entry() { # <README> <tag>: a dated entry of the section's changelog names the tag
  section "$1" | grep -qE "^- [0-9]{4}-[0-9]{2}-[0-9]{2} — \`${2//./\\.}\`" || { echo "no changelog entry for $2"; return 1; }
}
change_bullet() { # <README>: the section's bullet on a change of the stack's Keycloak, its lines joined
  section "$1" | awk '/^- \*\*A change\*\*/ { inside = 1; printf "%s", $0; next }
    inside && /^  / { sub(/^ +/, " "); printf "%s", $0; next } inside { exit }'
}
entries() { # <README>: each entry of the section's changelog on one line: its tag, a tab, its lines joined
  section "$1" | awk '/^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { if (entry != "") print entry
      tag = $0; sub(/^[^`]*`/, "", tag); sub(/`.*$/, "", tag); entry = tag "\t" $0; next }
    entry != "" && /^  / { sub(/^ +/, " "); entry = entry $0; next }
    entry != "" { print entry; entry = "" }
    END { if (entry != "") print entry }'
}
admin_client_named() { # <README>: the entry of each version change (another version than the entry below it, or the oldest) names the generated admin client
  local lines i tag below missing=0
  mapfile -t lines < <(entries "$1")
  [ "${#lines[@]}" -gt 0 ] || { echo "no changelog entry read"; return 1; }
  for i in "${!lines[@]}"; do
    tag=${lines[i]%%$'\t'*} below=
    [ $((i + 1)) -ge "${#lines[@]}" ] || below=${lines[i + 1]%%$'\t'*}
    [ "${tag%-*}" != "${below%-*}" ] || continue
    grep -qF 'Generated admin client:' <<< "${lines[i]#*$'\t'}" \
      || { echo "$tag: a version change whose entry doesn't name the generated admin client"; missing=1; }
  done
  return "$missing"
}
with_entry() { # <README> <entry line>: a copy whose changelog starts with that entry
  awk -v entry="$2" '/^### Keycloak in an application.s tests$/ { inside = 1 }
    inside && !done && /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { print entry; done = 1 } { print }' "$1"
}
not_named() { # <tag> <README>: admin_client_named names no entry of that tag
  local output
  output=$(admin_client_named "$2" 2>&1)
  ! grep -qF -- "$1:" <<< "$output" || { echo "output:"; printf '%s\n' "$output"; return 1; }
}
refused_naming() { # <text> <command…>: the command fails, its output holding the text
  local output
  ! output=$("${@:2}" 2>&1) && grep -qF -- "$1" <<< "$output" || { echo "output:"; printf '%s\n' "$output"; return 1; }
}
refused_lines() { # <line numbers> <description>: form refuses it, naming these lines and no other
  local output named
  ! output=$(form "$2" 2>&1) || { echo "accepted"; return 1; }
  named=$(sed -n 's/^\([0-9][0-9]*\):.*/\1/p' <<< "$output" | LC_ALL=C sort -un | paste -sd ' ' -)
  [ "$named" = "$1" ] || { echo "lines named: $named"; printf '%s\n' "$output"; return 1; }
}
crs() { # <file>: its CR bytes, counted without reading it as text
  od -An -tx1 "$1" | tr -s ' ' '\n' | grep -cx 0d
}

check "(a) the description's lines are comments or KEY=value, no CR" form "$DESCRIPTION"
check "(b) sourced by bash, each value is its line's text" sourced_as_written "$DESCRIPTION"
check "(c) every ENV line of keycloak/Dockerfile is one KC_*=value" env_lines_read "$DOCKERFILE"
check "(c) its settings are keycloak/Dockerfile's, both ways" same_settings "$DOCKERFILE" "$DESCRIPTION"
tree=$(keycloak_tree)
check "(d) keycloak/'s tree read ($tree)" grep -qE '^[0-9a-f]{12}$' <<< "$tree"
check "(d) KC_PUBLISHED_IMAGE is $REPOSITORY:<KC_VERSION>-$tree" published_here "$DESCRIPTION" "$tree"

# The differences named, on copies
version=$(built "$DOCKERFILE" | sed -n 's/^KC_VERSION=//p')
features=$(built "$DOCKERFILE" | sed -n 's/^KC_FEATURES=//p')
fewer=${features%,*}
[ "$fewer" != "$features" ] || fewer=
sed "s/^ENV KC_FEATURES=.*/ENV KC_FEATURES=$fewer/" "$DOCKERFILE" > "$work/feature-removed"
check "(c) a feature removed from the Dockerfile: named" \
  refused_naming "KC_FEATURES: $work/feature-removed says $fewer, $DESCRIPTION says $features" \
  same_settings "$work/feature-removed" "$DESCRIPTION"
sed "s/^KC_VERSION=.*/KC_VERSION=$version.0/" "$DESCRIPTION" > "$work/other-version"
check "(c) another version in the description: named" \
  refused_naming "KC_VERSION: $DOCKERFILE says $version, $work/other-version says $version.0" same_settings "$DOCKERFILE" "$work/other-version"
{ cat "$DOCKERFILE"; echo 'ENV KC_LOG_LEVEL=info'; } > "$work/env-added"
check "(c) an ENV added to the Dockerfile: named" \
  refused_naming "KC_LOG_LEVEL: in $work/env-added, not in $DESCRIPTION" same_settings "$work/env-added" "$DESCRIPTION"
{ cat "$DESCRIPTION"; echo 'KC_LOG_LEVEL=info'; } > "$work/key-added"
check "(c) a key added to the description: named" \
  refused_naming "KC_LOG_LEVEL: in $work/key-added, not in $DOCKERFILE" same_settings "$DOCKERFILE" "$work/key-added"
{ cat "$DOCKERFILE"; echo 'ENV KC_LOG_LEVEL info'; } > "$work/env-unread"
check "(c) an ENV line of another form: named" refused_naming 'ENV KC_LOG_LEVEL info' env_lines_read "$work/env-unread"
check "(d) another tree: named" \
  refused_naming "keycloak/ gives $REPOSITORY:$version-000000000000" published_here "$DESCRIPTION" 000000000000
git_dir=$(git rev-parse --absolute-git-dir)
head_tree=$(git rev-parse --short=12 HEAD:keycloak)
mkdir -p "$work/here/keycloak" "$work/other/keycloak"
cp "$DOCKERFILE" "$work/here/keycloak/"
cp "$DOCKERFILE" "$work/other/keycloak/"
cp "$DESCRIPTION" "$work/here/"
sed "s|^KC_PUBLISHED_IMAGE=.*|KC_PUBLISHED_IMAGE=$REPOSITORY:$version-000000000000|" "$DESCRIPTION" > "$work/other/$DESCRIPTION"
check "(e) the workflow's Compute the images block read" test -n "$(compute_block)"
if [ "$head_tree" = "$tree" ]; then
  check "(e) the block passes on this description" computed "$work/here"
  check "(e) the version reference it publishes is KC_PUBLISHED_IMAGE" \
    test "$(output "$work/here" version_image)" = "$(sed -n 's/^KC_PUBLISHED_IMAGE=//p' "$DESCRIPTION")"
  check "(e) the deployment's stays the tree's, $REPOSITORY:$head_tree" test "$(output "$work/here" image)" = "$REPOSITORY:$head_tree"
else
  echo "# (e) skipped: keycloak/ isn't HEAD's ($tree, HEAD $head_tree), which the workflow reads"
fi
check "(e) a description naming another reference: the block stops, naming both" \
  refused_naming "::error::keycloak-image.properties names $REPOSITORY:$version-000000000000, keycloak/ gives $REPOSITORY:$version-$head_tree" \
  computed "$work/other"
check "(e) and writes no output" test ! -s "$work/other/output"

published=$(sed -n 's/^KC_PUBLISHED_IMAGE=//p' "$DESCRIPTION")
check "(f) the README's changelog has a dated entry for ${published##*:}" changelog_entry README.md "${published##*:}"
grep -vF "\`${published##*:}\`" README.md > "$work/README.md"
check "(f) a README without it: named" refused_naming "no changelog entry for ${published##*:}" changelog_entry "$work/README.md" "${published##*:}"
for text in keycloak-image.properties start-dev KC_DB=dev-file; do
  check "(g) the section names $text" grep -qF -- "$text" <(section README.md)
done
check "(g) docs/migration.md points to it" grep -qF "#keycloak-in-an-applications-tests" docs/migration.md

check "(h) the bullet on a change names the generated admin client" \
  grep -qF 'Generated admin client:' <(change_bullet README.md)
check "(h) each version change's entry names the generated admin client" admin_client_named README.md
with_entry README.md "- 2026-10-30 — \`$version.0-000000000000\`: another version." > "$work/README-other-version.md"
check "(h) an entry of another version without it: named" \
  refused_naming "$version.0-000000000000: a version change whose entry doesn't name the generated admin client" \
  admin_client_named "$work/README-other-version.md"
with_entry README.md "- 2026-10-30 — \`$version-000000000000\`: the same version." > "$work/README-same-version.md"
check "(h) an entry of the same version without it: not named" not_named "$version-000000000000" "$work/README-same-version.md"

# (a) on copies of the description, one line changed in each, written straight to the file: under
# Git Bash, $(…) drops a CR written $'\r' inside it, and the CR before its output's last LF
key_line=$(grep -n '^[A-Z]' "$DESCRIPTION" | head -n 1 | cut -d: -f1)
last_line=$(grep -c '' "$DESCRIPTION")
sed "${key_line}s/\$/\r/" "$DESCRIPTION" > "$work/crlf"
{ head -n -1 "$DESCRIPTION"; printf '%s\r' "$(tail -n 1 "$DESCRIPTION")"; } > "$work/cr-end"
sed '1s/^#/#\r/' "$DESCRIPTION" > "$work/cr-comment"
sed "${key_line}s/\$/ x/" "$DESCRIPTION" > "$work/space"
sed "${key_line}s/^KC_/kc_/" "$DESCRIPTION" > "$work/lowercase"
sed "${key_line}s/=\(.*\)\$/=\"\1\"/" "$DESCRIPTION" > "$work/quoted"
for copy in crlf cr-end cr-comment; do
  check "(a) the copy $copy holds one CR" test "$(crs "$work/$copy")" = 1
done
check "(a) a CRLF line end: refused, naming line $key_line alone" refused_lines "$key_line" "$work/crlf"
check "(a) a CR ending the last line, no LF: refused, naming line $last_line alone" refused_lines "$last_line" "$work/cr-end"
check "(a) a CR inside a comment: refused, naming line 1 alone" refused_lines 1 "$work/cr-comment"
check "(a) a space in a value: refused, naming line $key_line alone" refused_lines "$key_line" "$work/space"
check "(a) a lowercase key: refused, naming line $key_line alone" refused_lines "$key_line" "$work/lowercase"
check "(a) a quoted value: refused" refused_lines "$key_line" "$work/quoted"
finish
