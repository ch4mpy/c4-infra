#!/usr/bin/env bash
# 0016: the stack holds no URL of Google, Facebook or Apple (AC-08): no tracked file outside
# docs/intent/ (which tells what is simulated) names Google's accounts host, Facebook's .com or
# Apple's appleid host (the pattern below, built from pieces so that this file doesn't name them).
#
#   bash tests/0016-no-real-provider.sh
#
# covers: keycloak/ keycloak-import/ caddy/ examples/ compose.yml compose.dev.yml compose.demo.yml
# covers: README.md CLAUDE.md docs/migration.md
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

dot='\.'
pattern="accounts${dot}google${dot}com|facebook${dot}com|appleid${dot}apple${dot}com"
none() {
  ! git grep -nE "$pattern" -- . ':!docs/intent/'
}
check "AC-08: no tracked file outside docs/intent/ names a real provider's host" none
finish
