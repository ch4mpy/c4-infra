# Spec: The suite's Docker preflight refuses every run on a machine whose locale writes a decimal comma

- Intent: [0050](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the suite's own housekeeping library, on the workstation; nothing an application or a host exposes)
- Policies applied: none (the project has no policy yet)
- Approved: 2026-10-31, Jérôme Wacongne (in the drafting session; every point of attention decided)

## Summary

`tests/lib/docker-preflight.sh` (0049) formats its measures and reads docker's sizes with awk, which, on an awk that honours the numeric locale, writes and reads numbers with a decimal comma: under `fr_FR.UTF-8` every measure compares as "short" and every run with a slow test is refused. The preflight's verdicts, the numbers it prints and the sizes it reads become the same whatever the caller's locale, on Linux and under Git Bash, without changing its contract; a floor or a bound written with a decimal comma is read as the same number as with a point.

## Requirements

- **RQ-01:** Under any locale the caller sets, `docker_preflight` compares each measure (Docker's VM disk and memory, the host's disk, the host's memory and swap) with its floor numerically and gives the verdict it gives under `C` for the same measures and floors. (intent: proposed outcome, "the same verdict whatever the caller's locale")
- **RQ-02:** Every number the library prints (measures, floors, sizes reclaimed, the disk image's allocation) is written with a point as decimal separator, whatever the locale. (intent: "its messages print numbers one way"; the PO, 2026-10-31: verdicts and messages)
- **RQ-03:** The sizes the library reads from docker's output (`1.5GB`, `512.3MB`…) are read with their decimal part whatever the locale, so that the totals it prints are the same as under `C`. (the PO, 2026-10-31: verdicts and messages)
- **RQ-04:** A floor (`C4_DOCKER_MIN_VM_DISK_GB`, `C4_DOCKER_MIN_HOST_DISK_GB`, `C4_DOCKER_MIN_VM_MEMORY_GIB`, `C4_DOCKER_MIN_HOST_MEMORY_GIB`) or the build cache's bound (`C4_DOCKER_BUILD_CACHE_GB`) written with a decimal comma (`2,5`) is taken as the same number as with a point (`2.5`), whatever the locale; the messages print it with a point. Any other value is refused as today ("not a number"). (the PO, 2026-10-31: accept both)
- **RQ-05:** A caller no longer needs to set `LC_ALL=C` around the library to get RQ-01 to RQ-04. (intent: "Callers no longer need `LC_ALL=C`")
- **IV-01:** The library's contract stays as 0049 delivered it: its function names, arguments and return codes, its output lines (`docker preflight: …`) apart from the numbers' separator, the variables' names, and the library needs only bash, coreutils, awk, sed and the docker CLI. (intent: constraints)
- **IV-02:** The library changes no locale variable in its caller's shell: a script that sources it keeps its own locale for what it runs afterwards. (intent: the library is sourced by the suite, the skills and generated projects)

## Out of scope

- The skills' `LC_ALL=C` around the library (`ch4mpy/claude`, 0122): theirs to drop once this is on `main`.
- The rest of c4-infra's suite under a decimal-comma locale: `tests/run.sh` already reads `EPOCHREALTIME` with either separator (`tests/run.sh:163`); `tests/0037-queue.sh:79` hands `$EPOCHREALTIME` to awk with `-v`, which under that locale may lose its fraction (not reproduced here). A defect the PO's run finds there (PA-01) is a new intent.
- Integer thresholds or another unit for the floors: their names and units stay (IV-01).

## Design

### Current behaviour

Reproduced in a throwaway `ubuntu:24.04` with mawk 1.3.4 and `LC_ALL=fr_FR.UTF-8` (2026-10-31):

| Command | Output |
| --- | --- |
| `awk 'BEGIN{printf "%.1f", 115.34}'` | `115,3` |
| `awk -v m=115,3 -v f=20 'BEGIN{print (m < f)}'` | `1` (compared as strings) |
| `awk -v m=115.3 -v f=20 'BEGIN{print (m < f)}'` | `0` |
| `echo 1.5GB \| awk '{ n=$0; sub(/[A-Za-z]+$/, "", n); print n * 1e9 }'` | `1000000000` |
| `awk -v f=20.5 'BEGIN{print f + 0}'` | `20,5` (read right, printed with a comma) |

- The measures are formatted by awk's `printf "%.1f"` (`tests/lib/docker-preflight.sh:309`, `:310`, `:331`, `:352`, `:353`), then compared by `_docker_short` (`:270`-`:271`): `115,3` against `20` is a string comparison, true, and the run is refused.
- `_docker_bytes` (`:122`) reads docker's sizes from its input: under that locale `1.5GB` counts as 1 GB; `_docker_size` (`:129`) and the disk image's allocation (`:344`) print with a comma.
- The floors and the bound are checked by `^[0-9]+([.][0-9]+)?$` (`:199`, `:263`): `2,5` is refused, "not a number".
- Under Git Bash, gawk 5.4.1 ignores the locale's separator by default and honours it in POSIX mode (`POSIXLY_CORRECT=1`: `115,3`); the workstation has `fr_FR.UTF-8`.

### Behaviour per persona

- **Developer** (Linux workstation, French locale): `bash tests/run.sh` with a slow test gets past the preflight when Docker has room, and its `docker preflight:` lines show `115.3 GB`, as under `C`.
- **Application** (a generated project's `verify.sh`, the skills' `tests/run.sh`): sources the library without `LC_ALL=C` and gets the same lines and return codes.

### API and contracts

Unchanged (IV-01), apart from:

- the floors' and the bound's accepted form: `^[0-9]+([.,][0-9]+)?$`, a comma read as a point (RQ-04);
- the numbers in the lines: always a point (RQ-02).

The library's header says that its numbers don't depend on the locale, and that a floor may be written with either separator.

Approach proposed (technical; the plan details it): the library runs its own awk calls with the numeric locale set to `C` for those calls only (an environment prefix on each call, or one wrapper), which fixes output, input and comparison at once and leaves the caller's locale alone (IV-02). Alternative considered: compare integers (kB, MiB) in bash: it fixes the verdicts but neither the sizes read from docker nor the printed numbers (RQ-02, RQ-03), and changes more lines.

### User interface

The `docker preflight:` lines, numbers with a point, e.g. `docker preflight: short: Docker's disk has 15.3 GB free, 20 needed after cleaning: …`; a floor given as `2,5` printed `2.5`.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy; the standing constraints of `CLAUDE.md` hold: scripts run under Git Bash and on Ubuntu, the tests sort with `LC_ALL=C sort` |

## Points of attention

### PA-01: The intent's success on the Linux workstation is checked by hand

- Issue: the intent's success criterion is "c4-infra's suite runs on the product owner's Linux workstation with its default locale". This workstation (Windows, Git Bash) can prove the library's behaviour under a decimal-comma locale (AC-01 to AC-05), not a whole run on that Linux machine, which other locale-dependent lines of the suite might still stop (Out of scope).
- Options: A, after delivery, the product owner runs `bash tests/run.sh --changed <base>` (or `--all`) on the Linux workstation with its default locale, and its last lines go into the plan's `## Verification`; a KO outside the library becomes a new intent / B, the stand-in host gets a French locale and runs the suite under it (a stand-in doesn't run the suite today: new machinery, out of this intent's size).
- Recommendation: A, because the library's behaviour is fully proven here and the remaining risk is elsewhere in the suite, where a new intent fits.
- Decides: PO
- Decision: A (the PO, 2026-10-31)

## Acceptance criteria

- **AC-01:** Given an awk that honours the numeric locale (mawk, or gawk in POSIX mode) and `LC_ALL=fr_FR.UTF-8`, when the preflight compares measures above and below their floors (e.g. 115.3 against 20, 2.4 against 3), then its verdicts and return code are the same as under `LC_ALL=C`. (RQ-01, RQ-05)
- **AC-02:** Given the same locale, when the preflight prints a measure, a floor, a size reclaimed or the disk image's allocation, then every number is written with a point and none with a comma. (RQ-02)
- **AC-03:** Given the same locale, when the library sums docker's sizes `1.5GB` and `512.3MB`, then it gets 2012300000 bytes, as under `C`. (RQ-03)
- **AC-04:** Given `C4_DOCKER_MIN_VM_DISK_GB=2,5` (and `C4_DOCKER_BUILD_CACHE_GB=2,5`), under `C` and under `fr_FR.UTF-8`, when the preflight runs, then the floor is 2.5 (the bound 2.5 GB), printed `2.5`; given `C4_DOCKER_MIN_VM_DISK_GB=2,5,1` or `abc`, then it is refused with the "not a number" line, as today. (RQ-04)
- **AC-05:** Given a shell under `fr_FR.UTF-8` that sources the library and runs `docker_preflight`, when it then runs `printf '%.1f\n' 1,5` (bash's own printf, locale-dependent), then it prints `1,5`: the caller's locale is untouched. (IV-02)
- **AC-06:** Given the suite's existing tests of the library (`tests/0049-docker-preflight.sh`, `tests/0049-docker-reap.stand-in.sh`, `tests/0049-docker-labels.sh`), when they run, then they pass unchanged. (IV-01)

## Intent questions

- Fix inside the library (set `LC_ALL=C` for its own awk calls) or compare in integers? → inside the library, the numeric locale set to `C` for its own awk calls only: it covers the verdicts, the printed numbers and the sizes read from docker; integers would cover the verdicts only (Design, "Approach proposed"; the plan decides the form).
- Does a decimal-comma locale also affect the thresholds a user sets (`C4_DOCKER_BUILD_CACHE_GB=2,5`)? → today they're refused, "not a number" (`tests/lib/docker-preflight.sh:199`, `:263`), whatever the locale; the PO, 2026-10-31: accept both separators (RQ-04).

## Change log

- v1 — 2026-10-31 — first version
- v1 — 2026-10-31 — approved by the PO in the drafting session; PA-01: A
