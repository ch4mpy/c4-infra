# Plan: The stand-in deployment test fails on a workstation whose locale isn't C

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

- 2026-10-28 — step 0. `LANG=fr_FR.UTF-8` here; `bash tests/0003-demo-deploy.stand-in.sh` without `LC_ALL`, on the code as it was: `KO - /root/c4-infra holds only what the deployment sends`, the found list in C order (`.env` first), the only failing check (`1 check(s) failed`).
- 2026-10-28 — step 1. The guard names 36 bare sorts, `tests/0003-demo-deploy.stand-in.sh:40,43` among them; the sort inside a jq program (`tests/0009-master-realm.sh:48`, jq's own, by code point) is left out, a command line run in a container (`sh -c '…'`) or by `eval '…'` is not. Step 2's check: the guard `every check passed`, `tests/0003-demo-deploy.stand-in.sh` without `LC_ALL` `every check passed`.
- 2026-10-28 — step 4, review round (bootstrap: one; `code-review high`). The guard missed a sort opening a quoted command line, after `do`/`then`/`!`/`xargs`/a backtick, behind `LANG=C` or `LC_COLLATE=C` (which don't win over `LC_ALL`), in an untracked file, and its jq purge could swallow a real sort further on the line: unfrozen with the product owner's approval (2026-10-28) and strengthened (one pipeline, `git grep --untracked`, only the quoted program right after `jq` and its options left out); a throw-away probe of those 13 forms: each named, `LC_ALL=C sort`, a jq program's sort and a comment not; at step 1's tree (526b25e) it names the 36 bare sorts. `tests/run.sh`: its test list, a glob that follows the locale's collation, sorted with `LC_ALL=C sort` (the order of lane 1 and of 0017's checks; the same today, not for names differing in punctuation only). Files: none new.
- 2026-10-28 — step 4, the verifier's gap: the guard missed a bare sort written right against `;`, `|`, `&`, `<` or `>` (`| sort; }`), and would pass reading nothing (outside a checkout). Fixed: any character that can't continue the name ends it; the guard fails when `git grep` finds no `LC_ALL=C sort` at all. A throw-away probe: `| sort; }`, `| sort|uniq`, `| sort>out`, `| sort&& true`, `sort<in` each named; `LC_ALL=C sort` before `;` or `|`, a jq program's sort and `./sort.sh` not. Rerun of what changed since the full run: `bash tests/run.sh --changed 0f0cdbd`.

## Verification

### Verification — 94ef408

- Verification command: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`, **without `LC_ALL`** (`LANG=fr_FR.UTF-8`), at 0f0cdbd → `total: 1524.1 s for 60 test(s)` / `verification passed (--changed: 60 of 60 tests)`; then `bash tests/run.sh --changed 0f0cdbd` at 94ef408 → `verification passed (--changed: 2 of 60 tests)` (2026-10-28)
- Risk tier: standard (tests only, and a line of `CLAUDE.md`; the project has no evals)
- Reviews: bootstrap mode: 1 round; bugs (`code-review high`) 9 findings, 6 fixed / 3 answered; no security pass (standard risk); no `simplify` pass (bootstrap)
  - fixed (0f0cdbd, 94ef408): the guard missed a sort opening a quoted command line, after `do`/`then`/`!`/`xargs`/a backtick, behind `LANG=C`/`LC_COLLATE=C`, in an untracked file, written against an operator (the verifier's), and its jq purge could hide a real sort; it now reads untracked files, fails when it reads nothing, runs as one pipeline; `tests/run.sh` lists the tests in C order (a glob follows the collation); the plan's *Deviations* filled
  - answered: the HANDOVER said "being delivered" while the index said planned — the index moves to delivered with this delivery
  - answered: a wrapper (`stand_in_exec sort`, `timeout 5 sort`) or a path (`/usr/bin/sort`) isn't named — none in the tests; the CLAUDE.md rule covers the next one
  - answered: the guard's header — kept short (five lines) for a rule a reader must understand
- Mutation check (bug): `tests/0003-demo-deploy.stand-in.sh` without `LC_ALL` at 526b25e (the guard, no fix), throw-away worktree → `KO - /root/c4-infra holds only what the deployment sends` / `1 check(s) failed` (the same 21 files, `.env` first in the found list, ninth in the expected one)
- Verifier: 5/5 criteria OK — table below; neighbouring flows: `tests/0003-compose.sh`, `tests/0017-run.sh`, `tests/0022-lanes.sh` pass under `fr_FR` (in the run); lane 1 started its tests in C order; a probe directory shows a glob's order differs between `fr_FR` and C for names differing in punctuation (`0001-a-b`, `0001-ab`, `0001-a_c`)
- Not verifiable here: Git Bash (the same `LC_ALL=C sort` idiom already runs there in `tests/lib/stand-in-host.sh`)
- Files outside the plan: none

| Criterion | Result | Evidence |
| --- | --- | --- |
| The check passes whatever the locale when the stand-in holds exactly what is sent | OK | `ok - /root/c4-infra holds only what the deployment sends` in the run under `fr_FR` |
| It still fails, naming the difference, when a file is missing or extra | OK | the comparison unchanged; the verifier's simulation: a missing and an extra file each exit 1, the found list printed |
| No test compares a list sorted in the workstation's locale | OK | `tests/0019-collation.sh` `every check passed`; it names the 36 bare sorts at 526b25e and every probe form |
| The verification runs without `LC_ALL=C` | OK | `verification passed (--changed: 60 of 60 tests)` under `fr_FR` |
| The bug is reproduced | OK | step 0 and the mutation check: `KO - /root/c4-infra holds only what the deployment sends` |

