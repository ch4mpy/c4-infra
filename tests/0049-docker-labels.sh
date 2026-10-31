#!/usr/bin/env bash
# 0049: what c4-infra's tests create on the host's Docker carries the labels of
# tests/lib/docker-preflight.sh and goes with its volumes; read, nothing run:
#
#   - AC-02: every `docker run`, `create`, `build`, `network create`, `volume create` and `compose … up`
#     of tests/*.sh and tests/lib/*.sh that runs on the host's Docker passes the labels (C4_LABELS,
#     C4_KEEP_LABELS, docker_labels or docker_keep_labels on its command; for compose, the file names
#     C4_INFRA_RUN in its labels), and every `docker rm` there has -v. Not read: comments, text in
#     double quotes or after a ^ (messages, patterns), what runs in a stand-in (a line calling
#     stand_in_exec, stand_in_ssh, on_host or in_stack, and the single-quoted script it opens), the 0049
#     tests, and the suite's lock, which carries no run label (IV-01);
#   - AC-08: the library sources nothing, calls no jq, and no line of it stops, restarts or resets
#     Docker or compacts its disk image; the skills' contract: docker_labels(), docker_reap() and
#     docker_preflight() defined at column 0, the three lines `^docker_(labels|reap|preflight)\(\)`
#     matches, and docker_keep_labels();
#   - IV-01: tests/lib/suite-lock.sh passes no run label;
#   - IV-02: the demo host never gets the library: demo/deploy-files.txt names nothing under tests/, and
#     nothing under demo/ names tests/lib.
#
#   bash tests/0049-docker-labels.sh
#
# covers: tests/ demo/
set -uo pipefail
cd "$(dirname "$0")/.."
source tests/lib/assert.sh

LIB=tests/lib/docker-preflight.sh

read -r -d '' PROGRAM << 'AWK'
# The shell's quoting, roughly: the quote state at the end of <s> from <state> (0 none, 1 single, 2
# double; "$( opens a command), `cut` set where a comment starts (0: none)
function scan(s, state,    i, c, n) {
  cut = 0
  n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (state == 1) { if (c == "'") state = 0; continue }
    if (c == "\\") { i++; continue }
    if (state == 2) {
      if (c == "\"") state = 0
      else if (c == "$" && substr(s, i + 1, 1) == "(") state = 0
      continue
    }
    if (c == "'") state = 1
    else if (c == "\"") state = 2
    else if (c == "#" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) { cut = i; return state }
  }
  return state
}
function report(kind) { printf "%s:%d: %s: %s\n", FILENAME, start, kind, cmd }
function check(s,    off, i, c, tail) {
  off = 0
  while ((i = index(substr(s, off + 1), "docker ")) > 0) {
    off += i
    c = off > 1 ? substr(s, off - 1, 1) : ""
    # the end of a word, a pattern (^), a path, a message, or a string assigned to be run elsewhere
    if (c ~ /[A-Za-z0-9_^\/.=-]/) continue
    if (off > 1 && scan(substr(s, 1, off - 1), 0) == 2) continue
    if (c == "'" && substr(s, off - 2, 1) == "=") continue
    tail = substr(s, off)
    if (tail ~ /^docker compose .*[ \t](up|run)([ \t]|$)/) {
      if (!index(has_run, " " FILENAME " ")) report("unlabelled")
    } else if (tail ~ /^docker (run|create|build|network create|volume create)([ \t]|$)/) {
      if (tail !~ /C4_LABELS|C4_KEEP_LABELS|docker_labels|docker_keep_labels/) report("unlabelled")
    }
    if (tail ~ /^docker (container )?rm([ \t]|$)/ && tail !~ /^docker (container )?rm[ \t]+(-[A-Za-z]+[ \t]+)*-[A-Za-z]*v/) report("rm without -v")
  }
}
FNR == 1 { inside = 0; pending = "" }
{
  line = $0
  if (inside) { if (scan(line, 1) != 1) inside = 0; next }
  if (pending == "") { cmd = line; start = FNR } else cmd = pending " " line
  if (line ~ /\\$/) { pending = cmd; next }
  pending = ""
  state = scan(cmd, 0)
  if (cut) cmd = substr(cmd, 1, cut - 1)
  if (cmd ~ /stand_in_exec|stand_in_ssh|on_host|in_stack/) { if (state == 1) inside = 1; next }
  check(cmd)
}
AWK

scanned() {
  local file
  for file in tests/*.sh tests/lib/*.sh; do
    case $file in
      tests/0049-*.sh | tests/lib/suite-lock.sh) ;;
      *) echo "$file" ;;
    esac
  done
}

found=$(mapfile -t files < <(scanned)
  awk -v has_run=" $(grep -l C4_INFRA_RUN "${files[@]}" | tr '\n' ' ') " "$PROGRAM" "${files[@]}")

check "AC-02: every creator on the host's Docker passes the labels" \
  eval '! grep ": unlabelled: " <<< "$found"'
check "AC-02: every docker rm on the host's Docker has -v" \
  eval '! grep ": rm without -v: " <<< "$found"'

check "AC-08: the library is there" test -f "$LIB"
check "AC-08: it sources nothing" eval '! grep -nE "^[[:space:]]*(source|\.)[[:space:]]" "$LIB"'
check "AC-08: it calls no jq" eval '! grep -nw jq "$LIB"'
check "AC-08: nothing of it stops, restarts or resets Docker, nor compacts its disk" \
  eval '! grep -niE "docker desktop (restart|stop|reset)|wsl(\.exe)? .*--shutdown|systemctl|Optimize-VHD|diskpart|compact vdisk|fstrim|qemu-img" "$LIB"'
check "AC-08: the skills' check finds docker_labels(), docker_reap() and docker_preflight(), once each" \
  test "$(grep -cE '^docker_(labels|reap|preflight)\(\)' "$LIB" 2> /dev/null)" = 3
check "AC-08: docker_keep_labels() is defined" grep -q '^docker_keep_labels()' "$LIB"

check "IV-01: the suite's lock passes no run label" \
  eval '! grep -nE "docker_labels|docker_keep_labels|C4_LABELS" tests/lib/suite-lock.sh'
check "IV-02: demo/deploy-files.txt names nothing under tests/" eval '! grep -n "^tests/" demo/deploy-files.txt'
check "IV-02: nothing under demo/ names tests/lib" eval '! grep -rn "tests/lib" demo/'
finish
