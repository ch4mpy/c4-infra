# Spec: Dev doesn't apply the demo's reverse-proxy rules

- Intent: [0003](intent.md)
- Status: draft
- Version: 1
- Risk: standard (no risk rule applies: the demo's exposure and headers don't change; dev gains the demo's headers)
- Policies applied: none yet; standing constraints: README design, Faito's decision 0001
- Approved: —

## Summary

One reverse proxy, written once, for dev and the demo host: the same routes and security headers for the shared services and for each application, the certificates being the only difference. Each application describes its routes in one file, and the shared services' versions are set in one place.

## Requirements

- REQ-1 The shared services' routes (Keycloak, realm discovery, Mailpit, Grafana, and RabbitMQ in dev) are written once and apply in dev and on the demo host (PA-1 decided). (intent: proposed outcome)
- REQ-2 Dev sends the demo's security headers for the applications' single-page apps (Content-Security-Policy, `X-Frame-Options`, `Permissions-Policy`, `X-Content-Type-Options`, `Referrer-Policy`); HSTS stays on the demo host only, so that browsers don't pin the workstation's host names. (intent: success criterion)
- REQ-3 An application describes its routes in one file, used in dev and on the demo host; `register-app.sh` installs it in both. (intent: success criterion)
- REQ-4 The versions of the shared services' images are set once for dev and the demo host (PA-2 decided). (intent)
- REQ-5 The `demo/` directory still deploys on its own (`rsync`), or the deployment sends whatever it needs with it. (intent: constraint)
- REQ-6 `create-dev-infra` generates that one file for a new project (follow-up in the skills, its own change), and `docs/migration.md` tells existing projects how to write it. (intent)

## Out of scope

- Changing the demo's headers or exposure.
- The applications' own Content-Security-Policy needs (an application that loads a third-party resource fixes it: Faito 0018).

## Design

### Current behaviour

- Dev: nginx, `nginx/nginx.conf` and each application's `nginx/apps/<app>.conf`; no security header.
- Demo: Caddy, `demo/caddy/Caddyfile` with `(common-headers)` and `(spa-headers)` snippets, each application's `caddy/apps/<app>.caddy`.
- Two compose files repeating the services and the image versions (`compose.yml`, `demo/compose.yml`); `register-app.sh` switches between nginx and Caddy (`PROXY` in `.env`).

### Behaviour per persona

- Developer: a page that the demo's headers would break is broken in dev too.
- Application: one routes file instead of two.

### API and contracts

- The application's routes file (its format follows PA-1, the details are settled in the plan): its host name and its upstreams (gateway, front end(s), MCP server) as placeholders filled per environment.
- `register-app.sh --proxy <file>`: one file for both environments.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (one origin per application, shared services on their own origin) | REQ-1, REQ-3 |
| Faito's decision 0001 | unchanged |

## Points of attention

### PA-1 The proxy in dev

- Issue: writing the rules once means one proxy language for both environments, or a generator for two.
- Options: A Caddy in dev too, with the dev certificate (`tls` with the files of `certs/`) / B nginx in dev and Caddy on the demo host, both generated from one description / C nginx in both (certificates by another tool on the demo host)
- Recommendation: A: one language, the demo's snippets as they are, nothing to generate.
- Decides: tech lead
- Decision: to decide

### PA-2 The compose files

- Options: A a base file with a dev and a demo override / B one file with profiles
- Recommendation: A: the demo directory keeps working on its own (the base is sent with it).
- Decides: tech lead
- Decision: to decide

## Acceptance criteria

- AC-1 Given Faito's front end in dev, when a page loads a Google font, then the browser's console reports the Content-Security-Policy blocking it, as on the demo host. (REQ-2)
- AC-2 Given the dev stack, then `https://faito.dev.localhost/` sends no `Strict-Transport-Security` header. (REQ-2)
- AC-3 Given one routes file for an application, when it registers in dev and on the demo host, then the same paths reach the same services. (REQ-3)
- AC-4 Given an image version changed in its one place, then `docker compose config` shows it for dev and for the demo host. (REQ-4)
- AC-5 The realm discovery route answers `200` on both hosts from the one definition. (REQ-1)

## Intent questions

- Caddy in dev, one site file, one compose base → PA-1, PA-2.

## Change log

- v1 — 2026-10-21 — first version
