#!/usr/bin/env bash
# 0002: the deployment workflows (AC-5, AC-6).
#
#   AC-6  every action of .github/workflows/*.yml, and of the workflow docs/migration.md describes
#         for the applications, is referenced by a 40-character commit SHA (the tag as a comment);
#   AC-5  the demo deployment pins the host's key before it connects: demo/trust-host-key.sh, run
#         before webfactory/ssh-agent receives the private key and before any ssh or rsync, fails
#         with a workflow error when VPS_KNOWN_HOSTS is empty, and appends it to ~/.ssh/known_hosts
#         otherwise; nothing scans a host key (no ssh-keyscan in .github/ nor demo/);
#   docs  the applications' workflow of docs/migration.md does the same: checkout and ssh-agent
#         pinned by commit, the host-key step (the script's own lines, inline) before the agent and
#         before any ssh or rsync, as <project>@ (its own account).
#
#   bash tests/0002-workflow.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

WORKFLOW=.github/workflows/deploy-demo.yml
# "uses: <action>@<40 hex>", an optional "# <tag>" after it
PINNED='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}([[:space:]]+#.*)?$'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Every "uses:" line of the files given is pinned by commit; prints the others
all_pinned() { # <file>…
  local found content others=()
  while IFS= read -r found; do
    found=${found%$'\r'}
    # "<file>:<line>:<content>"
    content=${found#*:}
    content=${content#*:}
    [[ $content =~ $PINNED ]] || others+=("$found")
  done < <(grep -HnE '^[[:space:]]*(-[[:space:]]+)?uses:' "$@")
  [ ${#others[@]} -eq 0 ] || { echo "not pinned by a 40-character SHA:"; printf '%s\n' "${others[@]}"; return 1; }
}
uses_count() { # <file>…
  grep -chE '^[[:space:]]*(-[[:space:]]+)?uses:' "$@" | awk '{ n += $1 } END { print n + 0 }'
}

# AC-6
check "AC-6: the workflows use actions ($(uses_count .github/workflows/*.yml) uses: lines)" \
  test "$(uses_count .github/workflows/*.yml)" -gt 0
check "AC-6: every uses: of .github/workflows/*.yml is pinned by a 40-character SHA" all_pinned .github/workflows/*.yml
check "AC-6: every uses: of docs/migration.md is pinned by a 40-character SHA" all_pinned docs/migration.md

# AC-5: no trust on first use
no_keyscan() {
  local found
  found=$(grep -rn ssh-keyscan .github demo)
  [ -z "$found" ] || { printf '%s\n' "$found"; return 1; }
}
check "AC-5: nothing in .github/ nor demo/ runs ssh-keyscan" no_keyscan

line_of() { # <extended regex>: the first matching line of the workflow, outside comments
  grep -nE "$1" "$WORKFLOW" | grep -vE '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1
}
trust_line=$(line_of 'run:[[:space:]]+bash demo/trust-host-key\.sh[[:space:]]*$')
agent_line=$(line_of 'uses:[[:space:]]+webfactory/ssh-agent@')
# the first command that connects: ssh, rsync or scp at the start of a run: line or of a script line
connect_line=$(line_of '^[[:space:]]*(run:[[:space:]]*)?(ssh|rsync|scp)[[:space:]]')
check "AC-5: the workflow runs bash demo/trust-host-key.sh (line ${trust_line:-none})" test -n "$trust_line"
check "AC-5: it uses webfactory/ssh-agent (line ${agent_line:-none})" test -n "$agent_line"
check "AC-5: it connects with ssh or rsync (first at line ${connect_line:-none})" test -n "$connect_line"
check "AC-5: the host key is pinned before the agent receives the private key" \
  test "${trust_line:-999999}" -lt "${agent_line:-0}"
check "AC-5: the host key is pinned before the first ssh or rsync" \
  test "${trust_line:-999999}" -lt "${connect_line:-0}"
trust_env() { # the step's env passes the secret VPS_KNOWN_HOSTS
  sed -n "${trust_line},$((trust_line + 3))p" "$WORKFLOW" | grep -qE 'VPS_KNOWN_HOSTS:[[:space:]]+\$\{\{ secrets\.VPS_KNOWN_HOSTS \}\}'
}
check "AC-5: the step reads the secret VPS_KNOWN_HOSTS" trust_env

# AC-5: the script itself
VPS_KNOWN_HOSTS= HOME="$work/empty" bash demo/trust-host-key.sh > "$work/empty.out" 2>&1
status=$?
check "AC-5: without VPS_KNOWN_HOSTS, trust-host-key.sh exits 1 (exit $status)" test "$status" -eq 1
says_error() {
  grep -q '^::error::' "$work/empty.out" || { echo "output:"; cat "$work/empty.out"; return 1; }
}
check "AC-5: with a workflow error (::error::)" says_error
check "AC-5: and writes no known_hosts" test ! -e "$work/empty/.ssh/known_hosts"

LINE='vps.example ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForTheTestOnly0000000000000000000000'
VPS_KNOWN_HOSTS=$LINE HOME="$work/set" bash demo/trust-host-key.sh > "$work/set.out" 2>&1
status=$?
check "AC-5: with VPS_KNOWN_HOSTS, trust-host-key.sh exits 0 (exit $status)" test "$status" -eq 0
check "AC-5: it appends the value to ~/.ssh/known_hosts" grep -qxF -- "$LINE" "$work/set/.ssh/known_hosts"
VPS_KNOWN_HOSTS=$LINE HOME="$work/set" bash demo/trust-host-key.sh > /dev/null 2>&1
check "AC-5: appended, never replaced (a second run adds a line)" test "$(grep -cxF -- "$LINE" "$work/set/.ssh/known_hosts")" -eq 2
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) echo "# ~/.ssh's mode: not checked under Windows (no POSIX modes)" ;;
  *) check "AC-5: ~/.ssh is mode 700" test "$(stat -c %a "$work/set/.ssh")" = 700 ;;
esac

# docs: the applications' workflow (docs/migration.md, "On the demo host")
MIGRATION=docs/migration.md
uses_in_migration() { # <action>: a uses: line of it, pinned
  grep -E "^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]+$1@" "$MIGRATION" | sed 's/\r$//' | grep -qE "$PINNED"
}
check "docs: migration.md's workflow uses actions/checkout, pinned" uses_in_migration actions/checkout
check "docs: and webfactory/ssh-agent, pinned" uses_in_migration webfactory/ssh-agent
# the script's lines from its test of VPS_KNOWN_HOSTS to its printf, without their indentation nor
# the blank lines
host_key_lines() { # <file>
  sed -n '/if \[ -z "\${VPS_KNOWN_HOSTS:-}" \]; then/,/>> "\$HOME\/.ssh\/known_hosts"/p' "$1" | sed 's/\r$//; s/^[[:space:]]*//; /^$/d'
}
host_key_lines demo/trust-host-key.sh > "$work/script.lines"
host_key_lines "$MIGRATION" > "$work/migration.lines"
check "docs: the script's host-key lines are found ($(wc -l < "$work/script.lines") lines)" test "$(wc -l < "$work/script.lines")" -ge 5
same_host_key_lines() { diff "$work/script.lines" "$work/migration.lines"; }
check "docs: migration.md's host-key step is demo/trust-host-key.sh's lines" same_host_key_lines
migration_line() { # <extended regex>: its first line in migration.md
  grep -nE "$1" "$MIGRATION" | head -n 1 | cut -d: -f1
}
doc_trust=$(migration_line 'if \[ -z "\$\{VPS_KNOWN_HOSTS:-\}" \]; then')
doc_agent=$(migration_line 'uses:[[:space:]]+webfactory/ssh-agent@')
doc_connect=$(migration_line '^[[:space:]]*(rsync|ssh|scp)[[:space:]].*\$VPS')
check "docs: the host key is pinned before the agent (lines ${doc_trust:-none}, ${doc_agent:-none})" \
  test "${doc_trust:-999999}" -lt "${doc_agent:-0}"
check "docs: and before the first rsync or ssh (line ${doc_connect:-none})" test "${doc_trust:-999999}" -lt "${doc_connect:-0}"
check "docs: the workflow connects as <project>@, its own account" grep -qF 'VPS: <project>@${{ secrets.VPS_HOST }}' "$MIGRATION"
finish
