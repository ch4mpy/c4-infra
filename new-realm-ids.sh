#!/usr/bin/env bash
# Gives realm exports ids of their own, in place: every UUID of a file, and every entity's id in
# Keycloak's short form (a user federation's), is replaced by a new random one of the same form, the
# same everywhere in that file, so that its references (roles' containerId, components' parentId,
# users' federationLink and origin, storage ids f:<component>:...) still hold. A file holding an id of
# another form (a readable one), or that jq can't read, is left as it was, named, and the script exits 1.
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
# Keycloak's short id: 16 random bytes in base64url, without padding
short='[A-Za-z0-9_-]{22}'
# a federated user's storage id names its component, which it follows
storage="f:($uuid|$short):.+"

refused=0
for file in "$@"; do
  if ! users=$(jq -r '.users[]? | [.id, .username] | @tsv' < "$file"); then
    echo "$file: left as it was: not JSON that jq can read" >&2
    refused=1
    continue
  fi
  users=${users//$'\r'/}
  # every entity's id, in Keycloak's layout ("id" : …) or jq's ("id": …)
  keyed=$(grep -oE '"(id|_id|internalId)" *: *"[^"]*"' "$file" | sed -E 's/.*: *"(.*)"$/\1/' | LC_ALL=C sort -u || true)
  others=$(grep -vxE "$uuid|$short|$storage" <<< "$keyed" | grep . || true)
  if [ -n "$others" ]; then
    echo "$file: left as it was: ids neither UUIDs nor Keycloak's short ids, which can't be renewed in place:" >&2
    sed 's/^/  /' <<< "$others" >&2
    refused=1
    continue
  fi
  ids=($(grep -oE "$uuid" "$file" | LC_ALL=C sort -u || true))
  shorts=($(grep -xE "$short" <<< "$keyed" || true))
  count=$((${#ids[@]} + ${#shorts[@]}))
  if [ "$count" -eq 0 ]; then
    echo "$file: no id"
    continue
  fi
  # one draw for every id of the file, cut into random (version 4) UUIDs
  [ ${#ids[@]} -eq 0 ] || random=$(openssl rand -hex $((16 * ${#ids[@]})))
  declare -A new_id=()
  script=$(mktemp)
  for i in "${!ids[@]}"; do
    hex=${random:$((32 * i)):32}
    new_id[${ids[$i]}]=$(printf '%s-%s-4%s-%x%s-%s' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
      $(((16#${hex:16:1} & 3) | 8)) "${hex:17:3}" "${hex:20:12}")
    echo "s/${ids[$i]}/${new_id[${ids[$i]}]}/g" >> "$script"
  done
  renewed=()
  for id in "${shorts[@]}"; do
    new_id[$id]=$(openssl rand -base64 16 | tr '+/' '-_' | tr -d '=\r\n')
    echo "s/$id/${new_id[$id]}/g" >> "$script"
    renewed+=("  id $id -> ${new_id[$id]}")
  done
  sed -i -f "$script" "$file"
  rm -f "$script"
  echo "$file: $count ids replaced"
  [ ${#renewed[@]} -eq 0 ] || printf '%s\n' "${renewed[@]}"
  while IFS=$'\t' read -r old name; do
    [ -n "$old" ] && echo "  user $name: $old -> ${new_id[$old]}"
  done <<< "$users"
  unset new_id
done
exit "$refused"
