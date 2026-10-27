# Intent: The registry test requires exactly four applications, so registering a new one fails the verification

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (delivery of 0013, 2026-10-27)
- Spec needed: no
- Status: accepted
- Opened: 2026-10-27
- Decided: 2026-10-27
- Supersedes: —
- Mode: bootstrap

## Problem

`registry.txt`'s header tells a new application to take the number `bash registry.sh next` prints and to add its line first, in a commit of its own, before anything registers; `create-dev-infra` does so for every project it prepares. `tests/0004-registry.sh` checks the real registry and requires exactly four entries (`entries: four entries`), the four applications of intent 0004. So every application registered as the header says makes the verification fail, though its line is valid.

- Steps: on `main` since `0cf541c` (immo takes block 5, 2026-10-27), `bash registry.sh check`, then `bash tests/0004-registry.sh`.
- Expected: `registry.sh check` exits 0 and the test passes.
- Observed: `registry.sh check` exits 0, the test prints `KO - entries: four entries` and `1 check(s) failed`, so `bash tests/run.sh` fails on `main`.
- Environment: the dev workstation, `main` at `6e03af8`.

Every intent planned after 0013 (0017, 0011, 0015, 0016) runs the full verification on a branch that merges `main`: each would start red.

## Proposed outcome

A valid application line added to `registry.txt` as its header says leaves `bash tests/run.sh` green. The test still checks that the real registry passes `registry.sh check` and still holds the four applications of intent 0004, each with one entry of seven fields; no other check changes.

Success criterion: `bash tests/0004-registry.sh` → `every check passed` on `main` with immo's line, and with one more valid line added.

## Affected users and systems

- Personas: Developer (registers an application, runs the verification); Application (its registry line)
- Modules / systems: registry (`registry.txt`, `registry.sh`) and its test

## Constraints

- Only the check that pins the number of entries is at fault: the test's other checks on the real registry stay as they are (frozen-test rule: the fix does not weaken them).
- Lands before 0017, 0011, 0015 and 0016, whose verifications run on top of `main`.

## Open questions

- None.
