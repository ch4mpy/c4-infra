# c4-infra

The infrastructure the c4-soft applications (Faito, Hurura'a, Tickee, Turu…) share on one machine:
the development workstation, and the demo VPS. One reverse proxy, one Keycloak (a realm or more per
application), one Mailpit, one RabbitMQ (a virtual host per application) and one Grafana LGTM,
instead of a copy of each per project: less memory, and no port conflict between projects.

Each application keeps in its own repository what is its own: its database(s), in its own compose
project; its realm export, its Keycloak theme, its RabbitMQ user, and its reverse-proxy server
block, which it installs here with [`register-app.sh`](register-app.sh) every time it deploys.

## Design

- **One origin per application.** Each application is served on its own host name, with the
  same paths as before the stack was shared (`/fr/`, `/en/`, `/gateway/`, `/mcp`):
  `https://<app>.dev.localhost/` in dev, `https://<app>.c4-soft.com/` on the demo host. Its
  cookies (session, `XSRF-TOKEN` at path `/`), its OAuth discovery documents at the root
  (`/.well-known/oauth-protected-resource/mcp`) and its Content-Security-Policy stay its own.
  Sharing one host with a path prefix per application would have mixed all three; so would
  sharing one host with a port per application (cookies ignore the port).
- **One origin for the shared services**: `https://host.docker.internal/` in dev,
  `https://infra.c4-soft.com/` on the demo host: `/auth/` (Keycloak), `/mailpit/`, `/grafana/`,
  and `/rabbitmq/` in dev. Every realm's issuer is `https://<that host>/auth/realms/<realm>`.
- **Host names that resolve where they are used.** Browsers resolve `*.localhost` to the loopback
  on their own; the JVMs and Node processes of the host don't (Windows doesn't), and neither do the
  containers. Hence the split: everything server-side (issuer, admin API, back-channel logout,
  OTLP, SMTP, AMQP) uses `host.docker.internal`, which reaches the workstation's loopback with
  Docker Desktop (a prerequisite): on the host through the hosts-file line of the prerequisites
  (`127.0.0.1`), in the containers through `extra_hosts: host-gateway`, Docker Desktop's gateway
  address, which it forwards to the host's loopback (Docker Engine on Linux doesn't); only the
  browser uses `<app>.dev.localhost`. A command-line client of an application's own origin
  (an MCP client such as Claude Code) needs a hosts-file line: `127.0.0.1 <app>.dev.localhost`.
- **One certificate.** The leaf the proxy, Keycloak and Mailpit serve is valid for
  `host.docker.internal`, `localhost` and `*.dev.localhost` (browsers refuse a second-level wildcard
  such as `*.localhost`), and signed by the local CA the projects already trust,
  `~/.ssh/host.docker.internal.crt`: adding an application needs no new certificate and no new
  trust ([`certs/make-certs.sh`](certs/make-certs.sh)).
- **Keycloak on PostgreSQL**, so that a realm is exported ([`export-realm.sh`](export-realm.sh))
  and the database backed up while Keycloak keeps serving every other application.
- **A block of 1 000 ports per application** for what runs on the host (dev servers, Spring Boot
  apps, databases), registered below; the shared services keep their usual ports.

## Development

Prerequisites:

- Docker Desktop and Git Bash;
- the local CA trusted by the browsers (it already is if a project was set up on this machine
  before; otherwise `certs/make-certs.sh` creates it and says how to trust it);
- `host.docker.internal` resolving to the loopback on the workstation: the single line
  `127.0.0.1 host.docker.internal` in the hosts file (`C:\Windows\System32\drivers\etc\hosts`,
  `/etc/hosts` elsewhere), and Docker Desktop's option "Add the \*.docker.internal names to the
  host's etc/hosts file" (Settings > General) turned off, since it writes the LAN address instead.
  `up.sh` stops, and says so, when the name resolves elsewhere.

The stack publishes its ports on `127.0.0.1` only, with no setting to open them: nothing of it
answers from the local network (Keycloak's master console, Mailpit, Grafana and RabbitMQ hold every
application's dev data). Testing an application from another device (a phone on the same network)
is not supported: the device would also need host names it resolves, the local CA and return
addresses the gateways allow.

```bash
bash ./up.sh   # writes .env and the certificate on first run, then starts (or updates) the stack
```

Every application's `deploy-dev.sh` runs `up.sh` and then registers itself: there is usually no
need to run anything here by hand. A project still running its own copy of these services holds
their ports: `up.sh` names its containers, to stop first.

| Service | URL | Ports on the host (`127.0.0.1` only) |
|---|---|---|
| Landing page (links to everything registered) | https://host.docker.internal/ | 80, 443 |
| Keycloak (admin `admin` / `secret`) | https://host.docker.internal/auth/admin/ | none: through the proxy only |
| Mailpit | https://host.docker.internal/mailpit/ | 1025 (SMTP, auth `mailpit` / `secret`), 8025 |
| Grafana LGTM | https://host.docker.internal/grafana/ | 3000, 4317 (OTLP gRPC), 4318 (OTLP HTTP) |
| RabbitMQ (admin user and password in `.env`) | https://host.docker.internal/rabbitmq/ | 5672 (AMQP), 15672 |

```bash
docker compose ps                     # health of every shared service
docker compose logs -f keycloak       # or reverse-proxy, rabbitmq...
docker compose stop                   # e.g. to start a project's former stack again
bash ./export-realm.sh faito ../faito/keycloak/import   # realm + users, Keycloak keeps running
```

### Port registry

Application number `n` owns the 1 000 ports starting at `(10 + n) × 1000` (prefix `10 + n`: `14000`–`14999`
for number 4, `20000`–`20999` for number 10); within its block, the offsets are the same for every
application: those of the table, `090` and `190` for the gateway and the REST API that the `openapi`
Maven profile starts to read the specs (not the dev ports: specs are regenerated while the dev
applications run), and a management port, if an application sets one, on its port + 1. Windows reserves
dynamic port ranges from 49152 on (and some fixed ones: `netsh interface ipv4 show
excludedportrange protocol=tcp`), so blocks stay below: `n` goes up to 38.

| n | Application | Host name (dev) | Front `fr` / `en` | Gateway | REST API | MCP server | REST API database |
|---|---|---|---|---|---|---|---|
| 1 | turu | turu.dev.localhost | 11200 / 11205 | 11080 | 11180 | 11280 | 11633 |
| 2 | hururaa | hururaa.dev.localhost | 12200 / 12205 | 12080 | 12180 | 12280 | 12633 |
| 3 | tickee | tickee.dev.localhost | 13200 / 13205 | 13080 | 13180 | 13280 | 13633 |
| 4 | faito | faito.dev.localhost | 14200 / 14205 | 14080 | 14180 | 14280 | 14633 |

A new application takes the next number, and adds its row here first.

### What an application provides

- its realm export(s), `keycloak/import/<realm>-realm.json`, with ids of their own (every id is a
  primary key of the shared database: a realm generated from a template gets new ones once, with
  [`new-realm-ids.sh`](new-realm-ids.sh)), and:
  - the BFF's redirect and post-logout URIs on `https://<app>.dev.localhost/`;
  - its back-channel logout URL (and admin URL) on the gateway itself, `https://host.docker.internal:<prefix>080/gateway/logout/connect/back-channel/<registration>` (Keycloak runs in a container: it can't resolve `<app>.dev.localhost`);
  - its SMTP server `host.docker.internal:1025`, user `mailpit`, password `secret`;
  - no keys (`"org.keycloak.keys.KeyProvider" : [ ]`): Keycloak generates the realm's own on
    import. A key committed in a template or a project would let anyone who reads it sign tokens
    the application accepts; `export-realm.sh` exports the generated ones, which stay dev keys:
    the demo rendering removes them again;
- its themes, if any, `keycloak/themes/<theme>/`;
- its nginx server block for `<app>.dev.localhost` (`listen 443 ssl`: the certificate is the
  proxy's), routing to its processes on the host through `host.docker.internal:<port>`;
- its RabbitMQ user and password (the virtual host is named after the application: Spring's
  `spring.rabbitmq.virtual-host`);
- its own compose project for its database(s), on its block's ports;
- in its `deploy-dev.sh`:

  ```bash
  C4_INFRA_DIR=${C4_INFRA_DIR:-../c4-infra}
  bash "$C4_INFRA_DIR/up.sh"
  bash "$C4_INFRA_DIR/register-app.sh" --app faito \
    --realm keycloak/import/faito-realm.json \
    --proxy reverse-proxy/faito.conf \
    --rabbitmq-user faito-api --rabbitmq-password-env RABBITMQ_PASSWORD   # exported, from .env
  docker compose -f compose-rest-api-db.yml up -d --wait
  ```

A project created before this stack existed moves onto it with [docs/migration.md](docs/migration.md).

`register-app.sh` is idempotent: a realm already in Keycloak is left alone (the users and clients
created since survive; `--reset-realms` re-imports it), a server block is checked by the proxy
before it replaces the previous one, a changed theme restarts Keycloak. No password goes on a
command line: Keycloak's admin CLI reads it from its environment, RabbitMQ receives a salted hash.

It logs in as Keycloak's bootstrap administrator (`KC_BOOTSTRAP_ADMIN_USERNAME` /
`KC_BOOTSTRAP_ADMIN_PASSWORD` in `.env`, the `KC_ADMIN_PASSWORD` secret on the demo host). Keycloak
reads them on its very first start only, and its console invites to replace that temporary
account: keep it, with the same password, or every registration fails. Changing the password means
changing it in the console and in `.env` (or the secret) together.

## Demo host

The same stack on one Ubuntu VPS, deployed by
[`.github/workflows/deploy-demo.yml`](.github/workflows/deploy-demo.yml) on every push to `main`:
Caddy instead of nginx (a Let's Encrypt certificate per site), plain HTTP inside the Docker
network, `https://infra.c4-soft.com/` for the shared services, and one site per application,
`https://<app>.c4-soft.com/`, which each application installs from its own deployment.

### One-time setup

Step by step in [docs/demo-setup.md](docs/demo-setup.md): VPS and DNS, deployment key, host
preparation, host key, passwords (three of them fixed by the first deployment), the GitHub `demo`
environment, first deployment and checks. Not set up yet (postponed on 2026-10-21).

### What an application's deployment does

From its own workflow, as `deploy@<vps>`, in `~/<app>/`:

- its compose project, whose containers that need the shared services join the external network
  `c4-infra`, with **unique container names** (`<app>.gateway`, `<app>.api`…): Caddy and Keycloak
  reach them by these names, and two applications' `gateway` services on the same network would be
  ambiguous. Its databases stay on its project's own network;
- its realm, rendered for the demo (public host, real client secrets, Mailpit's SMTP password,
  back-channel logout on `http://<app>.gateway:7080/...`), then
  `bash ~/c4-infra/register-app.sh --app <app> --realm … --proxy <app>.caddy --rabbitmq-user … --rabbitmq-password-env …`;
- its Caddy site, importing the `common-headers` and `spa-headers` snippets of
  [`demo/caddy/Caddyfile`](demo/caddy/Caddyfile):

  ```caddyfile
  faito.c4-soft.com {
      encode zstd gzip
      import common-headers
      handle /gateway/* {
          reverse_proxy faito.gateway:7080
      }
      @locales path /fr/* /en/*
      handle @locales {
          import spa-headers
          reverse_proxy faito.frontend:80
      }
      handle {
          redir * /fr/ temporary
      }
  }
  ```

### Day to day

On the host, as `deploy`, from `~/c4-infra`:

```bash
docker compose ps                  # health of every shared service
docker compose logs -f keycloak    # or reverse-proxy, rabbitmq...
```

`docker compose down -v` wipes Keycloak (every application's users) and Mailpit: take a backup
first.

### Backups

The workflow installs [`demo/backup.sh`](demo/backup.sh) in the `deploy` user's crontab, nightly
at 03:15 (host time): a hot `pg_dump` of Keycloak's database in `~/backups/`, kept 7 days. Each
application backs up its own databases. To restore, from `~/c4-infra`:

```bash
docker compose stop keycloak
docker compose exec -T keycloak-db pg_restore -U keycloak -d keycloak --clean --if-exists \
  < ~/backups/c4-infra-keycloak-db-<stamp>.dump
docker compose start keycloak
```
