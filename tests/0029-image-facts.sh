#!/usr/bin/env bash
# 0029: the stack's Keycloak image, as an application's tests run it, says and does what
# keycloak-image.properties describes (facts of the image, measured; run by --all):
#
#   - (a) the image there (pulled when it isn't); its label org.opencontainers.image.version is
#     KC_VERSION; its environment holds each setting of the description;
#   - (b) it holds no credential: no environment variable or label named after a password, a secret,
#     a token, a credential or a private key, nor valued like one; the files it adds or changes over
#     quay.io/keycloak/keycloak:<KC_VERSION> are the healthcheck, the stack's themes (as
#     keycloak/stack-themes/ holds them) and their JAR, and kc.sh build's output: no realm, no import;
#   - (c) started as the README says, `-e KC_DB=dev-file <image> start-dev` and a bootstrap
#     administrator, nothing else: ready, the master realm answering over plain HTTP under /auth,
#     the description's features enabled and no other preview or experimental one, the simulated
#     providers' login themes there.
#
#   bash tests/0029-image-facts.sh [<image>]   (c4-infra/keycloak, up.sh's build, by default; the
#                                              published reference after its publication)
#
# The throwaway is removed whatever happens.
#
# covers: keycloak/ keycloak-image.properties
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
source tests/lib/keycloak.sh

IMAGE=${1:-c4-infra/keycloak}
NAME=c4-infra.0029-facts
SERVER=http://localhost:8080/auth
DESCRIPTION=keycloak-image.properties
export MSYS_NO_PATHCONV=1

host_path() { if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
described() { sed -n "s/^$1=//p" "$DESCRIPTION"; }

umask 022
work=$(mktemp -d)
cleanup() {
  docker rm -f "$NAME" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
docker rm -f "$NAME" > /dev/null 2>&1

# (a) what the image says
docker image inspect "$IMAGE" > /dev/null 2>&1 || docker pull --quiet "$IMAGE" > /dev/null
check "(a) $IMAGE is there" docker image inspect "$IMAGE"
version=$(described KC_VERSION)
check "(a) $IMAGE: org.opencontainers.image.version is $version" \
  test "$(docker image inspect "$IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.version"}}' | tr -d '\r')" = "$version"
docker image inspect "$IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}' | tr -d '\r' > "$work/env"
for key in $(grep -E '^[A-Z]' "$DESCRIPTION" | cut -d= -f1 | grep -vxE 'KC_VERSION|KC_PUBLISHED_IMAGE'); do
  check "(a) its $key is the description's ($(described "$key"))" grep -qxF "$key=$(described "$key")" "$work/env"
done

# (b) no credential, and only the expected files
docker image inspect "$IMAGE" --format '{{range $k, $v := .Config.Labels}}{{println $k "=" $v}}{{end}}' | tr -d '\r' \
  | grep -v '^com\.docker\.compose\.' > "$work/labels"
credential_free() {
  local found
  [ -s "$work/env" ] || { echo "no environment read"; return 1; }
  found=$(cut -d= -f1 "$work/env" "$work/labels" | grep -iE 'pass|secret|token|credential|private'
    cut -d= -f2- "$work/env" "$work/labels" | grep -iE 'pass|secret|credential|private')
  [ -z "$found" ] || { printf '%s\n' "$found"; return 1; }
}
check "(b) no environment variable or label holds a credential" credential_free
files() { # <image>: each file of /opt/keycloak and its checksum (the image has no awk)
  docker run --rm --entrypoint bash "$1" -c 'cd /opt/keycloak && find . \( -type f -o -type l \) -print0 | LC_ALL=C sort -z \
    | xargs -0 sha256sum | while read -r sum file; do printf "%s %s\n" "$file" "$sum"; done'
}
files "quay.io/keycloak/keycloak:$version" > "$work/upstream"
files "$IMAGE" > "$work/image"
check "(b) the files of both images listed ($(wc -l < "$work/upstream"), $(wc -l < "$work/image"))" \
  eval '[ "$(wc -l < "$work/upstream")" -gt 100 ] && [ "$(wc -l < "$work/image")" -gt 100 ]'
added_expected() {
  local other
  other=$(LC_ALL=C comm -13 "$work/upstream" "$work/image" | cut -d' ' -f1 \
    | grep -vE '^\./(healthcheck/[^/]+|providers/c4-infra-stack-themes\.jar|stack-themes/.+|lib/quarkus/.+)$')
  [ -z "$other" ] || { echo "added or changed:"; printf '%s\n' "$other"; return 1; }
}
check "(b) it adds or changes only the healthcheck, the stack's themes, their JAR and kc.sh build's output" added_expected
check "(b) no realm file, no data/import" eval '! grep -E "realm\.json|^\./data/import/" "$work/image"'
stack_themes() { # keycloak/stack-themes/'s files and checksums, as the image lists its own
  (cd keycloak/stack-themes && find . -type f | LC_ALL=C sort | while read -r f; do
    printf './stack-themes/%s %s\n' "${f#./}" "$(sha256sum "$f" | cut -d' ' -f1)"
  done)
}
check "(b) its stack-themes/ is keycloak/stack-themes/, file by file" \
  diff <(stack_themes) <(grep '^\./stack-themes/' "$work/image")

# (c) started as an application's tests start it
KC_CLI_PASSWORD=$(openssl rand -hex 16)
export KC_CLI_PASSWORD
printf '%s\n' KC_BOOTSTRAP_ADMIN_USERNAME=admin "KC_BOOTSTRAP_ADMIN_PASSWORD=$KC_CLI_PASSWORD" > "$work/admin.env"
chmod 600 "$work/admin.env"
docker run -d --name "$NAME" --env-file "$(host_path "$work/admin.env")" -e KC_DB=dev-file "$IMAGE" start-dev > /dev/null
check "(c) started with KC_DB=dev-file and start-dev: ready" kc_throwaway_ready "$NAME"
master_answers() {
  docker exec "$NAME" bash -c 'exec 3<> /dev/tcp/localhost/8080
    printf "GET /auth/realms/master HTTP/1.0\r\nHost: localhost\r\n\r\n" >&3
    head -n 1 <&3' | grep -q ' 200 '
}
check "(c) the master realm answers over plain HTTP, under /auth" master_answers
docker exec -e KC_CLI_PASSWORD "$NAME" /opt/keycloak/bin/kcadm.sh get serverinfo \
  --no-config --server "$SERVER" --realm master --user admin 2> /dev/null > "$work/serverinfo.json"
# serverinfo names a feature in capitals (token-exchange-delegation: TOKEN_EXCHANGE_DELEGATION), with its type
features() { described KC_FEATURES | tr ',' '\n' | tr 'a-z-' 'A-Z_' | grep . | LC_ALL=C sort; }
for feature in $(features); do
  check "(c) the feature $feature is enabled" \
    jq -e --arg f "$feature" 'any(.features[]; .name == $f and .enabled)' < "$work/serverinfo.json"
done
other_features() {
  local other
  other=$(jq -r '.features[] | select(.enabled and (.type == "PREVIEW" or .type == "EXPERIMENTAL")) | .name' \
    < "$work/serverinfo.json" | LC_ALL=C sort | LC_ALL=C comm -23 - <(features))
  [ -z "$other" ] || { echo "enabled, not described:"; printf '%s\n' "$other"; return 1; }
}
check "(c) no other preview or experimental feature is enabled" other_features
for theme in simulated-google simulated-facebook simulated-apple; do
  check "(c) the login theme $theme is there" jq -e --arg t "$theme" 'any(.themes.login[]; .name == $t)' < "$work/serverinfo.json"
done
finish
