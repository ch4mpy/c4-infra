# Intent: The suite's Docker preflight refuses every run on a machine whose locale writes a decimal comma

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent in the skills' batch (`ch4mpy/claude`, branch `batch-2026-10-29`, intent 0122's step 3)
- Kind: bug
- Source: conversation (2026-10-31, found by the skills' 0122 worker on the product owner's Linux workstation)
- Spec needed: yes
- Status: proposed
- Opened: 2026-10-31
- Decided: —
- Supersedes: —
- Mode: bootstrap

## Problem

On a machine whose numeric locale writes a decimal comma (`LC_NUMERIC=fr_FR.UTF-8`, the product owner's Linux workstation), `tests/lib/docker-preflight.sh` (0049) finds every measure "short" and refuses the run: `docker preflight: short: … has 115,3 GB free, 20 needed`. c4-infra's own suite refuses every run there. The skills' `tests/run.sh` and generated projects' `verify.sh` call the library under `LC_ALL=C` to work around it (skills' 0122, `1c072bc`).

- Steps to reproduce: on that workstation, `tests/run.sh` with a slow test, the preflight on.
- Expected: the preflight compares the measures with the floors and passes when there is room.
- Observed: the measures are formatted with `printf "%.1f"` in awk (`vm_disk`, `vm_memory`, `host_disk`), which under that locale prints `115,3`; the comparison `awk -v m="$1" -v f="$2" 'BEGIN { exit !(m < f) }'` then reads it as `115` or as a string, and the run is refused. Reproduced with mawk 1.3.4: `m=$(awk 'BEGIN{printf "%.1f", 115.34}')` prints `115,3`, and the comparison with 20 says short. gawk honours `LC_NUMERIC` the same way with `--use-lc-numeric` or POSIX mode; Git Bash on Windows may differ.
- Environment: Ubuntu, mawk 1.3.4 20260129, `LANG=fr_FR.UTF-8`; Docker Desktop.

## Proposed outcome

The preflight gives the same verdict whatever the caller's locale, on Linux and on Windows (Git Bash), and its messages print numbers one way. Success: c4-infra's suite runs on the product owner's Linux workstation with its default locale, and a test runs the preflight's measures and comparisons under a decimal-comma locale and under `C`, with the same verdicts. Callers no longer need `LC_ALL=C` (the skills can then drop theirs).

## Affected users and systems

- Developer, Agent; c4-infra's suite and every caller of `tests/lib/docker-preflight.sh` (the skills' `tests/run.sh`, generated projects' `verify.sh`).

## Constraints

- The library's contract (its function names, its output lines, the thresholds' names `C4_DOCKER_MIN_*`, `C4_DOCKER_BUILD_CACHE_GB`) stays as 0049 delivered it: the skills read it.
- It keeps needing only bash, coreutils, awk, sed and the docker CLI.

## Open questions

- Fix inside the library (set `LC_ALL=C` for its own awk calls) or compare in integers? — spec.
- Does a decimal-comma locale also affect the thresholds a user sets (`C4_DOCKER_BUILD_CACHE_GB=2,5`)? — spec.
