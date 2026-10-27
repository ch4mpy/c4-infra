#!/usr/bin/env bash
# 0004: the demo deployment sends the registry next to register-app.sh (RQ-06, AC-05). Runs the
# workflow's own upload command (its "Upload the deployment files" step), with a scratch directory
# of an alpine container instead of the demo host, then lists what arrived.
#
#   bash tests/0004-upload.sh
#
# covers: .github/workflows/ demo/deploy-files.txt registry.sh registry.txt register-app.sh
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

WORKFLOW=.github/workflows/deploy-demo.yml
REMOTE='"$VPS:~/c4-infra/"'
DEST=/dest/

# the docker CLI of Windows wants a Windows path for a bind mount
host_path() {
  if command -v cygpath > /dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

line=$(grep -m1 'rsync -az' "$WORKFLOW")
command=${line#*run: }
upload=${command/"$REMOTE"/$DEST}
check "the workflow uploads with rsync -az" test -n "$line"
check "its destination is $REMOTE (replaced by $DEST here)" test "$upload" != "$command"
echo "# $upload"

arrived=$(MSYS_NO_PATHCONV=1 docker run --rm -v "$(host_path "$PWD"):/src:ro" -w /src alpine:3 \
  sh -c "apk add --no-cache rsync > /dev/null && $upload && ls -1 $DEST" 2>&1)
status=$?
check "the upload command runs (exit $status)" test "$status" -eq 0

arrived() { # <file>: in the destination's listing
  grep -qx -- "$1" <<< "$arrived" || { echo "the destination holds:"; printf '%s\n' "$arrived"; return 1; }
}
for file in register-app.sh registry.txt registry.sh compose.yml; do
  check "$file arrives in ~/c4-infra/" arrived "$file"
done
finish
