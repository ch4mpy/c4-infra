#!/usr/bin/env bash
# Exports a realm, users included, from the shared Keycloak without stopping it: a one-off
# container of the keycloak service (its image and database settings, none of its ports) runs
# kc.sh export against the same database.
#
#   export-realm.sh <realm> <destination directory>
#
# Writes <destination directory>/<realm>-realm.json, the file register-app.sh imports, without the
# realm's keys: whoever reads a key can sign tokens the applications accept, and Keycloak generates
# new ones when it imports a realm that has none.
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
mkdir -p "$destination"
destination=$(cd "$destination" && pwd)

cd "$(dirname "$0")"

container="c4-infra.keycloak-export-$realm"
docker rm -f "$container" > /dev/null 2>&1 || true
trap 'docker rm -f "$container" > /dev/null 2>&1 || true' EXIT

docker compose run --no-deps --name "$container" keycloak \
  export --optimized --realm "$realm" --users realm_file --dir /tmp/export

exported=$(mktemp)
docker cp "$container:/tmp/export/$realm-realm.json" "$(host_path "$exported")"
# the key providers' array, from its opening line to its closing one, becomes an empty array
awk '
  skip && /^    \} \],?$/ {
    skip = 0
    print "    \"org.keycloak.keys.KeyProvider\" : [ ]" (/,$/ ? "," : "")
    next
  }
  skip { next }
  /^    "org\.keycloak\.keys\.KeyProvider" : \[ \{$/ { skip = 1; next }
  { print }
' "$exported" > "$destination/$realm-realm.json"
rm -f "$exported"
# a layout the awk script doesn't know must not let a key through
if grep -q '"privateKey"\|"secret" : \[ "[A-Za-z0-9_-]\{20,\}' "$destination/$realm-realm.json"; then
  rm -f "$destination/$realm-realm.json"
  echo "The export still holds the realm's keys (unknown layout): nothing written" >&2
  exit 1
fi
echo "Exported $destination/$realm-realm.json (keys removed)"
