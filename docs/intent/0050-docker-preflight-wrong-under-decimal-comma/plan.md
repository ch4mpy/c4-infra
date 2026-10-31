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

## Verification
