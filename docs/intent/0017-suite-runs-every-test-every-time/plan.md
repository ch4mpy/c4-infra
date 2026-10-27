# Plan: The verification runs every test every time, and says nothing of where its time goes

- Spec: [v1](spec.md)
- Status: approved
- Branch: 0017-suite-runs-every-test-every-time
- Approved: 2026-10-27, Jérôme Wacongne (engineer), in plan mode

## Starting point

- Delivered right after 0013, before 0011, 0015 and 0016 (engineer, 2026-10-27): they then use `--changed` and the lock while they're implemented. Step 0 merges `origin/main` once 0013 is delivered, else 0013's branch. Each later branch adds the `# covers:` lines of its own new tests when it merges `main`: RQ-04 fails its run until it does, which is the reminder.
- `tests/run.sh` (45 lines): `bash -n` of every tracked and untracked `*.sh` (`:23-27`), then the tests in name order, `*.stand-in.sh` with `--all` only (`:29-37`), `FAILED:` or `verification passed`. On 0013's branch: 40 tests, 4 facts tests (`0006-keycloak-facts`, `0009-master-import-facts`, `0012-import-facts`, `0013-keycloak-facts`).
- Tracked scripts outside `tests/` (0013's branch): `certs/{make-certs,self-signed,trust-ca-in-jdk}.sh`, `demo/{backup,deploy,trust-host-key,vps-bootstrap,write-env}.sh`, `demo/c4-app`, `env.sh`, `export-realm.sh`, `networks.sh`, `new-realm-ids.sh`, `register-app.sh`, `registration-account.sh`, `registry.sh`, `routes.sh`, `up.sh`. `git grep`: **no test runs `export-realm.sh` or `new-realm-ids.sh`**, so RQ-04 would fail the suite at delivery.
- `tests/lib/stand-in-host.sh` names its container and volume (`STAND_IN_NAME`, `STAND_IN_VOLUME`): two stand-in runs collide like two dev-stack runs; the lock covers both, since it holds the whole run.

## Engineer's choices

Decided by Jérôme Wacongne (engineer) on 2026-10-27:

- `export-realm.sh` and `new-realm-ids.sh` get tests of their own, so RQ-04 holds as written (A).
- The lock is a Docker container, `c4-infra.suite-lock`, labelled with the run's worktree and start time, fed by a pipe from the run: it ends when the run ends, `kill -9` included; it holds for everything on that Docker, other clones included (A, measured at step 1).
- Delivery order: 0013 → **0017** → 0011 → 0015 → 0016.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/run.sh` | modified: `--changed [<base>]` (default base `origin/main`, else `main`): the changed files are `git diff --name-only <base>...HEAD`, `--cached`, unstaged and `git ls-files --others --exclude-standard`; each test's `# covers:` lines read (paths, a trailing `/` a directory, globs); a test runs when a changed file matches, every test the run would run without the option when a changed file is under `tests/run.sh`/`tests/lib/` or matches no test; others printed `== <test>: skipped (not concerned by the change)`; the facts tests (`*-facts.sh`) out of the plain run, in `--all`, in `--changed` when concerned; the coverage check (every tracked `*.sh` outside `tests/` and `demo/c4-app` matched by a test's covers, else `uncovered: <file>` and exit 1 before any test); the duration after each test and, at the end, the total and the five slowest; the lock taken before the first test (`waiting for the run of <worktree>, started <time>` while another holds it) | RQ-01 to RQ-06 |
| `tests/lib/suite-lock.sh` | new: `suite_lock_take` / its release by the pipe's end; the name from `SUITE_LOCK_NAME` (default `c4-infra.suite-lock`), so the test of the lock never touches a real run's | RQ-06 |
| `tests/[0-9][0-9][0-9][0-9]-*.sh` (every test, 40 with 0013's) | modified: one `# covers:` line under the header comment, from what each test runs (e.g. `tests/0003-routes.sh`: `routes.sh register-app.sh registry.sh examples/routes/ tests/fixtures/0003/`) | RQ-03, RQ-04 |
| `tests/0017-new-realm-ids.sh`, `tests/fixtures/0017/two-users-realm.json` | new, no Docker: every UUID replaced, the same one everywhere in the file, references kept (`containerId`, `parentId`), the users' new ids printed, a file without ids reported | RQ-04 |
| `tests/0017-export-realm.sh` | new (dev stack): a realm registered from a fixture, exported to a temp directory: `<realm>-realm.json` holds its users and no keys; Keycloak keeps running | RQ-04 |
| `tests/0017-run.sh`, `tests/fixtures/0017/suite/` | new: `run.sh` run on a throwaway git repository holding a copy of `tests/run.sh`, `tests/lib/` and fake tests (each sleeps briefly and prints its name), with `SUITE_LOCK_NAME` of its own: durations and slowest; `--changed` for an unstaged, a committed and an untracked change, a `tests/lib/` change and an undeclared file; an uncovered script refused; plain and `--all` sets; two runs at once (the second waits, names the first, starts after); a run killed with `kill -9`, one interrupted, one failed: the next doesn't wait | AC-01 to AC-06 |
| `CLAUDE.md` | modified: "Verification": `--changed`, `--all` stays the proof before review, the `# covers:` line and the coverage check, the lock | RQ-07 |
| `docs/intent/0017-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned; index row (each row's status from its intent's own `intent.md` after `main` is merged) | — |

## Order of work

0. **Setup**: `git merge origin/main` once 0013 is delivered, else `git merge origin/0013-stack-lacks-what-turu-and-hururaa-need`; `bash up.sh`. — skill: none — check: `git status --short` empty, `bash tests/run.sh` → `verification passed`.
1. **Facts**: the lock under Git Bash and on Linux: a `docker run --rm -i --name <lock> … sh -c 'cat >/dev/null'` fed from the run's file descriptor is removed when the run exits, fails, is interrupted and is killed with `kill -9`; a second `docker run --name <lock>` fails while it lives. Measured by hand, written into `tests/0017-run.sh`'s comments. — skill: none — check: the four endings measured; a failure is a deviation before step 3 (fallback: B, a lock in the repository's common git directory, the engineer asked).
2. **The covers lines**: one per test; `tests/0017-new-realm-ids.sh` and `tests/0017-export-realm.sh` with their fixture. — skill: none — check: `bash tests/0017-new-realm-ids.sh && bash tests/0017-export-realm.sh`, then `bash tests/run.sh` (unchanged so far) passes.
3. **`run.sh`**: durations, coverage check, `--changed`, the facts tests' place; `tests/lib/suite-lock.sh` and the lock. — skill: none — check: `bash tests/0017-run.sh`, then `bash tests/run.sh` → `verification passed`, then `bash tests/run.sh --changed` on a one-line change to `routes.sh` runs the 0003 tests that declare it.
4. **Docs**: CLAUDE.md "Verification". — skill: none — check: reread against RQ-07; `grep -n -- '--changed' CLAUDE.md`.
5. **Verification**: `bash tests/run.sh --all` (the set: every test, compared with step 0's); two `bash tests/run.sh --changed` started together in two worktrees (the second waits); mutation checks: `tests/run.sh` from step 0's head → `tests/0017-run.sh` `KO`; one `# covers:` line removed → the run fails, `uncovered:`; then `/sdlc-verify 0017`. — skill: sdlc-verify — check: `verification passed`.

## Risks

- A test's covers line forgets a file it depends on → `--changed` skips it on a change of that file; RQ-03 runs everything for a file no test declares, and `--all` stays the proof before review (RQ-05).
- The lock's container outlives a killed run under Git Bash (the pipe not closed by Windows) → step 1 measures it first; fallback B.
- A run waits forever behind a run that hangs → the waiting message names the holder's worktree and start time; `docker rm -f c4-infra.suite-lock` (in CLAUDE.md) frees it.
- 0011, 0015 and 0016 add tests after 0017 is delivered → RQ-04 fails their runs until their tests carry a covers line; a deviation line in each of their plans when they merge `main`.
- The facts tests leave the plain run → a Keycloak or Caddy version change is caught by `--changed` (their covers name `keycloak/`, `reverse-proxy/`) and by `--all` before review (PA-02).
- A new script outside `tests/` → the coverage check refuses it until a test covers it: wanted.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test | `tests/0017-run.sh`: each fake test's duration line, the total and the slowest in order |
| AC-02 | automated test | `tests/0017-run.sh`: unstaged, committed and untracked changes run exactly the declaring tests in order, the others skipped with the reason; step 3's `routes.sh` check on the real suite |
| AC-03 | automated test | `tests/0017-run.sh`: a `tests/lib/` change and an undeclared file run the plain set |
| AC-04 | automated test + mutation check | `tests/0017-run.sh`: an uncovered script fails before the first test, named; step 5: a covers line removed from the real suite → `uncovered:` |
| AC-05 | automated test + command | `tests/0017-run.sh`: plain and `--all` sets; step 5: `--all` runs every `tests/[0-9][0-9][0-9][0-9]-*.sh`, the plain run step 0's set minus the facts tests |
| AC-06 | automated test + command | `tests/0017-run.sh`: the second run waits, names the first, starts after it; `kill -9`, interrupted and failed runs don't hold the next; step 5: two real runs in two worktrees |
| AC-07 | command + review | `grep -n -- '--changed\|# covers:' CLAUDE.md`; "Verification" reread against RQ-07 |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
