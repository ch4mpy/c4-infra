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
     virtual host; on the demo host its account, intent 0002; its network `c4-infra.<app>`, in dev
     as on the demo host, intent 0007); `realms`, `rabbitmq-user` and `themes` what its
     registrations may create or change (intent 0002); `dev-host` and `demo-host` the host names
     its site is served on (intent 0003).

   Every port of the project moves into its block:

   | Process | Before | After |
   |---|---|---|
   | front `fr` / `en` | 4200 / 4205 | p200 / p205 |
   | gateway / management | 7080 / 7081 | p080 / p081 |
   | REST API / management | 8080 / 8081 | p180 / p181 |
   | MCP server / management | 9080 / 9081 | p280 / p281 |
   | REST API database | 2633 | p633 |
   | `openapi` profile: gateway / REST API | dev ports | p090 / p190, passed as `--server.port` |
   | `openapi` profile: their management | dev ports + 1 | p091 / p191, passed as `--management.server.port` (else they take the dev applications' p081 / p181) |

   In `application.yml`'s default and dev profiles, not the `demo` one's (`server.port`,
   `management.server.port`, `rest-api-v1` and the like), the poms' `integration-tests.port`
   (`openapi` profile), `angular.json` / `package.json` (`--port`), `.env` (`REST_API_DB_PORT`) and
   `.vscode/launch.json` if it names ports.

   Only what runs on the workstation moves. On the demo host the containers keep their ports and
   publish none: its Caddy reaches `<project>.gateway:7080`, `<project>.frontend:80` and
   `<project>.mcp:9080` (`registry.sh upstream`). So a port the default profile moved is set back
   for the demo containers, by their `demo` profile or their compose file's environment
   (`SERVER_PORT`): the gateway's `7080`, the MCP server's `9080`, the REST API's `8080`, which the
   demo `rest-api-v1` names, and the management ports the compose file's healthchecks name.
2. **Origin.** The project is served on `https://<project>.dev.localhost/`:
   - gateway: a new `app-uri: https://<project>.dev.localhost` replaces `reverse-proxy-uri` in
     `client-uri`, `post-login-*` and `post-logout-*` (the allowed patterns become
     `${app-uri}(/.*)?`); the `issuer` stays `https://${cn}/auth/realms/<realm>`, written without
     `reverse-proxy-uri`; `back-channel-logout.internal-logout-uri` becomes
     `https://${cn}:${server.port}${server.servlet.context-path}/logout/connect/back-channel/<registration>`;
   - REST API: `issuer` and the Keycloak admin client's base URI on `https://${cn}/auth`, without
     a port (a project's own Keycloak port, such as Tickee's `:3643`, goes: the proxy serves
     Keycloak); in its `demo` profile, the admin client on `http://keycloak:8080/auth`;
   - an MCP server: it is served on an origin of its own, `https://<project>-mcp.dev.localhost/`
     (c4-infra 0013: the project's cookies never reach it), its protected resource
     `https://<project>-mcp.dev.localhost/mcp`, which it derives from `X-Forwarded-Host` and
     `X-Forwarded-Proto` (Spring: `server.forward-headers-strategy: framework`); a command-line MCP
     client needs `127.0.0.1 <project>-mcp.dev.localhost` in the hosts file. The authorization
     server metadata (`/.well-known/oauth-authorization-server/auth/realms/<realm>`) is served by
     the shared host, for every realm: drop the project's own route;
   - TLS, as Faito: the gateway, the REST API and the MCP server serve c4-infra's leaf
     (`${C4_INFRA_CERTS_DIR}/tls.crt` and `tls.key`, an SSL bundle) and trust its local CA through
     the JDK's trust store (`bash ../c4-infra/certs/trust-ca-in-jdk.sh <JDK home>`); no certificate
     is packed into the jars anymore; CI generates a throwaway pair and sets `C4_INFRA_CERTS_DIR`;
   - Angular: `serve.options.allowedHosts: ["<project>.dev.localhost"]` (instead of
     `host.docker.internal`).
3. **Unique names in the shared services**: `spring.application.name` of the gateway becomes
   `<project>-gateway` (Grafana tells the services apart by it); `spring.rabbitmq.virtual-host:
   <project>` in every module that uses RabbitMQ.
4. **Realm(s)**: in `keycloak/import/*-realm.json`, each BFF client's `rootUrl`, `adminUrl`,
   `baseUrl` and `post.logout.redirect.uris` on `https://<project>.dev.localhost/`, and its
   `backchannel.logout.url` on the gateway itself:
   `https://host.docker.internal:p080/gateway/logout/connect/back-channel/<registration>` (its
   `adminUrl` too); each organization's `redirectUrl` on the new origin
   (`https://<project>.dev.localhost/<locale>/…`). Empty the realm's keys, `"org.keycloak.keys.KeyProvider" : [ ]`: the realms
   exported from the former template all carry its private keys, which would let anyone who reads
   them sign tokens; Keycloak generates new ones on import. The
   SMTP server stays `host.docker.internal:1025`. Export the realm from the project's Keycloak
   first (`keycloak/export.sh`) if it holds users or settings not committed yet. Then give each
   realm file ids of its own, once: `bash ../c4-infra/new-realm-ids.sh keycloak/import/*-realm.json`.
   The realms created from the former skill's template all carry its ids, which the shared
   database refuses twice ("Duplicate resource error"). The script prints the users' new ids:
   update whatever the project stores about them (dev seed data such as Liquibase `dev` contexts,
   tests naming a user id). It maps each file on its own: a reference from one realm file to
   another's ids (Tickee's `federatedIdentities[].userId`, which name users of its tenants' realms)
   breaks, and is rewritten with the ids it printed for that other file.
5. **Routes file**: `reverse-proxy/<project>.routes`, the paths of the project's site, the same
   file in dev and on the demo host (notation, roles and upstreams: the
   [README's "Routes file"](../README.md#routes-file)). One line per path the project's
   `nginx-reverse-proxy/nginx.conf` (or its demo Caddyfile) served beyond the shared ones, each
   naming the role it goes to, never a host or a port: `/gateway/*`, the front ends (`/fr/*`,
   `/en/*`, or `/ui/*` without i18n), `/assets/`, `/mcp`,
   `/.well-known/oauth-protected-resource/mcp`, special routes (a regular expression, a body
   limit), in the order they must be tried, the narrowest first; the `mcp` routes are served on the
   project's MCP origin, the others on its own. Turu's, Hurura'a's and Faito's
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
   services must reach (a directory a realm federates, which the project runs and maintains itself,
   the stack providing none; the gateway runs on the host, step 4) joins the project's own network
   `c4-infra.<project>` as an external one, never `c4-infra` (the shared services' own), under a
   unique container name: `deploy-dev.sh`'s registration creates that network and attaches the
   shared services to it (c4-infra's README, "One network per application").
7. **Keycloak in its tests**: tests that start a Keycloak of their own (Testcontainers) run the
   stack's: the image `KC_PUBLISHED_IMAGE` of c4-infra's `keycloak-image.properties`, or upstream
   Keycloak with its `KC_VERSION` and `KC_FEATURES`; never a floating tag (c4-infra's README,
   ["Keycloak in an application's tests"](../README.md#keycloak-in-an-applications-tests)).
8. **Docs**: `CLAUDE.md` / `.claude/README.md` (ports, host names, the shared stack), `README.md`.
9. **Check**: `./deploy-dev.sh`, start the apps, log in and out on
   `https://<project>.dev.localhost/`, then end the session from Keycloak's admin console (the
   back-channel logout must log the gateway session out). Then stop the project's former
   containers for good: `docker compose -p <project> down` (its volumes stay until `-v`).

## On the demo host

The demo host deploys GitHub projects, each from its own GitHub Actions workflow. A GitLab project
(immo) isn't deployed by this stack: "In dev" applies to it, not these steps.

1. c4-infra runs on the demo host (deployed since 2026-10-23, its README). Its Caddy holds ports 80
   and 443: a project's own Caddy can't run beside it, so a project still deploying one on that
   host moves in one maintenance window.
2. **Its account** on the host, `<project>`, named after its registry entry, opened by its own key
   only: [demo-setup.md](demo-setup.md), step 9, "Adding an application" (its registry entry
   deployed, its key pair, `vps-bootstrap.sh app <project> '<key>'`, its secrets `VPS_HOST`,
   `VPS_SSH_KEY` and `VPS_KNOWN_HOSTS`). That account isn't in the `docker` group: the project
   deploys through `sudo c4-app` only, which acts on its own compose project and registers it with
   what its registry entry assigns to it ([README](../README.md), "Accounts").
3. What its workflow sends to `~/<project>/`, a `deploy/` directory of the runner: `compose.yml`
   (the project's compose model, at its root), its `.env` (written on the runner, mode 600: the
   variables compose interpolates, and the RabbitMQ password), its routes file, its rendered realm
   file(s) and its themes, if any; nothing that is a symbolic link (`c4-app` refuses it). In
   `compose.yml`: drop `caddy`, `keycloak`, `mailpit`, `rabbitmq` and `grafana-lgtm`; the services
   that need the shared ones (gateway, API, frontend, a directory a realm federates) join the
   project's own network `c4-infra.<project>` as an external one (its registration creates it and
   attaches the shared services to it, under their usual names), never `c4-infra`, and keep their unique
   `container_name` (`<project>.gateway`…); the databases stay on the project's network only; every
   file it mounts or reads (`env_file`) is inside `~/<project>/`, relative to it (the model is read
   as the project's account: it can't read any other). Its data go in named volumes: what is
   mounted from `~/<project>/` is root's copy, made again, as sent, by each `sudo c4-app` command.
   Every service runs an `image:`, pulled as it is: the project's own, built and pushed by its CI
   to its registry (GHCR, GitLab's, any registry `sudo c4-app pull --registry` logs in to), or a
   public one (`postgres`…). `sudo c4-app up` pulls the images the host lacks without logging in
   anywhere: an image behind a login comes first through `sudo c4-app pull --registry <host>
   --registry-user <user>` (step 5 below, which gives the forms it accepts), one registry per pull,
   which pulls every image under that login: the private ones come from one registry. No `build:`,
   which `sudo c4-app up` and `pull` refuse (the demo host builds nothing, intent 0011).
   No published port, no `network_mode`, no other network, no alias or container name outside
   `<project>.`, nothing privileged: `sudo c4-app up` refuses them, naming the rule (c4-infra's
   README, "Accounts"):

   ```yaml
   services:
     gateway:
       container_name: <project>.gateway
       networks: [c4-infra.<project>, default]
   networks:
     c4-infra.<project>:
       external: true
   ```

   No `logging:` either, nor the `x-logging` anchor its services reference: `sudo c4-app up` and
   `pull` refuse it, and the host bounds every container's output itself, to 30 MB, the oldest lines
   dropped first (c4-infra's README, "Accounts"). That output is a short buffer, which only
   `c4-infra` reads: for its history, the project exports its logs, traces and metrics by OTLP to
   Grafana LGTM, `http://grafana-lgtm:4318/v1/logs`, `/v1/traces` and `/v1/metrics` on
   `c4-infra.<project>` (in dev, `http://host.docker.internal:4318/v1/…`), which keeps them 14 days.
   Every application's network can read them (c4-infra's README, "Reachable from an application's
   network"): nothing secret in them. With Spring Boot 4, as Faito's backend exports them in dev
   (`spring-boot-starter-opentelemetry`, and OpenTelemetry's Logback appender,
   `opentelemetry-logback-appender-1.0`, declared in its `logback-spring.xml` and installed by its
   `OpenTelemetryConfiguration`: Spring Boot ships none), the `application.yml` sets the dev
   endpoints, and the `demo` profile the demo host's (Faito's doesn't yet):

   ```yaml
   management:
     opentelemetry:
       tracing.export.otlp.endpoint: http://host.docker.internal:4318/v1/traces
       logging.export.otlp.endpoint: http://host.docker.internal:4318/v1/logs
     otlp.metrics.export.url: http://host.docker.internal:4318/v1/metrics
   ---
   spring.config.activate.on-profile: demo
   management:
     opentelemetry:
       tracing.export.otlp.endpoint: http://grafana-lgtm:4318/v1/traces
       logging.export.otlp.endpoint: http://grafana-lgtm:4318/v1/logs
     otlp.metrics.export.url: http://grafana-lgtm:4318/v1/metrics
   ```
4. Its realm rendering (`deploy/keycloak/render-realms.sh`), into `deploy/<realm>-realm.json` (the
   file's name is the realm it is imported as, one of its registry entry's): no
   `org.keycloak.keys.KeyProvider` components (the dev keys are in the repository), issuer host
   `infra.c4-soft.com`, the BFF's redirect URIs on `<project>.c4-soft.com`, back-channel logout on
   `http://<project>.gateway:7080/gateway/logout/connect/back-channel/<registration>`, SMTP
   `mailpit:1025` with c4-infra's `MAILPIT_SMTP_PASSWORD`. Its brute-force settings needn't be
   rendered: `register-app.sh` replaces them at import with c4-infra's (README, "Brute-force
   protection"), in dev as on the demo host.
5. **Its workflow**, as `<project>@<vps>`: the host's key pinned before anything connects (the lines
   of c4-infra's [`demo/trust-host-key.sh`](../demo/trust-host-key.sh), inline), every action pinned
   by commit (the tag as a comment: the ssh agent receives the private key), then `rsync` to
   `~/<project>/`, `sudo c4-app pull` (its registry's token on stdin: GHCR's here),
   `sudo c4-app register` (paths relative to `~/<project>/`; `--rabbitmq-password-env` names a
   variable of `~/<project>/.env`) and `sudo c4-app up`:

   ```yaml
     deploy:
       runs-on: ubuntu-latest
       environment: demo
       permissions:
         contents: read
         packages: read
       env:
         VPS: <project>@${{ secrets.VPS_HOST }}
       steps:
         - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

         - name: Trust the VPS host key
           # c4-infra's demo/trust-host-key.sh: no connection to a host whose key isn't pinned
           run: |
             if [ -z "${VPS_KNOWN_HOSTS:-}" ]; then
               echo "::error::VPS_KNOWN_HOSTS is not set: the deployment connects only to a host whose key is pinned (docs/demo-setup.md, step 4, \"Host key\")"
               exit 1
             fi
             mkdir -p "$HOME/.ssh"
             chmod 700 "$HOME/.ssh"
             printf '%s\n' "$VPS_KNOWN_HOSTS" >> "$HOME/.ssh/known_hosts"
           env:
             VPS_KNOWN_HOSTS: ${{ secrets.VPS_KNOWN_HOSTS }}

         # ... the project's own steps: deploy/.env (mode 600), its realm rendered into deploy/ ...

         - uses: webfactory/ssh-agent@e83874834305fe9a4a2997156cb26c5de65a8555 # v0.10.0
           with:
             ssh-private-key: ${{ secrets.VPS_SSH_KEY }}

         - name: Deploy
           # the token on stdin, never on a command line; the registration with c4-infra's
           # registration account, which this account can't read
           run: |
             rsync -az --delete deploy/ "$VPS:~/<project>/"
             ssh "$VPS" sudo c4-app pull --registry ghcr.io --registry-user "$GHCR_USER" <<< "$GHCR_TOKEN"
             ssh "$VPS" sudo c4-app register --realm <realm>-realm.json --proxy <project>.routes --rabbitmq-user <project>-api --rabbitmq-password-env RABBITMQ_PASSWORD
             ssh "$VPS" sudo c4-app up
           env:
             GHCR_USER: ${{ github.actor }}
             GHCR_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

   On another platform (GitLab, any CI that runs a shell), the job does the same, in the same order:
   the host's key pinned from `VPS_KNOWN_HOSTS` before anything connects (the lines of
   `demo/trust-host-key.sh`), `VPS_SSH_KEY` in an ssh agent, what the job runs pinned as the
   actions are (an image by digest, anything it includes by commit), then the `rsync`,
   `sudo c4-app pull --registry <registry host> --registry-user <user>` with the registry's token on
   stdin, read from a secret variable of the platform (never on a command line), `register` and
   `up`. `--registry` takes a host name, with an optional `:port` and no path; `--registry-user`
   letters, digits, `.`, `_` and `-`. Without `--registry`, `pull` logs in nowhere, which is enough
   when every image is public. `VPS_HOST`, `VPS_SSH_KEY` and `VPS_KNOWN_HOSTS` become secret
   variables of that platform, given only to the deployment's protected branch or environment (as
   `environment: demo` does here), and never printed by the job.

   A project without messaging leaves out `--rabbitmq-*`; one with themes adds `--themes <dir>` (a
   directory of `~/<project>/`, holding its registry entry's themes only). No Caddy site to write:
   its dev routes file, `reverse-proxy/<project>.routes` (dev step 5), gives its site on its demo
   host name, to its containers on the ports the README fixes (`<project>.gateway:7080`,
   `<project>.frontend:80`, its MCP server `<project>.mcp:9080` on
   `https://<project>-mcp.c4-soft.com/`, which needs a DNS record of its own:
   [demo-setup.md](demo-setup.md), step 1). A realm, a theme or a RabbitMQ user its registry entry doesn't
   assign is refused, before anything changes. Its secrets no longer include Keycloak's, Mailpit's,
   RabbitMQ's admin or Grafana's.
6. Users created during a demo live in the former Keycloak: export the realm from it
   (`kc.sh export --realm <realm> --users realm_file`) before switching, and register that export.
7. `deploy/backup.sh` goes: the demo host backs up each application's data every night at 03:45
   ([README](../README.md), "Backups"), as its account runs no `docker` command. The project labels
   the services that hold its data in its `compose.yml`: `c4-infra.backup: postgres` on a
   PostgreSQL service (a hot dump of its `POSTGRES_DB`), `c4-infra.backup: volumes` on a service
   whose named volumes are copied, the service stopped meanwhile. Tickee: `rest-api-db` `postgres`,
   and `ldap2` `volumes` if its directory is to be kept rather than rebuilt from `ldap/*.ldif`;
   immo: `rest_api_db` `postgres`, `rustfs` `volumes`. Its workflow may run
   `ssh "$VPS" sudo c4-app backup` before a deployment that migrates its database. Its backups are
   in `/var/backups/c4-apps/<project>/`, which its account reads (and may pull with `rsync`), kept 7
   days; `sudo c4-app restore` lists them, `sudo c4-app restore <stamp> --yes` restores one, once
   the state before is backed up.

## Per project

### Turu (n° 1, ports 11xxx, realm `turu`)

- Branch `master` until its first demo deployment.
- MCP server (`mcp-server`, 9080 → 11280, management 9081 → 11281) and its clients in the realm
  (`turu-mcp`, `turu-agent-dev`, `turu-agent-dev-actor`): routes `/mcp` and
  `/.well-known/oauth-protected-resource/mcp` to the `mcp` role, served on
  `turu-mcp.dev.localhost` and `turu-mcp.c4-soft.com`; drop the
  `/.well-known/oauth-authorization-server/...` and `/.well-known/openid-configuration/...` routes
  (c4-infra serves them). Its agents' delegation relies on the shared Keycloak's
  `token-exchange-delegation` and `parameterized-scopes` (c4-infra 0013);
  `keycloak/check-agent-delegation.sh` may name the old ports.
- Extra route: the migration runs upload
  (`~^/gateway/bff/api/v1/agencies/[^/]+/migrations/[^/]+/runs$`, to the gateway, `max-body=64MB`),
  first. No `/assets/` route: its front end (Material) names no absolute `/assets/` path. All in
  [`examples/routes/turu.routes`](../examples/routes/turu.routes).
- `.env`: `MAIL_SSL_TRUST=host.docker.internal` stays (the shared Mailpit serves a leaf signed by
  the same CA, valid for that host).
- Demo on `turu.c4-soft.com`, its MCP server `turu.mcp:9080` on `turu-mcp.c4-soft.com` (two DNS
  records): steps above.

### Hurura'a (n° 2, ports 12xxx, realm `public-facing`)

- Branch `0004-hururaa-application-comme-les-autres` in progress.
- The realm also holds the sample applications' clients (`te-fenua-*`, `escales-*`, `anahei-*`):
  only `hururaa-bff`'s URLs move to `hururaa.dev.localhost`; the others keep theirs.
- Extra route: `/assets/` → the `fr` front end, prefixed with `/fr` (pf-ui's images, absolute
  paths): [`examples/routes/hururaa.routes`](../examples/routes/hururaa.routes).
- Demo on `hururaa.c4-soft.com`: steps above; the demo users and the clients Hurura'a provisions
  are in the former Keycloak's H2 volume (export first, step 6).

### Tickee (n° 3, ports 13xxx, realms `tickee`, `brasserie`, `tenant2`, `tenant3`)

- Four realm files: `deploy-dev.sh` registers every `keycloak/import/*-realm.json`.
- Theme `tickee` (`keycloak/themes/tickee`): installed by `register-app.sh --themes`. To iterate on
  it in dev, edit it, run `bash ../c4-infra/register-app.sh --app tickee --themes keycloak/themes`
  (or `deploy-dev.sh`), then reload the login page: the dev Keycloak caches no theme and isn't
  restarted, so the other applications' sessions stay valid.
- `tenant2` federates Tickee's own LDAP server, `ldap://tickee.ldap-tenant2:389`: its `ldap2`
  container, now started by the project's own compose (move `ldap2` out of `compose-keycloak.yml`),
  on Tickee's own network `c4-infra.tickee` (external), in dev as in the demo. Tickee runs,
  monitors and upgrades it: the stack provides no directory (intent 0023). Keycloak, attached to
  that network by Tickee's registration, federates it, and no other application's container
  reaches it.
- The realm `tickee` has two BFF clients with back-channel logout (`gateway` and `tickee-bff`):
  both URLs move to the gateway's port.
- Demo: steps above (Tickee's `ldap2` container joins `c4-infra.tickee`).

### Faito (n° 4, ports 14xxx, realm `faito`)

- Created on this stack: nothing to migrate but its site. Its routes file,
  [`examples/routes/faito.routes`](../examples/routes/faito.routes), replaces its nginx block
  `reverse-proxy/faito.conf` (Faito 0021: copied to `reverse-proxy/faito.routes`, passed to
  `--proxy`). Since c4-infra 0013, `register-app.sh` refuses a `.conf`, as any file that isn't a
  routes file.
