# Plan: The suite's Docker preflight refuses every run on a machine whose locale writes a decimal comma

- Spec: [v1](spec.md) (approved 2026-10-31, PA-01 A)
- Status: approved
- Branch: `0050-docker-preflight-wrong-under-decimal-comma` (worktree `D:/workspaces/c4-infra-0050`; on `origin` at 729f20a)
- Approved: 2026-10-31, Jérôme Wacongne (engineer and tech lead, ExitPlanMode)

## Context

0049's `tests/lib/docker-preflight.sh` formats its measures with awk's `printf "%.1f"` and reads docker's sizes with awk. An awk that honours the numeric locale (mawk, Ubuntu's default; gawk with `--use-lc-numeric` or in POSIX mode) writes `115,3` under `fr_FR.UTF-8`, which `_docker_short` then compares as a string: every measure is "short", and every run with a slow test is refused on the product owner's Linux workstation. The same awk reads `1.5GB` as 1 GB in `_docker_bytes`. Reproduced on this workstation with `LC_ALL=fr_FR.UTF-8 gawk --use-lc-numeric`: `115,3`, `1000000000`, and `m=115,3 < f=20` true, the three symptoms of mawk 1.3.4 in `ubuntu:24.04`.

The product owner has the verification and the delivery done by an agent on the Linux workstation, under remote control, with its French locale: this session implements, checks what it can here, writes the handover note and pushes; the Linux agent runs `sdlc-verify` and `sdlc-ship`.

## Design

- **The library's awk under `C`** (RQ-01 to RQ-03, RQ-05, IV-02): one helper `_docker_awk() { LC_ALL=C awk "$@"; }` (documentation comment: awk with a point as decimal separator, whatever the caller's locale), and each of the library's 15 `awk` calls goes through it. `LC_ALL`, not `LC_NUMERIC`: a caller's `LC_ALL` overrides `LC_NUMERIC`. The prefix applies to that command only: the caller's shell keeps its locale (IV-02). No function named `awk`: it would change the caller's own awk once sourced.
- **The floors and the bound** (RQ-04): `_docker_floor` and `_docker_reap_unlabelled`'s bound accept `^[0-9]+([.,][0-9]+)?$` and hand on the value with its comma made a point (`${value/,/.}`); the "not a number" lines unchanged for anything else.
- **The header** (IV-01): the library's numbers don't depend on the caller's locale; a floor or the bound may be written with either separator. Function names, lines and variables unchanged.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0050-preflight-locale.sh` | new: the library under `fr_FR.UTF-8` with an awk that honours it, and under `C`; no Docker (a `docker` shim prints a canned `df -Pk /` and `/proc/meminfo`); `# covers: tests/lib/docker-preflight.sh` | AC-01 to AC-05 |
| `tests/lib/docker-preflight.sh` | `_docker_awk`, every awk call through it; floors and bound with either separator; header | RQ-01 to RQ-05, IV-01, IV-02 |
| `docs/intent/HANDOVER.md` | the handover note for the Linux agent (below); fact (e) of `0033-limits-facts` "monitored" (the product owner, 2026-10-31) | PA-01 |
| `docs/intent/0050-…/plan.md`, `intent.md`, `docs/intent/README.md` | the plan, `planned` | |

## The test, `tests/0050-preflight-locale.sh`

- **The awk that honours the locale**: a shim directory first on `PATH`: when `awk` already writes `1,5` for `printf "%.1f", 1.5` under `fr_FR.UTF-8` (mawk on the Linux workstation), no shim; else `awk` → `exec gawk --use-lc-numeric "$@"` (Git Bash). Neither, or no `fr_FR.UTF-8` (`locale -a`): the test fails, naming what is missing (never skipped).
- **A `docker` shim**: `run … df -Pk /; cat /proc/meminfo` prints a canned output (a disk of 115.34 GB free, 2.4 GiB of `MemAvailable`); anything else exits 0 silently. `docker_preflight --no-clean`, `C4_DOCKER_DISK_DIR` a temporary directory, `C4_DOCKER_MIN_HOST_*` 0.
- **Checks**, each under `C` and under `fr_FR.UTF-8` (the library sourced in a `bash -c` per locale):
  - AC-01: floors 20 and 3 → exit 1 naming the VM's memory only (2.4 < 3), the disk not short; floors 20 and 2 → exit 0; the same verdicts under both locales;
  - AC-02: no `docker preflight:` line holds a digit, a comma and a digit; the disk's line says `115.3`;
  - AC-03: `_docker_bytes 1.5GB 512.3MB` → `2012300000` under both;
  - AC-04: `C4_DOCKER_MIN_VM_DISK_GB=2,5` → the measure line says `floor 2.5`; `2,5,1` and `abc` → the "not a number" line, exit 1; `C4_DOCKER_BUILD_CACHE_GB=2,5` → `_docker_reap_unlabelled` hands `2500000000` to the shim's `builder prune` (its log);
  - AC-05: after `docker_preflight` under `fr_FR.UTF-8`, `printf '%.1f\n' 1,5` in the same shell prints `1,5`.

## Order of work

1. **Failing test** — skill: none — check: `bash tests/0050-preflight-locale.sh` KO on AC-01 to AC-04 under `fr_FR.UTF-8` (the `C` checks and AC-05 OK), its KO lines into *Deviations*. Commit `test(0050): the preflight under a decimal-comma locale`; frozen.
2. **The fix** — skill: none — check: `bash -n tests/lib/docker-preflight.sh`; `bash tests/0050-preflight-locale.sh` → `every check passed`; with no other session's run (PowerShell `Get-CimInstance`), `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed` (the 0049 tests that cover the library: AC-06) → `verification passed`. Commit `fix(0050): the preflight's numbers don't depend on the caller's locale`.
3. **Handover note and push** — skill: none — check: `git status --short` empty, `git ls-remote` shows the branch's head. HANDOVER.md's *Open* gets 0050: branch and worktree-free state, the commits; what the Linux agent does, in order:
   1. `git fetch`, a worktree on `0050-docker-preflight-wrong-under-decimal-comma`, its locale as is (no `LC_ALL=C`; `locale` shows `fr_FR.UTF-8`), the dev stack up and Faito registered (CLAUDE.md, "Verification");
   2. the mutation check: `bash tests/0050-preflight-locale.sh` at the step-1 commit (mawk, no shim) → KO; at the head → `every check passed`;
   3. `/sdlc-verify 0050` (bootstrap: the bugs pass, one round), whose run is `bash tests/run.sh --changed --all` under the French locale: that run passing its preflight is PA-01's proof; the verifier; the evidence into `## Verification`, with the machine and its `locale`;
   4. `/sdlc-ship 0050`: delivered, merged into `main`, pushed (Markdown and `tests/` only: deploy-demo's paths still trigger on `tests/`, check; nothing deployed changes);
   5. tell the skills' session that their `LC_ALL=C` around the library can go (out of scope here).
   Commit `plan: 0050, handover to the Linux workstation`; push the branch.

## Risks

- `LC_ALL=C` on awk changes how it reads non-ASCII input → the library's awk reads docker's and `df`'s output and `/proc/meminfo`, ASCII; the 0049 tests run at step 2.
- The shim makes Git Bash's gawk behave like mawk, but not exactly → the Linux agent runs the same test with the real mawk, before and after the fix (handover 2).
- The Linux workstation's run finds another locale defect elsewhere in the suite (`tests/0037-queue.sh:79` suspected) → a new intent (spec, out of scope; PA-01 A).
- `--changed` here selects few tests and Docker is shared → the lock; no other session's run first.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 to AC-05 | automated test, mutation | `tests/0050-preflight-locale.sh`: KO at step 1, green at step 2 (here, gawk `--use-lc-numeric`); the same on the Linux workstation with mawk (handover 2) |
| AC-06 | automated tests | `bash tests/run.sh --changed` here (step 2); `--changed --all` on the Linux workstation (handover 3) |
| PA-01 (the intent's success) | command, on the Linux workstation | the Linux agent's `bash tests/run.sh --changed --all` under `fr_FR.UTF-8` passes its preflight, last lines in `## Verification` |

## Deviations

- 2026-10-31 — step 1: `bash tests/0050-preflight-locale.sh` (gawk `--use-lc-numeric`), `exit 1`, KO as planned under fr_FR.UTF-8 on AC-01 (the VM's disk short, floors 20 and 2 exit 1), AC-02 (`115,3`), AC-03 (`1512000000` for 1.5GB and 512.3MB), AC-04; AC-04 is KO under `C` too (`2,5` refused "not a number" whatever the locale today: the plan's "the `C` checks OK" meant AC-01 to AC-03); AC-05 OK. No impact on files or proof.
- 2026-10-31 — step 2: the first `bash tests/run.sh --changed` ran from this worktree, which has no `.env` (the stack's tests KO on `KC_IMAGE` and the others unset: 104 KO lines, none in the library's tests), and was stopped by my own `timeout 1500` (exit 124, in `0022-lanes`): not a result. The check runs again from the main checkout detached at the `fix(0050)` commit, as the suite expects, so the fix is committed before its run. No impact on files or proof.
- 2026-10-31 — verification on the product owner's Linux workstation (Ubuntu 26.04.1 LTS, `LC_NUMERIC="fr_FR.UTF-8"`, mawk 1.3.4 20260129): that machine's Docker and dev stack were shared with another agent's work (poc-immo-pf), so every run set `C4_DOCKER_REAP=labelled` (the preflight measures and compares with the default floors, but reaps only what the suite labelled, never the build cache nor the anonymous volumes), and nothing shared was started, restarted, recreated or pruned. The handover's `bash tests/run.sh --changed --all` (every test: the change touches `tests/lib/`) was not run: it restarts shared containers (`tests/0026-stack-bounds.sh:165`, `c4-infra.grafana-lgtm`; `tests/0005-themes.sh`, the dev Keycloak in its demo part) and registers fixture realms on the shared Keycloak. In its place, under the shared suite lock: `tests/run.sh`'s lock take and preflight (its lines 378-386, the same libraries, `--pins <(bash tests/docker-pins.sh)`, cleaning on) with the default floors, then the tests that cover the library. The shell's environment carried `LOCPATH=/snap/code/273/usr/lib/locale` (VS Code's snap), which makes `locale` fail on `LC_CTYPE`: unset for every run, the locale left as is. Impact: PA-01's literal command and AC-06's stand-in and facts part wait for a run on a Docker no one else uses (the product owner decides).

- 2026-10-31 — the full run on the free workstation: `bash tests/run.sh --changed --all` cannot pass from a worktree. The shared stack bind-mounts its checkout's `caddy/`, `certs/` and `keycloak/themes` (`c4-infra.reverse-proxy`, `c4-infra.keycloak`), so a test that registers from the worktree writes routes the proxy never reads (`0003-dev-routes`, 22 KO; `0003-env-switch`, 4 KO). Faito's `deploy-dev.sh`, which several tests run, brings the stack back up from `../c4-infra`, the path set in Faito's `.env`, in the middle of the suite (`0007-dev` AC-11, 1 KO). A worktree with no `.env` makes the stack's tests fail on unset variables, and a test then writes a `.env` with fresh secrets. Three runs were stopped (Ctrl-C, exit 130) once that was seen. Detaching the main checkout at the branch head to run there was refused by the agent's permission check (the main checkout is the shared stack's source), so the PO decides how the full run is made. The preflight with the default floors and full cleaning ran in all three runs (`C4_DOCKER_REAP` not set): this supersedes the `C4_DOCKER_REAP=labelled` deviation above for PA-01. The stack is back on `main` (`bash up.sh` from the main checkout, Faito's realm and `faito-api` present). No impact on files.
- 2026-10-31 — delivered on the full run of `87acaf4` (88 of 90 passed, PA-01 met under `fr_FR.UTF-8`), the product owner's decision — `0048-landing-page` fails the same way on `main` at `ae74575` without 0050 (`KO - AC-10: shows it`, `KO - AC-04: lists no account`), a bug intent of its own; `0002-accounts.stand-in` intermittent, passing alone — none on files.

## Verification

### Verification — 87acaf4 (the local merge into `main`, the full run from the main checkout)

- The product owner's "vas-y, fusionne 0050 dans main" (2026-10-31), option A: `git merge --no-ff origin/0050-docker-preflight-wrong-under-decimal-comma` in the main checkout (87acaf4, over `ae74575`), not pushed; the run from there. Machine: the PO's Linux workstation, Docker free of other runs; `LC_NUMERIC="fr_FR.UTF-8"`, `LC_ALL` empty, `LOCPATH` unset; `mawk 1.3.4 20260129`; `TMPDIR=/home/jerome/.cache/c4-infra-tests`; no `C4_DOCKER_REAP`.
- **KO, not 0050's: `bash tests/run.sh --changed origin/main --all` → `run.sh exit 1`, 42m12s (`total: 2523.3 s for 90 test(s)`), `FAILED: tests/0002-accounts.stand-in.sh tests/0048-landing-page.sh`.**
  - `tests/0048-landing-page.sh`: `KO - AC-10: shows it`, `KO - AC-04: lists no account`; the same two KOs alone under fr_FR (30 s, `2 check(s) failed`) and alone under `LC_ALL=C` (diagnosis only): not the locale. Cause: Docker Desktop's file sharing of the checkout's `caddy/` (mounted at `/etc/caddy`) serves a file's old content after `register-app.sh` renames the new page over it (`mv`, `register-app.sh:214`): a probe file renamed over in `caddy/html/` still read `v1` in `c4-infra.reverse-proxy` 6 s after `v2` was written; the container's `index.html` caught up later. The proxy was recreated during the run (started 21:00:09Z). 0050 changes nothing that test runs: `git diff origin/main 87acaf4` outside `docs/` is `tests/0050-preflight-locale.sh` and `tests/lib/docker-preflight.sh` only, which the test doesn't source. Not passing alone, so the merge was not pushed and was undone (`git reset --hard origin/main` in the main checkout, nothing else lost); the delivered mark reverted on this branch.
  - `tests/0002-accounts.stand-in.sh`: `KO - it leaves no temporary configuration in /tmp` in the run; alone → `every check passed` (3m04s): intermittent.
- PA-01, the run's preflight, default floors, full cleaning, under fr_FR:
  ```
  docker preflight: run 1793479909-2428694-2181114770
  docker preflight: runs over: 5 container(s), 1 network(s), 0 volume(s), 0 image(s) removed
  docker preflight: kept, their path gone: 0 volume(s), 0 image(s) removed
  docker preflight: build cache: 3.008GB reclaimed (bound 5 GB)
  docker preflight: anonymous volumes no container uses: 0 removed (0B)
  docker preflight: images a pin replaced: 0 removed (0.0 MB)
  docker preflight: VM disk: 424.8 GB free (floor 20)
  docker preflight: VM memory: 8.7 GiB available (floor 3)
  docker preflight: host disk under Docker's disk image (/): 114.8 GB free (floor 20)
  docker preflight: host memory: 9.7 GiB MemAvailable + 2.1 GiB SwapFree (floor 6)
  ```
  The run went past its preflight and ran all 90 tests, 88 passing; every 0049/0050 test among them passed. The worktree runs below are superseded by this one for PA-01.
- The product owner decides: deliver on this run (0048-landing-page's KO an environment defect, a bug intent), or a run after the file-sharing staleness is dealt with.

| Criterion | Result | Evidence |
| --- | --- | --- |
| PA-01 | OK | the full run under fr_FR past its `docker preflight:` lines, default floors, 90 tests run |
| AC-06 | OK | the 0049 and 0050 tests passed in the full run |
| the full run's end | KO (environment, not 0050) | `0048-landing-page` KO, alone too (Docker Desktop file sharing stale after a rename); `0002-accounts` intermittent, passing alone |

### Verification — 2ca4649 (the merge of `main`, the full run)

- Machine: the PO's Linux workstation, Docker free of other runs (the PO's go, 2026-10-31); `LC_NUMERIC=fr_FR.UTF-8`, `LC_ALL` empty, `LOCPATH` unset; `mawk 1.3.4 20260129`; `TMPDIR=/home/jerome/.cache/c4-infra-tests`; no `C4_DOCKER_REAP`.
- **KO, not 0050's: `bash tests/run.sh --changed --all` from the worktree did not complete.** Three runs were stopped after 31m37s, about 1 min and about 9 min, exit 130. Their KOs come from the checkout the stack runs from (*Deviations*, this date): `0001-loopback-ports` (10), `0003-dev-routes` (22), `0003-env-switch` (4), `0007-dev` AC-11 (1). None is in the library or concerns the locale. The PO decides how the full run is made: from the main checkout at the branch head, or after the merge into `main`.
- Merge: `git merge origin/main` (0051 and 0052) conflicted on `docs/intent/HANDOVER.md` and `README.md` only; both sides kept; `bash tests/0050-preflight-locale.sh` → `every check passed`.
- PA-01, the preflight as `tests/run.sh` runs it, default floors, full cleaning, under fr_FR. First run:
  ```
  docker preflight: run 1793475458-1951334-392427863
  docker preflight: runs over: 0 container(s), 0 network(s), 0 volume(s), 0 image(s) removed
  docker preflight: kept, their path gone: 0 volume(s), 0 image(s) removed
  docker preflight: build cache: 0B reclaimed (bound 5 GB)
  docker preflight: anonymous volumes no container uses: 21 removed (1.019GB)
  docker preflight: images a pin replaced: 0 removed (0.0 MB)
  docker preflight: VM disk: 429.6 GB free (floor 20)
  docker preflight: VM memory: 8.3 GiB available (floor 3)
  docker preflight: host disk under Docker's disk image (/): 115.7 GB free (floor 20)
  docker preflight: host memory: 10.3 GiB MemAvailable + 1.6 GiB SwapFree (floor 6)
  ```
  Second and third runs: the same, `build cache: 4.772MB reclaimed` and then `2.437GB reclaimed (bound 5 GB)`, `0 removed (0B)` anonymous volumes. Every number is written with a point and every run went past its preflight. `bml-db`, still stopped, and its anonymous volume survived the prune, as did `immo.*` and their volumes.
- AC-06, under fr_FR: `bash tests/0049-docker-preflight.sh` → exit 0, 21 s, 35 ok, `every check passed`, the shim's guard and 0052's window checks included. `bash tests/0049-docker-labels.sh` → `every check passed`. `tests/0049-docker-reap.stand-in.sh` (first run) → `every check passed`, 30.7 s. `tests/0037-queue.sh` (first run) → `every check passed`.
- Verifier (since 898a040): 10/11 OK, 0 KO; the merge kept both sides, no markers, the library and frozen test unchanged; AC-01..AC-06 OK under fr_FR. Not verifiable for the verifier: the reap stand-in test, which its brief excluded and the first run passed above.
- Durations: runs 31m37s + about 1 min + about 9 min, all stopped; library tests 22 s; verifier 1m33s.

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 to AC-05 | OK | `tests/0050-preflight-locale.sh` under fr_FR, mawk: `every check passed` |
| AC-06 | OK | `0049-docker-preflight` (35 ok), `0049-docker-labels`, `0049-docker-reap.stand-in` all `every check passed` under fr_FR |
| PA-01 | preflight OK; the full run's end not reached (environment) | three `tests/run.sh --changed --all` runs went past `docker preflight:` with the default floors; the suite stopped on the checkout issue above |

### Verification — dca25ea

Bootstrap mode (intent home's `Mode` line): no PR, no stage label, gates decided in this session; the release gate does not hold pushes to `main`.

- Machine: the product owner's Linux workstation, Ubuntu 26.04.1 LTS, Docker shared with another agent's work; `locale` → `LC_NUMERIC="fr_FR.UTF-8"` (`LANG=fr_FR.UTF-8`, `LC_ALL` empty, `LOCPATH` unset: *Deviations*); `awk -W version` → `mawk 1.3.4 20260129`; `TMPDIR=/home/jerome/.cache/c4-infra-tests`; `C4_DOCKER_REAP=labelled` on every run.
- **KO, pre-existing, not 0050's:** `bash tests/0049-docker-preflight.sh` (under the suite lock) → `KO - AC-07: the shim saw the preflight's reaping, before the tests` / `1 check(s) failed`, at dca25ea; the same KO at `c6a8872` (`main`) under fr_FR.UTF-8 (beside 4 KOs of 0050's bug there: AC-05, AC-09 ×3, `5 check(s) failed`) and under `LC_ALL=C` (diagnosis only, `1 check(s) failed`). Cause: the test's `$work/shim/docker` (lines 114-121) is never `chmod +x`, so on Linux `PATH` skips it and its log stays empty (a copy of the test keeping that log: 0 lines); Git Bash runs it anyway. AC-07's other check ("no prune nor removal during the tests") passes vacuously on Linux for the same reason. A bug intent for the product owner.
- **Not run:** `C4_DOCKER_REAP=labelled bash tests/run.sh --changed --all`: it restarts shared containers on this shared Docker (*Deviations*). PA-01's literal command and the stand-in and facts tests wait for a free Docker.
- Mutation check (mawk, no shim): `bash tests/0050-preflight-locale.sh` in a scratch worktree at `be2d214` → 9 KO (`AC-04 (C)` ×2; under fr_FR.UTF-8 `AC-01` ×2, `AC-02` ×2 with `docker preflight: VM disk: 115,3 GB free (floor 20)`, `AC-03`, `AC-04` ×2), last line `9 check(s) failed`; at dca25ea → `every check passed` (exit 0). The verifier reran both: same results.
- The preflight as `tests/run.sh` runs it (lines 378-386, under the shared lock `c4-infra.suite-lock`, taken at once; default floors, cleaning on), 2026-10-31 07:57:
  ```
  docker preflight: run 1793469428-2622432-743331067
  docker preflight: runs over: 0 container(s), 0 network(s), 0 volume(s), 0 image(s) removed
  docker preflight: kept, their path gone: 0 volume(s), 1 image(s) removed
  docker preflight: VM disk: 428.4 GB free (floor 20)
  docker preflight: VM memory: 7.0 GiB available (floor 3)
  docker preflight: host disk under Docker's disk image (/): 115.9 GB free (floor 20)
  docker preflight: host memory: 10.2 GiB MemAvailable + 1.2 GiB SwapFree (floor 6)
  preflight: exit 0
  -- tests/0050-preflight-locale.sh: exit 0, 0s, last line: every check passed
  -- tests/0049-docker-labels.sh: exit 0, 0s, last line: every check passed
  -- tests/0049-docker-preflight.sh: exit 1, 19s, last line: 1 check(s) failed
  ```
  `bash -n` on `tests/lib/docker-preflight.sh`, `tests/0050-preflight-locale.sh`, `tests/run.sh`: ok.
- `tests/0037-queue.sh` (the spec's suspected line 79), under the lock, fr_FR.UTF-8 → `every check passed` (exit 0, 41 s): it sets `LC_ALL=C` itself; no defect there.
- Rerun after the fixes: none (no Important finding).
- Durations: lock 0 s; bugs review 4m28s; preflight and library tests 24 s, the 0049 diagnosis reruns about 15 min; verifier 2m28s.
- Risk tier: standard (tests only; none of the intent home's high-risk rules).
- Reviews: bootstrap mode: 1 round, on c6a8872..dca25ea (`/home/jerome/workspaces/c4-infra-0050`); bugs (`code-review`, high): covered c6a8872..dca25ea, 0 Important, 0 fixed, 6 details, 2 pre-existing. The added comments are documentation comments only.
  - Details, the first five on the frozen test, kept: AC-02 doesn't exercise `_docker_size` nor the allocation line (`tests/0050-preflight-locale.sh:86`; the verifier checked both by hand under fr_FR: `2.0 GB`, `512.3 MB`, `0.0 GB`); the host floors are 0, so the host verdicts aren't compared under fr_FR (`:27`; checked by hand: a host-disk short line, exit 1, points); `locale -a | grep -q` under `pipefail` may SIGPIPE (`:56`); `"$short$room"` joined without a newline hides one line from the comma check (`:74`); AC-05 can't fail and nothing guards against a bare `awk` coming back (`:89`; today `grep` finds only `_docker_awk`'s own). The handover assumes the real mawk (`HANDOVER.md:23`): here `awk` is mawk, checked. The bound's check repeats `_docker_floor`'s (`tests/lib/docker-preflight.sh:204`): maintainability.
- Verifier: 12/14 criteria OK, 1 KO (AC-06: `0049-docker-preflight` AC-07, pre-existing above), 1 not verifiable (PA-01's literal command).
- Not verifiable here: PA-01's `tests/run.sh --changed --all` and AC-06's stand-in and facts part (`tests/0049-docker-reap.stand-in.sh` would also recreate the shared, unlabelled stand-in volume): for a run on a Docker no one else uses.
- Files outside the plan: `spec.md` (intent document, the approved spec).
- Pre-existing findings (not fixed, out of scope): `0049-docker-preflight.sh`'s shim not executable on Linux (KO above) → bug intent suggested; `_docker_short` compares the rounded values (`tests/lib/docker-preflight.sh:326`, 2.995 GiB shown `3.0` passes a floor of 3); `df` run twice and `/proc/meminfo` read three times (`:338-360`).

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `tests/0050-preflight-locale.sh` (mawk, fr_FR.UTF-8 and C) → `every check passed`; KO at be2d214 |
| AC-02 | OK | same test (`VM disk: 115.3 GB`, no `[0-9],[0-9]`); `_docker_size` and the allocation line checked by hand under fr_FR |
| AC-03 | OK | same test: `_docker_bytes 1.5GB 512.3MB` → `2012300000` under both |
| AC-04 | OK | same test: `(floor 2.5)`, `2,5,1` and `abc` refused, bound `2,5` → `--max-used-space 2500000000`; real Docker: `(floor 2.5)`, `(floor 0.5)`, exit 0 |
| AC-05 | OK | same test; the verifier's driver: `LC_ALL` unset, `printf 1,5` → `1,5` after six library calls |
| AC-06 | KO (pre-existing) | `0049-docker-labels` passed; `0049-docker-preflight` AC-07 KO at dca25ea and at c6a8872; stand-in and facts not run |
| PA-01 | stand-in OK; literal command not run | run.sh's lock take and preflight with the default floors under fr_FR.UTF-8 → `preflight: exit 0`, every measure with a point |
| IV-01, IV-02 | OK | functions and `docker preflight:` lines unchanged but `_docker_awk`; the one `LC_ALL=C` is the prefix in `_docker_awk` |
| RQ-01 to RQ-05 | OK | as AC-01 to AC-04; no bare `awk` left, 14 `_docker_awk` calls |
- 2026-10-31 — merged into `main` as `98c6737` and pushed; deploy-demo run 41245803288 on `98c6737`: `success` (its two jobs); nothing the demo host runs changes.
