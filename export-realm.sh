#!/usr/bin/env bash
# Exports a realm, users included, from the shared Keycloak without stopping it: a one-off
# container of the same image runs kc.sh export against the same database.
#
#   export-realm.sh <realm> <destination directory>
#
# Writes <destination directory>/<realm>-realm.json, the file register-app.sh imports.
set -euo pipefail
export MSYS_NO_PATHCONV=1

# A host path as the docker CLI expects it: a Windows path under Git Bash, unchanged elsewhere
host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else echo "$1"; fi
}

if [ $# -ne 2 ]; then
  echo "usage: $0 <realm> <destination directory>" >&2
  exit 1
fi
realm=$1
destination=$2

INFRA_DIR=$(cd "$(dirname "$0")" && pwd)
source "$INFRA_DIR/.env"

container="c4-infra.keycloak-export-$realm"
docker rm -f "$container" > /dev/null 2>&1 || true
trap 'docker rm -f "$container" > /dev/null 2>&1 || true' EXIT

docker create --name "$container" --network c4-infra \
  -e KC_DB_URL=jdbc:postgresql://keycloak-db:5432/keycloak \
  -e KC_DB_USERNAME=keycloak \
  -e KC_DB_PASSWORD="$KC_DB_PASSWORD" \
  "c4-infra/keycloak:$KC_VERSION" \
  export --optimized --realm "$realm" --users realm_file --dir /tmp/export > /dev/null
docker start -a "$container"

mkdir -p "$destination"
docker cp "$container:/tmp/export/$realm-realm.json" "$(host_path "$destination/$realm-realm.json")"
echo "Exported $destination/$realm-realm.json"
