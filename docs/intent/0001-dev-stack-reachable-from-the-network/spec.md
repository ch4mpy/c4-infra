# Spec: The dev stack is reachable from the local network

- Intent: [0001](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: what a host exposes to the network, secrets — the Keycloak administrator of every application's realm; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, Faito's decision 0001
- Approved: 2026-10-21, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

The dev stack publishes its ports on the workstation's loopback only, so that nothing of it answers from the local network, with no setting to open it. `up.sh` refuses to start when `host.docker.internal` doesn't resolve to the loopback, the one case where a loopback binding would break the workstation's own clients.

## Requirements

- REQ-1 Every port the dev stack publishes (80, 443, 1025, 8025, 5672, 15672, 3000, 4317, 4318) is bound to `127.0.0.1`, with no setting to publish it on another interface (PA-2 decided). (intent: proposed outcome)
- REQ-2 From another device on the local network, none of these ports answers. (intent: success criterion)
- REQ-3 The browser, the JVMs and the Node processes of the workstation reach the stack as today through `host.docker.internal`; an application's login, logout and back-channel logout keep working, and so do the e-mails Keycloak sends through the shared Mailpit (`host.docker.internal:1025`). (intent: success criterion)
- REQ-4 When `host.docker.internal` doesn't resolve to `127.0.0.1` on the workstation, `up.sh` stops before starting anything and says how to fix it: a hosts-file line `127.0.0.1 host.docker.internal`, and Docker Desktop's option that writes that line turned off (PA-1 decided). (intent: constraint)

## Out of scope

- The applications' own processes (Faito's gateway and REST API listen on every interface): each project's intent (Faito 0019, skills 0013).
- Testing an application from another device of the local network: the device would need host names it can resolve, a certificate authority it trusts and return addresses the gateways allow — a need of its own (PA-2).
- The demo host: only Caddy publishes 80 and 443, by design.

## Design

### Current behaviour

- `compose.yml`: `ports: - 80:80`, `- 443:443`, `- 1025:1025`, … (no address: every interface).
- On this workstation, `host.docker.internal` resolves to `127.0.0.1` from Java (checked on 2026-10-21) and from the browser, through a hosts-file line; from the containers, `extra_hosts: host.docker.internal:host-gateway`, which Docker Desktop forwards to the workstation's loopback (checked for the Angular dev servers on 2026-10-21).
- Reachable without credentials or with the dev ones: Keycloak's master console (`admin` / `secret`), Mailpit's UI, Grafana (anonymous Admin, the image's default), RabbitMQ's management UI.

### Behaviour per persona

- Developer: unchanged on the workstation; nothing of the stack answers from elsewhere.

### API and contracts

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

### PA-1 `host.docker.internal` resolving to the LAN address (decided)

- Issue: Docker Desktop can write the machine's LAN address for `host.docker.internal` in the hosts file; a loopback binding then breaks the workstation's own clients.
- Options: A `up.sh` refuses, with how to point the name at `127.0.0.1` / B `up.sh` binds to whatever address the name resolves to (the LAN address: exposed again) / C ignore it
- Recommendation: A: a clear stop beats a silent exposure (B) or a broken stack (C).
- Decides: tech lead
- Decision: A, `up.sh` refuses and explains (tech lead, 2026-10-21)

### PA-2 Opening the stack to the local network (decided)

- Issue: an opt-in setting would put Keycloak's master console, Mailpit and Grafana back on the local network, without making a device test work (host names, certificate authority, allowed return addresses).
- Options: A loopback only, no opt-in; testing from a device is a need of its own / B an opt-in setting publishing every interface
- Recommendation: A: closed, for a use the setting wouldn't serve anyway.
- Decides: PO
- Decision: A, no opening (PO, 2026-10-21)

## Acceptance criteria

- AC-1 Given the stack started by `up.sh`, then `docker ps` shows every published port on `127.0.0.1`. (REQ-1)
- AC-2 From another device on the local network, a connection to 443, 8025 or 15672 of the workstation is refused. (REQ-2)
- AC-3 Given Faito registered, when a user logs in and out on `https://faito.dev.localhost/` and Keycloak ends their sessions, then `/me` turns anonymous. (REQ-3)
- AC-4 Given a user registering in Faito's realm, then Keycloak's verification e-mail shows in Mailpit. (REQ-3)
- AC-5 Given `host.docker.internal` resolving to a LAN address, when `up.sh` runs, then it stops with its message and starts nothing. (REQ-4)

## Intent questions

- Reachable from a phone on the local network → PA-2: no.
- Loopback binding with a setting to open it → REQ-1: loopback, no setting (PA-2).

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (no opt-in, SMTP path, hosts-file wording), PA-1 and PA-2 decided
- v1 — 2026-10-21 — approved: every point of attention decided; tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
