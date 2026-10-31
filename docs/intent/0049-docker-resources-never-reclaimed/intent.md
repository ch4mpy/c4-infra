# Intent: The Docker resources the suite's runs leave behind are never reclaimed

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (2026-10-30, Docker Desktop's engine stopped three times on the product owner's
  Linux workstation; the twin of the skills' intent 0122, whose spec is approved), drafted in the skills'
  repository (`ch4mpy/claude`, branch `batch-2026-10-29`, 6d2b2b3c,
  `docs/intent/0122-docker-resources-never-reclaimed/c4-infra-twin-intent.md`) and taken into c4-infra's
  batch by the product owner on 2026-10-30
- Spec needed: yes
- Status: planned
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

The suite's runs, the skills' runs that share its lock, and the projects generated from the skills
pile up resources in Docker Desktop, and nothing reclaims them. On 2026-10-30 the engine stopped
three times ("Docker Desktop is unable to start"), each time taking the suite's lock and every
running test down with it:

- its virtual disk had grown to 132 GB; a prune reclaimed 9.9 GB of build cache and a 10.1 GB image;
- two stand-in volumes of checkouts gone for days held 8.5 and 6.4 GB (`STAND_IN_VOLUME` of
  per-checkout stand-ins: `stand_in_down` keeps the volume on purpose, and nothing removes it once
  its checkout is gone);
- the third stop came from memory exhaustion while several agents built; the host's swap was raised
  from 4 to 16 GB.

Measured on the workstation the same day (Docker 29.6.1, containerd's image store):

- the tests that start containers on the host (`0003-demo-edge.sh`, `0009-master-import-facts.sh`
  and others) remove them with `docker rm -f` without `-v`: anonymous volumes of images that declare
  a `VOLUME` stay (two unlabelled volumes of 48.5 MB that night, which no one can trace);
- tags `c4-infra/keycloak:before`, `:before-0016` and `localhost:50290/facts/probe` stay after the
  runs that made them;
- images pulled by digest show `<none>` without being dangling: `docker image prune` reclaims
  nothing, `-a` would take every pin and other projects' images;
- inside the VM 429 GB are free while the host's file `Docker.raw` allocates 132 GB for 27 GB used:
  the VM never gives freed blocks back to the host, so its own free space overstates what's left;
- no run checks, before it starts, that Docker has the disk and memory to finish.

## Proposed outcome

The suite's lock library gets a neighbour, `tests/lib/docker-preflight.sh`, the one code that
c4-infra's suite, the skills' suite (read from c4-infra's `main`, as the lock is since the skills'
0119) and the generated projects' `verify.sh` (through `C4_INFRA_DIR`) use:

- a label contract every creator sets: `c4-infra.owner=<repository>`, `c4-infra.run=<run id>`,
  `c4-infra.created=<epoch seconds>`, `c4-infra.ttl=<seconds>` for a run's resources, and
  `c4-infra.keep=<worktree or workspace path>` for one kept between runs (the stand-in's volume);
- a reaper that removes the labelled resources whose run is over (its time to live passed, or its
  liveness container gone) and those whose `keep` path no longer exists; then, without a label, only
  build cache beyond a bound, anonymous volumes no container uses, and the images a pin given to it
  replaced, when no container uses them;
- a preflight that the holder of the suite's lock runs before its first test: it cleans first, then
  measures Docker's free disk in the VM, the host's free disk under Docker's disk image, the VM's
  available memory and the host's available memory plus free swap, and stops the run only when they
  stay below floors the environment can override (defaults: 20 GB, 20 GB, 3 GiB, 6 GiB; build cache
  bound 5 GB); a `--no-clean` mode measures only, for a caller that doesn't hold the lock;
- a test's own label namespace and a mode that skips the unlabelled classes, so a test of it never
  touches what it didn't create;
- c4-infra's own tests labelled, `rm -f -v`, their extra tags removed, the stand-in's volume
  labelled `keep` with its checkout.

The skills' plan for 0122 names the functions it calls: `docker_labels <owner> [ttl]`,
`docker_keep_labels <owner> <path>`, `docker_reap [--pins <file>]`,
`docker_preflight [--no-clean] [--pins <file>]`, `C4_DOCKER_LABEL_NS`, `C4_DOCKER_REAP=labelled`.
The spec here fixes them; a change reaches the skills' spec as its v2.

Success criterion: after a full run of c4-infra's suite, Docker holds no container, volume, network
or tag of that run's id, and no stand-in volume of a checkout that is gone; a run killed with
`kill -9` leaves nothing the next lock take doesn't reclaim; a run that starts short of disk or
memory after cleaning stops before its first test, naming what is short.

## Affected users and systems

- Developer and Agent: every machine that runs the suite, the skills' suite or a generated project.
- The suite's libraries (`tests/lib/suite-lock.sh`'s neighbour, `tests/lib/stand-in-host.sh`),
  `tests/run.sh`, the tests that start containers on the host.

## Constraints

- Never remove what another project, session or the shared stack uses: a running or stopped
  container it didn't label, a named volume it didn't label, a tagged image of a repository it
  doesn't pin, the stack's volumes and images.
- Docker Desktop is shared: nothing stops, restarts or resets it, or compacts its disk; when the
  host's side is short, the preflight says so and gives the human's command.
- No cleaning while a test that measures time may run: the cleaning runs only under the suite's
  lock, before the first test.
- Linux and Windows (Git Bash with native `jq.exe` read with `-b`, paths to native executables on
  standard input, Docker Desktop on WSL2).
- Delivered on `main` before the skills' 0122 resumes (its plan's step 0).

## Open questions

- Each test's own disk and memory need: the floors start fixed and are tuned from the preflight's
  lines after a week — the PO.
- The reaper's run liveness: the time to live alone, or also a liveness container like the lock's
  pipe — the spec.
