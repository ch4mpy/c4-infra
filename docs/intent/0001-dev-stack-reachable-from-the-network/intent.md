# Intent: The dev stack is reachable from the local network

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (security review of the shared stack, 2026-10-21)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-21
- Decided: 2026-10-21
- Supersedes: —

## Problem

The dev stack publishes its ports on every interface of the workstation (`compose.yml`: 80/443, 1025/8025, 5672/15672, 3000/4317/4318). On a shared network (coworking, café, trade show), any device on it reaches:

- Keycloak's master administration console, with the dev credentials `admin` / `secret`: every application's realm, users and clients;
- Mailpit's web UI, without authentication: every e-mail the applications sent (account verification, password resets);
- Grafana, whose image grants anonymous visitors the Admin role: every application's logs and traces;
- RabbitMQ's management UI and AMQP port;
- through the reverse proxy, with the right `Host` header, the applications' dev servers, though those listen on the loopback only.

Sharing the stack raised the stake: one exposed Keycloak now holds every project's realms. The former per-project stacks published the same ports, so this predates the shared stack.

## Proposed outcome

From another device on the local network, nothing of the dev stack answers, while the browser, the JVMs and the containers of the workstation keep working as today. Success criterion: a port scan of the workstation from another device finds none of the stack's ports open, and an application's login, logout and back-channel logout still work.

## Affected users and systems

- Developer (the workstation and the dev data of every application).
- Dev stack (`compose.yml`); possibly the certificates and the applications' settings that name `host.docker.internal`.

## Constraints

- `host.docker.internal` must keep resolving to something the published ports answer on, for the browser and the JVMs: on this workstation it is `127.0.0.1` (hosts file), but Docker Desktop may write the LAN address on another machine.
- The same question for the applications' own processes is tracked in each project (Faito: 0019).

## Open questions

- Must the stack stay reachable from a phone on the local network, to test an application on a real device? — PO.
- *Suggested solution*: bind the published ports to the loopback, with a setting to open them deliberately — to be settled in the spec.
