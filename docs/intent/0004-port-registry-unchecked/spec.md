# Spec: Nothing prevents two applications from taking the same port block

- Intent: [0004](intent.md)
- Status: draft
- Version: 1
- Risk: standard (no risk rule applies: the ports stay on the workstation; an application's traffic sent to another one's processes is what the change prevents)
- Policies applied: none yet; standing constraints: README design and port registry
- Approved: —

## Summary

The port registry becomes a file that scripts read, one line per application (number, name). `register-app.sh` refuses an application missing from it, and a server block routing to ports outside the application's block; the README's table points to the file, and `create-dev-infra` takes the next free number from it.

## Requirements

- REQ-1 The registry is a file of this repository, one entry per application: its number and its name. (intent: "without reading prose")
- REQ-2 `register-app.sh` refuses an application whose name isn't in the registry, naming the file to edit. (intent)
- REQ-3 `register-app.sh` refuses a server block that routes to a port of the host outside the application's block (`(10 + n) × 1000` to `+ 999`), naming the block's owner when there is one (PA-1 decided). (intent: success criterion)
- REQ-4 Two entries with the same number, or the same name, make `register-app.sh` and `up.sh` fail, naming both. (intent: success criterion)
- REQ-5 The next free number is the smallest number no entry has, from 1 to 38. (intent)
- REQ-6 `create-dev-infra` reads and writes this file (follow-up in the skills, its own change); the README's table is replaced by a pointer to it. (intent)

## Out of scope

- Ports of the shared services (fixed, listed in the README).
- Ports that a build or a test opens (skills 0008).

## Design

### Current behaviour

The registry is the README's "Port registry" table, read by the agent that runs `create-dev-infra`; `register-app.sh` doesn't look at it (2026-10-21).

### Behaviour per persona

- Developer: a clear refusal instead of an application routed to another one's processes.
- Application: registers under its registered name only.

### API and contracts

- The registry file (format settled in the plan; one line per application, readable by bash and by an agent).
- `register-app.sh`: two new refusals (REQ-2, REQ-3).

### User interface

None.

### Data

The registry file.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (a block of 1 000 ports per application, below 49152) | REQ-3, REQ-5 |

## Points of attention

### PA-1 Checking the ports of a server block

- Issue: reading the ports of an nginx or Caddy block takes a pattern match on its upstreams, which can miss an unusual syntax.
- Options: A match the `host.docker.internal:<port>` upstreams of the block, and refuse those outside the block / B no check of the ports, only of the name and number
- Recommendation: A: the upstreams are written by `create-dev-infra` in one form; a miss lets a block through, as today, without breaking anything.
- Decides: tech lead
- Decision: to decide

## Acceptance criteria

- AC-1 Given the registry without `verif`, when `register-app.sh --app verif` runs, then it is refused, naming the registry file. (REQ-2)
- AC-2 Given Faito (number 4), when its server block routes to `host.docker.internal:12080`, then the registration is refused, naming Hurura'a. (REQ-3)
- AC-3 Given two entries numbered 4, when `up.sh` runs, then it fails, naming both. (REQ-4)
- AC-4 Given numbers 1 to 4 taken, then the next free number is 5. (REQ-5)

## Intent questions

- None.

## Change log

- v1 — 2026-10-21 — first version
