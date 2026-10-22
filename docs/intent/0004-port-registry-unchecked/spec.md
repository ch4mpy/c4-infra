# Spec: Nothing prevents two applications from taking the same port block

- Intent: [0004](intent.md)
- Status: approved
- Version: 1
- Risk: high (rule: the isolation between applications — one application's traffic routed to another one's processes; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design and port registry
- Approved: 2026-10-21, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

The port registry becomes a file that scripts read, one entry per application: its number, its name, and what it owns in the shared stack (its realms, its RabbitMQ user, its themes, its host names in dev and on the demo host). `register-app.sh` refuses an application missing from it, a duplicate, and a routes file that names a host or a port: the upstreams are derived from the entry. A command prints the next free number, which `create-dev-infra` will take (skills follow-up).

## Requirements

- REQ-1 The registry is a file of this repository, one entry per application: its number, its name, its realms, its RabbitMQ user, its themes, and its host names (dev and demo). (intent: "without reading prose"; 0002 relies on these fields)
- REQ-2 `register-app.sh` refuses an application whose name isn't in the registry, naming the file to edit. (intent)
- REQ-3 The upstreams a registration routes to are derived from the entry and never written in the routes file (PA-1 decided): in dev, the ports of the application's block (`(10 + n) × 1000` to `+ 999`) by role; on the demo host, the application's containers on the container ports the README fixes for their role (0003 REQ-4; none yet for the MCP server). A routes file naming a host or a port is refused. (intent: success criterion; 0003 REQ-4)
- REQ-4 Two entries with the same number, the same name, or a realm, theme, user or host name in common make `register-app.sh` and `up.sh` fail, naming both. (intent: success criterion)
- REQ-5 A command of this repository prints the next free number: the smallest number no entry has, from 1 to 38. (intent)
- REQ-6 The demo deployment sends the registry to the demo host with `register-app.sh`, so that registrations there are checked the same way. (intent)
- REQ-7 The README's table is replaced by a pointer to the registry file. (intent)

## Out of scope

- Ports of the shared services (fixed, listed in the README).
- Ports that a build or a test opens (skills 0008).
- The `create-dev-infra` skill, which reads and writes the README's table today: a follow-up intent in the skills repository, to open once this spec is approved.

## Design

### Current behaviour

The registry is the README's "Port registry" table, read by the agent that runs `create-dev-infra`; `register-app.sh` doesn't look at it; the demo deployment sends `demo/` and `register-app.sh` only (2026-10-21).

### Behaviour per persona

- Developer: a clear refusal instead of an application routed to another one's processes.
- Application: registers under its registered name, with what its entry assigns it.

### API and contracts

- The registry file (format settled in the plan; one entry per application, readable by bash and by an agent).
- `register-app.sh`: new refusals (REQ-2 to REQ-4).
- The command printing the next free number (REQ-5).

### User interface

None.

### Data

The registry file.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (a block of 1 000 ports per application, below 49152) | REQ-3, REQ-5 |

## Points of attention

### PA-1 The ports of a server block (decided)

- Issue: reading ports out of an nginx or Caddy block takes a pattern match that an unusual syntax escapes; 0003 makes the routes file name its upstreams by role.
- Options: A ports derived from the registry: the routes file names roles, never ports / B match the ports written in the block, and refuse those outside the block / C no check of the ports
- Recommendation: A: the check holds by construction, and agrees with 0003.
- Decides: tech lead
- Decision: A, ports derived from the registry (tech lead, 2026-10-21)

## Acceptance criteria

- AC-1 Given the registry without `verif`, when `register-app.sh --app verif` runs, then it is refused, naming the registry file. (REQ-2)
- AC-2 Given Faito's routes file naming `host.docker.internal:12080`, when Faito registers, then it is refused. (REQ-3)
- AC-3 Given two entries numbered 4, or two entries owning the realm `public-facing` or the theme `tickee`, when `up.sh` runs, then it fails, naming both. (REQ-4)
- AC-4 Given numbers 1 to 4 taken, when the next-number command runs, then it prints 5; given 1, 2 and 4 taken, it prints 3. (REQ-5)
- AC-5 Given the demo deployment, then the registry is on the host next to `register-app.sh`. (REQ-6)
- AC-6 The registry file holds an entry for each of Turu, Hurura'a, Tickee and Faito with every field of REQ-1; Tickee's has the number 3, the realms `tickee`, `brasserie`, `tenant2` and `tenant3`, its RabbitMQ user, the theme `tickee`, and the host names `tickee.dev.localhost` and `tickee.c4-soft.com`. (REQ-1)
- AC-7 The README's "Port registry" section points to the registry file and holds no table of numbers. (REQ-7)

## Intent questions

- None.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (risk high, entries carry what 0002 confines, ports by role as in 0003, registry sent to the demo host, skills follow-up), PA-1 decided
- v1 — 2026-10-21 — draft: second coherence review (themes in the entry, demo upstreams on the fixed container ports, a command for the next free number, criterion for REQ-7)
- v1 — 2026-10-21 — draft: third coherence review (AC-6 proves the entry's fields; refusing another application's theme stays 0002's, AC-3 there)
- v1 — 2026-10-21 — approved: every point of attention decided; tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
