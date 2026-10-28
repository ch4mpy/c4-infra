# Plan: The verification runs every test every time, and says nothing of where its time goes

- Spec: [v2](spec.md)
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
| AC-08 | automated test | `tests/0017-run.sh`: changes under `docs/intent/` only run no test, each skipped with the reason; with a `routes.sh` change too, the declaring tests only (spec v2) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-27 — step 0, on another workstation (bootstrap mode since 2026-10-27): `origin/main` merged (0013 and 0018 delivered; the index's conflict resolved by keeping every row). Its baseline is not rerun: the merged tree's code is the same as 0018's verified head (`git diff --stat e49e53c HEAD -- . ':!docs' ':!CLAUDE.md'` empty), whose `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh` → `verification passed` (2026-10-27, 20:06–20:28 UTC). Step 0's set, for AC-05: that run's 32 tests, the 9 stand-in tests skipped. On this workstation every run needs `TMPDIR` (Docker Desktop, CLAUDE.md). Impact: none on files; the new tests of 0018 (`tests/0018-registry-grows.sh`) get a covers line at step 2.
- 2026-10-27 — step 1, measured on Linux (Docker Desktop) only: `docker run --rm -i --name <lock> --label … alpine:3 sh -c 'echo held; exec cat >/dev/null'` as a bash coprocess, the holder reading `held`: the container is removed within a second when the holder exits 0, exits 1, gets SIGINT (its process group), is killed with `kill -9` with its child, and killed alone while its child lives on (the coprocess's pipe isn't inherited by the child); a second `docker run --name <lock>` while it lives exits 125, `Conflict. The container name … is already in use`; its labels are read back. A holder started with `&` from a non-interactive shell ignores SIGINT (no job control), so the measure starts it with SIGINT at its default, as a terminal does. Git Bash can't be measured on this workstation: kept as not verifiable here, with the product owner's go (2026-10-27); CLAUDE.md says how to free a stuck lock. Impact: AC-06's Windows half not verifiable here.
- 2026-10-27 — step 2: 41 tests given their covers lines (`0013`'s and `0018`'s included), every tracked script covered (checked with the matching `run.sh` uses: a trailing `/` a directory, else a glob or the exact path). `tests/0017-export-realm.sh` registers 0010's fixture realm (`verif-lockout`, one user) rather than a fixture of its own. Its check's full `bash tests/run.sh` is folded into step 3's: step 2 changes comments only, besides the two new tests, run here (`every check passed` each), and `bash -n` of every test passes. Impact: none on proof (step 3 and step 5 run the full suite).
- 2026-10-27 — step 3, spec v2 (product owner, in this session): RQ-03 as written made `--changed` run every test on any intent's branch, whose `plan.md`, `intent.md` and index row differ from the base; the intent home's files (`docs/intent/`) now concern no test, AC-08 proves it (Proof). Impact: `tests/run.sh` and `tests/0017-run.sh` as in *Files*, one more criterion.
- 2026-10-28 — `tests/fixtures/0017/suite/` (*Files*) isn't created: `tests/0017-run.sh` writes its fake tests itself (`fake_test`), each one's covers and sleep in its arguments. No impact on proof.

## Verification

### Verification — 1502732

- **KO, pre-existing, not fixed:** `tests/0007-dev.sh`, `KO - control: from c4-infra.tickee, tickee.ldap-standin:389 answers` in the proof run below; run alone twice on 1502732: `every check passed`, then `1 check(s) failed` on the same control. 0017 only adds its covers line; Keycloak's `testLDAPConnection` passes just before it, so most likely `osixia/openldap` restarting `slapd` after its first configuration (from 20 fresh containers, a running service's name and port answered 20 times). Delivered with this KO by the product owner's decision (2026-10-28) → bug intent suggested.
- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` → `FAILED:` / `tests/0007-dev.sh` (the KO above alone; 2026-10-27/28, `total: 3271.7 s for 44 test(s)`). `LC_ALL=C` because `tests/0003-demo-deploy.stand-in.sh` compares a list sorted on the host with one sorted in the stand-in (C): under fr_FR it fails on the same files (`--all` on 24b1a60: `KO - /root/c4-infra holds only what the deployment sends`) → bug intent suggested. That `--all` on 24b1a60 (44 tests, 3562 s) failed on it and on `tests/0007-isolation.stand-in.sh`, whose probe build hit `DNS: transient error` in the stand-in (again when run alone, passed in the proof run) → bug intent suggested. Step 3: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh` → `verification passed` (31 tests, 822 s, before b6f13ee).
- Risk tier: standard (spec)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high): 10 findings, 7 fixed in 1502732, 3 answered; no security pass (standard risk), no quality pass (bootstrap mode)
  - fixed: the facts tests a change concerns were skipped when every test runs (PA-02; tests/run.sh); covers globs expanded against the working tree (tests/run.sh); the registration's files missing from `0017-export-realm.sh`'s covers, and from every test declaring `register-app.sh`; the stand-in tests not declaring `tests/stand-in-host/`; `0017-run.sh`'s slowest order only 0.1 s apart; no `nullglob`; `pkill`, absent from Git Bash, in `0017-run.sh`'s cleanup; `suite-lock.sh`'s long header
  - the two run.sh fixes proven both ways: `0017-run.sh`'s new checks (PA-02 with every test running; `glob/*.conf` matching `glob/sub/new.conf`) are `KO` with 24b1a60's run.sh, `ok` with 1502732's
  - answered, the spec: `CLAUDE.md`, `.gitignore` and the other files no test declares run every test (RQ-03, spec v2 excepting `docs/intent/` only; tests/run.sh); the coverage check reads tracked scripts only (RQ-04)
  - answered, minor: Ctrl-C while waiting leaves two small files in `TMPDIR` (tests/lib/suite-lock.sh)
- Mutation checks: 2e1c2f2's `tests/run.sh` (before 0017) → `tests/0017-run.sh` → `25 check(s) failed` (at 24b1a60), `27 check(s) failed` (verifier, at 1502732); `0017-new-realm-ids.sh`'s covers line removed → `uncovered: new-realm-ids.sh (no test declares it in a "# covers:" line)`, exit 1, no test run; `{SUITE_LOCK_FD}>&-` removed (verifier) → `KO - AC-06, kill-9: the next run doesn't wait for it` (`took 34 s`), the interrupted one too
- On the real suite: `--changed HEAD` on a one-line `routes.sh` change (24b1a60) → exactly the 16 tests declaring it, in the suite's order, `verification passed (--changed: 16 of 44 tests)` (18 at 1502732, the review's covers lines, verifier on stubs); two runs from two worktrees → the second: `waiting for the run of /home/jerome/workspaces/c4-infra, started 2026-10-27 13:10:28`, its test after the first one's end
- Verifier: 8/8 criteria OK, 0 KO
  - details it raised, not fixed (one fix round): run.sh reads `# covers:` lines anywhere in a test, so `0017-run.sh`'s heredoc line `# covers: $*` is a stray pattern (harmless today); `docs/intent/` is kept out of the every-test fallback, not out of matching; an uncovered script exits 1 without a `FAILED:` line; no `total:` when no test runs; no check of a change to `tests/run.sh` itself; under `--changed` without `--all`, a stand-in test is skipped "--all runs it" rather than "not concerned"
- Not verifiable here: AC-06 under Git Bash (this workstation is Linux; *Deviations*, the product owner's go)
- Files outside the plan: none (`tests/fixtures/0017/suite/` planned, not created: *Deviations*)
- Pre-existing findings (not fixed, out of scope): the three above (0007-dev's LDAP control, 0003-demo-deploy's locale, the stand-in's DNS) → bug intents suggested; Docker Desktop stopped starting any container once (2026-10-27 21:06 UTC, restarted, cause unknown)

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `tests/0017-run.sh` → `ok - AC-01: each test's duration, then the total`, `ok - AC-01: the slowest first`, `ok - AC-01: --all, the slowest first`; the proof run: `total: 3271.7 s for 44 test(s); the slowest:` then `409.5 s  tests/0009-master-realm.stand-in.sh` |
| AC-02 | OK | `tests/0017-run.sh`: unstaged, committed and untracked changes; the real `routes.sh` change above |
| AC-03 | OK | `tests/0017-run.sh`: `tests/lib/` and `notes.txt` run the plain set, saying why |
| AC-04 | OK | `tests/0017-run.sh` → `ok - AC-04: an uncovered script: exit 1`, `named`, `before any test`; the covers-line mutation above |
| AC-05 | OK | the plain run: 31 tests (step 0's 32, the four facts tests out, 0017's three new tests in); `--all`: 44, every `tests/[0-9][0-9][0-9][0-9]-*.sh` |
| AC-06 | OK (Linux); Git Bash not verifiable here | `tests/0017-run.sh` (the second run waits, names the first, starts after it; kill -9, Ctrl-C and failed runs don't hold the next); the two worktrees above |
| AC-07 | OK | `CLAUDE.md`:15 (`--all` the proof, `--changed [<base>]`, never a proof), :17 (a covers line, `docs/intent/`), :19 (the lock, `docker rm -f c4-infra.suite-lock`) |
| AC-08 | OK | `tests/0017-run.sh` → `ok - AC-08: docs/intent/ only: no test runs`, `each one skipped, not concerned`, `with a.sh too: the tests declaring a.sh only` |

