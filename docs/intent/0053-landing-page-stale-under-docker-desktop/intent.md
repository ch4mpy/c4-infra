# Intent: On the Linux workstation, the landing page keeps showing what an earlier registration wrote

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent in the skills' batch session (`ch4mpy/claude`, `batch-2026-10-29`)
- Kind: bug
- Source: conversation (2026-10-31, the full run of 0050's merge `87acaf4` on the product owner's Linux workstation; skills' improvement log P-24)
- Spec needed: yes
- Status: planned
- Opened: 2026-10-31
- Decided: 2026-10-31
- Supersedes: —
- Mode: bootstrap

## Problem

On the product owner's Linux workstation (Ubuntu, Docker Desktop), `tests/0048-landing-page.sh` fails on `main` (`ae74575`, without 0050; and at `87acaf4`), alone and in a full run, under `fr_FR.UTF-8` as under `LC_ALL=C`:

- `KO - AC-10: shows it` (`tests/0048-landing-page.sh:122`): after a registration with `--accounts`, the page still lacks `ann`'s new group;
- `KO - AC-04: lists no account` (`:132`): after a registration whose accounts file holds comments only, the page still lists `ann`.

Steps to reproduce: on that workstation, the dev stack up from the main checkout (`bash up.sh`), `bash tests/0048-landing-page.sh`. Expected: every check passes. Observed: `2 check(s) failed`, about 30 s.

Probable cause, from the diagnosis of 2026-10-31 (to confirm in the spec): `register-app.sh`'s `write_index` writes the page to a temporary file and renames it over `caddy/html/index.html` (`register-app.sh:214`, `mv`); the reverse proxy reads `./caddy/` through a bind mount (`compose.yml:71`, `./caddy/:/etc/caddy/:ro`). Under Docker Desktop's file sharing on Linux, a file renamed over in that directory kept serving its old content inside `c4-infra.reverse-proxy` 6 s after the new one was written: the page the test reads over HTTPS (`:57`, `page_holds`) is the earlier one. It passed on the Windows workstation (0048's delivery) and in the `--all` on `main` at `c6a8872` on 2026-10-31 morning, before `up.sh` recreated the stack that afternoon: whether it depends on the stack's age, the mount's cache or the rename is open.

What it costs: the milestone run before a push of `main` is red on this workstation (0050 was delivered on the product owner's decision despite it); and a registration's page may show stale accounts to the person reading it in dev.

## Proposed outcome

After a registration, the landing page the proxy serves is the one it just wrote, on Linux and on Windows, at once. Success: `tests/0048-landing-page.sh` passes on the Linux workstation, alone and in a full run, several times in a row; it still passes on the Windows workstation.

## Affected users and systems

- Developer (dev landing page), the suite's milestone runs; `register-app.sh` (`write_index`), the reverse proxy's mount (`compose.yml`), possibly `caddy/` config.

## Constraints

- Nothing the demo host runs may change behaviour without its own check (deploy-demo).
- **The fix's proof needs the Linux workstation**: the bug doesn't show on Windows. An agent implementing it on Windows hands the Linux runs over (HANDOVER.md), as 0050 did.

## Open questions

- Is it the rename (a new inode the shared mount doesn't see), the mount's cache, or the stack's age? A minimal reproduction (write in place vs. `mv`, inside and outside the proxy) — spec.
- Fix in the writer (write in place, `cp` then truncate, or `cat >`), in the proxy (reload, or a mount of `caddy/html/` of its own), or both? — spec.
