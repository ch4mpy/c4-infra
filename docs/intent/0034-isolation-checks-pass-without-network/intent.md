# Intent: tests/0007-dev.sh's isolation checks pass when the application's network doesn't exist

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (0023's evidence, 2026-10-28; HANDOVER "Left open")
- Spec needed: yes
- Status: planned
- Opened: 2026-10-28
- Decided: 2026-10-28
- Supersedes: —
- Mode: bootstrap

## Problem

`tests/0007-dev.sh` proves, among others, that a container on an application's network `c4-infra.faito` can't reach what it mustn't (`:181`, `:185`): `fails docker run --rm --network c4-infra.faito alpine:3 nc -z -w 3 <address> 7080`. `fails` (`:95-100`) passes whenever the command fails, whatever the reason: when `c4-infra.faito` doesn't exist, `docker run` fails with "network … not found" and the check passes, proving nothing.

- Steps: run `bash tests/0007-dev.sh` with Faito not registered (no `c4-infra.faito`).
- Expected: those checks fail (or the test refuses to run), saying the network is missing.
- Observed: they pass (0023's evidence).

## Proposed outcome

The test's negative checks pass only when the connection itself is refused or times out from inside an existing application network; a missing network, image or Docker error fails them, naming the cause.

## Affected users and systems

- Personas: Developer (the suite's verdict, which c4-infra's proofs rest on)
- Modules / systems: tests (`tests/0007-dev.sh`)

## Constraints

- None beyond the suite's rules (`# covers:`, `LC_ALL=C sort`, Git Bash).

## Open questions

- Whether other tests share the same `fails` pattern — the plan (a grep of the suite).
