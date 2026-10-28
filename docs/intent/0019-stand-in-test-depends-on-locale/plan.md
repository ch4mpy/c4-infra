# Plan: The stand-in deployment test fails on a workstation whose locale isn't C (0019)

- Spec: none, the [intent](intent.md) (bug, spec needed: no)
- Status: approved
- Branch: 0019-stand-in-test-depends-on-locale
- Approved: 2026-10-28, Jérôme Wacongne (engineer), in plan mode

## Starting point

- `tests/0003-demo-deploy.stand-in.sh:40` sorts the expected list on the workstation (`| sort`, its locale's collation), `:43` sorts the found list inside the stand-in (C); compared whole at `:45`. This workstation: `LANG=fr_FR.UTF-8` (measured 2026-10-28), so `.env` sorts after `caddy/…` here and first there.
- Every proof since 0017 ran with `LC_ALL=C` to work around it.
- The intent's open question, answered by a grep of `sort` in `tests/` (2026-10-28): that is the only list compared across two machines; about fifteen others compare a list sorted on the workstation with a literal written in C order (`tests/0007-isolation.stand-in.sh:97,109`, `tests/0007-dev.sh:61,76,80`, `tests/0003-compose.sh:32,68`, `tests/0016-realms.sh:63`, `tests/0017-run.sh:92`, `tests/0022-lanes.sh:103`, `tests/lib/keycloak.sh:133`, …): they pass under `fr_FR` only because the names they sort differ in letters, not punctuation. The rest are diagnostics (`sort | uniq -c`), de-duplications or numeric sorts.
- The project's idiom exists already: `LC_ALL=C sort` (`tests/lib/stand-in-host.sh:112`, `tests/0002-register-scope.sh:36`).

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every `sort` under `tests/` becomes `LC_ALL=C sort`, `tests/run.sh` and the numeric ones included (one rule, nothing to judge case by case), and a fast static test refuses a bare `sort` there. The tests keep running the stack's scripts under the developer's locale. Rejected: `export LC_ALL=C` in `tests/lib/assert.sh` (the scripts under test would never run under a developer's locale again).

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0019-collation.sh` | new, frozen after step 1: every `sort` in command position (after a pipe, `$(`, `;`, `&&`, a line's start) in `tests/*.sh`, `tests/lib/*` is `LC_ALL=C sort`; a bare one is named `<file>:<line>`; its pattern built from pieces, so that it doesn't match itself; `# covers: tests/` | the outcome (the guard) |
| `tests/*.sh`, `tests/lib/keycloak.sh`, `tests/run.sh` | modified: each `sort` → `LC_ALL=C sort` (about 35 lines, `tests/0003-demo-deploy.stand-in.sh:40,43` among them); nothing else | the outcome |
| `CLAUDE.md` | modified: the scripts' line — the tests sort with `LC_ALL=C sort` (`tests/0019-collation.sh`) | the outcome (the rule, for the next test) |
| `docs/intent/HANDOVER.md` | modified: "`LC_ALL=C` until 0019" goes | — |
| `docs/intent/0019-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

0. **Setup and facts**: the branch from `origin/0019-…`, `git merge main`; `locale` (`fr_FR.UTF-8`); `bash tests/0003-demo-deploy.stand-in.sh`, without `LC_ALL`, on the code as it is: `KO - /root/c4-infra holds only what the deployment sends`, the same files in two orders. — skill: none — check: recorded under *Deviations*.
1. **Failing test**: `tests/0019-collation.sh`. — skill: none — check: `bash tests/0019-collation.sh` exits 1, naming the bare sorts (`tests/0003-demo-deploy.stand-in.sh:40` among them). Commit `test(0019): …` alone, freeze it.
2. **Fix**: `LC_ALL=C sort` everywhere under `tests/`. — skill: none — check: `bash tests/0019-collation.sh` `every check passed`; `bash tests/0003-demo-deploy.stand-in.sh` without `LC_ALL`: `every check passed`. Commit `fix(0019): …`.
3. **Docs**: `CLAUDE.md`, `HANDOVER.md`. — skill: none — check: reread. Commit `docs(0019): …`. (`CLAUDE.md` is agent configuration: the project has no evals; said in the evidence.)
4. **Verification**: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` **without `LC_ALL`** (`tests/run.sh` changed: every test, under `fr_FR.UTF-8`); mutation check: step 1's tree in a throw-away worktree → `tests/0003-demo-deploy.stand-in.sh` (without `LC_ALL`) `KO` on the same check; `/sdlc-verify 0019` (bootstrap: one round, standard risk). — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0019`.

## Risks

- The full run under `fr_FR` finds another locale dependence than sorting (a translated message a test greps: bash's, coreutils', git's) → a deviation: fixed test-side the same way (`LC_ALL=C` on that one command), named in *Deviations*; a script of the stack that depends on the locale is a new intent.
- A sort the guard's pattern misses (a `sort` after an unusual separator) → the guard lists what it found; the step 2 grep (`grep -nw sort tests/`) is reread by hand.
- `LC_ALL=C sort` under Git Bash → already used by `tests/lib/stand-in-host.sh` there.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| The check passes whatever the locale when the stand-in holds exactly what is sent | automated test, under `fr_FR.UTF-8` | `tests/0003-demo-deploy.stand-in.sh` without `LC_ALL`: `ok - /root/c4-infra holds only what the deployment sends` (in step 4's run) |
| It still fails, naming the difference, when a file is missing or extra | read + unchanged check | the comparison stays whole (`[ "$found" = "$expected" ]`, the found list printed): only its sorts change |
| No test compares a list sorted in the workstation's locale | automated test | `tests/0019-collation.sh` |
| The verification runs without `LC_ALL=C` | the verification command | step 4's `--changed --all` under `fr_FR.UTF-8`: `verification passed` |
| The bug is reproduced | mutation check | step 1's tree → `tests/0003-demo-deploy.stand-in.sh` `KO` (step 0, and in a worktree at step 4) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
