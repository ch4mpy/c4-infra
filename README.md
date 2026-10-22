# c4-infra

The infrastructure the c4-soft applications (Faito, Hurura'a, Tickee, Turu…) share on one machine:
the development workstation, and the demo VPS. One reverse proxy, one Keycloak (a realm or more per
application), one Mailpit, one RabbitMQ (a virtual host per application) and one Grafana LGTM,
instead of a copy of each per project: less memory, and no port conflict between projects.

Each application keeps in its own repository what is its own: its database(s), in its own compose
project; its realm export, its Keycloak theme, its RabbitMQ user, and its routes file (the paths of
its site on the reverse proxy), which it installs here with [`register-app.sh`](register-app.sh)
every time it deploys.

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
  (`127.0.0.1`), in the containers through `extra_hosts: [host.docker.internal:host-gateway]`
  (`host-gateway` is Docker Desktop's gateway address, which it forwards to the host's loopback;
  Docker Engine on Linux doesn't); only the browser uses `<app>.dev.localhost`. A command-line
  client of an application's own origin (an MCP client such as Claude Code) needs a hosts-file
  line: `127.0.0.1 <app>.dev.localhost`.
- **One certificate.** The leaf the proxy, Keycloak and Mailpit serve is valid for
  `host.docker.internal`, `localhost` and `*.dev.localhost` (browsers refuse a second-level wildcard
  such as `*.localhost`), and signed by the local CA the projects already trust,
  `~/.ssh/host.docker.internal.crt`: adding an application needs no new certificate and no new
  trust ([`certs/make-certs.sh`](certs/make-certs.sh)).
- **Keycloak on PostgreSQL**, so that a realm is exported ([`export-realm.sh`](export-realm.sh))
  and the database backed up while Keycloak keeps serving every other application.
- **A block of 1 000 ports per application** for what runs on the host (dev servers, Spring Boot
  apps, databases), registered in [`registry.txt`](registry.txt) (see the port registry below);
  the shared services keep their usual ports.
- **One reverse proxy, Caddy, in dev as on the demo host.** The shared services' routes and the
  headers of the applications' sites are written once, in [`caddy/Caddyfile`](caddy/Caddyfile);
  only what must differ is in [`caddy/env/dev.caddy`](caddy/env/dev.caddy) and
  [`caddy/env/demo.caddy`](caddy/env/demo.caddy): the certificate (the dev leaf, Let's Encrypt),
  HSTS (on the demo host only, so that browsers don't pin the workstation's host names), Mailpit's
  basic authentication (demo host) and RabbitMQ's management UI (dev). A page that the demo's
  Content-Security-Policy blocks is blocked in dev too. Each application's site is generated from
  its [routes file](#routes-file).
- **One compose base, an override per environment.** [`compose.yml`](compose.yml) holds every
  service and every image version; [`compose.dev.yml`](compose.dev.yml) (ports on `127.0.0.1`, the
  dev certificate, Keycloak built here, RabbitMQ's UI) and [`compose.demo.yml`](compose.demo.yml)
  (ports 80 and 443 only, the demo's passwords and memory limits) add what differs. Published ports
  are declared in the overrides only, since compose merges `ports` lists. `COMPOSE_FILE` in `.env`
  names the pair: `docker compose` commands need no `-f`.
- **The environment is a setting**: `INFRA_ENV` in `.env`, `dev` (written by [`env.sh`](env.sh))
  or `demo` (written by [`demo/write-env.sh`](demo/write-env.sh)). Caddy reads it when it starts
  (which `caddy/env/*.caddy` it applies), `register-app.sh` at each registration (the site's host
  name and upstreams).

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
| Mailpit | https://host.docker.internal/mailpit/ | 1025 (SMTP, auth `mailpit` / `secret`), 8025 (its UI, over plain HTTP) |
| Grafana LGTM | https://host.docker.internal/grafana/ | 3000, 4317 (OTLP gRPC), 4318 (OTLP HTTP) |
| RabbitMQ (admin user and password in `.env`) | https://host.docker.internal/rabbitmq/ | 5672 (AMQP), 15672 |

```bash
docker compose ps                     # health of every shared service
docker compose logs -f keycloak       # or reverse-proxy, rabbitmq...
docker compose stop                   # e.g. to start a project's former stack again
bash ./export-realm.sh faito ../faito/keycloak/import   # realm + users, Keycloak keeps running
```

Mailpit's UI serves no TLS since the dev proxy is Caddy (one Mailpit route for both environments):
`https://host.docker.internal/mailpit/` is the way in, and `http://127.0.0.1:8025/mailpit/` the
direct one (nothing in Faito, Turu or Hurura'a calls `https://…:8025`). SMTP on 1025 keeps its
STARTTLS, with the shared leaf.

### Port registry

Application number `n` owns the 1 000 ports starting at `(10 + n) × 1000` (prefix `p = 10 + n`:
`14000`–`14999` for number 4, `20000`–`20999` for number 10). Within its block, the offsets are the
same for every application:

- front `fr` / `en`: `p200` / `p205`; gateway: `p080`; REST API: `p180`; MCP server: `p280`; REST
  API database: `p633`;
- `p090` and `p190`: the gateway and the REST API that the `openapi` Maven profile starts to read
  the specs (not the dev ports: specs are regenerated while the dev applications run);
- a management port, if an application sets one, on its port + 1.

Windows reserves dynamic port ranges from 49152 on (and some fixed ones: `netsh interface ipv4 show
excludedportrange protocol=tcp`), so blocks stay below: `n` goes up to 38.

The numbers are in [`registry.txt`](registry.txt), one line per application with what it owns in
the shared stack (its realms, RabbitMQ user, themes and host names; the file's header says how to
write a line). `up.sh` and `register-app.sh` check it ([`registry.sh`](registry.sh)): two
applications sharing a number, a name, a realm, a theme, a RabbitMQ user or a host name stop both,
naming the two lines, and `register-app.sh` registers nothing for an application missing from it.
A new application takes the number `bash registry.sh next` prints, and adds its line to
`registry.txt` first, in a commit of its own, before anything registers.

### What an application provides

- its registry entry, one line of [`registry.txt`](registry.txt) (its number, the name it
  registers under, its realms, RabbitMQ user, themes and host names), committed before it first
  registers;
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
- its themes, if any, `keycloak/themes/<theme>/`, passed to `register-app.sh --themes`. In dev,
  Keycloak caches no theme: a theme change shows on reload once the registration has been run again
  (`deploy-dev.sh`, or `register-app.sh --themes`), and Keycloak isn't restarted. On the demo host
  it keeps its caches: a deployment that changes a theme restarts Keycloak, once, for every
  application of the host;
- its [routes file](#routes-file), `reverse-proxy/<app>.routes`, the same in both environments:
  `register-app.sh` generates its site from it, on its registry entry's host name, to its processes
  on the host in dev and to its containers on the demo host;
- its RabbitMQ user and password (the virtual host is named after the application: Spring's
  `spring.rabbitmq.virtual-host`);
- its own compose project for its database(s), on its block's ports;
- in its `deploy-dev.sh`:

  ```bash
  C4_INFRA_DIR=${C4_INFRA_DIR:-../c4-infra}
  bash "$C4_INFRA_DIR/up.sh"
  bash "$C4_INFRA_DIR/register-app.sh" --app faito \
    --realm keycloak/import/faito-realm.json \
    --proxy reverse-proxy/faito.routes \
    --rabbitmq-user faito-api --rabbitmq-password-env RABBITMQ_PASSWORD   # exported, from .env
  docker compose -f compose-rest-api-db.yml up -d --wait
  ```

  Until Faito registers with its routes file (Faito 0021), its `deploy-dev.sh` passes its former
  nginx block, `reverse-proxy/faito.conf`: `register-app.sh` then registers
  [`examples/routes/faito.routes`](examples/routes/faito.routes) in its place, with a warning.

A project created before this stack existed moves onto it with [docs/migration.md](docs/migration.md).

`register-app.sh` is idempotent: a realm already in Keycloak is left alone (the users and clients
created since survive; `--reset-realms` re-imports it), a site is validated by Caddy before it
replaces the previous one (Caddy is reloaded, never restarted), an unchanged theme is left alone; a
changed one is installed, and shows on reload in dev (no restart), while on the demo host it
restarts Keycloak once per registration, whatever the number of themes.
No password goes on a command line: Keycloak's admin CLI reads the registration account's secret
from its environment, RabbitMQ receives a salted hash.

### The registration account

`register-app.sh` logs in to Keycloak as a service account of its master realm,
`c4-infra-registration` (`KC_REGISTRATION_CLIENT_ID` / `KC_REGISTRATION_CLIENT_SECRET` in `.env`;
on the demo host, the `KC_REGISTRATION_CLIENT_SECRET` secret of the `demo` environment), never as a
user. The account may:

- create realms (`create-realm`): Keycloak grants a realm to whoever creates it;
- manage the realms of the registry ([`registry.txt`](registry.txt)), those created before it
  included: every role of the master realm's client `<realm>-realm`;

and nothing else: the master realm and the realms no registry entry assigns answer it `403`. A
registration that targets a realm the account may not manage stops, says so, and changes nothing.
Keycloak gives an account that may create realms a reduced view of any realm (`get
realms/<realm>`: its name, display name and a few flags, no secret nor user data): inherent to
`create-realm`, and accepted; registrations ask `get realms/<realm>/roles` instead (missing, `403`,
or theirs).

[`registration-account.sh`](registration-account.sh):

- `ensure`, which `up.sh` (dev) and `demo/deploy.sh` (demo host) run after each start: logs in as
  the account and probes every realm of the registry. Only when the account is missing, its secret
  isn't `.env`'s, or a realm that exists isn't granted to it, does it log in as an administrator to
  repair it: the bootstrap administrator of `.env` while it works, else `KC_SETUP_ADMIN_USERNAME` /
  `KC_SETUP_ADMIN_PASSWORD` from the environment, else, on a terminal, the one it asks for;
- `rotate` (dev): a new secret into `.env`, then `ensure`. On the demo host, the secret is the
  `demo` environment's ([docs/demo-setup.md](docs/demo-setup.md), "Rotating the registration
  secret").

Keycloak's administrators are free to change: following its console's invitation to replace the
temporary bootstrap administrator by a permanent one and delete it, or changing its password,
doesn't affect the registrations. Once it no longer logs in, an administrator is needed only to
create the account again or to rotate its secret: in dev, `bash registration-account.sh ensure`
from a terminal asks for one; on the demo host, `KC_SETUP_ADMIN_*` are set for one deployment.

### Routes file

An application writes the paths of its site once, for both environments: each path, the role it
goes to, and its options. It names neither a host, a scheme nor a port: its host names are its
registry entry's, and each role's upstream is derived from its number (dev) or its container (demo
host). `bash routes.sh generate <routes file> <app> <dev|demo>` prints the site `register-app.sh`
installs.

```text
# one route per line; '#' starts a comment
<path>  <target>  [<option>...]
  path:    /exact  |  /prefix/*  |  ~<regular expression>   (characters: A-Z a-z 0-9 . _ ~ / -, and for a regex ^ $ * + ? ( ) | [ ])
  target:  gateway | mcp | fr | en | ui | redirect
  options: to=<path>          redirect only, required: a path on the same host (not //...)
           max-body=<n>KB|MB  request body limit (413 beyond)
           prefix=<path>      prepended to the request's path before proxying
```

Faito's, [`examples/routes/faito.routes`](examples/routes/faito.routes) (Hurura'a's and Turu's are
next to it):

```text
/           redirect  to=/fr/
/gateway/*  gateway
/fr/*       fr
/en/*       en
```

- **First match.** Routes are tried in the file's order, and the first one that matches serves the
  request: a narrower route goes before a wider one (Turu's 64 MB upload, a regular expression,
  before `/gateway/*`). A `/<p>/*` route also redirects `/<p>` to `/<p>/` (301). Any other path
  answers `404`.
- **Roles and their upstreams**, with `p = 10 + n` (port registry above). The front end without
  i18n is `ui`.

  | Role | dev | demo host |
  |---|---|---|
  | `gateway` | `https://host.docker.internal:p080` | `http://<app>.gateway:7080` |
  | `mcp` | `https://host.docker.internal:p280` | none yet: refused (see "What an application's deployment does") |
  | `fr`, `ui` | `http://host.docker.internal:p200` | `http://<app>.frontend:80` |
  | `en` | `http://host.docker.internal:p205` | `http://<app>.frontend:80` |

  Dev's HTTPS upstreams are checked against the local CA (`certs/ca.crt`) and get the client's
  `Host` (`<app>.dev.localhost`).
- **Headers.** The front ends (`fr`, `en`, `ui`) get the single-page-app headers
  (Content-Security-Policy, `X-Frame-Options`, `Permissions-Policy`: the `spa-headers` snippet of
  [`caddy/Caddyfile`](caddy/Caddyfile)); every response gets `X-Content-Type-Options` and
  `Referrer-Policy`, and no `Server`; `Strict-Transport-Security` on the demo host only.
- **Refused**, as `<file>:<line>: …`, before anything is registered: a line outside the notation,
  and any host name, scheme or port (`routes name neither a host nor a port: '<token>'`): an
  application's routes reach its own processes only.

## Demo host

The same stack on one Ubuntu VPS, deployed by
[`.github/workflows/deploy-demo.yml`](.github/workflows/deploy-demo.yml) on every push to `main`:
the compose base with its demo override, [`compose.demo.yml`](compose.demo.yml), and the same Caddy
configuration with the demo's rules (`INFRA_ENV=demo`: a Let's Encrypt certificate per site, HSTS,
Mailpit behind its basic authentication, no RabbitMQ UI); plain HTTP inside the Docker network,
`https://infra.c4-soft.com/` for the shared services, and one site per application,
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
  `bash ~/c4-infra/register-app.sh --app <app> --realm … --proxy <app>.routes --rabbitmq-user … --rabbitmq-password-env …`;
- no Caddy site to write: its routes file, the one it registers in dev (see "Routes file"), gives
  its site on the demo host name of its registry entry, to its containers on the ports fixed here:
  the gateway on `<app>.gateway:7080`, and every locale's front end on `<app>.frontend:80` (`/fr/`
  and `/en/` are directories of that one container). No container port is fixed yet for an MCP
  server, since no application deploys one here: a routes file naming the `mcp` role is refused
  on the demo host, and the first application that deploys one fixes its port in this section.

### On the host

`~/c4-infra` holds what the deployment sends, the files of
[`demo/deploy-files.txt`](demo/deploy-files.txt) (the compose base and its demo override, the
shared Caddyfile and `caddy/env/demo.caddy`, the registry, `routes.sh`, `register-app.sh`,
`registration-account.sh`, `demo/deploy.sh` and `demo/backup.sh`), its `.env` (mode 600, written by
[`demo/write-env.sh`](demo/write-env.sh) on the workflow's runner: `INFRA_ENV=demo`,
`COMPOSE_FILE=compose.yml:compose.demo.yml`, the secrets), and what the applications register
(`caddy/apps/`, `keycloak/themes/`). The workflow then runs [`demo/deploy.sh`](demo/deploy.sh)
there: `docker compose up` until every service is healthy, a Caddy reload, the registration
account (`registration-account.sh ensure`, see "The registration account"), the nightly backup.

### Day to day

On the host, as `deploy`, from `~/c4-infra`:

```bash
docker compose ps                  # health of every shared service
docker compose logs -f keycloak    # or reverse-proxy, rabbitmq...
```

`docker compose down -v` wipes Keycloak (every application's users) and Mailpit: take a backup
first.

### Backups

[`demo/deploy.sh`](demo/deploy.sh) installs [`demo/backup.sh`](demo/backup.sh) in the `deploy` user's crontab, nightly
at 03:15 (host time): a hot `pg_dump` of Keycloak's database in `~/backups/`, kept 7 days. Each
application backs up its own databases. To restore, from `~/c4-infra`:

```bash
docker compose stop keycloak
docker compose exec -T keycloak-db pg_restore -U keycloak -d keycloak --clean --if-exists \
  < ~/backups/c4-infra-keycloak-db-<stamp>.dump
docker compose start keycloak
```
