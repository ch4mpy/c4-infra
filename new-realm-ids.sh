#!/usr/bin/env bash
# Gives realm exports ids of their own, in place: every UUID of a file is replaced by a new random
# one, the same everywhere in that file, so that its references (roles' containerId, components'
# parentId...) still hold.
#
#   new-realm-ids.sh <realm file>...
#
# The shared Keycloak keeps every application's realms in one database, where each id (realm,
# client, role, user, group, flow...) is a primary key: two realms exported from the same template
# can't both be imported ("Duplicate resource error"). Run it once per realm file, before its first
# registration, and commit the result. The users' new ids are printed: whatever the project stores
# about them (dev seed data, for instance) must follow.
set -euo pipefail

uuid=$'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

new_uuid() {
  local hex
  hex=$(openssl rand -hex 16)
  # version 4, variant 10xx
  printf '%s-%s-4%s-%x%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" $(( (16#${hex:16:1} & 3) | 8 )) "${hex:17:3}" "${hex:20:12}"
}

for file in "$@"; do
  script=$(mktemp)
  users_before=$(mktemp)
  # "id" : "<uuid>", then "username" : "<name>" on the next line: the export's layout for users
  grep -A1 -E "^    \"id\" : \"$uuid\",$" "$file" | grep -B1 '"username"' \
    | sed -n 's/.*"id" : "\(.*\)",/\1/p; s/.*"username" : "\(.*\)",/\1/p' | paste - - > "$users_before" || true
  for id in $(grep -oE "$uuid" "$file" | sort -u); do
    echo "s/$id/$(new_uuid)/g" >> "$script"
  done
  sed -i -f "$script" "$file"
  echo "$file: $(wc -l < "$script") ids replaced"
  while IFS=$'\t' read -r old name; do
    [ -n "$old" ] || continue
    echo "  user $name: $old -> $(sed -n "s|^s/$old/\(.*\)/g$|\1|p" "$script")"
  done < "$users_before"
  rm -f "$script" "$users_before"
done
