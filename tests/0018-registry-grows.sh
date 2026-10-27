#!/usr/bin/env bash
# 0018: an application added to registry.txt as its header says leaves tests/0004-registry.sh green.
#
#   bash tests/0018-registry-grows.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh
unset REGISTRY_FILE

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/tests/fixtures"
cp registry.sh registry.txt "$work/"
cp -r tests/lib tests/0004-registry.sh "$work/tests/"
cp -r tests/fixtures/0004 "$work/tests/fixtures/"
# never verif, which tests/0004-registry.sh checks the real registry lacks; on a line of its own,
# since registry.txt's last line may lack its new line
printf '\n%s extra extra - - extra.dev.localhost extra.c4-soft.com\n' "$(bash "$work/registry.sh" next)" \
  >> "$work/registry.txt"

check "the added entry passes registry.sh check" bash "$work/registry.sh" check
check "tests/0004-registry.sh's registry part passes with one more entry" bash "$work/tests/0004-registry.sh" registry
finish
