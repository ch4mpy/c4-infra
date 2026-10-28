# Plan: The demo host backs up no application's data

- Spec: [v1](spec.md)
- Status: approved
- Branch: 0027-demo-host-backs-up-no-application-data
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the batch and the agents, product owner)
- Builds on: `main` at 75d2809 (0025 delivered: `copy_in`, `read_model`, `check_model`, `pull_missing`, `place_copy`); merged at step 0

## Starting point

- `demo/c4-app` (at `main` 75d2809). Its header lists `pull`, `up`, `down`, `register` (`:7-23`), as does `usage` (`:91-101`). The application comes from `SUDO_USER` (`:104-109`, root without it refused at `:106`) and must be in the registry (`:111-116`). One command at a time per application: `flock -w 600` on `/var/lib/c4-apps/.<app>.lock` (`:127-130`), silent while it waits; `trap 'rm -rf "$incoming"' EXIT` (`:131`). `copy_in` removes the root-only snapshot `.run.<app>/` (`:138`): `register` and a refused `up` both leave it different from what runs, so the model can't tell what runs. `down` stops by the project's name with no file (`:413-418`). In `check_model`, a service's `labels` are allowed (`:216`), a volume's labels aren't checked, its name is `<app>_<key>`, local, never external (`:239-244`), a service's name is `[a-z0-9][a-z0-9_-]*` (`:252-253`), `container_name` starts with `<app>.` (`:262-263`), and a bind mount is read-only, inside `/var/lib/c4-apps/<app>/` (`:278-282`). The spec's line numbers (`:189`, `:212-217`, `:122-125`, `:134`, `:371-390`) are from before 0025; the facts they cite still hold.
- `demo/vps-bootstrap.sh`: `%c4-apps ALL=(root) NOPASSWD: /usr/local/sbin/c4-app` (`:102`) allows any arguments, so `backup` and `restore` need no new sudo rule. Each application's account is created `--groups c4-apps` (`:164`), so `getent group c4-apps` lists them. No new outgoing connection from that group (`:125`). Nothing is scheduled as root.
- `demo/backup.sh:22-25`: Keycloak's dump, `docker compose exec … sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc'`, the pattern RQ-06 asks for. Its header says "Each application backs up its own databases" (`:3-4`), and so does `README.md:714-715`. `demo/deploy.sh:66-74` installs it in `c4-infra`'s crontab at 03:15.
- `compose.yml:80-81`: Keycloak's database runs `postgres:18.6` (Debian, GNU tar). It is on every demo host and has a running container, `c4-infra.keycloak-db`.
- Docs: `README.md` "Accounts" (`:556-624`) and "Backups" (`:711-748`); `docs/migration.md:238-240` (step 7, "open as an intent"); `docs/demo-setup.md` step 3 (`:41-60`), step 7 (`:168`, Keycloak's nightly backup), step 8 (`:185`, `crontab -l`) and step 9 (`:187-229`). The demo host runs the stack (deployed by every push to `main` since 2026-10-23; `README.md:554` is stale, intent 0028) and no application yet: there is no application data to migrate.
- Tests: `tests/lib/stand-in-host.sh`. The stand-in is privileged (`:79-80`) and its image has `cron`, `sudo` and `jq`. `stand_in_accounts` (`:189-229`) creates the accounts and deploys the stack, so `postgres:18.6` runs there. `tests/0025-refused-stage.stand-in.sh` is the model (`as_faito`, `refused`, `says`, `send`).
- The applications: Tickee's `rest-api-db` (`postgres:18`, `POSTGRES_USER: rest-api`, with a hyphen, so it must be quoted as an identifier) and `ldap2` (`ldap2_data`, `ldap2_config`); immo's `rest_api_db` (`POSTGRES_PASSWORD_FILE`, so the dump goes through the container's local socket, which the official image trusts) and `rustfs`.

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Proposed by Claude, for Jérôme Wacongne (engineer, and tech lead for the high risk) to approve with this plan. The ones marked **to confirm** are open questions.

- **E1. Everything goes in `demo/c4-app`.** `backup`, `restore` and the nightly run all live there. `deploy.sh` installs that one file through `c4-infra`'s one exact sudo rule. Rejected: a second root-owned script, which would need a second sudo rule.
- **E2. The nightly run is a root-only `c4-app nightly`** (**to confirm**).
  - `vps-bootstrap.sh` writes `/etc/cron.d/c4-apps-backup` (0644 root): `45 3 * * * root /usr/local/sbin/c4-app nightly`.
  - `c4-app` accepts `nightly` only from root without `SUDO_USER`. `sudo` always sets `SUDO_USER`, so an application can't run it.
  - For each member of `c4-apps` (name checked `^[a-z][a-z0-9-]*$`), it runs `runuser -u <app> -- sudo -n /usr/local/sbin/c4-app backup`, which is RQ-01 run as that account. Each run is appended to `/var/backups/c4-apps/<app>/backup.log` (0640 `root:<app>`), between a dated header and the exit status.
  - Rejected: `c4-infra`'s crontab (its sudo rule only installs `c4-app`); a loop written into the cron file (it couldn't be updated by a deployment); calling the backup as root with the name set (not "as that account").
- **E3. What a backup or restore selects.**
  - A container must carry the label `com.docker.compose.project=<app>` **and** be named `/<app>.…` or `/<app>-…`. A volume must carry the label **and** be named `<app>_…` (RQ-06).
  - The service name (label `com.docker.compose.service`) must match `^[a-z0-9][a-z0-9_-]*$`, and a volume name `^<app>_[A-Za-z0-9][A-Za-z0-9_.-]*$`, before either is used as a file name or a Docker argument.
  - A declared service with more than one container (replicas) is refused.
  - The value of `c4-infra.backup` must be exactly `postgres` or `volumes`. In a message it is printed with `printf %q`, so no control character reaches the log.
- **E4. Streams, not mounts.**
  - A dump: `docker exec <id> sh -c 'pg_dump -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-${POSTGRES_USER:-postgres}}" -Fc'`. The script is fixed and its values are read inside the container.
  - A volume: `docker run --rm -i --pull never --network none --read-only --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add FSETID [--cap-add MKNOD] --security-opt no-new-privileges --log-driver none --mount type=volume,src=<vol>,dst=/data --entrypoint tar <image> --numeric-owner -cpf - -C /data .`
  - Restore pipes the file back the same way: `pg_restore` in the database's container, `find /data -mindepth 1 -delete && tar -xpf -` in the throwaway container. Root's own shell writes and reads the files, so the throwaway container mounts the volume and nothing else (RQ-06 allows "that volume and that backup's directory": this mounts one less), and nothing is bind-mounted, so no mount source is left on the stand-in.
  - `<image>` is the image id of the running `c4-infra.keycloak-db` (**to confirm**): it is the stack's own image, it is present, it needs no pull, and it has GNU tar. Rejected: the reverse proxy's Caddy (BusyBox tar); a dedicated image (one more pull, and not "of the stack"). Step 1 measures the tar options and the capabilities needed.
- **E5. Layout and rotation.**
  - Paths: `/var/backups/c4-apps/` (0755 root, created by `c4-app` as `:128` does for `/var/lib/c4-apps`), then `<app>/` (0750 `root:<app>`), then `<stamp>/` (0750) holding `<service>.dump` and `<service>.<volume key>.tar` (0640 `root:<app>`).
  - The stamp is `date -u +%Y%m%d-%H%M%S`. A backup is written into `<stamp>.partial/` and renamed when complete, so an interrupted backup is never listed or restored, and the next run of that application removes it. A second backup in the same second waits for the next.
  - Restore accepts `^[0-9]{8}-[0-9]{6}$` only.
  - Rotation (PA-04 A) runs at each run of the application, whether on demand, nightly or a restore's safety backup. It removes every stamp lexically older than `date -u -d '7 days ago'`, and never `backup.log`.
- **E6. The disk floor (PA-05 B)** (**to confirm** how to read "10 % or 5 GB").
  - Free space is read with `df -P -B1` on `/var/backups/c4-apps`.
  - A backup is refused when the free space is under 5 GiB **or** under 10 % of the size: the larger of the two floors.
  - It is checked before each item and after the last. Under the floor, the `.partial` is removed and the refusal names the free space and the floor. Earlier backups are untouched.
- **E7. The order of a restore (PA-06 A).**
  1. Every check comes first, and a refusal stops nothing: `--yes` given; the stamp complete; each `.dump` matched to a running container whose label is `postgres`, and each `.tar` to a volume of the project; the floor for the safety backup.
  2. Every running container of the project but the `postgres` ones stops (`docker stop`).
  3. The safety backup, which is E5 unchanged: its dumps are taken hot from the databases still running, its volumes are copied cold, and nothing writes in between.
  4. Each database: `DROP DATABASE … WITH (FORCE)` and `CREATE … OWNER`, sent to `psql` on stdin as `:"db"` and `:"owner"` variables (Tickee's `rest-api`), then `pg_restore --exit-on-error`.
  5. Each volume is emptied and filled again, with every container mounting it stopped.
  6. The stopped containers start again (`docker start`). The restore waits for them to run, and to be healthy where they have a healthcheck, for up to 300 s.
  - A failure after step 2 starts the containers again (a trap on EXIT, INT and TERM, which also does the current `rm -rf "$incoming"`) and names the safety backup.
  - Rejected: `docker compose -p <app> stop/start` with no file. It selects by label only. Step 1 measures whether it honours `depends_on`; if E3's double match proves useless (fact a), it can replace step 6.
- **E8. Exit status** (**to confirm**).
  - A project with no container, none running, or no `c4-infra.backup` label: the message, nothing written, exit 0. A workflow's `sudo c4-app backup` before its first deployment then passes, and the nightly log names it.
  - A refusal (a label's value, the floor, a stopped database, a failed item) or a failure: exit 1.
  - The volumes no declaration covers, beyond the databases' own, are named: `not backed up: <app>_cache`. This is PA-01's "a forgotten one shows".
- **E9. Waiting for the lock.** The lock stays as it is, plus one line when it has to wait: `c4-app: waiting for another c4-app command of <app> (600 s at most)` (`flock -n`, then `flock -w 600`). That line is AC-07's evidence.
- **E10. No check of the label at `up`.** Rejected for now: AC-05 wants the refusal at backup time, and its test deploys the label through `up`. A later intent can add it to the allowlist.
- **E11. Free space in the tests.** The stand-in tests mount a tmpfs at `/var/backups/c4-apps` (`size=20g`, which uses RAM only for what is written). The floor then doesn't depend on the workstation's disk. AC-08 remounts it at `size=4g`.

## Files

| File | Change | For |
| --- | --- | --- |
| `demo/c4-app` | modified: `backup` (E3 to E6, E8), `restore` (with no argument it lists the stamps and their sizes; `restore <stamp> --yes` follows E7; without `--yes` it is refused, saying how), `nightly` (E2), the lock's waiting line (E9), the EXIT trap combined; header and `usage` | RQ-01 to RQ-07, RQ-08, AC-01 to AC-08 |
| `demo/vps-bootstrap.sh` | modified: `/etc/cron.d/c4-apps-backup` written at every run (0644 root, 03:45, `c4-app nightly`); header | RQ-03, AC-06 |
| `demo/backup.sh` | modified: header comment only. "Each application backs up its own databases" now names `sudo c4-app backup`. Keycloak's backup is unchanged (out of scope) | RQ-08 |
| `README.md` | modified: "Accounts" gets `sudo c4-app backup` and `restore` (what runs, that they stage and pull nothing, the lock). "Backups" gets the applications' part: the label, the directory and its modes, the nightly run at 03:45 and its log, 7 days, the floor, the restore and its safety backup, a dump that covers `POSTGRES_DB` only (PostgreSQL 13 or later), PA-07 B (the application pulls its own copy with `rsync` through its key), and a departed application's backups removed by hand | RQ-08, AC-09 |
| `docs/migration.md` | modified: step 7. `deploy/backup.sh` goes; the project labels its services (Tickee: `rest-api-db` `postgres`, optionally `ldap2` `volumes`; immo: `rest_api_db` `postgres`, `rustfs` `volumes`); optional `ssh "$VPS" sudo c4-app backup` before a deployment that migrates its database; no more "open an intent" | RQ-08, AC-09 |
| `docs/demo-setup.md` | modified: step 3 (the nightly run of the applications, `/etc/cron.d/c4-apps-backup`), step 7 (`:168`), step 8 (`cat /etc/cron.d/c4-apps-backup`), step 9 (an application's backups, its log, its off-host copy; removing a departed application's backups) | RQ-08, AC-09 |
| `tests/0027-backup-facts.stand-in.sh`, `tests/fixtures/0027/facts/` | new: step 1's facts, on a bare stand-in | step 1 |
| `tests/0027-backup.stand-in.sh` | new: Faito with `tests/fixtures/0027/data.yml` (`db` `postgres:18.6` labelled `postgres`, user `fixture-user`, with `POSTGRES_HOST_AUTH_METHOD: trust`, so no password; `files`, a Caddy labelled `volumes` on `files_data`; `other` on `cache`, undeclared): AC-01, AC-02, AC-04, AC-05, AC-07, AC-08 | AC-01, AC-02, AC-04, AC-05, AC-07, AC-08 |
| `tests/0027-isolation.stand-in.sh` | new: accounts `faito`, `hururaa`, `turu` and `tickee`. Faito (A) with `forged.yml`, a service and a volume labelled `com.docker.compose.project: hururaa`; Hurura'a (B) with `hururaa.yml`; Turu declaring nothing; Tickee with no project. AC-03, then AC-06 | AC-03, AC-06 |
| `tests/0027-docs.sh` | new: the README, `c4-app`'s usage (read from the file), `docs/migration.md` and `docs/demo-setup.md` name `c4-infra.backup`, `sudo c4-app backup`, `sudo c4-app restore`, `/var/backups/c4-apps/` and 03:45; `docs/migration.md` no longer says "open as an intent" | AC-09 |
| `tests/fixtures/0027/` | new: `data.yml`, `relabelled.yml`, `refused.yml` (a published port), `label-rsync.yml`, `label-injection.yml` (`postgres;id`), `slow-up.yml` (a service healthy after about 15 s), `forged.yml`, `hururaa.yml`, `turu.yml` | the tests above |
| `docs/intent/0027-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

**Batch** (the product owner, 2026-10-28): 0026 to 0031 are delivered in one batch, merged in this order into `batch-0031-0030-0028-0026-0027-0029`, from `main`: 0031, 0030, 0028, 0026, 0027, 0029. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the six in the batch's order, with one push of `main`, validated by the product owner.

**Implemented by an agent** (the product owner, 2026-10-28), in a worktree of this branch. `.env` and `certs/` are copied from the main tree and removed with the worktree. Its stand-in tests run on `c4-infra-stand-in` (`STAND_IN_NAME=c4-infra-stand-in STAND_IN_VOLUME=c4-infra-stand-in-docker`), the other agent's being on the other host. It never starts or changes the dev stack from the worktree (`up.sh`, `docker compose` of the project `c4-infra`): the dev stack's mounts would point into the worktree. A deviation that changes the scope, a risk or a proof stops it, reported, until the engineer decides.

0. **Setup**: `git switch 0027-demo-host-backs-up-no-application-data && git merge main`, which brings in 0025's `c4-app`. — skill: none — check: `git status --short` is empty; `bash -n demo/c4-app`.
1. **Facts**, measured first: `tests/0027-backup-facts.stand-in.sh` (`stand_in_up`, no accounts; root's `docker compose` on a `config --format json` model, as `c4-app` runs it). — skill: none — check: the test passes, and each fact is recorded under *Deviations*. A fact that differs is a deviation before its step. Commit `test(0027): …`.
   - (a) A service whose `labels` set `com.docker.compose.project: other` and `com.docker.compose.service: x`, and a volume whose `labels` set the project too: the labels the container and the volume carry (compose's, or the file's). This decides E3 and the *Risks*.
   - (b) `docker compose -p <p> stop`, then `start`, run from an empty directory with no file: whether they act on the project, whether `start` honours `depends_on`, whether `--wait` works (E7).
   - (c) `postgres:18.6` (read from `compose.yml`): a hot `pg_dump -Fc` through `docker exec`, with a user that has a hyphen; `DROP … WITH (FORCE)` while a session is open, `CREATE … OWNER` through `psql` variables on stdin, then `pg_restore --exit-on-error` into the new database: exit 0, and the rows are the same.
   - (d) A cold copy of a named volume, with E4's throwaway container (that image's id, `--cap-drop ALL` plus the listed capabilities, `--network none`, `--read-only`, `--pull never`). The volume holds owners 999 and 70, modes 0700 and 2755, a relative and an absolute symbolic link (both kept as links and not followed), a hard-link pair, a fifo, an empty directory, and names with a space, a leading `-` and a newline. After emptying and restoring, `find -printf '%P %U %G %m %y %l'` and the contents' checksums are the same. This also finds the smallest set of capabilities and tar options that works.
   - (e) Free space: `df -P -B1 --output=avail,size` of a tmpfs mounted at `/var/backups/c4-apps` with `size=20g`, then remounted at `4g`; root's redirections into it work. The reading of the stand-in's own disk is recorded but not checked.
   - (f) `getent group c4-apps` lists an account created with `useradd --groups c4-apps`. `runuser -u <it> -- sudo -n <stub>`, with no terminal and the sudo rule of `vps-bootstrap.sh:102` pointed at a stub, gives `SUDO_USER=<it>`.
2. **Backup**: `demo/c4-app` `backup`, with E9's waiting line; `tests/0027-backup.stand-in.sh` with the checks for AC-01, AC-04, AC-05, AC-07 and AC-08, written first and shown to fail (`usage`). — skill: none — check: `bash -n demo/c4-app && bash tests/0027-backup.stand-in.sh && bash tests/0025-refused-stage.stand-in.sh`: `every check passed`. Commit `feat(0027): sudo c4-app backup …`.
3. **Restore**: `demo/c4-app` `restore`; AC-02's checks added to the same test, shown to fail first. — skill: none — check: `bash tests/0027-backup.stand-in.sh && bash tests/0011-demo-host.stand-in.sh`. Commit `feat(0027): sudo c4-app restore …`.
4. **Nightly run and isolation**: `demo/vps-bootstrap.sh` (the cron file), `demo/c4-app` `nightly`; `tests/0027-isolation.stand-in.sh` (AC-03, AC-06). — skill: none — check: `bash tests/0027-isolation.stand-in.sh && bash tests/0002-accounts.stand-in.sh`. The latter shows the bootstrap still works and `sudo -l` still lists `c4-app` only. Commit `feat(0027): …`.
5. **Docs**: `README.md`, the header and `usage` of `demo/c4-app`, `docs/migration.md`, `docs/demo-setup.md`, the comment of `demo/backup.sh`; `tests/0027-docs.sh`. — skill: none — check: `bash tests/0027-docs.sh && bash tests/0002-workflow.sh`, and a reread against RQ-08's list. Commit `docs(0027): …`.
6. **Verification**: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`. Mutation checks, each in a throw-away worktree:
   - the stamp's pattern dropped: `tests/0027-isolation.stand-in.sh` KO on `../hururaa/<stamp>`;
   - the floor dropped: `tests/0027-backup.stand-in.sh` KO (AC-08);
   - the safety backup dropped: KO (AC-02);
   - the rotation dropped: the isolation test KO (AC-06);
   - `flock -w` replaced by a refusal: KO (AC-07).

   Then `/sdlc-verify 0027`: bootstrap mode, so one round; high risk, so the security pass too. — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0027`.
7. **After deployment**: the push deploys the demo host, which installs the new `c4-app` (the deploy-demo run's log: `c4-app installed`). `/etc/cron.d/c4-apps-backup` is written by the next run of `vps-bootstrap.sh` on the host, the human's: the first application's (`vps-bootstrap.sh app <name>`, `docs/demo-setup.md` step 9), since none is there yet to back up; its step 8 then checks the cron file and the first `backup.log`. — skill: sdlc-ship — check: recorded under `### After deployment`.

## Risks

- **Compose may keep a service's or volume's own `com.docker.compose.project` (fact a).** Then RQ-06's `<app>-` name prefix doesn't tell `faito` from a later `faito-2`: `faito-2` could label a default-named container `faito-2-x-1` with the project `faito`. → Fact a is measured before any code. If compose keeps the file's label, the deviation is to refuse `com.docker.compose.*` labels in `check_model`, and AC-03's "given" then needs a spec v2 (A's `up` would be refused). No current pair of registry names is a prefix of the other followed by `-`.
- **`root` reads and writes an application's data.**
  - Root runs `pg_dump` in the application's own container, through a fixed script whose values are read inside it. Its output is data that root writes to a file and never runs or parses.
  - The throwaway container mounts only that volume. It has no network, its capabilities are dropped and its root filesystem is read-only.
  - Names are checked by pattern, and the label's value comes from a fixed list.
- **A failed restore can leave the data half restored.** → The safety backup is taken first and named in the failure message. The trap starts the containers again.
- **A cold copy stops a service others depend on** (immo's RustFS during the nightly run). → For seconds, at 03:45, as PA-01 B accepted; the containers are waited for afterwards.
- **The disk.** Uploaded files times 7 days. → The floor (E6). It also refuses a restore, whose safety backup wouldn't fit, before anything stops.
- **Keycloak's database container isn't running at 03:45** (a stack deployment at that time). → The volume items are refused that night and the log names it; the next night runs again.
- **One application's run holds the nightly loop** (up to 600 s waiting on its lock). → The applications run one after the other; each refusal goes to its own log.
- **A dump covers `POSTGRES_DB` only** (no roles, no other database), and `WITH (FORCE)` needs PostgreSQL 13 or later. → The README says so; Tickee and immo run PostgreSQL 18.
- **The stand-in tests take longer.** Two more stand-in tests of about 6 to 8 minutes. → They split across the two lanes; tmpfs keeps them independent of the workstation's disk.
- **0026 (the logs, `check_model`) and 0028 (`docs/migration.md`) change the same files.** → Whichever is delivered second merges `main` at its step 0; `--changed --all` covers the result.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test (stand-in) | `tests/0027-backup.stand-in.sh`: a new stamp holds `db.dump` (`pg_restore --list` reads it) and `files.files_data.tar` (lists `a`). A `pg_isready` loop during the backup gets 0 failures, and `faito.db`'s `StartedAt` is unchanged. `faito.files` was restarted (`StartedAt` changed) and runs. `faito_cache` is named as not backed up. Modes are 0750 and 0640 `root:faito`; Faito's account reads its backup and can't delete it |
| AC-02 | automated test (stand-in) | the same test: after rows and files change, `restore <stamp>` without `--yes` is refused and changes nothing. With `--yes`, the rows and files are the backup's (`b` gone), the three containers run, and a newer stamp holds the state before (`r3` in its dump, `b` in its tar). `restore` alone lists both stamps |
| AC-03 | automated test (stand-in) | `tests/0027-isolation.stand-in.sh`: A's backup and restore leave B's containers' `StartedAt` and B's rows, files and backups tree (`find -printf` plus `cksum`) unchanged. As A, `ls /var/backups/c4-apps/hururaa/` is refused. A's `restore` refuses B's stamp, `/var/backups/c4-apps/hururaa/<stamp>`, `../hururaa/<stamp>` and `..` |
| AC-04 | automated test (stand-in) | `tests/0027-backup.stand-in.sh`: `relabelled.yml` placed in `~/faito/faito/` but not deployed, then `refused.yml` refused by `up`. Each backup holds the running items. The checksum of `/var/lib/c4-apps/faito/` and of `.run.faito/` is unchanged |
| AC-05 | automated test (stand-in) | the same test: `label-rsync.yml` and `label-injection.yml` deployed. The backup is refused, naming `service files` and the value; no stamp and no `.partial` is written |
| AC-06 | automated test (stand-in) | `tests/0027-isolation.stand-in.sh`: the command of `/etc/cron.d/c4-apps-backup` (0644, 03:45) is run as root. Faito and Hurura'a each get a new stamp. Turu's log says it declares nothing; Tickee's says it has no container. A planted stamp 8 days old is removed and one 6 days old is kept |
| AC-07 | automated test (stand-in) | `tests/0027-backup.stand-in.sh`: `up` of `slow-up.yml` runs in the background, then a backup starts. It says `waiting for another c4-app command of faito`, ends after `up`, and its stamp is no earlier than `up`'s end |
| AC-08 | automated test (stand-in) | the same test: with the tmpfs at 4 GiB, the backup is refused naming the free space and the floor, the nightly log names it, the earlier stamps stay, and no `.partial` is left. `restore --yes` is refused and the containers still run. The 10 % branch can't be reached on a tmpfs (it needs more than 50 GiB): the verifier checks it by reading the code |
| AC-09 | automated test, plus a reread | `tests/0027-docs.sh`; a reread against RQ-08's list |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
