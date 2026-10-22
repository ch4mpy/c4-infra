# Moving a project onto c4-infra

How a project that still runs its own copy of the shared services (Turu, Hurura'a, Tickee, created
with the former `create-dev-infra` skill) moves onto this stack. Faito was created on it, with the
updated skills: its repository is the reference for every file named below.

Until a project has moved, it can't run at the same time as `c4-infra` (same ports); `c4-infra/up.sh`
names its containers. Going back meanwhile: `docker compose -p c4-infra stop`, then
`docker start $(docker ps -aq -f name=^<project>\\.)`.

## In dev

On a branch of its own (each project's SDLC: an intent, then a plan), from a clean working tree.

1. **Port block.** Take the project's number in the [registry](../README.md#port-registry)
   (`n`, prefix `p = 10 + n`). Every port of the project moves into its block:

   | Process | Before | After |
   |---|---|---|
   | front `fr` / `en` | 4200 / 4205 | p200 / p205 |
   | gateway / management | 7080 / 7081 | p080 / p081 |
   | REST API / management | 8080 / 8081 | p180 / p181 |
   | MCP server / management | 9080 / 9081 | p280 / p281 |
   | REST API database | 2633 | p633 |
   | `openapi` profile: gateway / REST API | dev ports | p090 / p190, passed as `--server.port` |

   In `application.yml` (`server.port`, `management.server.port`, `rest-api-v1` and the like), the
   poms' `integration-tests.port` (`openapi` profile), `angular.json` / `package.json` (`--port`),
   `.env` (`REST_API_DB_PORT`) and `.vscode/launch.json` if it names ports.
2. **Origin.** The project is served on `https://<project>.dev.localhost/`:
   - gateway: a new `app-uri: https://<project>.dev.localhost` replaces `reverse-proxy-uri` in
     `client-uri`, `post-login-*` and `post-logout-*` (the allowed patterns become
     `${app-uri}(/.*)?`); the `issuer` stays `https://${cn}/auth/realms/<realm>`, written without
     `reverse-proxy-uri`; `back-channel-logout.internal-logout-uri` becomes
     `https://${cn}:${server.port}${server.servlet.context-path}/logout/connect/back-channel/<registration>`;
   - REST API: `issuer` and the Keycloak admin client's base URI on `https://${cn}/auth`, unchanged
     in value;
   - an MCP server: its protected resource becomes `https://<project>.dev.localhost/mcp`; a
     command-line MCP client needs `127.0.0.1 <project>.dev.localhost` in the hosts file. The
     authorization server metadata (`/.well-known/oauth-authorization-server/auth/realms/<realm>`)
     is now served by the shared host, for every realm: drop the project's own route;
   - Angular: `serve.options.allowedHosts: ["<project>.dev.localhost"]` (instead of
     `host.docker.internal`).
3. **Unique names in the shared services**: `spring.application.name` of the gateway becomes
   `<project>-gateway` (Grafana tells the services apart by it); `spring.rabbitmq.virtual-host:
   <project>` in every module that uses RabbitMQ.
4. **Realm(s)**: in `keycloak/import/*-realm.json`, each BFF client's `rootUrl`, `adminUrl`,
   `baseUrl` and `post.logout.redirect.uris` on `https://<project>.dev.localhost/`, and its
   `backchannel.logout.url` on the gateway itself:
   `https://host.docker.internal:p080/gateway/logout/connect/back-channel/<registration>` (its
   `adminUrl` too). Empty the realm's keys, `"org.keycloak.keys.KeyProvider" : [ ]`: the realms
   exported from the former template all carry its private keys, which would let anyone who reads
   them sign tokens; Keycloak generates new ones on import. The
   SMTP server stays `host.docker.internal:1025`. Export the realm from the project's Keycloak
   first (`keycloak/export.sh`) if it holds users or settings not committed yet. Then give each
   realm file ids of its own, once: `bash ../c4-infra/new-realm-ids.sh keycloak/import/*-realm.json`.
   The realms created from the former skill's template all carry its ids, which the shared
   database refuses twice ("Duplicate resource error"). The script prints the users' new ids:
   update whatever the project stores about them (dev seed data such as Liquibase `dev` contexts,
   tests naming a user id).
5. **Reverse proxy**: `reverse-proxy/<project>.conf`, the project's `server` for
   `<project>.dev.localhost` (see Faito's, or `create-dev-infra/reverse-proxy/i18n.conf`), with the
   routes the project's `nginx-reverse-proxy/nginx.conf` had beyond the shared ones (`/assets/`,
   `/mcp`, `/.well-known/oauth-protected-resource/mcp`, special routes), on the new ports.
6. **Scripts**: `build-0-env.sh`, `deploy-dev.sh` and `keycloak/export.sh` from the
   `create-dev-infra` skill (placeholders replaced as its SKILL.md says), `compose-rest-api-db.yml`
   kept. Delete `build-1-images.sh`, `compose-keycloak.yml`, `compose-mailpit.yml`,
   `compose-observability.yml`, `compose-rabbitmq.yml`, `compose-reverse-proxy.yml`,
   `nginx-reverse-proxy/`, `keycloak/Dockerfile`, `keycloak/HealthCheck.java` and the Keycloak and
   mail entries of `.env` and `secrets/`. Another container of the project that the shared
   Keycloak must reach (an LDAP server of a user federation) joins the external network
   `c4-infra`, under a unique container name.
7. **Docs**: `CLAUDE.md` / `.claude/README.md` (ports, host names, the shared stack), `README.md`.
8. **Check**: `./deploy-dev.sh`, start the apps, log in and out on
   `https://<project>.dev.localhost/`, then end the session from Keycloak's admin console (the
   back-channel logout must log the gateway session out). Then stop the project's former
   containers for good: `docker compose -p <project> down` (its volumes stay until `-v`).

## On the demo host

1. Deploy `c4-infra` on the VPS first (its README). Its Caddy takes ports 80 and 443: a project
   still deploying its own Caddy on the same host must move in the same maintenance window.
2. In the project's `deploy/compose.yml`: drop `caddy`, `keycloak`, `mailpit`, `rabbitmq` and
   `grafana-lgtm`; the services that need the shared ones (gateway, API, frontend, an LDAP
   server) join the external network `c4-infra` and keep their unique `container_name`
   (`<project>.gateway`…); the databases stay on the project's network only.
3. Its realm rendering (`deploy/keycloak/render-realms.sh`): no `org.keycloak.keys.KeyProvider`
   components (the dev keys are in the repository), issuer host `infra.c4-soft.com`, the
   BFF's redirect URIs on `<project>.c4-soft.com`, back-channel logout on
   `http://<project>.gateway:7080/gateway/logout/connect/back-channel/<registration>`, SMTP
   `mailpit:1025` with c4-infra's `MAILPIT_SMTP_PASSWORD`.
4. Its Caddy site, `deploy/caddy/<project>.caddy` (example in the README), and its workflow:
   `rsync` to `~/<project>/` as `deploy@<vps>`, `docker compose up -d --wait`, then
   `bash ~/c4-infra/register-app.sh --app <project> --realm … --proxy <project>.caddy --rabbitmq-user …
   --rabbitmq-password-env …` (no password on a command line). Its secrets no longer include Keycloak's, Mailpit's, RabbitMQ's admin
   or Grafana's.
5. Users created during a demo live in the former Keycloak: export the realm from it
   (`kc.sh export --realm <realm> --users realm_file`) before switching, and register that export.
6. `deploy/backup.sh`: only the project's databases (c4-infra backs Keycloak up).

## Per project

### Turu (n° 1, ports 11xxx, realm `turu`)

- Branch `master`; uncommitted work in progress on it: migrate once it is committed.
- MCP server (`mcp-server`, 9080 → 11280, management 9081 → 11281) and its clients in the realm
  (`turu-mcp`, `turu-agent-dev`, `turu-agent-dev-actor`): routes `/mcp` and
  `/.well-known/oauth-protected-resource/mcp` in `reverse-proxy/turu.conf`; drop the
  `/.well-known/oauth-authorization-server/...` and `/.well-known/openid-configuration/...` routes
  (c4-infra serves them). `keycloak/check-agent-delegation.sh` may name the old ports.
- Extra routes: `/assets/` → the `fr` dev server; the migration runs upload
  (`~ ^/gateway/bff/api/v1/agencies/[^/]+/migrations/[^/]+/runs$`, proxied without URI rewriting,
  `client_max_body_size 64m`), on 11080.
- `.env`: `MAIL_SSL_TRUST=host.docker.internal` stays (the shared Mailpit serves a leaf signed by
  the same CA, valid for that host).
- No demo deployment yet.

### Hurura'a (n° 2, ports 12xxx, realm `public-facing`)

- Branch `0004-hururaa-application-comme-les-autres` in progress.
- The realm also holds the sample applications' clients (`te-fenua-*`, `escales-*`, `anahei-*`):
  only `hururaa-bff`'s URLs move to `hururaa.dev.localhost`; the others keep theirs.
- Extra route: `/assets/` → the `fr` dev server (pf-ui's images, absolute paths).
- Demo on `hururaa.c4-soft.com`: steps above; the demo users and the clients Hurura'a provisions
  are in the former Keycloak's H2 volume (export first, step 5).

### Tickee (n° 3, ports 13xxx, realms `tickee`, `brasserie`, `tenant2`, `tenant3`)

- Four realm files: `deploy-dev.sh` registers every `keycloak/import/*-realm.json`.
- Theme `tickee` (`keycloak/themes/tickee`): installed by `register-app.sh --themes`.
- `tenant2` federates the LDAP server `ldap://tickee.ldap-tenant2:389`, now started by the
  project's own compose (move `ldap2` out of `compose-keycloak.yml`), on the `c4-infra` network,
  in dev as in the demo.
- The realm `tickee` has two BFF clients with back-channel logout (`gateway` and `tickee-bff`):
  both URLs move to the gateway's port.
- Demo: steps above (the LDAP container joins `c4-infra`).
