# Plan: Deploying to the demo host gives every application's workflow the whole host

- Spec: [v1](spec.md)
- Status: approved
- Branch: main (grouped pass of 2026-10-21)
- Approved: 2026-10-22, Jérôme Wacongne (engineer, product owner and tech lead), after two rounds of cross-plan coherence review
- Builds on: 0004 (the registry entry each registration is scoped by), 0003 (routes files without host or port, `demo/deploy.sh`, `demo/write-env.sh`, `demo/deploy-files.txt`, the stand-in host), 0006 (the registration account, its secret in the stack's `.env`), 0001 (`tests/lib/`). 0007, implemented next, adds the checks of an application's compose model to the command created here (its REQ-9 enforces this spec's REQ-1 against a hostile compose file).

## Starting point

- `demo/vps-bootstrap.sh` creates one `deploy` user in the `docker` group; every workflow's key goes into its `authorized_keys`.
- After 0003 and 0006: the workflow sends `demo/deploy-files.txt` to `~/c4-infra/`, writes `.env` there (`demo/write-env.sh` sets mode `600` on the runner, `rsync -a` keeps it; it holds the registration secret), and runs `demo/deploy.sh`; `register-app.sh` refuses an application missing from the registry and a routes file naming a host or a port, but still accepts any realm file, theme name or RabbitMQ user.
- The workflow's actions are pinned by tag (`actions/checkout@v7`, `docker/login-action@v4`, `docker/setup-buildx-action@v4`, `docker/build-push-action@v7`, `webfactory/ssh-agent@v0.10.0`); without `VPS_KNOWN_HOSTS` it falls back to `ssh-keyscan`.
- Commit SHAs, from `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` (annotated tags dereferenced) on 2026-10-21 — the major tags in use point at the same commits today:
  `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1), `docker/login-action@dbcb813823bdd20940b903addbd779551569679f` (v4.6.0), `docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069` (v4.4.1), `docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc` (v7.4.0), `webfactory/ssh-agent@e83874834305fe9a4a2997156cb26c5de65a8555` (v0.10.0).
- No demo host exists: no account to migrate. Until 0007 is delivered, the command below runs whatever compose model an application writes (privileged containers included): no application may deploy to a real host before 0007 — none can, the host doesn't exist.

## Files

| File | Change | For |
| --- | --- | --- |
| `demo/vps-bootstrap.sh` | rewritten: `vps-bootstrap.sh c4-infra '<key>'` (Docker if missing, `ufw` 22/80/443, `jq` and `rsync`, group `c4-apps`, `/etc/sudoers.d/c4-infra` checked with `visudo -cf`, user `c4-infra` in `docker`, home `0750`, `~/c4-infra`) and `vps-bootstrap.sh app <name> '<key>'` (user `<name>`, not in `docker`, in `c4-apps`, home `0750`, `~/<name>/`); keys appended as `restrict <key>` (no forwarding, no pty); the firewall part runs every time (idempotent), Docker's install only when missing; a rule rejecting new outgoing connections of the `c4-apps` group except on `lo`, in `ufw-before-output` (`before.rules`) and `ufw6-before-output` (`before6.rules`), then `ufw reload` (below) | REQ-1, REQ-2, REQ-5, AC-1, AC-7 |
| `demo/c4-app` | new: the root-owned command an application's account runs through sudo (below) | REQ-1 to REQ-4, AC-1 to AC-4 |
| `demo/trust-host-key.sh` | new: fails (`::error::`, exit 1) when `VPS_KNOWN_HOSTS` is empty, else appends it to `~/.ssh/known_hosts` (directory `700`); no `ssh-keyscan` | REQ-7, AC-5 |
| `demo/deploy.sh` | modified: when `demo/c4-app` differs from `/usr/local/sbin/c4-app`, `sudo -n /usr/bin/install -o root -g root -m 0755 "$PWD/demo/c4-app" /usr/local/sbin/c4-app` — on the host `$PWD` is `/home/c4-infra/c4-infra`, the path of the `c4-infra` account's only sudo rule; the stand-in tests of 0003 and 0006, run as root in `/root/c4-infra`, keep working | REQ-4, REQ-5 |
| `demo/deploy-files.txt` | modified: `demo/c4-app` | REQ-4 |
| `.github/workflows/deploy-demo.yml` | modified: `VPS: c4-infra@${{ secrets.VPS_HOST }}`; "Trust the VPS host key" (`bash demo/trust-host-key.sh`) moved before `webfactory/ssh-agent`; every `uses:` pinned by the SHAs above, with the tag as a comment | REQ-5, REQ-6, REQ-7, AC-5, AC-6 |
| `register-app.sh` | modified: before any change, every argument checked against the entry: each `--realm` file's realm (from its name) in the entry's realms, imported with `-s realm=<that name>` (the file's own `realm` field can't name another), each theme directory's name in the entry's themes, `--rabbitmq-user` equal to the entry's; run as root (through `c4-app`), what it writes under the stack's directory is `chown --reference` to that directory | REQ-3, AC-3 |
| `README.md` | modified: "Demo host": one account per application, `sudo c4-app`, what a registration may touch; "Day to day" as `c4-infra@<vps>` | REQ-1, REQ-8 |
| `docs/demo-setup.md` | modified: step 2 (a key pair for c4-infra's workflow, one per application later), step 3 (`sudo bash /tmp/vps-bootstrap.sh c4-infra '<key>'`), step 4 (the host key is required), step 8 (`ssh c4-infra@…`), a new step "Adding an application" (its key pair, `vps-bootstrap.sh app <name> '<key>'`, its registry entry committed and deployed first, its secrets `VPS_HOST`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS`) | REQ-8, AC-8 |
| `docs/migration.md` | modified: "On the demo host": the application's workflow as `<app>@<vps>`, the host-key step (the script's lines, inline), the pinned `webfactory/ssh-agent` and `actions/checkout`, `rsync` to `~/<app>/`, then `sudo c4-app pull` (GHCR token on stdin), `sudo c4-app register …` (paths relative to `~/<app>/`, `--rabbitmq-password-env` read from `~/<app>/.env`), `sudo c4-app up` | REQ-6, REQ-8, AC-8 |
| `tests/stand-in-host/Dockerfile` | modified only if a package is missing (`sudo`, `openssh-server`, `ufw`, `jq` are there since 0003) | AC-1 to AC-8 |
| `tests/lib/stand-in-host.sh` | modified: `stand_in_accounts <app>…` (keys generated inside the stand-in, `vps-bootstrap.sh c4-infra` and `app <app>` for each, the shared stack sent to `/home/c4-infra/c4-infra` and deployed as `c4-infra` over ssh) and `stand_in_ssh <account> <command>` (ssh to `127.0.0.1` inside the stand-in with that account's key), reused by 0007 | AC-1 to AC-8 |
| `tests/fixtures/0002/` | new: `faito/compose.yml` (two echo services `faito.gateway`, `faito.frontend` on the external network `c4-infra`, as the README says before 0007), `faito/faito.routes`, `faito/.env` (`RABBITMQ_PASSWORD`), `hururaa/` (the same for `hururaa.gateway`, with a `.env` the test fills with a marker value), `public-facing-realm.json` (minimal), `faito-realm-named-public-facing.json` (file name `faito-realm.json`, `"realm": "public-facing"` inside), `themes/tickee/login/theme.properties`, `routes-hururaa-host.routes`, `routes-keycloak-port.routes` | AC-2, AC-3 |
| `tests/0002-workflow.sh` | new: AC-5 and AC-6 | AC-5, AC-6 |
| `tests/0002-register-scope.sh` | new: AC-3 on the workstation (stubbed `docker`: refused before any call) | AC-3 |
| `tests/0002-accounts.stand-in.sh` | new: AC-1 to AC-4, AC-7, AC-8 on the stand-in host, over ssh with generated keys | AC-1 to AC-4, AC-7, AC-8 |
| `docs/intent/0002-demo-deployment-access/plan.md` | new: this plan (`approved` at the gate) | bookkeeping |
| `docs/intent/0002-demo-deployment-access/intent.md` | modified: status `planned` at approval | bookkeeping |
| `docs/intent/README.md` | modified: index row 0002 → `planned` | bookkeeping |

`/etc/sudoers.d/c4-infra` (written by the bootstrap):

```text
%c4-apps ALL=(root) NOPASSWD: /usr/local/sbin/c4-app
c4-infra ALL=(root) NOPASSWD: /usr/bin/install -o root -g root -m 0755 /home/c4-infra/c4-infra/demo/c4-app /usr/local/sbin/c4-app
```

`demo/c4-app` (installed `root:root 0755` in `/usr/local/sbin`):

- `sudo c4-app pull [--registry <host> --registry-user <user>]` (token on stdin, used with a temporary `DOCKER_CONFIG` removed at once), `sudo c4-app up`, `sudo c4-app down`, `sudo c4-app register [register-app.sh's options]`; nothing else.
- The application is `$SUDO_USER` (never an argument): refused when empty, `root`, `c4-infra`, or absent from `/home/c4-infra/c4-infra/registry.txt` (`registry.sh` sourced, `REGISTRY_FILE` unset). `PATH` fixed, `umask 027`, `flock` per application.
- **Staging**: `/home/<app>/<app>/` is copied by root into `/var/lib/c4-apps/<app>/` (`root:<app>`, `0750`, the application can read but not write it); a symbolic link or a special file in the copy → refused. Every path argument must resolve (`realpath -m`) inside the staging directory.
- **The compose model is read as the application**: `runuser -u <app> -- env HOME=/home/<app> docker compose --project-directory <staging> -p <app> -f <staging>/compose.yml config --format json` (no daemon needed; another application's `env_file`, `extends` or `include` can't be read by that account) into **one** root-owned file, `<staging>/.c4-app.model.json` (compose reads JSON as YAML); `pull`, `up -d --wait --remove-orphans` and `down` run as root with `-f <staging>/.c4-app.model.json` only. 0007 checks that same file with `jq` before `up`: the model checked is the model started.
- `register`: `--rabbitmq-password-env <VAR>` takes `<VAR>` from the staging `.env` (read as data, exported, never on a command line); then `bash /home/c4-infra/c4-infra/register-app.sh --app <app> …` with the staged paths. The registration secret stays in `/home/c4-infra/c4-infra/.env` (`600`, `c4-infra`), which only root reads.

Firewall rule, before the `*filter` table's `COMMIT`: in `/etc/ufw/before.rules`, `-A ufw-before-output -m owner --gid-owner c4-apps --suppl-groups -m conntrack --ctstate NEW ! -o lo -j REJECT`; in `/etc/ufw/before6.rules`, the same on IPv6's chain, `-A ufw6-before-output …`. An application's account opens no connection of its own (its ssh and rsync are inbound), so it can't reach the containers' addresses from the host either. Added once (a `grep -qF` before appending), then `ufw reload`.

## Order of work

1. **Workflow: pinned actions, required host key**: `demo/trust-host-key.sh`, the workflow, `tests/0002-workflow.sh` (every `uses:` of `.github/workflows/*.yml` ends in `@` + 40 hex characters; `grep -rn ssh-keyscan .github demo` finds nothing; the host-key step's line comes before `webfactory/ssh-agent`'s and before any `ssh`/`rsync`; `VPS_KNOWN_HOSTS= HOME=<tmp> bash demo/trust-host-key.sh` exits 1 with `::error::`, with a value it writes `<tmp>/.ssh/known_hosts`). — skill: none — check: `bash tests/0002-workflow.sh`.
2. **Registrations scoped by the entry** in `register-app.sh`, `tests/fixtures/0002/`, `tests/0002-register-scope.sh` (with 0001's stubbed `docker`, each refused before any `docker` call: `--app faito --realm <tmp>/public-facing-realm.json --reset-realms`; `--rabbitmq-user hururaa-api`; `--themes tests/fixtures/0002/themes` (holding `tickee`), and `keycloak/themes/tickee` is as before (absent, or same `cksum`); `--proxy routes-hururaa-host.routes`; `--proxy routes-keycloak-port.routes`). — skill: none — check: `bash tests/0002-register-scope.sh && bash ../faito/deploy-dev.sh` (Faito's own registration still passes).
3. **The root-owned command** `demo/c4-app`, `demo/deploy.sh`, `demo/deploy-files.txt`. — skill: none — check: `bash -n demo/c4-app` and the stand-in test of step 5 (written with it, run there).
4. **Host bootstrap** `demo/vps-bootstrap.sh`. — skill: none — check: on a fresh stand-in, `bash demo/vps-bootstrap.sh c4-infra "$(cat <key>.pub)"` then `… app faito …` and `… app hururaa …`: exit 0; run twice: same result (idempotent, each rule present once); `visudo -c` ok; `id faito` shows no `docker`; `ufw reload` exits 0; `iptables -S ufw-before-output | grep -c gid-owner` and `ip6tables -S ufw6-before-output | grep -c gid-owner` both print `1`.
5. **Accounts end to end**: `tests/0002-accounts.stand-in.sh` — keys generated in a temporary directory inside the stand-in; the shared stack deployed as `c4-infra` over ssh (`stand_in_send /home/c4-infra/c4-infra`, `.env` from `stand_in_env`, `bash demo/deploy.sh`), which installs `c4-app`; Hurura'a's fixture rsynced to `~hururaa/hururaa/` and deployed with Hurura'a's key (`sudo c4-app register --proxy hururaa.routes`, `sudo c4-app up`), Faito's rsynced to `~faito/faito/` with Faito's; then, over ssh with Faito's key:
   - AC-2: `sudo c4-app pull`, `sudo c4-app register --proxy faito.routes`, `sudo c4-app up` exit 0, `faito.gateway` runs, `caddy/apps/faito.caddy` exists and is owned by `c4-infra`;
   - AC-1: `cat /home/hururaa/hururaa/.env`, `cat /home/c4-infra/c4-infra/.env`, `docker ps`, `docker stop hururaa.gateway`, `sudo -n docker ps` → refused; `curl --max-time 3 http://<IP of hururaa.gateway>:7080/` → refused (firewall rule); `sudo c4-app down` stops Faito's project only (Hurura'a's fixture container still runs);
   - AC-3: through `sudo c4-app register`: Hurura'a's realm file with `--reset-realms`, `--rabbitmq-user hururaa-api`, `--themes` holding `tickee` (and `keycloak/themes/tickee`, placed beforehand, unchanged), the two hostile routes files, a path outside `~/faito/` (`../hururaa/x`), a symbolic link in `~/faito/` → each refused; `faito-realm-named-public-facing.json` (as `faito-realm.json`) imports realm `faito`, and no `public-facing` realm appears;
   - AC-4: the registration secret never in any output of `c4-app` (`grep -F -f`), `.env` unreadable (`stat -c %a /home/c4-infra/c4-infra/.env` is `600`, owner `c4-infra`), `sudo -l` lists `c4-app` only;
   - AC-7: as `c4-infra`, `bash demo/deploy.sh` restarts the stack; as `faito`, `cd /home/c4-infra/c4-infra`, `docker compose -p c4-infra restart`, `sudo -n /usr/bin/install … /usr/local/sbin/c4-app` → refused;
   - AC-8: the sequence above is exactly `docs/demo-setup.md`'s and `docs/migration.md`'s commands, with the stand-in's address.
   — skill: none — check: `bash tests/0002-accounts.stand-in.sh && bash tests/0006-bootstrap-admin-replaced.stand-in.sh && bash tests/0003-demo-deploy.stand-in.sh`.
6. **Docs**: README, `docs/demo-setup.md`, `docs/migration.md`. — skill: none — check: `bash tests/run.sh`; `grep -rn 'deploy@' README.md docs/` finds nothing.

## Risks

- A compose model can still escape a container (privileged, the Docker socket, host paths, another application's volume or network) until 0007 → stated in the Starting point; 0007 is the next plan of the pass, before any demo deployment.
- An application changing its files while `c4-app` runs (symlink swap, file replaced) → root works on its own staging copy, checked after the copy; the application can't write it.
- Reading the model as the application needs `docker compose config` to work without the daemon → step 5 runs it as `faito` (not in `docker`); if compose needs the socket for `config`, it is a deviation to raise before going on (the confinement against another application's `env_file`, `extends` or `include` depends on it).
- `ufw` inside the stand-in container may not apply its rules → if so, the firewall line of AC-1 is proven on the first demo deployment only (`sudo -u faito curl …`), recorded as a deviation.
- The `c4-infra` account can install root code through its `install` rule → it is in `docker` already (root-equivalent, REQ-5's account); the rule takes one exact command line, no wildcard.
- An application's GHCR token on `c4-app pull`'s stdin → a temporary `DOCKER_CONFIG` (`0700`, removed on exit); never in root's `~/.docker`.
- Pinning by SHA freezes the actions' updates → the tag stays as a comment; Dependabot or a periodic `gh api` check updates them (out of scope).
- `restrict` on keys also forbids an interactive shell's pty → the workflows run non-interactive commands only; the operator logs in as `ubuntu` (OVH's sudoer), not with a workflow key.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-1 | automated test (stand-in host), then first demo deployment | `bash tests/0002-accounts.stand-in.sh` — reads, `docker`, another project's containers, the containers' addresses: refused. Not verifiable here — first demo deployment: the same commands with Faito's real key (`ssh faito@<vps> 'cat ~c4-infra/c4-infra/.env; docker ps'` refused) |
| AC-2 | automated test (stand-in host), then first demo deployment | `bash tests/0002-accounts.stand-in.sh` — pull, register, up with Faito's key. Not verifiable here — first demo deployment: Faito's real workflow (its images, its realm) succeeds |
| AC-3 | automated tests | `bash tests/0002-register-scope.sh` (dev, refused before any `docker` call; Tickee's theme unchanged), `bash tests/0002-accounts.stand-in.sh` (the same through `sudo c4-app register`, plus the realm-name forcing) |
| AC-4 | automated test (stand-in host) | `bash tests/0002-accounts.stand-in.sh` — `.env` unreadable, secret in no output, `sudo -l` |
| AC-5 | automated test, then a human-triggered run | `bash tests/0002-workflow.sh`. Not verifiable here — the workflow on GitHub: a run of `deploy-demo.yml` while `VPS_KNOWN_HOSTS` is unset fails at "Trust the VPS host key", before `webfactory/ssh-agent` (a human's `gh workflow run`, or the first deployment attempt before step 6 of `docs/demo-setup.md`) |
| AC-6 | automated test | `bash tests/0002-workflow.sh` — every `uses:` by a 40-character SHA; `docs/migration.md`'s snippet too (`grep -n 'uses:' docs/migration.md`) |
| AC-7 | automated test (stand-in host) | `bash tests/0002-accounts.stand-in.sh` — `c4-infra` deploys; Faito's account can't |
| AC-8 | automated test (stand-in host), then first demo deployment | `bash tests/0002-accounts.stand-in.sh` follows the two documents' commands. Not verifiable here — first demo deployment: the demo operator follows `docs/demo-setup.md` and `docs/migration.md` for Faito on the real VPS, with no other step |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-22 — `registry.sh check` also refuses an entry owning Keycloak's `master` realm or the RabbitMQ administrator's user (`RABBITMQ_ADMIN_USER` of the `.env` next to it, `admin` by default) — once registrations are scoped by the entry (REQ-3), such an entry would authorize deleting the master realm (`--realm master-realm.json --reset-realms`) or overwriting the administrator's password (`--rabbitmq-user admin`), and `registration-account.sh ensure` would grant the master realm's roles — files: `registry.sh` (beyond *Files*), two fixture registries in `tests/fixtures/0002/`, their cases in `tests/0002-register-scope.sh` (step 2; 0004's test untouched) — approved by Jérôme Wacongne (approver of the grouped pass), with the check of REQ-3's `--realm` scoping (a realm file not named in the entry refused), already step 2's first case.
- 2026-10-22 — the applications' fixture `.env` files (`faito/.env`, `hururaa/.env`) are written by `tests/0002-accounts.stand-in.sh` into the copy it uploads (Faito's with a random `RABBITMQ_PASSWORD`, Hurura'a's with the marker), not committed under `tests/fixtures/0002/` — `.gitignore` ignores every `.env`, and a committed fixture would need `git add -f` — files: no `tests/fixtures/0002/*/.env`; proof unchanged.
- 2026-10-22 — `c4-app`'s staging copy is read as the application (`runuser -u <app> -- tar -C ~/<app> -cf - .`) and written by root (extracted into a root-only directory, checked for symbolic links and special files, then `rsync -a --delete` into `/var/lib/c4-apps/<app>/`, whose inode stays) — root never reads a file of the application's directory on its behalf (a hard link, a file swapped while copying); `down` also passes `--remove-orphans`; root's `docker compose` reads the model with `--env-file /dev/null` (the model is interpolated already: checked on the stand-in, `env_file` is merged into `environment` and leaves no path in the model, `$` stays escaped) — files: `demo/c4-app` only; proof unchanged.
- 2026-10-22 — step 5: `stand_in_accounts` removes the homes it is about to create (and `/var/lib/c4-apps`) first, naming each leftover — the stand-in's dockerd restarts an earlier run's containers from its persisted volume before `stand_in_up` removes them, and their bind mounts recreate `/home/c4-infra/c4-infra/…` root-owned: `useradd` then keeps a root-owned home and sshd refuses c4-infra's key (seen once, in the run that followed a passing run; diagnosed with a one-shot debug sshd, `_stand_in_ssh_diagnose`, kept for a failing login) — files: `tests/lib/stand-in-host.sh` only; proof unchanged.
- 2026-10-22 — AC-8's part of `tests/0002-accounts.stand-in.sh` (Faito deployed with `docs/migration.md`'s own lines, `docs/demo-setup.md`'s bootstrap commands matched) is written at step 6, with the documents it reads; it runs in the final `bash tests/run.sh --all` — the documents don't exist at step 5 — files: none beyond *Files*; proof unchanged (AC-8 still by the stand-in test).
- 2026-10-22 — step 6's `grep -rn 'deploy@' README.md docs/` finds one line, this plan's own step 6 quoting that command (the intent home is under `docs/`): the check is read as "nothing in the documentation", `--exclude-dir=intent`, both outputs shown — files: none; proof unchanged.
