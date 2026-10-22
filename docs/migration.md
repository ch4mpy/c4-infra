# Moving a project onto c4-infra

How a project that still runs its own copy of the shared services (Turu, Hurura'a, Tickee, created
with the former `create-dev-infra` skill) moves onto this stack. Faito was created on it, with the
updated skills: its repository is the reference for every file named below.

Until a project has moved, it can't run at the same time as `c4-infra` (same ports); `c4-infra/up.sh`
names its containers. Going back meanwhile: `docker compose -p c4-infra stop`, then
`docker start $(docker ps -aq -f name=^<project>\\.)`.

## In dev

On a branch of its own (each project's SDLC: an intent, then a plan), from a clean working tree.

1. **Port block.** Take the project's number in the registry, [`registry.txt`](../registry.txt)
   (`n`, prefix `p = 10 + n`; the block rule is the [README's](../README.md#port-registry)). Turu,
   Hurura'a and Tickee have theirs. A project without one, and the `create-dev-infra` skill for a
   new project, rely on this contract:
   - `bash registry.sh next`, in c4-infra, prints the number to take: the smallest one no entry
     has, from 1 to 38;
   - the entry is one line of `registry.txt`, in these columns:

     ```text
     n app realms rabbitmq-user themes dev-host demo-host
     ```

     spaces between the columns, commas inside a list, `-` for none. Faito's:

     ```text
     4 faito faito faito-api - faito.dev.localhost faito.c4-soft.com
     ```

   - the line is added in a commit of its own, before anything registers: `register-app.sh`
     registers nothing for an application missing from the registry, and `up.sh` and
     `register-app.sh` stop on a line sharing a number, a name, a realm, a theme, a RabbitMQ user or
     a host name with another (`bash registry.sh check` names both lines);
   - what each column then allows: `n` the ports of the block, from which the reverse proxy's
     upstreams are derived (intent 0003); `app` the name the project registers under (its RabbitMQ
     virtual host; on the demo host its account, intent 0002, and its network `c4-infra.<app>`,
     intent 0007); `realms`, `rabbitmq-user` and `themes` what its registrations may create or
     change (intent 0002); `dev-host` and `demo-host` the host names its site is served on
     (intent 0003).

   Every port of the project moves into its block:

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
5. **Routes file**: `reverse-proxy/<project>.routes`, the paths of the project's site, the same
   file in dev and on the demo host (notation, roles and upstreams: the
   [README's "Routes file"](../README.md#routes-file)). One line per path the project's
   `nginx-reverse-proxy/nginx.conf` (or its demo Caddyfile) served beyond the shared ones, each
   naming the role it goes to, never a host or a port: `/gateway/*`, the front ends (`/fr/*`,
   `/en/*`, or `/ui/*` without i18n), `/assets/`, `/mcp`,
   `/.well-known/oauth-protected-resource/mcp`, special routes (a regular expression, a body
   limit), in the order they must be tried, the narrowest first. Turu's, Hurura'a's and Faito's
   are written: [`examples/routes/`](../examples/routes/) (copy the project's into its
   `reverse-proxy/`). `register-app.sh --proxy reverse-proxy/<project>.routes` generates the
   project's site, on its registry entry's dev host name; the dev and demo upstreams are derived
   from its number (no port in the file).
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
4. No Caddy site to write: its workflow sends its dev routes file, `reverse-proxy/<project>.routes`
   (dev step 5), with the rest: `rsync` to `~/<project>/` as `deploy@<vps>`,
   `docker compose up -d --wait`, then
   `bash ~/c4-infra/register-app.sh --app <project> --realm … --proxy <project>.routes --rabbitmq-user …
   --rabbitmq-password-env …` (no password on a command line). The site is generated on its demo
   host name, to its containers on the ports the README fixes (`<project>.gateway:7080`,
   `<project>.frontend:80`). A route to the `mcp` role is refused there until the README fixes the
   MCP server's container port. Its secrets no longer include Keycloak's, Mailpit's, RabbitMQ's
   admin or Grafana's.
5. Users created during a demo live in the former Keycloak: export the realm from it
   (`kc.sh export --realm <realm> --users realm_file`) before switching, and register that export.
6. `deploy/backup.sh`: only the project's databases (c4-infra backs Keycloak up).

## Per project

### Turu (n° 1, ports 11xxx, realm `turu`)

- Branch `master`; uncommitted work in progress on it: migrate once it is committed.
- MCP server (`mcp-server`, 9080 → 11280, management 9081 → 11281) and its clients in the realm
  (`turu-mcp`, `turu-agent-dev`, `turu-agent-dev-actor`): routes `/mcp` and
  `/.well-known/oauth-protected-resource/mcp` to the `mcp` role; drop the
  `/.well-known/oauth-authorization-server/...` and `/.well-known/openid-configuration/...` routes
  (c4-infra serves them). `keycloak/check-agent-delegation.sh` may name the old ports.
- Extra routes: `/assets/` → the `fr` front end, prefixed with `/fr`; the migration runs upload
  (`~^/gateway/bff/api/v1/agencies/[^/]+/migrations/[^/]+/runs$`, to the gateway, `max-body=64MB`),
  first. All in [`examples/routes/turu.routes`](../examples/routes/turu.routes).
- `.env`: `MAIL_SSL_TRUST=host.docker.internal` stays (the shared Mailpit serves a leaf signed by
  the same CA, valid for that host).
- No demo deployment yet.

### Hurura'a (n° 2, ports 12xxx, realm `public-facing`)

- Branch `0004-hururaa-application-comme-les-autres` in progress.
- The realm also holds the sample applications' clients (`te-fenua-*`, `escales-*`, `anahei-*`):
  only `hururaa-bff`'s URLs move to `hururaa.dev.localhost`; the others keep theirs.
- Extra route: `/assets/` → the `fr` front end, prefixed with `/fr` (pf-ui's images, absolute
  paths): [`examples/routes/hururaa.routes`](../examples/routes/hururaa.routes).
- Demo on `hururaa.c4-soft.com`: steps above; the demo users and the clients Hurura'a provisions
  are in the former Keycloak's H2 volume (export first, step 5).

### Tickee (n° 3, ports 13xxx, realms `tickee`, `brasserie`, `tenant2`, `tenant3`)

- Four realm files: `deploy-dev.sh` registers every `keycloak/import/*-realm.json`.
- Theme `tickee` (`keycloak/themes/tickee`): installed by `register-app.sh --themes`. To iterate on
  it in dev, edit it, run `bash ../c4-infra/register-app.sh --app tickee --themes keycloak/themes`
  (or `deploy-dev.sh`), then reload the login page: the dev Keycloak caches no theme and isn't
  restarted, so the other applications' sessions stay valid.
- `tenant2` federates the LDAP server `ldap://tickee.ldap-tenant2:389`, now started by the
  project's own compose (move `ldap2` out of `compose-keycloak.yml`), on the `c4-infra` network,
  in dev as in the demo.
- The realm `tickee` has two BFF clients with back-channel logout (`gateway` and `tickee-bff`):
  both URLs move to the gateway's port.
- Demo: steps above (the LDAP container joins `c4-infra`).

### Faito (n° 4, ports 14xxx, realm `faito`)

- Created on this stack: nothing to migrate but its site. Its routes file,
  [`examples/routes/faito.routes`](../examples/routes/faito.routes), replaces its nginx block
  `reverse-proxy/faito.conf` (Faito 0021: copied to `reverse-proxy/faito.routes`, passed to
  `--proxy`). Until then, `register-app.sh` registers c4-infra's copy in place of the `.conf`, with
  a warning.
