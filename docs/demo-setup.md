# Setting up the demo host

Status: deployed since 2026-10-23 (the first successful run of `deploy-demo.yml`). Steps 0 to 8 set
a host up, once, in order; step 9 adds an application; steps 10 to 12 are operations on a running
host.

The demo host runs the shared stack (Caddy, Keycloak on PostgreSQL, Mailpit, RabbitMQ, Grafana
LGTM): the compose base [compose.yml](../compose.yml) with its demo override
[compose.demo.yml](../compose.demo.yml), and the shared Caddy configuration of [caddy/](../caddy/)
with the demo's rules (`INFRA_ENV=demo`), deployed by
[deploy-demo.yml](../.github/workflows/deploy-demo.yml) on every push to `main` that isn't only
Markdown. The applications deploy themselves on top of it afterwards
([migration.md](migration.md), "On the demo host").

## 0. Before anything

- The repository's `main` holds what is to be deployed: the workflow runs on a push to `main` (or
  by hand), and fails at its deploy job until the `demo` environment of step 6 exists.
- If the VPS already runs an application's own demo stack (Hurura'a's or Tickee's Caddy on ports
  80 and 443), that application moves onto the shared stack in the same maintenance window: the
  two can't hold the same ports.

## 1. VPS and DNS

1. Order an Ubuntu LTS VPS (8 GB of RAM for the shared stack and a few applications) and note its
   IP address.
2. DNS: an `A` record pointing at that IP for `infra.c4-soft.com`, and one per application host
   (`faito.c4-soft.com`, `hururaa.c4-soft.com`…), and one per application with an MCP server for
   its MCP origin (`turu-mcp.c4-soft.com`: intent 0013). Caddy needs them to get its Let's Encrypt
   certificates.
3. If OVH's network firewall is enabled for the VPS, open ports 80 and 443 there (SSH, 22, too).

## 2. Deployment key

A key pair for this repository's workflow only, which opens the shared stack's account `c4-infra`
(each application gets its own key pair and its own account later, step 9):

```bash
ssh-keygen -t ed25519 -f c4-infra-demo -C c4-infra-demo -N ""
```

## 3. Prepare the host

OVH's images give no SSH access to root, but an `ubuntu` sudoer. Copy the script over and run it
with sudo, so that sudo can ask for its password:

```bash
scp demo/vps-bootstrap.sh ubuntu@<vps-ip>:/tmp/
ssh -t ubuntu@<vps-ip> "sudo bash /tmp/vps-bootstrap.sh c4-infra '$(cat c4-infra-demo.pub)'"
```

It installs Docker from its official repository and `unattended-upgrades`, `jq` and `rsync`; opens
22, 80 and 443 only (`ufw`), and rejects any new outgoing connection of the applications' accounts
(group `c4-apps`) but on the loopback; writes `/etc/sudoers.d/c4-infra` (checked by `visudo`): the
group `c4-apps` may run `sudo c4-app` only, and `c4-infra` may install `c4-app` (one exact command
line, `demo/deploy.sh`'s); writes `/etc/cron.d/c4-apps-backup`, the applications' nightly backup
at 03:45 (host time, after Keycloak's at 03:15: root runs `c4-app nightly`, which runs each
application's `sudo c4-app backup` as its account; [README](../README.md), "Backups"); and creates
the account `c4-infra`, the only one in the `docker` group,
with `~/c4-infra` and the key installed as `restrict <key>` (no forwarding, no terminal: the
workflow runs commands; you log in as `ubuntu`). It ends with
`Done. c4-infra's workflow can now deploy as c4-infra@<ip>`.

Run again, it changes nothing but appends a key it doesn't have yet (keys are never replaced).

## 4. Host key

Required: every deployment pins the host's key before it connects, and fails (`VPS_KNOWN_HOSTS is
not set`) without it, before the ssh agent receives its key; nothing trusts a host key on first use.
From a machine you trust (not through an unknown network):

```bash
ssh-keyscan -H <vps-ip> > c4-infra-demo.known_hosts
ssh-keygen -lf c4-infra-demo.known_hosts   # compare with the fingerprints OVH's console shows
```

It becomes the `VPS_KNOWN_HOSTS` secret, of c4-infra's `demo` environment (step 6) and of each
application's (step 9): a host answering with another key then fails the deployment instead of
receiving its secrets.

## 5. Passwords

Generate them, e.g. `openssl rand -base64 32`, and **store them in a password manager first**:

| Secret | Used for | Note |
| --- | --- | --- |
| `KC_ADMIN_PASSWORD` | Keycloak's administrator `admin` (`/auth/admin/`) | read on Keycloak's first start only |
| `KC_DB_PASSWORD` | Keycloak's database | set when the database volume is created |
| `KC_REGISTRATION_CLIENT_SECRET` | the registration account `c4-infra-registration`, which `register-app.sh` logs in as | `openssl rand -hex 32`; rotated in step 10 |
| `RABBITMQ_ADMIN_PASSWORD` | the broker's administrator `admin` | set when RabbitMQ's volume is created |
| `MAILPIT_SMTP_PASSWORD` | SMTP user `mailpit` | the applications render it into their realms |
| `GRAFANA_ADMIN_PASSWORD` | Grafana's `admin` user | |
| `MAILPIT_UI_PASSWORD_HASH` | Mailpit's UI and API (`/mailpit/`, or `mailpit:8025` from a container), user `demo` | the bcrypt hash of a password of your choice (below); Mailpit reads it (`MP_UI_AUTH`) |

The password typed without echo, then given to `caddy hash-password` on its stdin, never on a
command line (`printf` is a shell builtin):

```bash
read -rsp 'Mailpit UI password: ' password && echo \
  && printf '%s\n' "$password" | docker run --rm -i caddy:2.11.4-alpine caddy hash-password; unset password
```

The first three are fixed by the first deployment: the services don't read them again. Changing
the secret afterwards breaks the stack unless the value is changed in the service as well
(Keycloak's console, `ALTER USER` in PostgreSQL, `rabbitmqctl change_password`); for
`MAILPIT_SMTP_PASSWORD`, step 12. `KC_ADMIN_PASSWORD`, `MAILPIT_SMTP_PASSWORD` and the variable
`KC_ADMIN_USERNAME` (step 6) hold neither a double quote, a backslash nor a control character, and
`INFRA_HOST` is a host name: Keycloak writes them into its master realm's JSON as they are, and
`demo/write-env.sh` refuses them (`openssl rand -base64 32` and `-hex 32` are fine). Replacing
Keycloak's administrator by another one is safe: the registrations log in as their own account
([README](../README.md), "The registration account"). Give each administrator of the master
realm, `KC_SETUP_ADMIN_*`'s included, a generated password (`openssl rand -base64 32`): its
console is public and nothing limits guessing there (no brute-force detection on the master realm,
[README](../README.md), "Brute-force protection"). With the master realm's *Verify email*, an
administrator who has an address verifies it (the mail is in `/mailpit/`) before the admin CLI
logs in as them.

## 6. GitHub environment `demo`

In this repository (`ch4mpy/c4-infra`), restricted to `main`, the branch it deploys from (the
environment's *Deployment branches*), so that a workflow run from another branch gets none of its
secrets. `gh secret set` reads the value on its standard input, so nothing lands in the shell's
history:

```bash
R=ch4mpy/c4-infra
gh api -X PUT repos/$R/environments/demo \
  -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'
gh api -X POST repos/$R/environments/demo/deployment-branch-policies -f name=main
gh secret set VPS_HOST --env demo -R $R --body '<vps-ip>'
gh secret set VPS_SSH_KEY --env demo -R $R < c4-infra-demo
gh secret set VPS_KNOWN_HOSTS --env demo -R $R < c4-infra-demo.known_hosts
for s in KC_ADMIN_PASSWORD KC_DB_PASSWORD KC_REGISTRATION_CLIENT_SECRET RABBITMQ_ADMIN_PASSWORD \
    MAILPIT_SMTP_PASSWORD MAILPIT_UI_PASSWORD_HASH GRAFANA_ADMIN_PASSWORD; do
  gh secret set $s --env demo -R $R   # paste the value, then Enter
done
```

The restriction, read back: `gh api repos/$R/environments/demo --jq .deployment_branch_policy`
gives `{"custom_branch_policies":true,"protected_branches":false}`, and
`gh api repos/$R/environments/demo/deployment-branch-policies --jq '[.branch_policies[].name]'`
gives `["main"]`.

Optional variables: `INFRA_HOST` (defaults to `infra.c4-soft.com`) and `KC_ADMIN_USERNAME`
(defaults to `admin`), e.g. `gh variable set INFRA_HOST --env demo -R $R --body infra.c4-soft.com`.

Optional secrets, `KC_SETUP_ADMIN_USERNAME` and `KC_SETUP_ADMIN_PASSWORD`: an administrator of
Keycloak's master realm, for the deployment to create the registration account or set its secret
once the bootstrap administrator no longer logs in (replaced, or its password changed). Until then
the deployment uses the bootstrap one and they stay unset. When a deployment fails saying to set
them: set them, run the deployment once, then delete them
(`gh secret delete KC_SETUP_ADMIN_PASSWORD --env demo -R $R`, and the user name).
A required reviewer on the environment (repository settings) makes each deployment wait for an
approval.

Then delete the local copy of the private key, or keep it in the password manager. Keep the
known-hosts file (it holds no secret): each application's environment gets it too (step 9).

## 7. First deployment

```bash
gh workflow run deploy-demo.yml -R ch4mpy/c4-infra   # or push to main
gh run watch -R ch4mpy/c4-infra
```

- The `build` job builds the Keycloak image and the reverse proxy's (Caddy with its rate-limit
  module, intent 0013) and pushes each to GHCR, tagged with the content of `keycloak/` and of
  `reverse-proxy/` (skipped when that tag exists). Keycloak's is also tagged `<version>-<tree>`,
  the reference `keycloak-image.properties` gives applications' tests, on the same image; a tag
  never moves (intent 0029: the job stops when the description names another one, or when the two
  tags differ).
- Once that run has passed, make the package `c4-infra-keycloak` public, so that applications'
  tests pull it without a login: on GitHub, the package's settings
  (`https://github.com/users/<owner>/packages/container/c4-infra-keycloak/settings`), *Danger Zone*,
  *Change visibility*, *Public*. It can't be made private again, and every version it holds
  becomes public: `keycloak/`'s history holds no secret (intent 0029's step 7 checks each one before).
- The `deploy` job pins the host's key first ([`demo/trust-host-key.sh`](../demo/trust-host-key.sh):
  it fails there without `VPS_KNOWN_HOSTS`), writes the host's `.env` on the runner with
  [`demo/write-env.sh`](../demo/write-env.sh) (failing by name if a secret is missing; mode 600,
  which `rsync -a` keeps), sends `~/c4-infra`, as `c4-infra`, exactly the files of
  [`demo/deploy-files.txt`](../demo/deploy-files.txt) (the compose base and its demo override, the
  shared Caddy configuration, the registry, `routes.sh`, `register-app.sh`,
  `registration-account.sh`, `keycloak-import/master-realm.json`, the host's scripts and
  `demo/c4-app`) and then `.env`, pulls the images, and runs
  [`demo/deploy.sh`](../demo/deploy.sh) on the host: it installs `c4-app` in `/usr/local/sbin`
  when it changed, waits up to 300 s for every service to be healthy (on an empty database,
  Keycloak creates its master realm pre-configured: [README](../README.md), "The master realm"),
  reloads Caddy, creates the registration account (as the administrator of `.env`), and installs the
  nightly backup of Keycloak's database (03:15, host time, `~/backups/`); the applications' is
  root's, at 03:45 (step 3). Every action of the
  workflow is pinned by commit (its tag as a comment).
- The first start takes a few minutes: Let's Encrypt certificates, then Keycloak's database
  migrations.

## 8. Check

- `https://infra.c4-soft.com/auth/admin/`: log in as `admin` with `KC_ADMIN_PASSWORD` (no
  *Forgot password?* on that page); realm master, *Realm settings* → *Email*: Mailpit
  (`mailpit:1025`), and *Test connection* delivers to `admin@infra.c4-soft.com`, in `/mailpit/`.
  Whoever reads Mailpit could follow a password-reset link sent to a master realm's account: on the
  demo host, never turn *Forgot password* back on in the master realm, nor send its users a
  *Credential reset* / *Update password* mail from the console (set the password there instead).
- `https://infra.c4-soft.com/mailpit/` asks for its credentials (user `demo`, the password of step
  5): Mailpit asks for them itself, through Caddy as from an application's container (only
  `/mailpit/livez` and `/mailpit/readyz` answer without);
- `https://infra.c4-soft.com/grafana/` (user `admin`; anonymous access is off).
- On the host: `ssh c4-infra@<vps-ip> 'cd ~/c4-infra && docker compose ps && crontab -l && cat /etc/cron.d/c4-apps-backup'`
  (Keycloak's backup at 03:15, the applications' at 03:45); once an application runs, its nightly
  log: `ssh -t ubuntu@<vps-ip> sudo tail /var/backups/c4-apps/<app>/backup.log`. To run the
  applications' nightly backup now, as root's cron does (`c4-app nightly` refuses `sudo`'s
  `SUDO_USER`): `ssh -t ubuntu@<vps-ip> sudo env -u SUDO_USER /usr/local/sbin/c4-app nightly`.
- The applications' backups run under time limits ([README](../README.md), "Backups"):
  `ITEM_TIMEOUT` (1800 s, each dump or volume's copy), `RESTORE_TIMEOUT` (3600 s, each restore
  step), `NIGHTLY_TIMEOUT` (7200 s, each application's nightly run). To give them more time, for
  every application, write root's `/etc/c4-app/limits` from `ubuntu` (one `KEY=<seconds>` per line,
  1 to 86400; a key left out keeps its default; `backup`, `restore` and the nightly run refuse a
  file that breaks these rules):
  `ssh -t ubuntu@<vps-ip> 'sudo install -d -m 0755 /etc/c4-app && echo ITEM_TIMEOUT=3600 | sudo tee /etc/c4-app/limits > /dev/null && sudo chmod 0644 /etc/c4-app/limits'`.

## 9. Adding an application

Each application deploys with its own account, `<app>` (its registry entry's name), outside the
`docker` group: it sends its files to `~/<app>/` and runs `sudo c4-app` there, which acts on its
own compose project and registers it with what its registry entry assigns to it, nothing else
([README](../README.md), "Accounts"). For each application, a GitHub project (the host deploys no
other: [README](../README.md), "Demo host"), once:

1. **Its registry entry** in [`registry.txt`](../registry.txt), committed in c4-infra and deployed
   (step 7: the deployment sends the registry): `c4-app` refuses an application missing from it.
2. **Its DNS record**, `<app>.c4-soft.com`, and `<app>-mcp.c4-soft.com` for an MCP server (step 1).
3. **Its key pair**, for its workflow only:

   ```bash
   ssh-keygen -t ed25519 -f <app>-demo -C <app>-demo -N ""
   ```

4. **Its account**, with that key (the script of step 3, copied again if `/tmp` was emptied):

   ```bash
   scp demo/vps-bootstrap.sh ubuntu@<vps-ip>:/tmp/
   ssh -t ubuntu@<vps-ip> "sudo bash /tmp/vps-bootstrap.sh app <app> '$(cat <app>-demo.pub)'"
   ```

   It creates the account `<app>` in the group `c4-apps` (not in `docker`), with `~/<app>/`, its
   home closed to the other accounts, and ends with
   `Done. <app>'s workflow can now deploy as <app>@<ip>`. It refuses an account it didn't create
   (`ubuntu`, a system user).
5. **Its secrets**, in the application's GitHub repository, its own `demo` environment, restricted
   to the branch it deploys from (the environment's *Deployment branches*), the keys read on stdin;
   its registry's token too when its images aren't on GHCR:

   ```bash
   A=ch4mpy/<app>
   B=<the branch it deploys from>   # main, master…
   gh api -X PUT repos/$A/environments/demo \
     -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'
   gh api -X POST repos/$A/environments/demo/deployment-branch-policies -f name=$B
   gh secret set VPS_HOST --env demo -R $A --body '<vps-ip>'
   gh secret set VPS_SSH_KEY --env demo -R $A < <app>-demo
   gh secret set VPS_KNOWN_HOSTS --env demo -R $A < c4-infra-demo.known_hosts
   ```

   then delete the local copy of the private key (or keep it in the password manager). The
   restriction reads back as the stack's does (step 6), `["$B"]` for its branch.
6. **Its workflow**: [migration.md](migration.md), "On the demo host" (its compose project on its
   own network `c4-infra.<app>` with unique container names, its routes file, the commands it runs
   as `<app>@<vps-ip>`).
7. **Its backups** ([README](../README.md), "Backups"): its `compose.yml` labels the services that
   hold its data (`c4-infra.backup: postgres` or `volumes`); the host backs it up every night at
   03:45 into `/var/backups/c4-apps/<app>/`, which its account reads, kept 7 days, the run's output
   in `backup.log` there. Step 4's `vps-bootstrap.sh` (re)writes `/etc/cron.d/c4-apps-backup`.
   Its workflow may run `sudo c4-app backup` itself (before a deployment that migrates its database);
   `sudo c4-app restore` lists its backups, `sudo c4-app restore <stamp> --yes` restores one. Each
   dump or volume's copy is stopped after 1800 s (`ITEM_TIMEOUT`), each restore step after 3600 s
   (`RESTORE_TIMEOUT`), its nightly run after 7200 s (`NIGHTLY_TIMEOUT`): what was stopped is said,
   exit 1; the operator changes these for every application in `/etc/c4-app/limits` (step 8). A copy
   off the host is the application's to pull, with `rsync` through its key. When an application
   leaves the host, its backups stay until removed: `sudo rm -rf /var/backups/c4-apps/<app>`, from
   `ubuntu`.

Faito has no demo deployment yet.

## 10. Rotating the registration secret

One step: a new value in the `demo` environment (`gh secret set` reads it on its standard input),
then a deployment, whose `demo/deploy.sh` sets it in Keycloak before any registration uses it:

```bash
openssl rand -hex 32 | gh secret set KC_REGISTRATION_CLIENT_SECRET --env demo -R ch4mpy/c4-infra
gh workflow run deploy-demo.yml -R ch4mpy/c4-infra
```

The former secret no longer logs in. Once the bootstrap administrator no longer logs in, set
`KC_SETUP_ADMIN_*` for that deployment (step 6).

## 11. Re-creating Keycloak's database

The one-shot `keycloak-import` creates the master realm pre-configured ([README](../README.md), "The master realm") on an
empty database only. A host deployed before intent 0009 (the first one, deployed on 2026-10-23)
gets that configuration once its database is re-created, which loses everything Keycloak holds:
the master realm's other administrators, the registration account and the applications' realms.
As `ubuntu`:

```bash
ssh -t ubuntu@<vps-ip> "sudo -u c4-infra -H bash -c 'cd ~/c4-infra && docker compose rm -sf keycloak keycloak-import keycloak-db && docker volume rm c4-infra_keycloak_db'"
gh workflow run deploy-demo.yml -R ch4mpy/c4-infra
```

The deployment runs `keycloak-import` on an empty database: it creates the master realm, with the
administrator of the `demo` environment (`KC_ADMIN_USERNAME`, `KC_ADMIN_PASSWORD`), and
`demo/deploy.sh` creates the registration account again. Each application imports its realm again
at its next deployment.

## 12. Changing Mailpit's SMTP password

A new `MAILPIT_SMTP_PASSWORD` in the `demo` environment, then a deployment: Mailpit and `keycloak-import`'s
containers are recreated with it (Keycloak doesn't restart). The master realm keeps the former password:
in the console, realm master, *Realm settings* → *Email*, type the new one, save, then *Test
connection*. So does every application realm already in Keycloak (a registration leaves a realm
that exists as it is): the same in each one's *Email* settings; only a realm imported again
(`--reset-realms`, which loses its users) takes the password its application renders.

```bash
gh secret set MAILPIT_SMTP_PASSWORD --env demo -R ch4mpy/c4-infra   # paste the value, then Enter
gh workflow run deploy-demo.yml -R ch4mpy/c4-infra
```
