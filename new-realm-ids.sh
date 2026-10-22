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

uuid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

for file in "$@"; do
  # "id" : "<uuid>", then "username" : "<name>" on the next line: the export's layout for users
  users=$(grep -A1 -E "^    \"id\" : \"$uuid\",$" "$file" | grep -B1 '"username"' \
    | sed -n 's/.*"id" : "\(.*\)",/\1/p; s/.*"username" : "\(.*\)",/\1/p' | paste - - || true)
  ids=($(grep -oE "$uuid" "$file" | sort -u || true))
  if [ ${#ids[@]} -eq 0 ]; then
    echo "$file: no id"
    continue
  fi
  # one draw for every id of the file, cut into random (version 4) UUIDs
  random=$(openssl rand -hex $((16 * ${#ids[@]})))
  declare -A new_id=()
  script=$(mktemp)
  for i in "${!ids[@]}"; do
    hex=${random:$((32 * i)):32}
    new_id[${ids[$i]}]=$(printf '%s-%s-4%s-%x%s-%s' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
      $(((16#${hex:16:1} & 3) | 8)) "${hex:17:3}" "${hex:20:12}")
    echo "s/${ids[$i]}/${new_id[${ids[$i]}]}/g" >> "$script"
  done
  sed -i -f "$script" "$file"
  rm -f "$script"
  echo "$file: ${#ids[@]} ids replaced"
  while IFS=$'\t' read -r old name; do
    [ -n "$old" ] && echo "  user $name: $old -> ${new_id[$old]}"
  done <<< "$users"
  unset new_id
done
