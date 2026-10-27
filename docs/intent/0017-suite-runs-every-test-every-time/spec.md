# Spec: The verification runs every test every time, and says nothing of where its time goes

- Intent: [0017](intent.md)
- Status: draft
- Version: 1
- Risk: standard (no risk rule applies: the change touches the verification only, no authentication, secret, isolation, exposure or personal data)
- Policies applied: none yet; standing constraints: CLAUDE.md "Verification" (`bash tests/run.sh` with the dev stack running; `--all` before a change to the demo host), `sdlc-verify` (the full run is the proof of a change)
- Approved: —

## Summary

`tests/run.sh` prints how long each test took; on request, it runs only the tests the changed files concern, while a plain run and `--all` run the same tests as today; and a run waits, naming it, while another run of the suite uses the same Docker. The facts tests run as PA-02 decides. Test authors say which files each test covers, and the suite refuses a tracked script no test covers, so a selection never silently runs nothing.

## Requirements

- **RQ-01:** Every run prints, after each test, its duration, and at its end the total and the slowest tests, in the order of their durations. (intent: success criterion, "the duration of each test is printed")
- **RQ-02:** A run asked for the changed files (an option) runs the tests those files concern, in the suite's order, and prints each other test as skipped with the reason. The changed files are those of the working tree (committed since the base branch, staged, unstaged and untracked); a run may also be given a base. (intent: outcome, an intermediate check)
- **RQ-03:** A test is concerned by a file it declares it covers (PA-01). A change to the suite's own machinery (`tests/run.sh`, `tests/lib/`) or to a file no test declares runs every test the run would run without the option. (intent: outcome, "never runs fewer tests" for what it can't place)
- **RQ-04:** The suite refuses, before running any test, a tracked script (`*.sh`, `demo/c4-app`) that no test declares it covers, naming it. (intent: outcome, no silent gap)
- **RQ-05:** A plain run runs the tests it runs today, and `--all` every test of `tests/`, the stand-in ones included; the facts tests as PA-02 decides. Neither ever runs fewer tests than today apart from PA-02's facts tests. (intent: constraint, the full run keeps every test; PO, 2026-10-27, the plain run unchanged)
- **RQ-06:** While a run of the suite uses the dev stack, a second run started on the same Docker (another session, another worktree of the repository) prints which run holds it (its worktree and start time), waits for its end, then runs. A run that ends in any way (passed, failed, interrupted, killed) releases the stack; a hold whose run no longer exists doesn't block the next one. (intent: success criterion; PO, 2026-10-27: it waits)
- **RQ-07:** CLAUDE.md "Verification" says how to run the tests a change concerns, that `--all` stays the proof of a change before review, and how a test declares what it covers. (intent: affected systems)

## Out of scope

- Running tests in parallel.
- Making any test faster by changing what it checks; a test's content changes only to declare what it covers.
- A numeric target for the durations (PA-03).
- Other projects' use of the same Docker: only runs of this suite wait for each other.

## Design

### Current behaviour

- `tests/run.sh:23-27` runs `bash -n` on every tracked or untracked `*.sh`; `:29-37` runs `tests/[0-9][0-9][0-9][0-9]-*.sh` in name order, skips `*.stand-in.sh` without `--all` (`== <test>: skipped (--all runs it)`), and ends with `FAILED:` and the list, or `verification passed` (`:39-44`). No duration, no selection, no lock.
- 33 tests on `main` (40 with 0013's): 7 `*.stand-in.sh`; 3 facts tests on `main` (`0006-keycloak-facts`, `0009-master-import-facts`, `0012-import-facts`), a 4th with 0013 (`0013-keycloak-facts`), 0015 and 0016 each planning one. On 2026-10-27, `--all` took 32 minutes for its first 28 tests.
- Every test sources `tests/lib/assert.sh`; the stand-in tests also `tests/lib/stand-in-host.sh`, whose container and volume are named, so two stand-in runs collide as two dev-stack runs do.
- 0013's step 8 (2026-10-24, *Deviations*): another session rebuilt and pruned an image under the running proxy; the run was done again.

### Behaviour per persona

- Developer: runs `bash tests/run.sh --changed` after a step of a plan, sees the tests it ran, those it skipped and why, and each duration; runs `bash tests/run.sh --all` before review, unchanged. When another session's run holds the stack, sees `waiting for the run of <worktree>, started <time>` and gets its own run once that one ends.

### API and contracts

- `bash tests/run.sh [--all] [--changed [<base>]]`: `--changed` selects (RQ-02), its base defaulting to the project's base branch; combined with `--all`, the stand-in tests are selectable too. Exit status as today: `0` and `verification passed`, `1` and `FAILED:`.
- A test's declaration of what it covers: a comment line of the test (PA-01), paths or globs relative to the repository, e.g. `# covers: routes.sh caddy/ examples/routes/`.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| CLAUDE.md "Verification" | RQ-05: the plain run and `--all` unchanged; RQ-07 documents the option |
| `sdlc-verify`: the full run is the proof | RQ-05, RQ-07: `--changed` is for intermediate checks only |

## Points of attention

### PA-01: How a test says what it covers

- Issue: the selection is only as good as the mapping from files to tests.
- Options: A) each test declares the paths it covers in a comment line, RQ-04 refusing a script no test covers / B) derived from what each test sources and runs (grep of script names): no declaration, but a test that runs a script through another (`up.sh` calling `registry.sh`) is missed / C) by the intent number in the file's history: a file changed by several intents runs their tests, a new file runs none.
- Recommendation: A: explicit, reviewed with the test, and RQ-03 and RQ-04 bound its errors (an undeclared file runs everything, an uncovered script fails the run).
- Decides: tech lead
- Decision: to decide

### PA-02: When the facts tests run

- Issue: they measure Keycloak's and Caddy's behaviour on throwaway containers, which only changes with their versions; today every plain run pays for them.
- Options: A) with `--all` only, and with `--changed` when a file they cover changes (the Keycloak or proxy image's version among them) / B) as today, every plain run / C) only when a version changes.
- Recommendation: A: the proof before review still measures them; an intermediate check measures them when what they guard changes. C would leave a facts test unrun when its own code changes.
- Decides: tech lead
- Decision: to decide

### PA-03: A target duration

- Issue: the intent's open question asks for targets, which only measured durations can set.
- Options: A) no target in this spec; the durations RQ-01 prints after delivery feed a later intent if one is needed / B) a target now (e.g. an intermediate check of a one-script change under 5 minutes), measured at delivery.
- Recommendation: A: a target set before any measurement is a guess.
- Decides: PO
- Decision: to decide

## Acceptance criteria

- **AC-01:** Given any run, then each test's line is followed by its duration, and the run ends with the total and the slowest tests by duration. (RQ-01)
- **AC-02:** Given a working tree whose only change is to `routes.sh` (unstaged), when `bash tests/run.sh --changed` runs, then it runs exactly the tests declaring `routes.sh`, in the suite's order, and prints every other test as skipped, "not concerned by the change". Likewise for a committed change since the base, and for a new untracked file. (RQ-02, RQ-03)
- **AC-03:** Given a change to `tests/lib/assert.sh`, or to a file no test declares, when `--changed` runs, then it runs every test the run without `--changed` runs. (RQ-03)
- **AC-04:** Given a tracked script no test declares, when any run starts, then it fails before the first test, naming the script. (RQ-04)
- **AC-05:** Given the repository, then a plain run runs the same tests as before this change (PA-02's facts tests aside), and `--all` runs every `tests/[0-9][0-9][0-9][0-9]-*.sh`. (RQ-05)
- **AC-06:** Given a run in progress in one worktree, when a run starts in another worktree on the same Docker, then the second prints the first's worktree and start time, starts no test until the first ends, then runs. Given a run killed (`kill -9`), the next run doesn't wait for it. Given a run interrupted (Ctrl-C) or failed, the next one doesn't wait either. (RQ-06)
- **AC-07:** Given CLAUDE.md, then "Verification" names `--changed`, says `--all` stays the proof before review, and shows a test's covers line. (RQ-07)

## Intent questions

- The target durations → PA-03.
- When the facts tests run → PA-02.
- How a changed file maps to its tests → PA-01.
- The suggested solution: a duration per test → RQ-01; `--changed` → RQ-02, its contract; a lock on the dev stack → RQ-06 (it waits, PO); facts tests on `--all` or a version change → PA-02.

## Change log

- v1 — 2026-10-27 — first version; the PO decided at draft that a second run waits and that a plain run stays unchanged
