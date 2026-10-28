#!/usr/bin/env bash
# 0032: the demo host deploys GitHub projects only (the product owner, 2026-10-28), and its documents
# say so (RQ-06):
#
#   - (a) the first paragraph of README.md's "Demo host" and of docs/migration.md's "On the demo host"
#     holds the statement, whatever its line breaks;
#   - (b) no tracked file outside docs/intent/ names GitLab but in that statement (this file aside).
#
#   bash tests/0032-demo-github-only.sh
#
# covers: README.md CLAUDE.md docs/ demo/ .github/ examples/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

GITHUB_ONLY='The demo host deploys GitHub projects, each from its own GitHub Actions workflow.'
GITLAB_NOT_HERE="A GitLab project (immo) isn't deployed by this stack"

flat() { tr -d '\r' | tr '\n\t' '  ' | tr -s ' '; }
first_paragraph() { # <file> <heading>: the first paragraph after the heading, on one line
  awk -v heading="$2" '$0 == heading { found = 1; next } found && NF { started = 1; print; next } started { exit }' "$1" | flat
}
opens_with_statement() { # <file> <heading>
  local paragraph
  paragraph=$(first_paragraph "$1" "$2")
  grep -qF -- "$GITHUB_ONLY" <<< "$paragraph" && grep -qF -- "$GITLAB_NOT_HERE" <<< "$paragraph" \
    || { echo "first paragraph after '$2':"; printf '%s\n' "${paragraph:0:300}"; return 1; }
}
gitlab_only_in_statement() {
  local file text named=()
  while IFS= read -r file; do
    text=$(flat < "$file")
    text=${text//"$GITLAB_NOT_HERE"/}
    grep -qi gitlab <<< "$text" && named+=("$file")
  done < <(git grep -il gitlab -- . ':!docs/intent/' ':!tests/0032-demo-github-only.sh')
  [ ${#named[@]} -eq 0 ] || { git grep -n -i gitlab -- "${named[@]}" | grep -vF 'A GitLab project (immo)'; return 1; }
}

check "(a) README.md's \"Demo host\" opens with the statement" opens_with_statement README.md '## Demo host'
check "(a) docs/migration.md's \"On the demo host\" opens with it" opens_with_statement docs/migration.md '## On the demo host'
check "(b) no tracked file outside docs/intent/ names GitLab but in the statement" gitlab_only_in_statement
finish
