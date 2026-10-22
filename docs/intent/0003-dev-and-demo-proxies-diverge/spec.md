# Spec: Dev doesn't apply the demo's reverse-proxy rules

- Intent: [0003](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: what a host exposes to the network, authentication — the demo host's public edge, Keycloak's console and Mailpit's protection, is rewritten; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, Faito's decision 0001
- Approved: —

## Summary

Caddy in dev as on the demo host: the shared services' routes and the applications' security headers written once, with a dev and a demo part only where they must differ (certificates, HSTS, Mailpit's protection, RabbitMQ's UI). Each application describes its routes in one file that names its upstreams by role; their ports come from the registry. The demo host's exposure doesn't change.

## Requirements

- REQ-1 The shared services' routes (Keycloak, realm discovery, Mailpit, Grafana) are written once, in Caddy, and apply in dev and on the demo host (PA-1 decided). (intent: proposed outcome)
- REQ-2 What the demo host exposes stays as it is: Mailpit behind its basic authentication, no RabbitMQ management UI, the same paths; dev's additions (RabbitMQ's UI, Mailpit without authentication) stay dev-only. (risk rules: exposure)
- REQ-3 Dev sends the demo's security headers for the applications' single-page apps (Content-Security-Policy, `X-Frame-Options`, `Permissions-Policy`, `X-Content-Type-Options`, `Referrer-Policy`); HSTS stays on the demo host only, so that browsers don't pin the workstation's host names. (intent: success criterion)
- REQ-4 An application describes its routes in one file, used in dev and on the demo host: its host name and its upstreams by role (gateway, front end(s), MCP server); the ports of a role come from the application's block in the registry (0004), never from the file. `register-app.sh` installs it in both environments. (intent: success criterion; 0004)
- REQ-5 The versions of the shared services' images are set once, in a compose base with a dev and a demo override (PA-2 decided). (intent)
- REQ-6 The demo deployment sends whatever the demo host needs (the compose base and its demo override, the shared Caddy configuration, the registry, `register-app.sh`). (intent: constraint)
- REQ-7 `register-app.sh` keeps telling dev from the demo host by one setting of the stack's `.env` (today `PROXY`), which other specs rely on (0005). (0005)
- REQ-8 `docs/migration.md` tells existing projects how to write their routes file. (intent)

## Out of scope

- Changing the demo's headers or exposure (REQ-2 keeps them).
- The applications' own Content-Security-Policy needs (an application that loads a third-party resource fixes it: Faito 0018).
- The `create-dev-infra` skill, which generates an nginx server block today: a follow-up intent in the skills repository, to open once this spec is approved.

## Design

### Current behaviour

- Dev: nginx, `nginx/nginx.conf` and each application's `nginx/apps/<app>.conf`; no security header; routes for `/rabbitmq/` and an unauthenticated Mailpit.
- Demo: Caddy, `demo/caddy/Caddyfile` with `(common-headers)` and `(spa-headers)` snippets, Mailpit behind `basic_auth`, no RabbitMQ route; each application's `caddy/apps/<app>.caddy`.
- Two compose files repeating the services and the image versions (`compose.yml`, `demo/compose.yml`); `register-app.sh` switches between nginx and Caddy (`PROXY` in `.env`).

### Behaviour per persona

- Developer: a page that the demo's headers would break is broken in dev too.
- Application: one routes file instead of two, without ports.

### API and contracts

- The application's routes file: its host name and its upstreams by role; the ports are derived from the registry (0004) per environment (host ports in dev, container names and ports on the demo host).
- `register-app.sh --proxy <file>`: one file for both environments.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (one origin per application, shared services on their own origin) | REQ-1, REQ-4 |
| Faito's decision 0001 | unchanged |

## Points of attention

### PA-1 The proxy in dev (decided)

- Issue: writing the rules once means one proxy language for both environments, or a generator for two.
- Options: A Caddy in dev too, with the dev certificate (the files of `certs/`) / B nginx in dev and Caddy on the demo host, both generated from one description / C nginx in both (certificates by another tool on the demo host)
- Recommendation: A: one language, the demo's snippets as they are, nothing to generate.
- Decides: tech lead
- Decision: A, Caddy in dev too (tech lead, 2026-10-21)

### PA-2 The compose files (decided)

- Issue: the services and their versions are written twice; the demo directory is deployed on its own.
- Options: A a base file with a dev and a demo override / B one file with profiles
- Recommendation: A: the demo deployment sends the base with its override (REQ-6).
- Decides: tech lead
- Decision: A, a base with overrides (tech lead, 2026-10-21)

## Acceptance criteria

- AC-1 Given an application's page in dev that loads a font from another origin, then the browser's console reports the Content-Security-Policy blocking it, as on the demo host. (REQ-3)
- AC-2 Given the dev stack, then `https://faito.dev.localhost/` sends no `Strict-Transport-Security` header. (REQ-3)
- AC-3 Given the demo configuration, then `/mailpit/` asks for its basic authentication and `/rabbitmq/` answers `404`, as today. (REQ-2)
- AC-4 Given one routes file for an application, when it registers in dev and on the demo host, then the same paths reach the same services, on the ports of its registry block. (REQ-4)
- AC-5 Given an image version changed in its one place, then `docker compose config` shows it for dev and for the demo host. (REQ-5)
- AC-6 The realm discovery route answers `200` on both hosts from the one definition. (REQ-1)

## Intent questions

- Caddy in dev, one site file, one compose base → PA-1, PA-2.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (risk high, demo exposure kept, upstreams by role from the registry, dev/demo setting kept for 0005, skills follow-up), PA-1 and PA-2 decided
