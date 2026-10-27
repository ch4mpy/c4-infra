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
  same paths as before the stack was shared (`/fr/`, `/en/`, `/gateway/`):
  `https://<app>.dev.localhost/` in dev, `https://<app>.c4-soft.com/` on the demo host. Its
  cookies (session, `XSRF-TOKEN` at path `/`), its OAuth discovery documents at the root and its
  Content-Security-Policy stay its own. Sharing one host with a path prefix per application would
  have mixed all three; so would sharing one host with a port per application (cookies ignore the
  port).
- **An MCP server on an origin of its own** (intent 0013): `https://<app>-mcp.dev.localhost/` in
  dev, `https://<app>-mcp.c4-soft.com/` on the demo host (the first label of the registry entry's
  host names, suffixed with `-mcp`). It serves the routes whose target is `mcp` (`/mcp`, its
  protected resource's document `/.well-known/oauth-protected-resource/mcp`), and the application's
  origin no longer does: the application's cookies never reach an MCP server, which takes bearer
  tokens only. It gets the headers every site gets, not the single-page applications'; Caddy sends
  it `X-Forwarded-Host` and `X-Forwarded-Proto`, from which it derives its public URL. The registry
  holds these host names as its entry's: no other entry may take them.
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
  client of an application's MCP server (an MCP client such as Claude Code) needs a hosts-file
  line: `127.0.0.1 <app>-mcp.dev.localhost`.
- **One certificate.** The leaf the proxy, Keycloak and Mailpit serve is valid for
  `host.docker.internal`, `localhost` and `*.dev.localhost` (browsers refuse a second-level wildcard
  such as `*.localhost`), the MCP origins `<app>-mcp.dev.localhost` included, and signed by the
  local CA the projects already trust,
  `~/.ssh/host.docker.internal.crt`: adding an application needs no new certificate and no new
  trust ([`certs/make-certs.sh`](certs/make-certs.sh)).
- **Keycloak on PostgreSQL**, so that a realm is exported ([`export-realm.sh`](export-realm.sh))
  and the database backed up while Keycloak keeps serving every other application.
- **Keycloak 26.8.1, pinned** ([`keycloak/Dockerfile`](keycloak/Dockerfile), intent 0013): a
  rebuild never changes its version unannounced. It enables two preview features,
  `token-exchange-delegation` and the `parameterized-scopes` it uses (an agent acts for a user: the
  delegated token's `act` claim names the agent, as Turu's agents need; a realm issues one only
  where an FGAP v2 `delegate` permission allows it. Keycloak checks that permission when it issues
  a token: removing it stops new delegated tokens, while a token issued before keeps its `may_act`
  until it expires, the access token's lifespan), and one experimental feature, `cimd` (an MCP
  client registers by the URL of its metadata document; a realm opts in through its client
  policies, which the registration checks: see "What an application provides"); no other. What an
  MCP client finds on the shared host: each realm's RFC 8414 metadata
  (`/.well-known/oauth-authorization-server/auth/realms/<realm>`) and OpenID discovery at the
  issuer host's root, PKCE `S256`, `iss` in the authorization response, the standard token exchange
  and, where a realm opts in, client ID metadata documents; a `resource` parameter is ignored
  (resource indicators stay off). A new Keycloak image migrates the database once, at the first
  `up` or deployment that runs it, Keycloak stopped first (see "Backups").
- **A block of 1 000 ports per application** for what runs on the host (dev servers, Spring Boot
  apps, databases), registered in [`registry.txt`](registry.txt) (see the port registry below);
  the shared services keep their usual ports.
- **One reverse proxy, Caddy, in dev as on the demo host.** The shared services' routes and the
  headers of the applications' sites are written once, in [`caddy/Caddyfile`](caddy/Caddyfile);
  only what must differ is in [`caddy/env/dev.caddy`](caddy/env/dev.caddy) and
  [`caddy/env/demo.caddy`](caddy/env/demo.caddy): the certificate (the dev leaf, Let's Encrypt),
  HSTS (on the demo host only, so that browsers don't pin the workstation's host names) and
  RabbitMQ's management UI (dev). A page that the demo's Content-Security-Policy blocks is blocked
  in dev too. Each application's site is generated from its [routes file](#routes-file). Its image
  is Caddy built with the rate-limit module ([`reverse-proxy/Dockerfile`](reverse-proxy/Dockerfile),
  intent 0013): a realm's client registration endpoint
  (`/auth/realms/<realm>/clients-registrations/…`, which an MCP client may call anonymously) takes
  10 requests a minute per client address, `429` beyond; nothing else is limited. The applications'
  containers, which reach `keycloak:8080` without the proxy, aren't limited either.
- **One network per application** (intent 0007). An application's containers join
  `c4-infra.<app>` (named after its registry entry), in dev as on the demo host (in dev, those the
  shared services must reach, such as Tickee's LDAP server), which no other application's
  container joins: two applications never reach each other's containers. Its registration
  ([`networks.sh`](networks.sh) `ensure`, run by `register-app.sh`) creates it and attaches the
  shared services to it under their usual names (`reverse-proxy`, `keycloak`, `mailpit`,
  `rabbitmq`, `grafana-lgtm`, and on the demo host the shared host's name, Caddy's), so that Caddy
  and Keycloak reach the application's containers and these reach the shared services; the
  generated `compose.apps.yml` (the last file of `COMPOSE_FILE`) keeps them attached when the stack
  is recreated. Keycloak's database is on a network of its own, `c4-infra.keycloak-db` (internal),
  which only Keycloak joins; `c4-infra` is the shared services' own network, which no application
  joins. On the demo host, Mailpit's UI and API ask for the demo's credentials themselves, wherever
  they are reached from; what else answers on an application's network is listed in "Reachable from
  an application's network" below.
- **One compose base, an override per environment.** [`compose.yml`](compose.yml) holds every
  service and every image version; [`compose.dev.yml`](compose.dev.yml) (ports on `127.0.0.1`, the
  dev certificate, Keycloak built here, RabbitMQ's UI) and [`compose.demo.yml`](compose.demo.yml)
  (ports 80 and 443 only, the demo's passwords and memory limits, Mailpit's credentials) add what
  differs. Published ports are declared in the overrides only, since compose merges `ports` lists.
  `COMPOSE_FILE` in `.env` names them, with `compose.apps.yml`: `docker compose` commands need no
  `-f`.
- **The environment is a setting**: `INFRA_ENV` in `.env`, `dev` (written by [`env.sh`](env.sh))
  or `demo` (written by [`demo/write-env.sh`](demo/write-env.sh)). Caddy reads it when it starts
  (which `caddy/env/*.caddy` it applies), `register-app.sh` at each registration (the site's host
  name and upstreams).

## Development

Prerequisites:

- Docker Desktop and Git Bash;
- `jq`, which `register-app.sh` reads a realm export with (intent 0013; the tests use it too);
- the local CA trusted by the browsers and by each JDK the projects run on (by the browsers, it
  already is if a project was set up on this machine before; otherwise `certs/make-certs.sh`
  creates it and says how to trust it). For each JDK, `bash certs/trust-ca-in-jdk.sh <JDK home>`
  imports the certificate only (`certs/ca.crt`, alias `host.docker.internal`; the CA's key stays in
  `~/.ssh`), says "already trusted" when it is, and replaces whatever else that alias holds, such
  as the CA's private key that a former advice imported with the CA's whole keystore. The JDK's
  trust store password comes from `CACERTS_PASSWORD` (default `changeit`); a JDK installed for
  every user needs an administrator's terminal;
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
An entry's MCP origins (`<first label>-mcp.<rest>` of each host name, intent 0013) are its host
names too, and no application may be named `<other>-mcp`.
No entry may claim what the shared stack itself owns: Keycloak's `master` realm, RabbitMQ's
administrator (`RABBITMQ_ADMIN_USER` of `.env`, `admin`), since a registration may reset its
entry's realms and set its RabbitMQ user's password.
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
  - client policies that fetch client metadata documents (`cimd`, intent 0013) over https from
    named domains: a registration refuses an export whose `client-id-metadata-document` executor
    allows the http scheme (`cimd-allow-http-scheme` other than `false`: Keycloak reads `"true"`,
    `"TRUE"` or `1` as true) or permits the domain `*` or `*.` (which matches every host written
    with a final dot), with which Keycloak, on every application's network, would fetch any URL an
    unauthenticated client names; or a permitted domain that names no public host, which Keycloak
    resolves on those networks (PA-08): an IP address (`10.0.0.1`, `[::1]`), a single label
    (`keycloak`), a last label outside the IANA root zone (`*.mcp`, `faito.gateway`,
    `host.docker.internal`; the list is
    [`tlds-alpha-by-domain.txt`](tlds-alpha-by-domain.txt)), a wildcard over a whole top-level
    domain (`*.com`, `*.xn--p1ai`: every domain of it; `*.xn--d1acufc.xn--p1ai` passes), or two
    labels whose first is a registered application's name or `c4-infra` (a container: `faito.app`,
    `c4-infra.rabbitmq`), after a leading `*.`, case ignored and a final dot removed; and one
    holding a realm attribute `client-policies.*`, where Keycloak stores the profiles and policies,
    out of that check. The check reads the domain's name, not what it resolves to: a public name
    pointed at an internal address passes, and would let Keycloak fetch from it;
- its themes, if any, `keycloak/themes/<theme>/`, passed to `register-app.sh --themes`. In dev,
  Keycloak caches no theme: a theme change shows on reload once the registration has been run again
  (`deploy-dev.sh`, or `register-app.sh --themes`), and Keycloak isn't restarted. On the demo host
  it keeps its caches: a deployment that changes a theme restarts Keycloak, once, for every
  application of the host. A theme holds no `${` in a `theme.properties` (Keycloak resolves
  `${env.NAME}` and Java's system properties there, and the theme's pages show the values: the
  master realm's administrator's password, once) and no symbolic link nor special file, nor is it a
  link itself (Keycloak serves a theme's files, a link's target included: `/proc/self/environ` is
  its whole environment). A registration refuses either, naming the file and its line, as Java
  reads it: `\u0024{`, `\$\{` or a `$` and a `{` joined by a continuation line are a `${` too
  (intent 0012). A `theme.properties` holds printable ASCII only, the tab, CR, LF and form feed
  besides (a character beyond is written `\uXXXX`): Keycloak then decodes it as the check reads it;
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

  Since intent 0013, `register-app.sh` refuses a `--proxy` nginx block (`reverse-proxy/faito.conf`,
  Faito's former one), as any file that isn't a routes file: Faito passes its routes file
  ([`examples/routes/faito.routes`](examples/routes/faito.routes), copied by Faito 0021).

A project created before this stack existed moves onto it with [docs/migration.md](docs/migration.md).

`register-app.sh` is idempotent: a realm already in Keycloak is left alone (the users and clients
created since survive; `--reset-realms` re-imports it), a site is validated by Caddy before it
replaces the previous one (Caddy is reloaded, never restarted), an unchanged theme is left alone; a
changed one is installed, and shows on reload in dev (no restart), while on the demo host it
restarts Keycloak once per registration, whatever the number of themes.
A registration touches only what the application's registry entry assigns to it, in dev as on the
demo host: each `--realm` file is named after a realm of the entry (`<realm>-realm.json`) and is
imported under that name, whatever its own `realm` field says; each theme directory of `--themes`
is named after a theme of the entry, and holds nothing that would show Keycloak's environment
(above); `--rabbitmq-user` is the entry's; the routes file gives a site
on the entry's host name, to the application's own upstreams. Anything else is refused, saying
why, before anything changes.
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

Keycloak's administrators are free to change: replacing the administrator of `.env` by another one
and deleting it, or changing its password, doesn't affect the registrations (on the demo host, each
one with a long random password: the master realm limits no guessing, "Brute-force protection"
below). Once it no longer
logs in, an administrator is needed only to create the account again or to rotate its secret: in
dev, `bash registration-account.sh ensure` from a terminal asks for one; on the demo host,
`KC_SETUP_ADMIN_*` are set for one deployment. With the master realm's *Verify email* (below), an
administrator who has an e-mail address verifies it before the admin CLI logs in as them: Keycloak
refuses that login ("Account is not fully set up") until then, and `registration-account.sh` says so.

### The master realm

The master realm is created pre-configured, from
[`keycloak-import/master-realm.json`](keycloak-import/master-realm.json) (intent 0009), by the
one-shot `keycloak-import` (`kc.sh import --override false`), which runs before Keycloak at each
start of the stack and exits (intent 0012): on an empty database only, a master realm that exists
being never imported again, whatever the file says.

- Its SMTP server is Mailpit, with Mailpit's SMTP credentials of `.env`: in dev
  `host.docker.internal:1025` with STARTTLS (Mailpit requires it, and the local leaf holds that
  name), on the demo host `mailpit:1025` without TLS; sender `noreply@<INFRA_HOST>`. The console's
  *Test connection* delivers to Mailpit.
- *Verify email* is on; *Forgot password* is on in dev only (on the demo host, its mails would land
  in Mailpit, where whoever reads them could reset an administrator's password).
- Its administrator is `.env`'s `KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD`, with
  the verified address `admin@<INFRA_HOST>`. `keycloak-import` gets them as
  `C4_MASTER_ADMIN_USERNAME` / `C4_MASTER_ADMIN_PASSWORD`: under their `KC_BOOTSTRAP_*` names,
  Keycloak would create its temporary administrator as well and abort. The running Keycloak's
  environment holds neither, nor Mailpit's SMTP credentials, only its database's password (a
  database only Keycloak and keycloak-import reach): a theme could show any variable of it (intent
  0012). Neither they nor
  Mailpit's SMTP password may hold a double quote, a backslash or a control character, which the
  import's JSON can't take (`demo/write-env.sh` refuses them on the demo host, `up.sh` in dev), and
  `INFRA_HOST` is a host name (`demo/write-env.sh` checks it).
- No brute-force detection, unlike the applications' realms (below).
- The rest is what Keycloak sets when it creates that realm itself (its display name, 60-second
  access tokens, a user profile where neither the address nor the names are required).

A stack started before intent 0009 keeps its master realm as it is. Re-creating Keycloak's
database gives it the configuration, at the cost of everything Keycloak holds: the master realm's
other administrators and the applications' realms. In dev:

```bash
docker compose rm -sf keycloak keycloak-import keycloak-db && docker volume rm c4-infra_keycloak_db
bash up.sh                        # keycloak-import creates the master realm, up.sh the registration account
bash ../<app>/deploy-dev.sh       # each application imports its realm again
```

(on the demo host: [docs/demo-setup.md](docs/demo-setup.md), "Re-creating Keycloak's database").
After a change of Mailpit's SMTP password (`MAILPIT_SMTP_PASSWORD`), the master realm keeps the
former one: type the new one in its *Email* settings. So does every application realm already in
Keycloak (`register-app.sh` leaves a realm that exists as it is): type it in each one's *Email*
settings too; only a realm imported again (`--reset-realms`, which loses its users) takes the
password its application renders. A new administrator's password in `.env` likewise: type it in
the console too (realm master, *Users* → the administrator → *Credentials*). Since that password,
`INFRA_HOST` and the administrator's are in `keycloak-import`'s environment, changing one of them
recreates its container at the next start, which leaves the master realm as it is (`INFRA_HOST`,
Keycloak's host name too, recreates Keycloak's).

### Brute-force protection

Every application's realm imported since intent 0010 locks an account for a while after repeated
failed logins, in dev as on the demo host: after 10 failures, the account is refused for a minute, even
with its right password; each further failure adds a minute, up to 15; the failures are forgotten
12 hours after the last one; nothing locks an account for good (Keycloak's temporary lockout,
linear strategy). Keycloak's quick-login rule comes on top: two failures less than a second apart
lock the account for a minute, whatever their count.

- An application's realm gets these settings each time `register-app.sh` imports it, whatever its
  export says (`brute_force` in [`register-app.sh`](register-app.sh)). A realm already in Keycloak
  keeps its own settings until it is imported again: one registered before intent 0010 gets them
  with its next `--reset-realms`, which loses its users, or, keeping them, from an administrator in
  the console (*Realm settings* → *Security defenses* → *Brute force detection*, the values above).
- The master realm has none: its console is public on the demo host, and anyone could keep its
  administrators locked out. Nothing limits guessing there: on the demo host, every administrator
  of the master realm gets a long random password (`openssl rand -base64 32`), the one of the
  `demo` environment as any added later (in dev, `.env`'s is `secret`: the stack publishes its
  ports on the loopback only).
- An administrator unlocks an application's account in the console, on the user's page. Whoever
  knows an account's user name can keep it locked for as long as they keep failing its logins (each
  lock at most 15 minutes): on the demo host, the shared demo accounts (their passwords are public)
  included. Accepted (PA-02).

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
           prefix=<path>      prepended to the request's path before proxying (not / alone)
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
  before `/gateway/*`). A `/<p>/*` route also redirects `/<p>` to `/<p>/` (301), even when a wider
  route that also matches `/<p>` comes first (a regular expression, `/*`): that route redirects it
  before proxying. A route of its own for `/<p>` takes it instead: `/<p>` itself, or a regular
  expression that matches `/<p>` and not `/<p>/` (`~^/docs$`, not `~^/`). Any other path answers
  `404`.
- **Roles and their upstreams**, with `p = 10 + n` (port registry above). The front end without
  i18n is `ui`.

  | Role | dev | demo host |
  |---|---|---|
  | `gateway` | `https://host.docker.internal:p080` | `http://<app>.gateway:7080` |
  | `mcp` | `https://host.docker.internal:p280` | `http://<app>.mcp:9080` |
  | `fr`, `ui` | `http://host.docker.internal:p200` | `http://<app>.frontend:80` |
  | `en` | `http://host.docker.internal:p205` | `http://<app>.frontend:80` |

  Dev's HTTPS upstreams are checked against the local CA (`certs/ca.crt`) and get the client's
  `Host` (`<app>.dev.localhost`, `<app>-mcp.dev.localhost`).
- **Two sites.** The `mcp` routes are served on the application's MCP origin,
  `<app>-mcp.dev.localhost` or `<app>-mcp.c4-soft.com` (see "Design"), and only there; the other
  routes on its own origin. Each site has its own first match and its own `404`; a file without
  `mcp` route gives one site.
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
no RabbitMQ UI), Mailpit asking for its own credentials; plain HTTP inside the Docker networks,
`https://infra.c4-soft.com/` for the shared services, and one site per application,
`https://<app>.c4-soft.com/`, which each application installs from its own deployment.

### One-time setup

Step by step in [docs/demo-setup.md](docs/demo-setup.md): VPS and DNS, deployment key, host
preparation, host key, passwords (three of them fixed by the first deployment), the GitHub `demo`
environment, first deployment and checks. Not set up yet (postponed on 2026-10-21).

### Accounts

One account per application, plus the shared stack's, each opened by one workflow's key only
(installed as `restrict <key>`: no forwarding, no terminal), and each home closed to the others
([`demo/vps-bootstrap.sh`](demo/vps-bootstrap.sh), [docs/demo-setup.md](docs/demo-setup.md)):

- `c4-infra`, the shared stack's: the only account in the `docker` group, the only one that changes
  the shared services (its workflow, `deploy-demo.yml`), with `~/c4-infra` and its `.env`, which
  holds every secret of the stack, the registration account's included (mode 600);
- `<app>`, one per application, named after its registry entry: outside the `docker` group, in the
  group `c4-apps`, whose one sudo rule is `sudo c4-app`; its workflow sends its files to
  `~/<app>/`. The firewall rejects any new outgoing connection of that group but on the loopback
  (its ssh and rsync are inbound): it can't reach the containers' addresses from the host either.

[`demo/c4-app`](demo/c4-app), installed root-owned by each deployment of the stack, acts for the
application whose account runs it (never an argument), on its own project only:

- `sudo c4-app pull [--registry <host> --registry-user <user>]` (the registry's token on stdin, in a
  temporary Docker configuration removed at once), `sudo c4-app up`, `sudo c4-app down`: its compose
  project, named after it (`-p <app>`, for the model and for root's compose: a top-level `name:` of
  its file changes nothing). Each command copies `~/<app>/` (read as the application) into
  `/var/lib/c4-apps/<app>/`, which root owns and the application can read but not write, refusing a
  symbolic link or a special file; that copy is only the containers' mount sources. The compose
  model is read as the application (`docker compose config`: no file its account can't read, such as
  another application's `env_file`) and, once checked, kept with the files root itself reads in a
  **root-only snapshot**, `/var/lib/c4-apps/.run.<app>/` (mode `0700 root:root`, outside anything a
  container may mount); root's `docker compose` runs that snapshot model, for every command;
- `sudo c4-app register <register-app.sh's options>`, without `--app`: paths relative to
  `~/<app>/`, which must stay inside it, and `--rabbitmq-password-env <VAR>` taken from
  `~/<app>/.env`. The registration then runs with the registration account's secret, which the
  application's account can't read, and touches only what its registry entry assigns to it (its
  realms, its themes, its RabbitMQ user and virtual host, its site: see "What an application
  provides"). It reads the realm, routes and theme files from the snapshot too, so a container can't
  swap them under it.

`sudo c4-app up`, `down` and `pull` all check that model before root's compose touches it (intent
0007): compose runs a provider's and a hook's executables, so an unchecked model must never reach
it. The check is an **allowlist** — the top-level keys, the service keys, and, for the nested
objects that can escape (`build`, `deploy`, `security_opt`, `volumes` and `networks` entries), their
sub-keys and values — and refuses anything else, naming the service (or network/volume) and the key:

- **a service may set** its `image` or its `build` (not both), `container_name` and network aliases
  under `<app>.`,
  `command`/`entrypoint`/`environment`/`env_file`, `expose`, its own networks and named volumes,
  **read-only** bind mounts inside `/var/lib/c4-apps/<app>/`, `healthcheck`, `depends_on`, resource
  limits, and the usual hardening (`read_only`, `cap_drop`, `user`, `tmpfs`, `init`, `security_opt:
  no-new-privileges`). A service name is `[a-z0-9_-]+` — no dot, which would be an alias on the
  shared network;
- **refused with their own message**: a service named after a shared service (`keycloak`,
  `mailpit`, `rabbitmq`, `grafana-lgtm`, `reverse-proxy`, `keycloak-db`) or the shared host
  (`infra.c4-soft.com`); a published port (`expose` is fine: only the shared Caddy publishes);
  `privileged`, `cap_add`, `devices`, `device_cgroup_rules`, a `deploy` reservation of host devices;
  `network_mode`, `links`, `external_links`, `volumes_from`; `pid`/`ipc`/`uts`/`userns_mode`/`cgroup`
  set to `host` or another container; a read-write bind mount, or one of the staging root or outside
  it (the Docker socket, another application's files…); a network or volume that is external, has a
  name or driver of its own, or `driver_opts`; a `build` context or Dockerfile outside the staging
  tree; a service that builds and sets an `image`, or whose name has a `-`. Compose names a built image
  `<project>-<service>` (`faito-gateway`), in the Docker daemon every application shares: an image
  name of the application's own choosing could be another application's, which root's build would
  replace for that application's next `up`; and with a `-` in a service's name, application `a`'s
  `b-c` and application `a-b`'s `c` would both build `a-b-c`;
- **refused by the allowlist** (not an application's to set): `use_api_socket`,
  `post_start`/`pre_stop` hooks, a `provider` service, `build.network`/`privileged`/`entitlements`/
  `ssh`/`tags` (`tags` names the image too), and anything else not listed above. A need for one of
  these is a new intent, not a change an application makes on its own.

Then `up` makes sure of the application's network (`networks.sh ensure`) and starts the snapshot
model it checked, outside anything the application or its containers can write.

### What an application's deployment does

From its own workflow, as `<app>@<vps>` (its own account, its own key; the host's key pinned), its
files rsynced to `~/<app>/`, then `sudo c4-app pull`, `sudo c4-app register …` and `sudo c4-app up`
([docs/migration.md](docs/migration.md), "On the demo host"):

- its compose project, `~/<app>/compose.yml`, whose containers that need the shared services join
  its own network `c4-infra.<app>` as an external one (created and given the shared services by its
  registration), with **unique container names** (`<app>.gateway`, `<app>.api`…): Caddy and
  Keycloak reach them by these names, on every application's network. Its databases stay on its
  project's own network. `sudo c4-app up` refuses a project that leaves that isolation (see
  "Accounts");
- its realm, rendered for the demo (public host, real client secrets, Mailpit's SMTP password,
  back-channel logout on `http://<app>.gateway:7080/...`), then
  `sudo c4-app register --realm <realm>-realm.json --proxy <app>.routes --rabbitmq-user … --rabbitmq-password-env …`;
- no Caddy site to write: its routes file, the one it registers in dev (see "Routes file"), gives
  its site on the demo host name of its registry entry, to its containers on the ports fixed here:
  the gateway on `<app>.gateway:7080`, every locale's front end on `<app>.frontend:80` (`/fr/`
  and `/en/` are directories of that one container), and its MCP server on `<app>.mcp:9080`, on
  its MCP origin `https://<app>-mcp.c4-soft.com/` (intent 0013: a DNS record of its own,
  [docs/demo-setup.md](docs/demo-setup.md)). That server exchanges tokens through
  `http://keycloak:8080/auth` (no proxy, no limit), for tokens issued by
  `https://infra.c4-soft.com/auth/realms/<realm>`.

### Reachable from an application's network

What answers an application's containers on `c4-infra.<app>`, besides its own containers: every
other application's containers, and Keycloak's database, are on networks it doesn't join (intent
0007; checked by `tests/0007-isolation.stand-in.sh` from an application's container, and by
`tests/0007-listeners.sh` for each image as configured). In dev, the same, plus RabbitMQ's
management UI (15672) and Mailpit without credentials.

| Service | Port | What answers | Why |
| --- | --- | --- | --- |
| `reverse-proxy`, `infra.c4-soft.com` | 80, 443 | Caddy: the issuer, every application's site | the issuer's name inside the network (RQ-02) |
| `keycloak` | 8080 | Keycloak over plain HTTP: the token endpoint, the admin API | the applications' calls, and back-channel logout from it (RQ-02) |
| `keycloak` | 9000 | its management port: health and metrics, without authentication | recorded, no personal data (PA-03, decided 2026-10-21) |
| `mailpit` | 1025 | SMTP, with Mailpit's SMTP credentials | the realms' mails (RQ-02) |
| `mailpit` | 8025 | its UI and API: `401` without the demo's credentials (`/livez`, `/readyz` open) | Mailpit asks for them itself (RQ-04) |
| `rabbitmq` | 5672 | AMQP: each application's own user, on its own virtual host | events (RQ-02) |
| `rabbitmq` | 15692 | Prometheus metrics, without authentication | recorded, no personal data (PA-03) |
| `grafana-lgtm` | 4317, 4318 | the OTLP receivers (gRPC, HTTP): any telemetry, so an application can write under another's name | Grafana LGTM attached as it is (PA-02, decided 2026-10-21) |
| `grafana-lgtm` | 9090, 3200, 3100, 4040 | Prometheus, Tempo, Loki and Pyroscope, without authentication: every application's metrics, traces, logs and profiles (URLs, user ids) can be read | Grafana LGTM attached as it is (PA-02) |
| `grafana-lgtm` | 3000 | Grafana, behind its login on the demo host | the dashboards (RQ-02) |

Kept on the containers' loopback, unreachable from any network:

- RabbitMQ's epmd (4369) and Erlang distribution (25672): behind its cookie, the distribution runs
  code in RabbitMQ, and its tools (`rabbitmqctl`, the healthcheck, the registration) run inside the
  container (PA-03, RQ-10: `ERL_EPMD_ADDRESS` and `inet_dist_use_interface` in
  [`compose.yml`](compose.yml));
- Grafana LGTM's memberlist (7946), Loki's, Tempo's and Pyroscope's gRPC ports (9095, 9096, 9097)
  and its collector's health check (13133): its components' own (PA-04, decided 2026-10-22,
  RQ-11: the `*_EXTRA_ARGS` of [`compose.yml`](compose.yml) and
  [`grafana-lgtm/tempo-config.yaml`](grafana-lgtm/tempo-config.yaml), a copy of the image's file
  to regenerate with each image upgrade: `tests/0007-lgtm.sh` fails until it is).

### On the host

`/home/c4-infra/c4-infra` (`~/c4-infra` of the `c4-infra` account) holds what the deployment sends,
the files of [`demo/deploy-files.txt`](demo/deploy-files.txt) (the compose base and its demo
override, the configuration of the services they mount, the registry, and the scripts the host
runs, `demo/c4-app` among them), its `.env` (mode 600, written by [`demo/write-env.sh`](demo/write-env.sh) on the
workflow's runner: `INFRA_ENV=demo`, `COMPOSE_FILE=compose.yml:compose.demo.yml:compose.apps.yml`, the secrets), and
what the applications register (`caddy/apps/`, `keycloak/themes/`, owned by `c4-infra` too). The
workflow pins the host's key first ([`demo/trust-host-key.sh`](demo/trust-host-key.sh): no
deployment without `VPS_KNOWN_HOSTS`), and pins every action it uses by commit; it then runs
[`demo/deploy.sh`](demo/deploy.sh) there, as `c4-infra`: `c4-app` installed in `/usr/local/sbin`
when it changed (the account's one sudo rule), `docker compose up` until every service is healthy, a
Caddy reload, the registration account (`registration-account.sh ensure`, see "The registration
account"), the nightly backup.

### Day to day

On the host, as `c4-infra`, from `~/c4-infra`: over ssh with its key, or from the operator's
`ubuntu` session (`sudo -iu c4-infra`), since the workflows' keys open no terminal:

```bash
ssh c4-infra@<vps> 'cd ~/c4-infra && docker compose ps'   # health of every shared service
docker compose logs -f keycloak    # or reverse-proxy, rabbitmq...
```

`docker compose down -v` wipes Keycloak (every application's users) and Mailpit: take a backup
first.

### Backups

[`demo/deploy.sh`](demo/deploy.sh) installs [`demo/backup.sh`](demo/backup.sh) in the `c4-infra` account's crontab, nightly
at 03:15 (host time): a hot `pg_dump` of Keycloak's database in `~/backups/`, kept 7 days. Each
application backs up its own databases. To restore, from `~/c4-infra`, into a database recreated
empty (`pg_restore --clean` drops only what the dump holds: a table created since, as a newer
Keycloak's migration adds, would stay; measured on a throwaway `postgres:18.6`, intent 0013):

```bash
docker compose stop keycloak
docker compose exec -T keycloak-db psql -U keycloak -d postgres -v ON_ERROR_STOP=1 \
  -c 'DROP DATABASE keycloak WITH (FORCE)' -c 'CREATE DATABASE keycloak OWNER keycloak'
docker compose exec -T keycloak-db pg_restore -U keycloak -d keycloak \
  < ~/backups/c4-infra-keycloak-db-<stamp>.dump
docker compose start keycloak
```

**A new Keycloak version** (intent 0013) migrates its database at its first run, with no way back
but a dump. When `c4-infra.keycloak` runs another image than `.env`'s `KC_IMAGE` (the workflow tags
it with the content of `keycloak/`), `demo/deploy.sh` dumps the database first,
`~/backups/c4-infra-keycloak-before-upgrade-<stamp>.dump` (out of the nightly rotation: kept until
removed by hand), stops Keycloak, then starts the stack: the new version's `keycloak-import`
migrates the database (`--spi-connections-jpa--quarkus--migration-strategy=update`; an import only
validates it by default), then the new Keycloak starts on it. Logins fail during that restart. To
go back: `docker compose stop keycloak`, restore that dump with the `psql` and `pg_restore` lines
above, which leave none of the tables the migration added (not
`start`: the newer Keycloak would migrate it again), then deploy the previous version (revert the
merge that brought the new one), whose import and Keycloak read the restored database (neither
reads one the newer version migrated). In dev, `up.sh` stops Keycloak when its image changed, and
dumps nothing.
