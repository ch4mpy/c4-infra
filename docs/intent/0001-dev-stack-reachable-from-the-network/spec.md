# Spec: The dev stack is reachable from the local network

- Intent: [0001](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: what a host exposes to the network, secrets — the Keycloak administrator of every application's realm; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, Faito's decision 0001
- Approved: —

## Summary

The dev stack publishes its ports on the workstation's loopback only, so that nothing of it answers from the local network; a setting opens them deliberately, for testing on a real device. `up.sh` refuses to start when `host.docker.internal` doesn't resolve to the loopback, the one case where a loopback binding would break the workstation's own clients.

## Requirements

- REQ-1 Every port the dev stack publishes (80, 443, 1025, 8025, 5672, 15672, 3000, 4317, 4318) is bound to `127.0.0.1` by default. (intent: proposed outcome)
- REQ-2 From another device on the local network, none of these ports answers. (intent: success criterion)
- REQ-3 The browser, the JVMs and the Node processes of the workstation reach the stack as today through `host.docker.internal`, and an application's login, logout and back-channel logout keep working. (intent: success criterion)
- REQ-4 When `host.docker.internal` doesn't resolve to `127.0.0.1` on the workstation, `up.sh` stops before starting anything and says how to fix it (PA-1 decided). (intent: constraint)
- REQ-5 A setting in `.env`, off by default and documented, publishes the stack on every interface, for testing an application from a device on the local network (PA-2 decided); `up.sh` prints a warning while it is on. (intent: open question)

## Out of scope

- The applications' own processes (Faito's gateway and REST API listen on every interface): each project's intent (Faito 0019, skills 0013).
- The demo host: only Caddy publishes 80 and 443, by design.

## Design

### Current behaviour

- `compose.yml`: `ports: - 80:80`, `- 443:443`, `- 1025:1025`, … (no address: every interface).
- On this workstation, `host.docker.internal` resolves to `127.0.0.1` from Java (checked on 2026-10-21) and from the browser (hosts file written by Docker Desktop); from the containers, `extra_hosts: host.docker.internal:host-gateway`.
- Reachable without credentials or with the dev ones: Keycloak's master console (`admin` / `secret`), Mailpit's UI, Grafana (anonymous Admin, the image's default), RabbitMQ's management UI.

### Behaviour per persona

- Developer: unchanged on the workstation; nothing answers from elsewhere, unless the setting of REQ-5 is on.

### API and contracts

- `.env`: a new entry (name settled in the plan) holding the address the ports are published on, `127.0.0.1` by default.
- `up.sh`: a new refusal, with its message, when `host.docker.internal` resolves elsewhere (REQ-4).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design ("host names that resolve where they are used") | REQ-3, REQ-4 |
| Faito's decision 0001 (back-channel logout on `host.docker.internal:<port>`) | REQ-3 |

## Points of attention

### PA-1 `host.docker.internal` resolving to the LAN address

- Issue: Docker Desktop may write the machine's LAN address for `host.docker.internal` in the hosts file; a loopback binding then breaks the workstation's own clients.
- Options: A `up.sh` refuses, with how to point the name at `127.0.0.1` / B `up.sh` binds to whatever address the name resolves to (the LAN address: exposed again) / C ignore it
- Recommendation: A: a clear stop beats a silent exposure (B) or a broken stack (C).
- Decides: tech lead
- Decision: to decide

### PA-2 Testing from a device on the local network

- Issue: a phone on the local network can't reach a loopback-only stack; the dev certificate isn't trusted by the phone either.
- Options: A loopback only, with the opt-in setting of REQ-5 / B no opt-in at all / C every interface by default (today)
- Recommendation: A: closed by default, open on purpose.
- Decides: PO
- Decision: to decide

## Acceptance criteria

- AC-1 Given the stack started by `up.sh`, then `docker ps` shows every published port on `127.0.0.1`. (REQ-1)
- AC-2 From another device on the local network, a connection to 443, 8025 or 15672 of the workstation is refused. (REQ-2)
- AC-3 Given Faito registered, when a user logs in and out on `https://faito.dev.localhost/` and Keycloak ends their sessions, then `/me` turns anonymous. (REQ-3)
- AC-4 Given `host.docker.internal` resolving to a LAN address, when `up.sh` runs, then it stops with its message and starts nothing. (REQ-4)
- AC-5 Given the setting of REQ-5 on, then the ports are published on every interface and `up.sh` warns about it. (REQ-5)

## Intent questions

- Reachable from a phone on the local network → PA-2.
- Loopback binding with a setting to open it → REQ-1, REQ-5.

## Change log

- v1 — 2026-10-21 — first version
