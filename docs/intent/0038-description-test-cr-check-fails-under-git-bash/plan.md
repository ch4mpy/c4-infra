# Plan: tests that fail under Git Bash on the Windows workstation (0038 and 0039, one pass, one delivery)

- Specs: [0038 v1](spec.md) (approved 2026-10-30, PA-01 A, PA-02 A), [0039 v1](../0039-keycloak-tests-fail-under-git-bash/spec.md) (approved 2026-10-30, PA-01 A, PA-02 A)
- Status: approved
- Branch: `0038-description-test-cr-check-fails-under-git-bash`, carrying both intents (worktree `D:/workspaces/c4-infra-0038`)
- Approved: 2026-10-30, Jérôme Wacongne (engineer, also PO and tech lead; in the session, its five open choices decided as recommended)

## Context

On the Windows workstation, since Git for Windows was installed again (2026-10-29), five tests fail in every run: `tests/0029-description.sh` (a) (0038), and `tests/0016-keycloak-facts.sh`, `0017-export-realm.sh`, `0029-image-facts.sh`, `0030-federation-ids.sh` (0039). No full run ends `verification passed`, and the tests guarding `keycloak/` are blind there. Both causes are Git Bash traps, measured on 2026-10-30. The product owner wants one plan, one pass, one delivery.

- **0038**: `form()` (`tests/0029-description.sh:40-44` once `main` is merged; (a) at `:152`) writes `$'\r'` inside `bad=$(…)`, where Git Bash drops it (`grep -n ''`: every line named). And Git Bash's `grep` 3.0 doesn't see a CR before LF without `-U`, so a CRLF description would pass even with the substitution fixed. The existing copy check "(a) a quoted value: refused" (`:222-223`) is built on a one-line copy, which the every-line bug satisfies too.
- **0039**: the four tests `export MSYS_NO_PATHCONV=1` for their whole length and hand `/c/Users/…` paths to `jq` (WinGet's `jq.exe`) and, in 0016, `curl` (`/ucrt64/bin/curl`): native programs that can't use them (jq exit 2, curl exit 23); through `< file` or `cygpath -w` both work. `register-app.sh:267-268` already feeds `jq` on stdin, `tests/lib/keycloak.sh:121` gives `curl` its CA through `cygpath -w`, and `tests/lib/assert.sh:10-16` wraps `jq` for the native build's `\r\n`.
- Two of the four tests' checks were `ok` in the batch run while their input was unreadable: 0029-image-facts' `other_features` (`$other` empty when `jq` fails) and 0016's (e) "sends the browser to sim's login page" (`page_holds` on the stale `page.html` that `login_page facts-folder` left, `browse`'s `curl -o` having failed). 0016's (f) passes with `curl -o /dev/null`, native `curl` unable to write it, `-w` printing anyway.
- Inventory (RQ-04 of 0039, read-only, 2026-10-30): of the 15 tracked scripts that export `MSYS_NO_PATHCONV=1`, only the four tests hand a native program (`jq`, `curl`, `git`, `openssl`, `java`, `node`, `python3` are native here) a host path in Git Bash's form. The export reaches child scripts too: `new-realm-ids.sh`, `export-realm.sh`, `tests/lib/keycloak.sh`, and through `register-app.sh` `routes.sh`, `registry.sh`, hand none; `certs/make-certs.sh:64` gives `openssl` `$CA_DIR`, reachable from `tests/0009-master-realm.sh` through `up.sh`, whose stub there stops before it: not live today, recorded.

## Decisions taken in the specs

- 0038 PA-01 A, 0039 PA-01 A: CLAUDE.md's Git Bash line names the traps, one line for both; no test of the whole repository.
- 0038 PA-02 A: `tests/0029-description.sh` run in an `ubuntu:24.04` container as a command proof. 0039 PA-02 A: Ubuntu not verifiable here, for the human reviewer.

## Design

- **One branch, one plan.** 0038's branch, `main` merged in (it then holds 0039's intent and spec), carries both changes. This plan becomes `docs/intent/0038-…/plan.md`; `docs/intent/0039-…/plan.md` is a pointer to it (status, approval, a `## Verification` naming the joint evidence block), so that each intent has the `plan.md` `/sdlc-ship` reads.
- **0038, the check.** `form()` keeps its two `grep`, the CR held in a variable built outside the substitution (`local cr=$'\r'`) and read with `grep -nU "$cr"`, if step 0 (a) shows `-nU` naming the line on both systems (else a bash `read` loop naming the lines, measured on both first).
- **0038, the proof.** Copies of the repository's description (twelve lines), each with one line changed, written straight to their file by `sed`/`printf` (never through a variable: `$(…)` drops a trailing `\r`, `assert.sh:10`), each with a check of its bytes (`od -An -tx1`, no `grep`) so that a KO can't come from a broken copy. A new helper asserts that `form` fails and that the line numbers it names, `LC_ALL=C sort -un` of the `^[0-9]+:` prefixes of its whole output (`2>&1`), are exactly the expected set: Linux names a CRLF line twice (both `grep`), Git Bash once after the fix, every line before it. The quoted-value check is rebuilt the same way (strengthened, same name).
- **0039, the hand-offs.** The global export stays (the tests' docker calls give container paths). `jq` gets its file on stdin, `check "…" jq … < "$file"` included (`check` passes its stdin on, `assert.sh:21`; the `jq` wrapper too); multi-line calls included (`0029-image-facts:114-115`, `0030:67-69`, `:111-112`). `curl`'s file options in 0016 (`-c`/`-b` at `:85` and in `browse`, `-D`, `-o` beside `-w`, and `-o /dev/null` at `:224` → a file of `$work`) go through the test's own `host_path()` (`:40`). Each check keeps its name and its assertion.
- **CLAUDE.md** (`:12`, "Scripts run under Git Bash…"): a native program (`jq`, `curl`, `git`, `openssl`…) gets a host path through a redirection or `cygpath -w` while conversion is off; a CR written `$'\r'` inside `$(…)` or `<(…)` is dropped (build it outside); Git Bash's `grep` sees a CR before LF only with `-U`.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0029-description.sh` | step 1: the CR and other-form copies, their byte checks, the exact-line helper, the quoted-value check rebuilt; step 2: `form()` only | 0038 RQ-01 to RQ-04, AC-01 to AC-04 |
| `tests/0016-keycloak-facts.sh` | `jq` on stdin; `curl`'s `-c`, `-b`, `-D`, `-o` through `host_path`, `-o /dev/null` → `$work` | 0039 RQ-01, RQ-03, AC-01, AC-03 |
| `tests/0017-export-realm.sh`, `tests/0029-image-facts.sh`, `tests/0030-federation-ids.sh` | `jq` on stdin | 0039 RQ-01, RQ-03, AC-01, AC-03 |
| `CLAUDE.md` | the Git Bash line names the three traps | 0038 RQ-05, AC-05; 0039 RQ-05, AC-05 |
| `docs/intent/0038-…/plan.md`, `docs/intent/0039-…/plan.md`, both `intent.md`, `docs/intent/README.md`, `docs/intent/HANDOVER.md` | this plan and its pointer, *Deviations*, `## Verification`; statuses `planned`, then `delivered`; the index rows; the handover at delivery | — |

Unchanged on purpose: the eleven other scripts and the child scripts (the inventory), `tests/lib/`, `certs/make-certs.sh` (not reached today), `keycloak-image.properties`.

## Order of work

**Bootstrap mode** (both intents' `Mode`): no PR, one `sdlc-verify` round, pushes without confirmation. Both are bugs, the failing test first. 0038's code under test, `form()`, lives in the test file itself, which therefore can't be frozen: step 2's diff must touch `form()` only (checked). 0039's four tests already fail on `main`: the batch's log at 3aab993 (`~/.cache/c4-infra-tests/batch-0036-0037-0035-all.log`, 11, 3, 6, 16 checks) is its reproduction, no new test.

Runs: `TMPDIR=~/.cache/c4-infra-tests` always. 0017-export-realm (it reads `.env`, runs `export-realm.sh`'s `docker compose run` and writes `caddy/apps/`, `keycloak/themes/`, `compose.apps.yml` where it runs, while the proxy mounts the main checkout's) and the `--all` run go from the main checkout detached at the commit (`git switch --detach <sha>`, then `git switch main`); the other tests from the worktree.

0. **Setup and facts.** — skill: none — check: `git status --short` empty; one index row per intent; each fact under *Deviations*.
   - In the worktree: `git merge origin/main`; the index rows checked (0038 and 0039 once each). This plan into `docs/intent/0038-…/plan.md`, its pointer into 0039's, both intents `planned`, the index rows; commit `plan: …`, push.
   - (a) In `ubuntu:24.04` and under Git Bash (the CR held in a variable, read inside `$(…)`): `grep -nU "$cr"` on the three CR copies prints `<n>:<line>`, no "Binary file matches"; the safe-form `grep` on `KEY=v\r`. Decides `-U` or the `read` loop.
   - (b) Under Git Bash with `MSYS_NO_PATHCONV=1`: `curl` with `$(cygpath -w …)` paths for `-o`, `-c`/`-b`, `-D` writes and reads its files.
1. **Failing test (0038).** — skill: none — check: under Git Bash, `bash tests/0029-description.sh`: the new CR checks and the rebuilt quoted-value check KO (every line named), the byte checks and the other-form checks `ok`; in `ubuntu:24.04` (`git` installed by `apt`, a clone of the branch, `safe.directory`), the same test ends `every check passed`: the reference for the expected sets. The KO lines under *Deviations* (the test's exit status proves nothing: (a) already fails on `main`).
   - Copies: a CRLF line end on one `KEY=value` line; a CR ending the last line, no LF; a CR inside a comment line; a value with a space; a lowercase key; the quoted value.
   - Commit `test(0038): check (a) refuses each carriage return and each other form, naming only its line`.
2. **The check (0038).** — skill: none — check: under Git Bash, `bash tests/0029-description.sh` ends `every check passed`; `git diff HEAD~1 -- tests/0029-description.sh` changes `form()` only.
   - Commit `fix(0038): check (a) sees a carriage return under Git Bash, a CRLF line end included`.
3. **The four tests (0039).** — skill: none — check: 0016, 0029-image-facts, 0030 from the worktree, 0017 from the main checkout detached at the step's commit, dev stack up: each `every check passed`; the list of their check names (`ok` and `KO` lines) equals the batch log's.
   - Commit `fix(0039): the four Keycloak tests hand jq and curl their files in a form a native program reads`.
4. **CLAUDE.md.** — skill: none — check: `bash tests/run.sh --changed HEAD~1` (0016-no-real-provider, 0032-demo-github-only, 0037-queue; the stand-in 0037-queue-linux waits for step 5) passes; the `jq` prerequisite unchanged.
   - Commit `fix(0038, 0039): CLAUDE.md names Git Bash's traps for the scripts`.
5. **Verification.** — skill: sdlc-verify (both intents, one round on the joint diff) — check: `verification passed`.
   - From the main checkout detached at HEAD: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` (one stand-in lane, about 75 min): 0039's success criterion is a full run without the four; with `main` unchanged since step 0, it is the delivery's milestone as well.
   - 0038 AC-03: `tests/0029-description.sh` in `ubuntu:24.04` on a clone at HEAD: `every check passed` (Linux's `grep` with `-U` on the final code).
   - Mutations, in throwaway worktrees, under Git Bash: 0038, `-U` removed → only the CRLF copy KO; `"$cr"` back as an inline `$'\r'` → every copy KO. 0039: 0029-image-facts, a preview feature dropped from what `features` expects → `other_features` KO; 0016, sim's login page expected to hold another form id → (e)'s first check KO; 0017, another username expected; 0030, the two copies' ids expected equal: each its check KO.
   - Inventories: 0038 AC-05, every CR ANSI-C quote of the tracked scripts (`git grep`), read: none inside a substitution, no `grep` relied on to see a CR before LF but (a)'s; 0039 AC-04, the 15 scripts and their child scripts listed again.
   - The `verifier`; the evidence block into this plan's `## Verification`, its pointer into 0039's; commit `plan: verification of 0038 and 0039`; push.
6. **Delivery.** — skill: sdlc-ship — `/sdlc-ship 0038 0039`: both `delivered` on the branch, one `git merge --no-ff` into `main` (`merge(0038, 0039): …`), the index rows checked, the handover updated, `main` pushed. The push runs the demo workflow (`tests/*.sh` aren't `**/*.md`): the same files deployed, nothing to check on the host.

## Risks

- `grep -nU` refused on Ubuntu, or printing "Binary file matches" → step 0 (a) decides; the fallback measured on both before step 2.
- A copy built through a Git Bash trap (its CR lost) → written straight to its file by `sed`/`printf`, its bytes checked by a check of its own.
- The exact-line helper fooled by duplicate lines or a `grep` error → the deduplicated set of numbers of the whole output, `2>&1`.
- A check of the four tests loosened while its plumbing changes, or still passing on unread input → the check names compared with the batch log; mutations aimed at the two checks that passed on unread input.
- 0017 run from the worktree writes into it, or misses `.env` → run from the main checkout only.
- The Ubuntu container can't reach the package archive for `git` → 0038's AC-03 recorded as not verifiable, the rest stands.
- `main` moves before delivery → `--all` again on the merge (CLAUDE.md's milestone).
- A merge of the index duplicates or drops a row (seen at 0037's delivery) → the rows checked after each merge (steps 0 and 6).

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| 0038 AC-01 | automated test | `tests/0029-description.sh` under Git Bash, "(a) the description's lines are comments or KEY=value, no CR" `ok`; KO on `main` |
| 0038 AC-02 | automated test, mutation | the same test, the CRLF, CR-at-end and CR-in-comment copies: refused, naming exactly their line, their bytes checked; KO at step 1; the two mutations of step 5 |
| 0038 AC-03 | command | the test in `ubuntu:24.04` (git installed), at step 1 and at HEAD, `every check passed` |
| 0038 AC-04 | automated test | the same test, the space-in-value, lowercase-key and quoted-value copies: refused, naming exactly their line |
| 0038 AC-05 | command, reading | step 5's `git grep` of CR ANSI-C quotes and of `grep` on a CR, read; CLAUDE.md's line |
| 0039 AC-01 | automated test | the four tests under Git Bash, `every check passed` each; KO in the batch log (3aab993) |
| 0039 AC-02 | not verifiable here | Ubuntu (PA-02 A), for the human reviewer |
| 0039 AC-03 | command, mutation | the check names equal to the batch log's; M1 to M4 KO, two of them on the checks that passed on unread input |
| 0039 AC-04 | command | the inventory of the 15 scripts and their child scripts; step 5's `--all` reports none of the four |
| 0039 AC-05 | command | `CLAUDE.md`: the `jq` prerequisite unchanged, the trap named |
| No regression | command | step 5's `bash tests/run.sh --all`, `verification passed` |

## Open choices for the engineer

Decided at approval (2026-10-30, Jérôme Wacongne): every choice as recommended.

Each with Claude's recommendation; the steps above follow the recommendations.

- **C1. Where the joint plan lives.** A (recommended): in 0038's folder, 0039's `plan.md` a pointer with its own `## Verification` line. B: the same plan in both folders (two copies to keep equal).
- **C2. The branch.** A (recommended): 0038's branch, `main` merged in. B: a new branch `0038-0039-git-bash-traps` from `main`, 0038's branch merged into it.
- **C3. 0039's fix.** A (recommended): the global export kept, `jq` on stdin, `curl`'s file options through `host_path`: the smallest diff, the forms `register-app.sh` and `tests/lib/keycloak.sh` already use. B: the export dropped, `MSYS_NO_PATHCONV=1` on each docker call that gives a container path: conversion back for everything else, but every docker call touched and other arguments (`key=/path`) exposed to MSYS's conversion.
- **C4. The verification run.** A (recommended): one `--all` at step 5, the delivery's milestone too if `main` doesn't move. B: `--changed --all` at step 5 (minutes), then `--all` at delivery.
- **C5. The quoted-value check** (`:222-223`, built on a one-line copy the bug satisfies). A (recommended): rebuilt on the full description with the exact-line assertion, its name kept. B: left as it is.

## Deviations

- 2026-10-30 — step 0: `git merge origin/main` didn't conflict, but the index came out with 0037's row twice (`accepted` from the branch's base, `delivered` from `main`) and 0038's before 0035's, as at 0037's delivery: set right in the plan's commit (3ad4e07), one row per intent.
- 2026-10-30 — step 0, fact (a), the three CR copies of the twelve-line description (scratchpad `0038-step0/facts.sh`): under Git Bash (GNU grep 3.0) and in `ubuntu:24.04` (GNU grep 3.11) alike, `grep -nU "$cr"`, the CR held in a variable and read inside `$(…)`, prints `5:KC_VERSION=26.8.1␍` for the CRLF copy, `12:KC_PUBLISHED_IMAGE=…␍` for the CR ending the last line, `1:#␍ The stack's Keycloak…` for the CR inside a comment, no "Binary file matches", and nothing on the repository's description (status 1). Without `-U`, Git Bash's `grep` and the safe-form `grep` both miss the CRLF line (Linux's see it). So `-U`: no `read` loop.
- 2026-10-30 — step 0, fact (b), under Git Bash with `MSYS_NO_PATHCONV=1`, against Mailpit (`http://127.0.0.1:8025/`): `curl -b`, `-c`, `-D`, `-o` with `$(cygpath -w …)` paths: exit 0, the cookie of the `-b` jar sent (`> Cookie: facts=measured`), the `-c` jar, the headers and the body written; `-o` to a file of the work directory exit 0; `-o /dev/null` (0016's `:224` today) exit 23, the `-w` code printed anyway.
- 2026-10-30 — step 1, under Git Bash (`~/.cache/c4-infra-tests/0038-step1-gitbash.log`), exit 1, `7 check(s) failed`, every one of (a): the repository's, and each of the six copies, `lines named: 1 2 3 4 5 6 7 8 9 10 11 12`; the three byte checks `ok` (`the copy crlf holds one CR`, …), every other check `ok`. A deviation from the step's check, which expected the other-form copies `ok`: today's `form()` names every line of any file under Git Bash, so they fail too, for the same cause. In `ubuntu:24.04` (a clone at 3ad4e07 with the step's test, `git` 2.43.0 from `apt`; `0038-step1-ubuntu.log`): `every check passed`, the reference for the expected sets. Committed alone (13e3d2d).
- 2026-10-30 — step 3: the four tests `every check passed` (`~/.cache/c4-infra-tests/0039-step3-<test>.log`), with the batch log's check names, 26, 9, 22 and 33 of them; three values in parentheses changed, the trace of checks that read stale or unread input before: 0016 (e)'s form action `/realms/facts-folder/…` → `/realms/sim/…`, its brokered user `null` → the user's JSON, its provider empty → `google`. 0017's run departs from the step's check (found by the verifier): the main checkout's reflog shows it detached at c776b3d from 07:31:06 to 07:31:35, the log, written at 07:31:30, passes, and c02d6d1 was committed at 07:31:55: it ran the step's change before its commit. The full run and the 0017 mutation at e538d54 stand in for it.
- 2026-10-30 — step 5, the review round (bootstrap mode, `code-review` high on the branch's diff from 359edca), 8 findings. Fixed in e538d54: the copies' comment (`tests/0029-description.sh:234`) said a CR held in a variable is lost under Git Bash, against the measured rule; `CLAUDE.md:12` named `$'\r'` alone, while `$'\x0d'` and `$'\015'` are dropped too; `last_line` counted with `wc -l`, one short on a file without a final LF, now `grep -c ''`. Answered: `MSYS_NO_PATHCONV=1` scoped to the docker calls (altitude) is C3's option B, set aside at the plan's approval (every docker call touched, other arguments exposed to the conversion); `cygpath` forked at each call of 0016's helpers: accepted, the test ran in 52.8 s in the full run; `host_path()` defined in 22 tests and not in `tests/lib/`: pre-existing, a follow-up suggested; `crs()` by `od` rather than `tr -cd '\r' | wc -c`: the plan's design, bytes read without a text tool; the quoted-value check's name without "naming line … alone": kept, per C5 A. After the fix: `0038-review-fix.log` `every check passed` under Git Bash, `0038-ubuntu-head.log` the same in `ubuntu:24.04`.

## Verification

### Verification — e538d54

- Verification command: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all`, from the main checkout detached at e538d54, one stand-in lane (Docker reports 7.6 GiB) → `total: 4896.2 s for 83 test(s)`, `verification passed`, `run.sh exit 0` (2026-10-30, `~/.cache/c4-infra-tests/0038-0039-all.log`), no `KO` line. `main` hasn't moved since step 0's merge (359edca): the run is the delivery's milestone as well (C4 A).
- Risk tier: standard (both specs: the suite's own files, no risk rule applies)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high) 3 fixed / 5 answered (Deviations, step 5); no security pass (standard risk); the comments the diff adds: function headers, the reason of the copies' form (Git Bash), of `form()`'s `cr` and `-U`.
  - The verifier's detail on `tests/0029-description.sh:234`, whose first half says what the code below does: kept, the section heading the file uses (`# The differences named, on copies`, :172), its second half the reason.
- Mutation check (bug):
  - 0038: `tests/0029-description.sh` at 13e3d2d (the failing test, before the fix): `7 check(s) failed`, every line named (the session at step 1, then the verifier). At e538d54: `-U` removed → `1 check(s) failed`, the CRLF copy alone (`0038-M1.log`); the CR written `$'\r'` inside `$(…)` → `7 check(s) failed`, every line named (`0038-M2.log`); both again by the verifier, and its M3, the safe-form class widened to a space and `"` → `2 check(s) failed`, the space and the quoted copies.
  - 0039: the four tests at 3aab993, before the fix: 11, 3, 6 and 16 checks failed, `jq: error: Could not open file /c/Users/…` (`batch-0036-0037-0035-all.log`). At e538d54, in a throwaway worktree (0017: an untracked copy in the main checkout), each `1 check(s) failed` (`~/.cache/c4-infra-tests/0039-M-<test>.log`): 0029-image-facts, `PARAMETERIZED_SCOPES` dropped from `features()` → `enabled, not described: PARAMETERIZED_SCOPES`; 0016, `page_holds 'kc-form-other'` → its page printed, `<title>Sign in to sim</title>`; 0017, `["someone"]` expected → `with its user`, `false`; 0030, a and b's component ids expected equal → `a: H_yjYcGfdX47D3KWkuizoA, b: DXoL0NKSnQo8SUxnXG6L-g`. 0016's would fail on a stale page too: the page's freshness is proven by its output and by :212's action, `/realms/sim/…` now, `/realms/facts-folder/…` before.
- Verifier: 10/11 rows OK, 0 KO, 1 not verifiable; table below.
- Not verifiable here: 0039 AC-02, the four tests under bash on Ubuntu (PA-02 A), for the human reviewer; the verifier found nothing against it (`host_path` returns the path unchanged without `cygpath`, a redirection reads the same in both shells).
- Files outside the plan: none (0038's `spec.md` is the spec's commit, before the plan).
- Agent configuration: `CLAUDE.md` changed; the project has no evals (`git ls-files` names none), so no eval report.
- Pre-existing findings (not fixed, out of scope): `tests/0029-image-facts.sh:112-117`, `other_features` ignores jq's status and passes on an empty `serverinfo.json` (noted at 0037's verification already); `tests/0016-keycloak-facts.sh:210`, `page_holds 'kc-form-login'` accepts any realm's login page (:212 catches a stale one); `host_path()` defined in 22 tests, not in `tests/lib/`; `certs/make-certs.sh:64` hands `openssl` `$CA_DIR`, not reached today (`up.sh`'s stub stops before it) → a bug intent suggested for the two checks, a follow-up for `host_path()`.

| Criterion | Result | Evidence |
| --- | --- | --- |
| 0038 AC-01 | OK | `bash tests/0029-description.sh` at e538d54 under Git Bash (verifier): exit 0, `ok - (a) the description's lines are comments or KEY=value, no CR`, `every check passed`; `1 check(s) failed`, (a), at 3aab993 (batch log) |
| 0038 AC-02 | OK | the same run: the three byte checks `ok`, the CRLF (line 5), CR-at-end (line 12) and CR-in-comment (line 1) copies `ok`, each naming its line alone (`refused_lines`: the exact set of the numbers named, `2>&1`); KO at 13e3d2d; the mutations above |
| 0038 AC-03 | OK | `ubuntu:24.04`, a clone at e538d54 (verifier): `git version 2.43.0`, `grep (GNU grep) 3.11`, `bash 5.2.21(1)-release`, `every check passed`; at step 1 the same (`0038-step1-ubuntu.log`) |
| 0038 AC-04 | OK | the space, lowercase and quoted copies `ok`, each naming line 5 alone; the verifier's M3 → the space and quoted copies `accepted`, KO |
| 0038 AC-05 | OK | `git grep` of every spelling of a CR as an ANSI-C quote: 13, each read, none inside `$(…)` or `<(…)` (parameter expansions, a `case` arm, a group piped to `od`, measured to keep its CR, `form()`'s `local cr`, a comment); the only `grep` asked to see a CR is `form()`'s `grep -nU "$cr"`; `CLAUDE.md:12` names both traps and the three spellings |
| 0039 AC-01 | OK | the full run at e538d54: 0016 26 `ok`, 0017 9, 0029-image-facts 22, 0030 33, each `every check passed`; 11, 3, 6 and 16 KO at 3aab993 |
| 0039 AC-02 | not verifiable | PA-02 A, for the human reviewer |
| 0039 AC-03 | OK | the four tests' check names, batch log against full run: identical but for values in parentheses (0016 (e)'s action and brokered user); the diff adds `< file` and `host_path` only, every filter and expression unchanged; the four mutations KO |
| 0039 AC-04 | OK | the 15 scripts exporting `MSYS_NO_PATHCONV=1` and their child scripts: every `jq` reads stdin, a pipe or a here-string, but `tests/0010-brute-force.sh:46` (a relative path; 0010 passes); `curl`'s file options in 0016 only, through `host_path`; `openssl` runs `rand` or reads through redirections; `certs/make-certs.sh` not reached |
| 0039 AC-05 | OK | `CLAUDE.md:16`'s `jq` prerequisite word for word that of 359edca; `CLAUDE.md:12` names the redirection or `cygpath -w` for a native program |
| No regression | OK | the full run: `verification passed`, 83 tests, no `KO` line |
