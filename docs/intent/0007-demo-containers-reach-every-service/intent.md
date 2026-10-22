# Intent: On the demo host, an application's containers reach every shared service and every other application

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: bug
- Source: conversation (follow-up of 0002, out of its scope; 2026-10-21)
- Spec needed: yes
- Status: planned
- Opened: 2026-10-21
- Decided: 2026-10-21
- Supersedes: —

## Problem

On the demo host, every container of every application joins the one `c4-infra` network (README design, `docs/migration.md` step 2), and so does every shared service, `keycloak-db` included: `demo/compose.yml` gives no service a network of its own. Whatever an application's container can reach there bypasses Caddy:

- Mailpit's web UI and API on `mailpit:8025`, without authentication: the basic authentication is Caddy's (`demo/caddy/Caddyfile`, `/mailpit/*`). Every realm's mails are there: the verification and password-reset links of every application's users.
- Keycloak's database (`keycloak-db:5432`), protected by its password only.
- Grafana LGTM's OTLP receivers, which accept any telemetry without authentication, and its other ports.
- Every other application's containers, on every port: gateways, REST APIs, actuators, MCP servers.

0002 confines what an application's *deployment* can do; this is what its *running containers* can do. One compromised application (a dependency, a flaw in its code) can read another application's password-reset mail and take over its users' accounts. That is personal data of the demo visitors, and the exposure grows with each migrated application.

## Proposed outcome

On the demo host, an application's containers reach their own containers and the shared services they use, through what those services protect, and nothing else. Success criterion: from one application's container, another application's gateway, Keycloak's database and Mailpit's mails can't be reached. The application still logs users in and out (back-channel logout included), sends mail, publishes events and exports telemetry.

## Affected users and systems

- Demo visitor (their accounts and mails in every application), Application, Demo operator.
- Demo stack (`demo/`), registration (`register-app.sh`), `docs/migration.md`; the dev stack where application containers join the network too (Tickee's LDAP server).

## Constraints

- One small VPS and one Docker daemon, no orchestrator (as in 0002).
- Keycloak must reach each application's gateway (back-channel logout), and Caddy each application's gateway and front end.
- 0002 (registration through a root-owned command), 0003 (one compose base with overrides), 0004 (the registry names each application) hold.

## Open questions

- Does any application need to reach another application's containers? — PO.
- What can't be protected inside the network (telemetry), and is that acceptable on the demo? — PO.
