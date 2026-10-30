# Intent: tests/0029-description.sh's carriage-return check fails under Git Bash on a description without one

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent during 0036's implementation
- Kind: bug
- Source: conversation (2026-10-29, 0036's step 1: a KO no change of 0036 explains)
- Spec needed: yes
- Status: specified
- Opened: 2026-10-29
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

On the Windows workstation, under Git Bash, `bash tests/0029-description.sh` fails its first check, `(a) the description's lines are comments or KEY=value, no CR`, listing every line of `keycloak-image.properties`, though the file has no carriage return (`git ls-files --eol`: `i/lf w/lf`; `od -c`). `main` at 8f0a090 fails it the same way. So every verification run on that workstation that selects the test (a change of `keycloak/`, `keycloak-image.properties`, `.github/workflows/`, `README.md` or `docs/migration.md`, and every full run) reports a KO that isn't one, and would hide a real one in the same check.

Observed cause (2026-10-29, bash 5.2 of Git for Windows 2.56): `$'\r'` written inside a command substitution loses its carriage return under Git Bash. `form()` runs `grep -n $'\r' "$1"` inside `bad=$(…)` (`tests/0029-description.sh:42`), which becomes `grep -n ''` and lists every line. The same carriage return built outside the substitution (`cr=$'\r'`) and used inside gives no line; Linux's grep gives no line on the same file (`ubuntu:24.04`).

## Proposed outcome

The check refuses a description with a carriage return and accepts one without, under Git Bash as under Linux.

Success criterion: on the Windows workstation, `bash tests/0029-description.sh` passes its check (a) on the repository's description, and still refuses a copy with a carriage return; the same on Linux.

## Affected users and systems

- Developer (the verification on the Windows workstation).
- The test suite (`tests/0029-description.sh`): *not declared in the project context's modules*.

## Constraints

- CLAUDE.md: the scripts run under Git Bash on Windows and bash on Ubuntu.
- The check is fixed, not weakened nor skipped: a description with a carriage return is still refused.

## Open questions

- Whether a check of the whole suite looks for other `$'…'` escapes inside a command substitution (none other found on 2026-10-29: the other `$'\r'` are parameter expansions) — the spec, or the plan if no spec is needed.
