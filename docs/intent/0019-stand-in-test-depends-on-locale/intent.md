# Intent: The stand-in deployment test fails on a workstation whose locale isn't C

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (verification of 0017, 2026-10-27)
- Spec needed: no
- Status: delivered (2026-10-28)
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0003-demo-deploy.stand-in.sh` checks that the stand-in demo host holds only what the deployment sends: it compares the expected list, sorted on the workstation, with the files found, sorted inside the stand-in. Where the workstation's collation isn't C, the same files sort in another order, and the check fails although nothing is missing or extra.

- Steps: on a workstation with `LANG=fr_FR.UTF-8`, `bash tests/run.sh --all` (or the test alone).
- Expected: `ok - /root/c4-infra holds only what the deployment sends`.
- Observed: `KO - /root/c4-infra holds only what the deployment sends`, the found list holding the same 18 files, `.env` first (C order) where the expected list puts it after `caddy/…`; `LC_ALL=C` makes it pass.
- Environment: Ubuntu workstation, Docker Desktop 29.6.1, 2026-10-27 (`--all` on 0017's branch, 24b1a60).

`--all` is the proof of every change before review (since 0017): it fails on such a workstation, or needs `LC_ALL=C`.

## Proposed outcome

The check passes whatever the workstation's locale when the stand-in holds exactly the files the deployment sends, and still fails, naming the difference, when a file is missing or extra.

## Affected users and systems

- Personas: Developer (runs the verification)
- Modules / systems: the demo host's deployment test (`tests/`), its stand-in host

## Constraints

- The check keeps comparing the whole list; only the comparison's dependence on the locale goes.

## Open questions

- Other comparisons between a list made on the workstation and one made in a container: none found by a grep of `sort` in `tests/` (2026-10-28) — the plan confirms.
