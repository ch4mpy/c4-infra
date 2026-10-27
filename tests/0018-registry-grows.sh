#!/usr/bin/env bash
# 0018: an application added to registry.txt as its header says (the number `bash registry.sh next`
# prints, a valid line) leaves tests/0004-registry.sh green.
#
#   bash tests/0018-registry-grows.sh
#
# Runs the registry part of tests/0004-registry.sh on a scratch copy of the registry with one more
# entry: the part reads registry.txt from the root it runs in, and registry.sh the one next to itself.
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# never verif: tests/0004-registry.sh checks that the real registry lacks it
added() { # <n>
  echo "$1 extra extra - - extra.dev.localhost extra.c4-soft.com"
}

mkdir -p "$work/tests/fixtures"
cp registry.sh registry.txt "$work/"
cp -r tests/lib tests/0004-registry.sh "$work/tests/"
cp -r tests/fixtures/0004 "$work/tests/fixtures/"
added "$(bash "$work/registry.sh" next)" >> "$work/registry.txt"

check "the added entry passes registry.sh check" bash "$work/registry.sh" check
check "tests/0004-registry.sh's registry part passes with one more entry" bash "$work/tests/0004-registry.sh" registry
finish
