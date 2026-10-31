# Spec: The Docker resources the suite's runs leave behind are never reclaimed

- Intent: [0049](intent.md)
- Status: draft
- Version: 1
- Risk: standard (no risk rule applies: the suite's harness and Docker housekeeping on a workstation; the demo host never runs it, IV-02; no secret, nothing exposed to the network; what another application or project uses is never removed, IV-01)
- Policies applied: none (the project has none yet)
- Approved: —

## Summary

Every resource c4-infra's tests and libraries create on the workstation's Docker carries the label contract of the skills' 0122 and is removed by its creator on every exit; what a killed run leaves is reaped at the next take of the suite's lock. A new library beside the lock, `tests/lib/docker-preflight.sh`, the one code c4-infra's suite, the skills' suite (from c4-infra's `main`) and generated projects (through `C4_INFRA_DIR`) use, cleans first, then measures Docker's disk and memory and stops a run that can't finish, before its first test. Nothing unlabelled that another project, session or the dev stack uses is ever removed, and no cleaning overlaps a running test.

## Requirements

- **RQ-01:** Every container, network, volume and image tag a c4-infra test or library creates on the host's Docker for one run carries the run labels of the *Label contract* (owner `c4-infra`, run, creation time, time to live); a resource kept between runs on purpose (a stand-in's volume, the images `c4-infra/stand-in-host` and `c4-test/probe`) carries the owner and the `keep` path of RQ-07. What runs inside a stand-in's own Docker is not concerned: it lives in the stand-in's volume. (intent: outcome, "a label contract every creator sets")
- **RQ-02:** A test removes what it created when it ends, passed, failed, interrupted (`INT`, `TERM`) or stopped by `timeout`: `docker rm -f -v`, its networks, its volumes, and the tags it built (`c4-infra/keycloak:before`, `c4-infra/keycloak:before-0016`). (intent: outcome, "`rm -f -v`, their extra tags removed")
- **RQ-03:** A run killed with `kill -9`, or cut by a stopped engine, leaves only labelled resources, and the preflight of the next run that takes the suite's lock on that Docker removes those whose run is over (PA-01). (intent: success criterion, "a run killed with `kill -9` leaves nothing the next lock take doesn't reclaim")
- **RQ-04:** Without a label, the cleaning removes only: build cache beyond a bound (`docker buildx prune --max-used-space`), anonymous volumes no container uses (Docker 29 labels them `com.docker.volume.anonymous`), and the images of a repository the `--pins` file names that no tag names any more and no container uses (an image the pin's rebuild or pull replaced). (intent: "then, without a label, only build cache beyond a bound, anonymous volumes no container uses, and the images a pin given to it replaced")
- **RQ-05:** The library is one file, `tests/lib/docker-preflight.sh`, sourced, depending on bash, coreutils, `awk`, `sed` and the docker CLI only (no `jq`, no other file of c4-infra), so that the skills read it with `git show main:…` as they read the lock; it offers the functions and variables of *API and contracts*, which the skills' plan for 0122 calls. (intent: "the one code that c4-infra's suite, the skills' suite … and the generated projects' `verify.sh` use"; PA-03 A of the skills' spec)
- **RQ-06:** The run that holds the suite's lock (PA-02) runs `docker_preflight` before its first test: it cleans (RQ-03, RQ-04), then measures the *Resources measured*; the run starts when each meets its floor, else it stops before any test, exit status 1, naming each resource short, its measure, its floor and what a human can do. `--no-clean` measures only, for a caller that doesn't hold the lock. (intent: "a preflight that the holder of the suite's lock runs before its first test")
- **RQ-07:** A stand-in's Docker volume carries `c4-infra.keep=<path>` (PA-03), and the reaper removes a volume whose `keep` path no longer exists on the machine, when no container uses it. (intent: "the stand-in's volume labelled `keep` with its checkout"; problem, the orphan stand-in volumes)
- **RQ-08:** Nothing in the library or the suite stops, restarts or resets Docker Desktop, or compacts its disk image; when the host's side of Docker's disk is short, the preflight says so and gives the human's procedure for the platform. (intent: constraint "Docker Desktop is shared")
- **RQ-09:** Each preflight prints one line per class it cleaned (count, bytes reclaimed) and one per measure with its floor, prefixed `docker preflight:`; the run's output keeps them. (intent: open question, floors "tuned from the preflight's lines after a week")
- **RQ-10:** No cleaning beyond a creator's own resources runs while a test may run: the reaper and the unlabelled classes run only from the preflight, under the suite's lock, before the first test. (intent: constraint "no cleaning while a test that measures time may run")
- **RQ-11:** A test of the cleaning touches only what it created: `C4_DOCKER_LABEL_NS` gives its resources and its reaper a label namespace of its own, and `C4_DOCKER_REAP=labelled` skips the unlabelled classes; `C4_DOCKER_PREFLIGHT=off` skips the preflight for a run (the tests that copy `tests/run.sh` onto a lock of their own: 0017, 0022, 0037). (intent: "a test's own label namespace and a mode that skips the unlabelled classes")
- **RQ-12:** The library and the reaper work alike under bash on Linux and under Git Bash on Windows with Docker Desktop on WSL2: the host's memory from `/proc/meminfo` (`MemAvailable`, or `MemFree` where Git Bash gives no `MemAvailable`) plus `SwapFree`; the host's disk from the directory holding Docker's disk image; paths given to the docker CLI under `MSYS_NO_PATHCONV=1` as CLAUDE.md says. (intent: constraint "Linux and Windows")
- **IV-01:** The cleaning never removes a container it didn't label (running or stopped), a named volume it didn't label, a tagged image of a repository the pins don't name, anything a container uses (its image, its volumes), the suite lock's and the queue's containers, nor the dev stack's volumes and images.
- **IV-02:** The demo host never runs the library: it isn't in `demo/deploy-files.txt`, and nothing under `demo/` sources it.

## Out of scope

- The skills' and the generated projects' own creators and their call of the preflight: the skills' 0122.
- Docker Desktop's settings (a disk cap, its memory) and the compaction of its disk image: human actions (RQ-08).
- What a stand-in's own Docker holds inside its volume: the volume is kept or removed whole.
- The projects' long-lived stacks and volumes (the dev stack, `faito_rest_api_data`, `anahei-dev_postgres_data`, `trivy-cache`): never reaped (IV-01).

## Design

### Current behaviour (at 4dce438)

| Creator | Creates on the host's Docker | Left behind |
| --- | --- | --- |
| Suite lock and tickets (`tests/lib/suite-lock.sh:29-56`, labels `c4-infra.suite.worktree`, `.started`, `.queue`) | `alpine:3`, `--rm`, fed by a pipe from the run | nothing: gone with the pipe |
| `tests/run.sh:375` | takes the lock whenever it runs a test, then `in_lanes` (`:229-283`) or `in_turn`; no run id, no measure of disk or memory (only `SUITE_DOCKER_MEMORY`, for the number of lanes, `:232`) | — |
| Stand-in lanes (`tests/run.sh:244-251`, `tests/lib/stand-in-host.sh:66-68`) | `c4-infra-stand-in` with volume `c4-infra-stand-in-docker`, `c4-infra-stand-in-2` with `c4-infra-stand-in-2-docker`: two fixed names, shared by every checkout of the machine (one run at a time per Docker) | the volumes, on purpose (`stand_in_down`, `:295-299`, removes the container only; `STAND_IN_FRESH=1` removes the volume at the next `stand_in_up`, `:97-99`); no label |
| `stand_in_up` (`:94`), `stand_in_probe` (`:138`) | images `c4-infra/stand-in-host`, `c4-test/probe` (labelled `c4-infra.fixture=<hash>`) | the images, on purpose; the earlier build, untagged, after a change |
| `tests/0013-upgrade.stand-in.sh:100`, `tests/0016-simulated.stand-in.sh:84` | tags `c4-infra/keycloak:before`, `c4-infra/keycloak:before-0016` | the tags, every run |
| 23 tests and libraries with `docker rm -f` without `-v` (among them `tests/0003-demo-edge.sh:32`, `tests/0009-master-import-facts.sh:47`, `tests/0006-keycloak-facts.sh:48`, `tests/0013-keycloak-facts.sh:46`, `tests/0016-keycloak-facts.sh:45`, `tests/0029-image-facts.sh:39`) | throwaway containers of `caddy:2.11.4-alpine`, `c4-infra/keycloak`, `c4-infra/reverse-proxy` | today nothing more: none of these images declares a `VOLUME` (`docker image inspect … .Config.Volumes`: `null` for each, measured); the `postgres` runs already pass `-v` (`tests/0007-listeners.sh:49`) or a named volume (`tests/0009-master-realm.sh:37`, `tests/0012-import-facts.sh:43`) |
| Tests that copy the suite (`tests/0017-run.sh:24`, `tests/0022-lanes.sh:26-27`, `tests/0037-queue.sh`) | a lock of their own, fake stand-ins `c4-infra-stand-in-<test>-$$` | their cleanup removes their containers (`0017-run.sh:25-33`, `0022-lanes.sh:31-39`) |

Nothing labels an owner but the lock (`c4-infra.suite.*`), the probe (`c4-infra.fixture`) and 0024 (`c4-infra.test`).

### Measures (this workstation, 2026-10-30, read-only plus one labelled `docker run --rm alpine:3`; no suite run in progress)

- Docker 29.9.2 client and server, Docker Desktop on WSL2 (kernel 5.15.153.1), containerd's image store (`overlayfs`, `io.containerd.snapshotter.v1`); `docker info` `MemTotal` 8 197 271 552 bytes (7.63 GiB); 7 containers running (the dev stack and `faito.rest-api-db`).
- `docker system df`: images 51, 15.64 GB (8.21 reclaimable); volumes 47, 13.17 GB (12.14 reclaimable); build cache 316 records, 13.94 GB (9.99 reclaimable).
- Volumes: `c4-infra-stand-in-docker` 6.59 GB, unattached, unlabelled, the only stand-in volume (no orphan of a gone checkout here); `trivy-cache` 4.60 GB; 30 anonymous volumes, 831 MB, created 2026-08-31 to 2026-10-24 (none since; some before c4-infra existed, 2026-10-21); other projects' named volumes (`anahei-dev_postgres_data`, `faito_rest_api_data`).
- Tags no current test creates: `c4-infra/keycloak:0013`, `:0012-dev`, `:26.7` (6 to 9 days old); `c4-infra/keycloak:before`, `:before-0016` (the two tests above). `localhost:50290/facts/probe`, which the intent names, isn't here and no c4-infra test creates it.
- The VM (in the throwaway): `df -P /` 1 055 762 868 KiB, 961 156 136 free (917 GiB, the WSL2 disk's virtual size); `MemAvailable` 5 162 408 kB (4.92 GiB), `SwapFree` 1 540 412 kB of 2 GiB.
- The host: `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx` 55.51 GB, on `C:`, 462 GB free (`df -P /c`: 484 800 572 KiB available): the VM's free space overstates the host's by half. Git Bash's `/proc/meminfo` gives `MemTotal`, `MemFree` 3 862 012 kB, `SwapTotal`, `SwapFree` 26 367 332 kB, no `MemAvailable`; Windows' own *available* is 3 494 MiB (`Win32_PerfFormattedData_PerfOS_Memory`), `FreePhysicalMemory` 3 829 052 kB.
- Against the skills' floors (PA-02 A there): VM disk 917 GiB ≥ 20 GB, host disk 462 GB ≥ 20 GB, VM memory 4.92 GiB ≥ 3 GiB, host memory plus swap 3.7 + 25.1 GiB ≥ 6 GiB: a run starts. The build cache bound of 5 GB prunes about 9 GB at the first preflight (then rebuilds of `c4-infra/keycloak` and the stand-in's images cost their build time once).
- `docker buildx` 0.38.1 has `prune --max-used-space`; a volume's labels can't be changed once it exists (`docker volume update` is for cluster volumes only).

### Behaviour per persona

- **Developer, Agent:** a run takes the lock, then prints `docker preflight: 3 containers, 1 volume, 1 network of runs over removed`, `docker preflight: build cache 8.9 GB reclaimed (bound 5 GB)`, `docker preflight: host disk under Docker's disk image 462 GB free (≥ 20)`, `docker preflight: VM memory 4.9 GiB available (≥ 3)`… and starts its first test; or stops, exit 1, with `docker preflight: the drive holding Docker's disk image (C:) has 9 GB free, 20 needed after cleaning; docker_data.vhdx allocates 55 GB: compacting it needs Docker Desktop stopped (a human's action: …)`.
- **The skills, a generated project:** the same library, read from c4-infra's `main`, through the API below (the skills' 0122).

### API and contracts

**Label contract** (the skills' 0122, fixed here; `<ns>` is `C4_DOCKER_LABEL_NS`, `c4-infra` by default): `<ns>.owner=<repository or project>`, `<ns>.run=<run id>`, `<ns>.created=<epoch seconds>`, `<ns>.ttl=<seconds>` for a run's resources; `<ns>.owner` and `<ns>.keep=<absolute path, as the creating shell writes it>` for a resource kept between runs, an orphan once that path is gone. A run is over when its time to live has passed, or as PA-01 decides.

**Functions** (sourced from `tests/lib/docker-preflight.sh`):

- `docker_labels <owner> [ttl]`: prints the `--label` arguments of a run's resource, one per line (default ttl: 14 400 s); `C4_INFRA_RUN` is set and exported when the library is sourced and it is unset, so that a command substitution sees the same run id.
- `docker_keep_labels <owner> <path>`: the same for a kept resource.
- `docker_reap [--pins <file>]`: removes the labelled resources whose run is over and the kept ones whose path is gone, then, unless `C4_DOCKER_REAP=labelled`, RQ-04's classes; one line per class (RQ-09).
- `docker_preflight [--no-clean] [--pins <file>]`: `docker_reap` unless `--no-clean`, then the measures; exit 0, or 1 with RQ-06's lines.

**Environment:** `C4_INFRA_RUN`, `C4_DOCKER_LABEL_NS`, `C4_DOCKER_REAP=labelled`, `C4_DOCKER_PREFLIGHT=off`; the floors `C4_DOCKER_MIN_VM_DISK_GB` (20), `C4_DOCKER_MIN_HOST_DISK_GB` (20), `C4_DOCKER_MIN_VM_MEMORY_GIB` (3), `C4_DOCKER_MIN_HOST_MEMORY_GIB` (6), the build cache bound `C4_DOCKER_BUILD_CACHE_GB` (5), and `C4_DOCKER_DISK_DIR`, the directory holding Docker's disk image (by default Docker Desktop's: `~/.docker/desktop/vms/0/data` on Linux, `$LOCALAPPDATA/Docker/wsl/disk` on Windows; none found: the host's disk line says it isn't measured).

**Resources measured:** Docker's free disk in the VM and its available memory (`df -P /` and `/proc/meminfo` in a labelled `alpine:3` throwaway, `--rm`); the host's free disk under `C4_DOCKER_DISK_DIR`; the host's available memory plus free swap (RQ-12).

**c4-infra's pins file:** the images `compose.yml` and its overrides name, the image `keycloak-image.properties` describes, and the images the tests run (`caddy:2.11.4-alpine`, `alpine:3`, `bash:5.2`, the stand-in's base), one reference per line, printed by a script of the suite from those sources.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy yet; the intent's constraints → RQ-08, RQ-10, IV-01; CLAUDE.md's Git Bash rules → RQ-12 |

## Points of attention

### PA-01: When is a run over

- Issue: the intent's open question. The time to live alone leaves a killed full run's resources (75 min, one lane) for hours; the suite's lock already tells which run is alive: a run killed with `kill -9` keeps the lock until its lanes' tests end (`tests/run.sh:202-203`), so a run that takes the lock knows every earlier holder is over. Tests run alone (`bash tests/<test>.sh`) and generated projects' `verify.sh` hold no lock.
- Options: **A** the time to live alone / **B** the time to live, plus: a resource labelled `<ns>.lock=<lock name>` (set by `docker_labels` when its run holds that lock) is over once another run holds that lock / **C** a liveness container per run, fed by its pipe as the lock is, the resource over once it's gone.
- Recommendation: B: a killed run is reclaimed at the very next lock take, with no extra container; A stays for the runs without the lock. The label is new to the skills' contract: their spec needs a v2 (additive). C adds a container to every run, and to every test run alone, for what the lock already says.
- Decides: PO
- Decision: to decide

### PA-02: Which runs run the preflight

- Issue: c4-infra's runs all take the lock (`tests/run.sh:375`), the quick `--changed` ones included; the skills run the preflight for a run with a slow test, and clean at each lock take (their PA-04 A).
- Options: **A** every run, at its lock take / **B** only a run with a stand-in or a facts test / **C** only `--all`.
- Recommendation: A: the reaping at each lock take is the skills' decision, and a quick run is the one most likely to follow a killed one; its cost (a few `docker` listings, one throwaway, the cache prune when over its bound) is measured at the plan's first step and recorded.
- Decides: PO
- Decision: to decide

### PA-03: The stand-in volumes' `keep` label

- Issue: the two lane volumes have fixed names shared by every checkout of the machine; the one here (6.59 GB) has no label, and Docker can't add one to an existing volume.
- Options: **A** `keep=<the clone>` (the directory above `git rev-parse --git-common-dir`, shared by its worktrees), and `stand_in_up` recreates once a stand-in volume of its own names that lacks the label (one slower first run: its images pulled again) / **B** `keep=<the checkout>` (`STAND_IN_ROOT`), the same adoption: removing a worktree that created the shared volume makes it an orphan / **C** the fixed names exempt, no label: an orphan only for a `STAND_IN_VOLUME` a caller names.
- Recommendation: A: the volume serves the clone, not one worktree, and a single re-pull adopts the existing one; B reaps a volume the main checkout still uses; C leaves the intent's orphans (per-checkout volumes named by callers) to a rule the reaper can't check.
- Decides: PO
- Decision: to decide

### PA-04: The tags no current test creates

- Issue: `c4-infra/keycloak:0013`, `:0012-dev`, `:26.7` (756 to 763 MB each, sharing layers, unused) carry no label; IV-01 keeps them, and RQ-02 only covers the tags the tests create from now on.
- Options: **A** listed in the delivery's plan and removed once, with the PO's go, when no container uses them / **B** the reaper removes every unused tag of `c4-infra/keycloak` but the one `.env` names / **C** left to the Developer.
- Recommendation: A: a one-time removal; B gives the reaper a rule on a repository a Developer may tag by hand.
- Decides: PO
- Decision: to decide

## Acceptance criteria

- **AC-01:** Given a run of `tests/run.sh --all`, when it ends, then no container, network, volume or image labelled with its run id remains, and neither `c4-infra/keycloak:before` nor `:before-0016`. (RQ-01, RQ-02)
- **AC-02:** Given the tests and libraries of `tests/`, then every `docker run`, `create`, `build`, `network create` and `volume create` on the host's Docker passes the labels' helper, and every `docker rm -f` has `-v`. (RQ-01, RQ-02)
- **AC-03:** Given a fake run on a lock of the test's own that created a container, a volume and a network with the test's namespace, killed with `kill -9`, when the next fake run takes that lock, then its preflight removes them and prints their count (with `C4_DOCKER_REAP=labelled`). (RQ-03, RQ-09, RQ-11)
- **AC-04:** Given, in a stand-in of the test's own, a stopped container, a named volume and a tagged image without labels, a pinned image a container uses, an unattached anonymous volume, an image a pin's rebuild replaced, and build cache over the bound, when the preflight cleans with that pins file, then the first four remain and the other three are removed (the cache down to its bound). (RQ-04, IV-01)
- **AC-05:** Given a floor set above what is free after cleaning, when a run starts, then it exits 1 before any test with RQ-06's lines; with `C4_DOCKER_PREFLIGHT=off` it starts. (RQ-06, RQ-11)
- **AC-06:** Given a stand-in volume whose `keep` path is gone and no container using it, when the preflight cleans, then it is removed; a stand-in volume whose path exists remains. (RQ-07)
- **AC-07:** Given a run whose lanes run tests, when they run, then no reaping or prune command runs between the first test's start and the last test's end (a `docker` shim's log). (RQ-10)
- **AC-08:** Given the library, then it sources no file, calls no `jq`, and no path of it calls `docker desktop restart|stop|reset`, `wsl --shutdown`, `systemctl … docker` or a disk compaction. (RQ-05, RQ-08)
- **AC-09:** Given this workstation (Git Bash, Docker Desktop on WSL2), when AC-03 to AC-06 run, then they pass, and the preflight's lines give the host's memory from `MemFree` and `SwapFree` and the host's disk from `C:`. (RQ-12)

## Intent questions

- Each test's own disk and memory need: the floors start fixed (the skills' PA-02 A, env-overridable) and are tuned from RQ-09's lines after a week → RQ-06, RQ-09; this workstation passes them today (*Measures*).
- The reaper's run liveness → PA-01.

## Change log

- v1 — 2026-10-30 — first version
