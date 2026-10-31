# Intent: tests/0049-docker-preflight.sh's docker shim never runs on Linux, so its AC-07 checks prove nothing there

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (the Linux validation of 0050 on the product owner's workstation, 2026-10-31: 0050's
  `plan.md`, Verification — dca25ea, "KO, pre-existing, not 0050's"; drafted at the product owner's request
  in the skills' batch session)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-31
- Decided: 2026-10-31
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0049-docker-preflight.sh` proves 0049's AC-07 (no reaping nor prune while the tests run, RQ-10) with
a `docker` shim that logs each call: the test writes it with a heredoc at `$work/shim/docker`
(`tests/0049-docker-preflight.sh:114-121`), puts its folder first on `PATH` for run E (`:235`), then reads
its log (`:239`, `:240-247`). Nothing makes the shim executable: the test has no `chmod` (`grep -n chmod`
finds none). On Linux, bash's `PATH` lookup skips a file that isn't executable, so the real `docker` runs
and `$work/docker.log` stays empty; Git Bash on Windows runs the file anyway, which is why 0049 passed on
the Windows workstation.

- Steps: on Linux, under the suite's lock, `bash tests/0049-docker-preflight.sh`.
- Expected: every check passes, AC-07's checks reading the docker calls of run E.
- Observed (0050's validation, 2026-10-31): `KO - AC-07: the shim saw the preflight's reaping, before the
  tests`, `1 check(s) failed`, on `main` (c6a8872) as on 0050's branch (dca25ea), under `fr_FR.UTF-8` and
  under `LC_ALL=C`; a copy of the test keeping the log: 0 lines.
- Environment: the product owner's Linux workstation, Ubuntu 26.04.1 LTS, Docker 29.x.

What it costs: on Linux, AC-07's other check, "no prune nor removal between the first test's start and the
last test's end" (`:247`), reads an empty log and passes without testing anything; so does the AC-09 check
that the VM's disk is read past what a pull prints first (`:237-238`), since the pull lines come from the
shim (`:117-119`). A regression of RQ-10 (a reap or prune during the tests) would pass the suite on Linux,
the product owner's main workstation; and every run of the suite there is KO on this test, which hides a
new KO behind a known one.

## Proposed outcome

On Linux and under Git Bash, the shim runs and logs run E's docker calls, and AC-07's checks fail when what
they check is absent: a preflight that doesn't reap fails the first, an empty log fails both. No other test
of the suite relies on a stub written without being made executable.

## Affected users and systems

- Personas: Developer (the suite's verdict, which c4-infra's proofs rest on)
- Modules / systems: tests (`tests/0049-docker-preflight.sh`; possibly `tests/lib/`, the shared stub
  helpers, and other tests that write stubs: the spec's grep)

## Constraints

- The suite's rules: `# covers:`, `LC_ALL=C sort`, bash on Ubuntu and Git Bash on Windows (CLAUDE.md,
  "Repository layout" and "Verification"); a change of `tests/lib/` runs every test.
- Docker is shared on the workstation: the proof runs under the suite's lock, with 0049's label namespace
  (`C4_DOCKER_REAP=labelled`), touching nothing it didn't create.

## Open questions

- Do other tests write a stub or shim they put on `PATH` without making it executable? — the spec (a grep of
  the suite).
- Fix this test alone, or give the suite a way that makes the omission impossible or detected? — the
  product owner, at the spec.
