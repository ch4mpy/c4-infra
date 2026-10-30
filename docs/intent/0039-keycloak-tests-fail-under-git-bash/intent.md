# Intent: Four Keycloak tests fail under Git Bash on the Windows workstation: the native jq and curl can't reach their files

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the pre-existing KOs of 0035's and 0037's full runs
- Kind: bug
- Source: conversation (2026-10-30: the five failures `origin/main` has too, 0037's plan, Deviations)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

On the Windows workstation, under Git Bash, `tests/0016-keycloak-facts.sh`, `tests/0017-export-realm.sh`, `tests/0029-image-facts.sh` and `tests/0030-federation-ids.sh` fail in every run observed on 2026-10-30: the full runs of 0037 and 0035, and `main` at 8f0a090 run alone. With 0038's KO, no full run on that workstation ends `verification passed`, so each verification lists five failures to set aside by hand, and a real failure of these tests, which cover `keycloak/`, would hide among them.

Observed (2026-10-30):

- Each KO names a file of the test's `mktemp` directory: `jq: error: Could not open file /c/Users/ch4mpy/.cache/c4-infra-tests/tmp.…/<file>.json: No such file or directory` (`token.json`, `serverinfo.json`, `a.json`, `b.json`, `export/verif-lockout-realm.json`). In 0017-export-realm, the file is there (`ok - it writes verif-lockout-realm.json`), and jq alone can't open it; `export-realm.sh` itself exits 0.
- The four tests `export MSYS_NO_PATHCONV=1` for the whole script (`:38`, `:19`, `:31`, `:33`), so the programs they call get the `/c/…` form of a path, unconverted. `jq` is jqlang's `jq.exe` from WinGet (1.8.2, installed 2026-10-09), `curl` is Git for Windows' `/ucrt64/bin/curl` (8.23.0, `x86_64-w64-mingw32`): two native Windows programs, which don't read that form.
- The four tests are unchanged since 2026-10-28 09:26 (`git log`), and passed in that day's `--all` at 205b8eb (`verification passed`, 72 tests). Git for Windows was installed again on 2026-10-29 at 18:16 (its `ucrt64/` directory created then, no `mingw64/` since). Why the tests passed before is not established: the reinstall is a lead, not a proven cause.

## Proposed outcome

The four tests pass on the Windows workstation under Git Bash as on Linux, and still fail when what they check is wrong.

Success criterion: on the Windows workstation, `bash tests/run.sh --all` reports none of these four tests as failed, while the Keycloak they check behaves as they expect; the same tests pass under bash on Ubuntu.

## Affected users and systems

- Developer (the verification on the Windows workstation).
- The test suite (`tests/0016-keycloak-facts.sh`, `tests/0017-export-realm.sh`, `tests/0029-image-facts.sh`, `tests/0030-federation-ids.sh`, perhaps `tests/lib/`): *not declared in the project context's modules*.

## Constraints

- CLAUDE.md: the scripts run under Git Bash on Windows and bash on Ubuntu; container paths need `MSYS_NO_PATHCONV=1`, host paths given to the docker CLI need `cygpath -w` under Git Bash.
- The tests are fixed, not weakened nor skipped: each check keeps asserting what it asserts today.
- CLAUDE.md lists `jq` among a run's prerequisites without saying which build: whatever the fix, a workstation with a native `jq` must keep working, or the prerequisite must say what it needs.

## Open questions

- Why these tests passed on 2026-10-28, and whether Git for Windows' reinstall changed which `curl` runs, or how `MSYS_NO_PATHCONV` behaves: the spec (a read-only measurement).
- Whether other tests or scripts give a native program a host path under `MSYS_NO_PATHCONV=1`, and fail the same way only when they run (e.g. a `--changed` selection that never picked them): the spec.
- Whether 0038's carriage return, observed on 2026-10-29 with the same bash, comes from the same reinstall: the spec of 0038.
