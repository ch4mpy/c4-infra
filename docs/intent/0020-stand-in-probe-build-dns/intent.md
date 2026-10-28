# Intent: The isolation test's probe image fails to build in the stand-in, now and then, on a DNS error

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (verification of 0017, 2026-10-27 and 28)
- Spec needed: no
- Status: planned
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0007-isolation.stand-in.sh` builds its probe image (`tests/fixtures/0007/probe/`: `apk add curl nmap netcat-openbsd`) in the stand-in demo host's own Docker. On this workstation the build failed in two runs out of three:

- Observed: `WARNING: fetching https://dl-cdn.alpinelinux.org/alpine/v3.23/main/x86_64/APKINDEX.tar.gz: DNS: transient error (try again later)`, then `ERROR: unable to select packages`; on a fresh stand-in, every later check fails too (35 `KO` in `--all` on 24b1a60); when an earlier test had built the image, only the build check fails.
- Expected: the probe image builds on a workstation with network access.
- Not reproduced elsewhere: in the same `--all`, `tests/0013-mcp.stand-in.sh` built the same image; containers of the workstation's own Docker resolved the name 20 times out of 20, with Docker Desktop's resolver and with public ones (8.8.8.8, 8.8.4.4, 1.1.1.1).
- Environment: Ubuntu workstation, Docker Desktop 29.6.1, the stand-in host of `tests/lib/stand-in-host.sh`, 2026-10-27 and 28.

A test that fails at random makes `--all`, the proof before review, red with no defect behind it, and a failed build hides the isolation checks behind 35 `KO`.

## Proposed outcome

The probe image builds in the stand-in on every run where the workstation has network access; when it can't be built, the test says so once, with the cause, instead of failing every isolation check.

## Affected users and systems

- Personas: Developer (runs the verification)
- Modules / systems: the stand-in host (`tests/lib/stand-in-host.sh`, `tests/stand-in-host/`), the isolation tests

## Constraints

- The isolation checks themselves stay as they are.

## Open questions

- Why the stand-in's own Docker sometimes can't resolve: its resolver, or the order of the test's steps (the shared stack deployed with `compose.no-acme.yml`'s `dns: [127.0.0.1]` just before) — the plan measures it.
