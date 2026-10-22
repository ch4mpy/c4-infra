# Intent: Dev doesn't apply the demo's reverse-proxy rules

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (quality review of the shared stack, 2026-10-21)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-21
- Decided: 2026-10-21
- Supersedes: —

## Problem

The dev stack and the demo stack are written twice, in two languages: nginx in dev (`nginx/nginx.conf`, each application's `.conf`), Caddy on the demo host (`demo/caddy/Caddyfile`, each application's `.caddy`), and two compose files repeating the same services and image versions.

- The security headers the demo sends (Content-Security-Policy, HSTS, `X-Frame-Options`…) don't exist in dev: an application that breaks them works in dev and fails first on the public demo. Faito's pages load their fonts from Google, which the demo's policy blocks (Faito 0018), and nothing in dev shows it.
- Each application writes and maintains two server blocks; the skill that creates a project generates only the nginx one, the Caddy one is copied from a README example.
- A shared route (the realm discovery for MCP clients) or an image upgrade has to be made in both places; forgetting one leaves dev and demo on different behaviours or versions.

## Proposed outcome

What an application meets behind the proxy (routes, headers, versions of the shared services) is the same in dev and on the demo host, written once. Success criterion: a page that the demo's security headers would block is blocked in dev too, and an application describes its routes in one file.

## Affected users and systems

- Developer, Application, Demo operator.
- Dev stack, demo stack, registration (`register-app.sh` switches between nginx and Caddy), the `create-dev-infra` skill (what it generates for a project).

## Constraints

- The demo directory is deployed by `rsync` on its own: whatever it needs must be in it, or deployed with it.
- Dev certificates are the local CA's; the demo's are Let's Encrypt's.

## Open questions

- *Suggested solution*: Caddy in dev too, one site file per application with placeholders, one compose base with a dev and a demo override — to be settled in the spec.
