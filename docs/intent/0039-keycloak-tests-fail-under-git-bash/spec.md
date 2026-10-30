# Spec: Four Keycloak tests fail under Git Bash on the Windows workstation: the native jq and curl can't reach their files

- Intent: [0039](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the test suite's own files on the workstation; no authentication, secret, isolation between applications, network exposure or personal data is changed)
- Policies applied: none yet; standing constraints: CLAUDE.md (the scripts run under Git Bash on Windows and bash on Ubuntu; container paths need `MSYS_NO_PATHCONV=1`, host paths given to the docker CLI `cygpath -w`; `jq` among a run's prerequisites), the four tests' own requirements (0016, 0017, 0029, 0030)
- Approved: 2026-10-30, Jérôme Wacongne (PO, also tech lead; in the drafting session, every point of attention decided)

## Summary

`tests/0016-keycloak-facts.sh`, `tests/0017-export-realm.sh`, `tests/0029-image-facts.sh` and `tests/0030-federation-ids.sh` turn path conversion off for their whole length, then hand host paths in Git Bash's form to `jq` and `curl`, which on this workstation are native Windows programs and can't use them. They must pass under Git Bash, with native `jq` and `curl`, as under Linux, each check asserting what it asserts today; the other scripts that turn conversion off the same way are checked for the same flaw. For the Developer: a full run on the Windows workstation without these four KOs, and a real failure of them seen again.

## Requirements

- **RQ-01:** Under Git Bash on the Windows workstation, with a native `jq` and `curl` (WinGet's `jq.exe`, Git for Windows' `/ucrt64/bin/curl`), each of the four tests ends `every check passed` when the Keycloak it checks behaves as it expects. (intent: proposed outcome, success criterion)
- **RQ-02:** They pass under bash on Ubuntu as well. (intent: success criterion; constraint, CLAUDE.md)
- **RQ-03:** Each check asserts what it asserts today: none removed, skipped or loosened, and each still fails when what it checks is wrong. (intent: constraint, "fixed, not weakened nor skipped")
- **RQ-04:** No other tracked script that turns path conversion off for its whole length hands a native program a host path in Git Bash's form; one that does is fixed by this change. (intent: open question, other tests or scripts)
- **RQ-05:** A workstation whose `jq` is a native build keeps working: CLAUDE.md's prerequisite (`jq` installed) stays true as written, or says what it needs. (intent: constraint)

## Out of scope

- 0038's carriage return in `tests/0029-description.sh`.
- Pinning a version of Git for Windows, `jq` or `curl`.
- What the four tests check: their Keycloak facts are unchanged.

## Design

### Current behaviour

Measured on 2026-10-30 on the Windows workstation (Git for Windows 2.56.0(4), installed again on 2026-10-29 at 18:16; `jq` 1.8.2 from WinGet, installed 2026-10-09, the only `jq` on `PATH`; `curl` 8.23.0 `x86_64-w64-mingw32`, the only `curl`):

- The four tests `export MSYS_NO_PATHCONV=1` for the whole script (`tests/0016-keycloak-facts.sh:38`, `tests/0017-export-realm.sh:19`, `tests/0029-image-facts.sh:31`, `tests/0030-federation-ids.sh:33`), and write their files under `mktemp -d`, a path like `/c/Users/<user>/.cache/c4-infra-tests/tmp.…`.
- With conversion off, a native program gets that path as written: `jq -e .a "$d/x.json"` exits 2 (`Could not open file /c/Users/…/x.json: No such file or directory`), `curl -s -o "$d/c2.out" …` exits 23 and writes nothing. With conversion on, or through a redirection (`jq … < "$d/x.json"`, `curl … > "$d/c3.out"`), or with the path from `cygpath -w`, both succeed. Git Bash's own programs (`grep`, `cat`) read the path either way.
- The KOs follow: 0016's `curl -o "$work/token.json"` (`:135`) writes no file, so `grep`, `cat` and `jq` then find none; in 0017, `export-realm.sh` writes the export (`ok - it writes verif-lockout-realm.json`) and `jq` alone can't open it; 0029-image-facts' `serverinfo.json` and 0030's `a.json`, `b.json` the same. A first count (`grep`, 2026-10-30): 0016, 5 `jq` and 2 `curl` with such a path; 0017, 3 `jq`; 0029-image-facts, 2; 0030, 3.
- `register-app.sh` already avoids it: `cimd_problems` gives `jq` its file on stdin, "jq may be a Windows program, which MSYS_NO_PATHCONV leaves with a path of Git Bash" (`register-app.sh:267-268`, `:294`).
- Fifteen tracked scripts turn conversion off for their whole length: the four tests, `export-realm.sh`, `networks.sh`, `register-app.sh`, `registration-account.sh`, and `tests/0006-keycloak-facts.sh`, `0009-master-import-facts.sh`, `0009-master-realm.sh`, `0010-brute-force.sh`, `0011-facts.sh`, `0012-import-facts.sh`, `0013-keycloak-facts.sh`. In the full runs of 2026-10-30 only the four failed; whether the others never hand such a path, or only on a branch the runs don't take, is RQ-04's inventory.
- The four tests passed in the `--all` of 2026-10-28 (HANDOVER.md, 205b8eb) and are unchanged since 2026-10-28 09:26. Why they passed then is not established: the `jq` was already there, and which `jq` and `curl` came first on `PATH` before the reinstall is not known here. The requirements don't depend on it: RQ-01 holds with native programs, whatever came before.

### Behaviour per persona

- **Developer**: on the Windows workstation, a run that selects these tests reports them as on Linux; a full run's failures are this run's. Nothing changes in the scripts a Developer runs, unless RQ-04's inventory finds one with the flaw.

### API and contracts, User interface, Data

None: the tests' checks and messages keep their names.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | No policy yet. Standing constraints: Git Bash and bash on Ubuntu → RQ-01, RQ-02, AC-01, AC-02, PA-02; container paths with `MSYS_NO_PATHCONV=1` → kept for the docker calls that need it; a test not weakened → RQ-03, AC-03 |

## Points of attention

### PA-01: Whether CLAUDE.md names the trap

- Issue: CLAUDE.md says container paths need `MSYS_NO_PATHCONV=1` and host paths for the docker CLI `cygpath -w`; it doesn't say that a native program (`jq`, `curl`) can't read a host path in Git Bash's form while conversion is off. `register-app.sh` knows it, the four tests didn't.
- Options:
  - A: CLAUDE.md's Git Bash line adds it (a native program gets a host path through a redirection or `cygpath -w` while conversion is off), in this change.
  - B: nothing beyond the fix.
- Recommendation: A. It is the line read before a script is written, beside the two rules it completes. It touches CLAUDE.md, the agent's configuration: the project has no evals, so no eval report. If 0038's PA-01 is decided A as well, both traps go in the same line.
- Decides: PO
- Decision: A (2026-10-30, Jérôme Wacongne); 0038's PA-01 was decided A too: whichever change comes second adds its trap to the line the first one wrote.

### PA-02: How the four tests are proven on Ubuntu (RQ-02)

- Issue: there is no Ubuntu workstation; `tests/0017-export-realm.sh` needs the dev stack, the three others throwaway Keycloak containers.
- Options:
  - A: not verifiable here, listed for the human reviewer, as 0035's AC-07; the fix uses only what bash and Linux read alike (redirections, conversion left on where no container path is given).
  - B: the three facts tests (0016, 0029-image-facts, 0030) run once on the stand-in host (Ubuntu, its own Docker, the stack's Keycloak image loaded into it), as a command proof; 0017-export-realm as A.
  - C: B, as a permanent stand-in test in every `--all`.
- Recommendation: A. A Keycloak image loaded into the stand-in and three facts tests run there cost far more than the risk they cover: a redirection reads the same in both shells, and the tests ran on Linux before (their 0016, 0029, 0030 facts were measured there).
- Decides: PO
- Decision: A (2026-10-30, Jérôme Wacongne)

## Acceptance criteria

- **AC-01:** Given the Windows workstation under Git Bash, `jq` the WinGet build and `curl` Git for Windows', and the dev stack up, when each of the four tests runs, then it ends `every check passed`. (RQ-01)
- **AC-02:** Given bash on Ubuntu, when the same tests run, then they end `every check passed`. (RQ-02; how: PA-02)
- **AC-03:** Given the change, when the four tests' checks are compared before and after, then each keeps its name and its assertion; and a check made to expect something false still fails under Git Bash. (RQ-03)
- **AC-04:** Given the fifteen scripts that turn conversion off for their whole length, when each hand-off of a host path to a native program is listed, then none is in Git Bash's form, or the change fixes it; and `bash tests/run.sh --all` on the workstation reports none of the four tests as failed. (RQ-04, intent's success criterion)
- **AC-05:** Given CLAUDE.md, the prerequisite `jq` stays as written (a native build works), and the trap is written down as PA-01 decides. (RQ-05)

## Intent questions

- Why these tests passed on 2026-10-28, and whether the reinstall changed which `curl` runs or how `MSYS_NO_PATHCONV` behaves → not established: the `jq` predates the run; the `curl` and `jq` that came first on `PATH` before the reinstall are not known here; native programs fail as measured, and RQ-01 holds whatever came before.
- Whether other tests or scripts hand a native program a host path under `MSYS_NO_PATHCONV=1` → fifteen scripts turn it off for their whole length; only the four fail in the full runs; `register-app.sh` already avoids it → RQ-04, AC-04.
- Whether 0038's carriage return comes from the same reinstall → 0038's spec: a lead, not proven (Git for Windows ships Bash 5.3.15 since 2.55.0, by its release notes; the version installed before is not known).

## Change log

- v1 — 2026-10-30 — first version; approved by the PO in the drafting session (PA-01 A, PA-02 A)
