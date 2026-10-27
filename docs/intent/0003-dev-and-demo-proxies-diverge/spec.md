# Spec: Dev doesn't apply the demo's reverse-proxy rules

- Intent: [0003](intent.md)
- Status: approved
- Version: 1
- Risk: high (rules: what a host exposes to the network, authentication — the demo host's public edge, Keycloak's console and Mailpit's protection, is rewritten; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, Faito's decision 0001, c4-infra 0001 (dev ports on the loopback)
- Approved: 2026-10-21, Jérôme Wacongne (PO, and tech lead for the high risk)

## Summary

Caddy in dev as on the demo host: the shared services' routes and the applications' security headers written once, with a dev and a demo part only where they must differ (certificates, HSTS, Mailpit's protection, RabbitMQ's UI, published ports). Each application describes its routes in one file that names the role each path goes to, with neither host name, scheme nor port: its registry entry (0004) gives its host name in each environment, and each role's upstream is derived per environment. A setting of the stack names the environment. The demo host's exposure doesn't change.

## Requirements

- **RQ-01:** The shared services' routes (Keycloak, realm discovery, Mailpit, Grafana) are written once, in Caddy, and apply in dev and on the demo host (PA-01 decided). (intent: proposed outcome)
- **RQ-02:** What the demo host exposes stays as it is: Mailpit behind its basic authentication, no RabbitMQ management UI, the same paths; dev's additions (RabbitMQ's UI, Mailpit without authentication) stay dev-only. (risk rules: exposure)
- **RQ-03:** Dev sends the demo's security headers for the applications' single-page apps (Content-Security-Policy, `X-Frame-Options`, `Permissions-Policy`, `X-Content-Type-Options`, `Referrer-Policy`); HSTS stays on the demo host only, so that browsers don't pin the workstation's host names. (intent: success criterion)
- **RQ-04:** An application describes its routes in one file, used in dev and on the demo host: its paths, the role each one goes to (gateway, MCP server, and the front end: one per locale with i18n, the single `ui` one without) and per-path options (e.g. a request body limit, a path rewrite), with neither host name, scheme nor port. Its host name in each environment comes from its registry entry (0004). A role's upstream is derived per environment:
  - in dev, `host.docker.internal` on the role's port in the application's block: the gateway (`<prefix>080`) and the MCP server (`<prefix>280`) over HTTPS, with the applications' dev certificate; the front ends over HTTP (`<prefix>200` for `fr` or `ui`, `<prefix>205` for `en`);
  - on the demo host, plain HTTP inside the Docker network, to the role's container on the port the README fixes for it: `<app>.gateway:7080`, and `<app>.frontend:80` for every locale. The README fixes no MCP server port yet, since no application deploys one there: it does when the first one does, and until then a routes file naming that role is refused on the demo host, saying so.

  `register-app.sh` installs the file in both environments. (intent: success criterion; 0004)
- **RQ-05:** The versions of the shared services' images are set once, in a compose base with a dev and a demo override (PA-02 decided). (intent)
- **RQ-06:** The demo deployment sends whatever the demo host needs (the compose base and its demo override, the shared Caddy configuration, the registry, `register-app.sh`). (intent: constraint, the demo directory is deployed on its own)
- **RQ-07:** The stack's `.env` names its environment (`dev` or `demo`), and `register-app.sh` tells dev from the demo host by that setting, not by the proxy, which is Caddy in both (PA-01). The routes of RQ-04 and the theme behaviour of c4-infra 0005 follow it; whichever of the two specs is delivered first introduces it. (intent: one routes file for both environments; PA-01 decided)
- **RQ-08:** `docs/migration.md` tells existing projects how to write their routes file. (intent)
- **RQ-09:** Published ports are declared in the overrides only, never in the base, since compose merges `ports` lists: the dev override binds every port to `127.0.0.1` (c4-infra 0001), the demo override publishes 80 and 443 only. (risk rules: exposure; c4-infra 0001)

## Out of scope

- Changing the demo's headers or exposure (RQ-02 keeps them).
- The applications' own Content-Security-Policy needs (an application that loads a third-party resource fixes it: Faito 0018).
- The `create-dev-infra` skill, which generates an nginx server block today: a follow-up intent in the skills repository, to open once this spec is approved.

## Design

### Current behaviour

- Dev: nginx, `nginx/nginx.conf` and each application's `nginx/apps/<app>.conf`; no security header; routes for `/rabbitmq/` and an unauthenticated Mailpit.
- Demo: Caddy, `demo/caddy/Caddyfile` with `(common-headers)` and `(spa-headers)` snippets, Mailpit behind `basic_auth`, no RabbitMQ route; each application's `caddy/apps/<app>.caddy`, naming its containers and their fixed ports (`faito.gateway:7080`, `faito.frontend:80` for `/fr/` and `/en/`: README, "What an application's deployment does").
- Two compose files repeating the services and the image versions (`compose.yml`, `demo/compose.yml`); `register-app.sh` switches between nginx and Caddy by `PROXY` in `.env` (`caddy` written by `deploy-demo.yml`), its only way of telling the environments apart.
- The demo deployment rsyncs `demo/` and `register-app.sh` (`deploy-demo.yml`, "Upload the deployment files").

### Behaviour per persona

- Developer: a page that the demo's headers would break is broken in dev too.
- Application: one routes file instead of two, without host name or port.

### API and contracts

- The application's routes file: paths, the role of each, per-path options; host names from the registry (0004), upstreams derived per environment (RQ-04).
- The stack's `.env`: the environment's name (RQ-07).
- `register-app.sh --proxy <file>`: one file for both environments.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (one origin per application, shared services on their own origin, fixed container ports on the demo host) | RQ-01, RQ-04 |
| Faito's decision 0001 | unchanged |
| c4-infra 0001 (dev ports on the loopback) | RQ-09 |

## Points of attention

### PA-01: The proxy in dev (decided)

- Issue: writing the rules once means one proxy language for both environments, or a generator for two.
- Options: A Caddy in dev too, with the dev certificate (the files of `certs/`) / B nginx in dev and Caddy on the demo host, both generated from one description / C nginx in both (certificates by another tool on the demo host)
- Recommendation: A: one language, the demo's snippets as they are, nothing to generate.
- Decides: tech lead
- Decision: A, Caddy in dev too (tech lead, 2026-10-21)

### PA-02: The compose files (decided)

- Issue: the services and their versions are written twice; the demo directory is deployed on its own.
- Options: A a base file with a dev and a demo override / B one file with profiles
- Recommendation: A: the demo deployment sends the base with its override (RQ-06).
- Decides: tech lead
- Decision: A, a base with overrides (tech lead, 2026-10-21)

## Acceptance criteria

- **AC-01:** Given an application's page in dev that loads a font from another origin, then the browser's console reports the Content-Security-Policy blocking it, as on the demo host. (RQ-03)
- **AC-02:** Given the dev stack, then `https://faito.dev.localhost/` sends no `Strict-Transport-Security` header. (RQ-03)
- **AC-03:** Given the demo configuration, then `/mailpit/` asks for its basic authentication and `/rabbitmq/` answers `404`, as today. (RQ-02)
- **AC-04:** Given one routes file for Faito, when Faito registers in dev, then on `faito.dev.localhost` `/gateway/` reaches `https://host.docker.internal:14080`, `/fr/` `http://host.docker.internal:14200` and `/en/` `http://host.docker.internal:14205`; when it registers on the demo host, then on `faito.c4-soft.com` `/gateway/` reaches `http://faito.gateway:7080`, and `/fr/` and `/en/` `http://faito.frontend:80`. (RQ-04)
- **AC-05:** Given an image version changed in its one place, then `docker compose config` shows it for dev and for the demo host. (RQ-05)
- **AC-06:** The realm discovery route answers `200` on both hosts from the one definition. (RQ-01)
- **AC-07:** Given the stack's environment set to `demo` on the workstation, with Caddy as in dev, when Faito registers, then its routes take the demo host names and upstreams of AC-04; set back to `dev`, the dev ones. (RQ-07)
- **AC-08:** Given a host holding only what the demo deployment sends, when the deployment's commands run there, then the stack starts healthy from the base and its demo override, and an application registers. (RQ-06)
- **AC-09:** Following `docs/migration.md`, the routes of Turu (`/mcp`, its discovery document, `/assets/`, the 64 MB upload), Hurura'a (`/assets/`) and Faito are written as routes files: Hurura'a's and Faito's register in both environments; Turu's registers in dev, and on the demo host is refused for its MCP server role, naming the README entry that is missing. (RQ-04, RQ-08)
- **AC-11:** Given a project without i18n, when its routes file sends `/ui/` to the front end, then in dev `/ui/` reaches `http://host.docker.internal:<prefix>200`. (RQ-04)
- **AC-10:** Given the dev override, then `docker compose config` lists every published port on `127.0.0.1` (c4-infra 0001's AC-01, run again); given the demo override, only 80 and 443. (RQ-09)

## Intent questions

- Caddy in dev, one site file, one compose base → PA-01, PA-02.

## Change log

- v1 — 2026-10-21 — first version
- v1 — 2026-10-21 — draft: coherence review (risk high, demo exposure kept, upstreams by role from the registry, dev/demo setting kept for 0005, skills follow-up), PA-01 and PA-02 decided
- v1 — 2026-10-21 — draft: second coherence review (demo upstreams on the fixed container ports, host names from the registry, an environment setting instead of `PROXY`, ports in the overrides only, criteria for RQ-06 to RQ-09)
- v1 — 2026-10-21 — draft: third coherence review (schemes per role and environment, the `ui` front end, no demo port for the MCP server until one is deployed there)
- v1 — 2026-10-21 — approved: every point of attention decided; tech lead's agreement for the high risk (Jérôme Wacongne, PO and tech lead)
