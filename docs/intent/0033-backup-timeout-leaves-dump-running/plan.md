# Plan: A demo host backup cut by its time limit may leave its dump running, a restore has no time limit, and four backup paths are untested

- Spec: [v1](spec.md)
- Status: approved
- Branch: 0033-backup-timeout-leaves-dump-running
- Approved: 2026-10-28, Jérôme Wacongne (engineer, and tech lead: the high risk agreed; the batch and the agent, product owner)
- Builds on: `main` at de2be13 (0027 delivered: `backup`, `restore` and `nightly` in `demo/c4-app`), merged into the branch at f3ba47e

## Starting point

- `demo/c4-app` (at `main` de2be13):
  - The limits are constants. `NIGHTLY_TIMEOUT=7200` (`:127`) bounds `timeout --kill-after=60 "$NIGHTLY_TIMEOUT" runuser -u <app> -- sudo -n /usr/local/sbin/c4-app backup` (`:144`); a 124 or 137 is logged `== exit <n>: stopped after 7200 s` (`:146-147`). `ITEM_TIMEOUT=1800` (`:508`). Nothing is read from a file, and the caller's environment is unset but `SUDO_USER` (`:89-95`).
  - `write_item` (`:652-666`) runs `timeout "$ITEM_TIMEOUT" "$@" < /dev/null | head -c "$room" > "$partial/$file"` in the foreground, with no `--kill-after`; a 124 is refused, `didn't end within` (`:664`). Its two commands: a dump, `docker exec <db> sh -c "$DUMP"` (`:767`; `DUMP` `:503`, `--lock-wait-timeout=120s`); a volume, `docker run "${THROWAWAY[@]}" … --entrypoint tar` (`:775-776`; `THROWAWAY` `:505-506`, `--rm`, no name, no label).
  - A restore's steps are unbounded and run in the foreground: each file read whole (`:857-864`, `docker exec -i <db> pg_restore -f /dev/null` and `docker run -i … tar -tf -`), each database recreated (`:908-910`, `RECREATE` `:810-813`, `psql`), its dump restored (`:911`, `RESTORE` `:814`), each volume emptied and refilled (`:917-921`). The restart waits 300 s per layer (`wait_running` `:702-717`, `start_again` `:720-753`). `altered=1` (`:906`) marks "data replaced".
  - The lock: `exec 9> /var/lib/c4-apps/.<app>.lock` then `flock` (`:190-194`); every child inherits fd 9. `leave` (`:202-214`), the EXIT trap, removes the `.partial` and starts the stopped containers with one unordered `docker start`; once `altered` is set, it leaves them stopped and names the safety backup. `trap 'exit 130' INT` and `trap 'exit 143' TERM` (`:216-217`) run only once the foreground command has ended.
  - The paths no test covers: a `volumes` service without a named volume is refused (`:610-611`); a shared volume is archived once, under the first `volumes` service, and a database's other volumes count as part of its dump (`:614-628`); every running mounter is stopped (`stop_mounters`, `:683-699`); the restart runs in `com.docker.compose.depends_on` layers (`:720-753`).
  - `stop_grace_period` and `stop_timeout` are allowed (`:311-312`), so a `docker stop` (`:698`, `:903`) may wait as long as the application says.
- `demo/vps-bootstrap.sh` writes `/etc/sudoers.d/c4-infra` and `/etc/cron.d/c4-apps-backup` (`:98-123`), and nothing for `c4-app`'s own settings. `docker top` runs the host's `ps` (procps, part of every Ubuntu install).
- Docs:
  - README "Backups" (`:803-914`) says "A dump or a volume's copy that hasn't ended within 1800 s is refused" (`:867-868`) and "Each night is stopped after 2 hours" (`:889-890`). It describes the restore (`:896-908`) with no limit. "Accounts" covers backup and restore at `:655-659`.
  - `docs/demo-setup.md`: step 8 runs the nightly by hand (`:198-202`); step 9.7 covers an application's backups (`:246-254`).
- Tests:
  - `tests/0027-backup.stand-in.sh` is the model: `as_faito`, `on_host`, `says`, `holds`, `started`, `runs`, `entries`, and the tmpfs at `/var/backups/c4-apps`. `tests/0027-isolation.stand-in.sh` runs two applications (`hururaa_state`). `tests/0027-backup-facts.stand-in.sh` is the model for facts: a bare stand-in running `compose.yml`'s `postgres:18.6`. `tests/fixtures/0027/data.yml` and `hururaa.yml` are reused here.
  - `stand_in_accounts` (`tests/lib/stand-in-host.sh:189-229`) deploys the stack, which installs `c4-app` from the working tree (`stand_in_send`, `:124-128`). A mutation check therefore runs from a throw-away worktree.
  - The stand-in's image (`tests/stand-in-host/Dockerfile`) is Ubuntu 24.04 with `docker.io` and `openssh-server`. `openssh-server` depends on `procps`, so `docker top` should work there; step 0 checks it.
  - `--changed --all` on this branch runs nearly every stand-in test, since they all cover `demo/`: 0002, 0003, 0006, 0007 ×2, 0009, 0011, 0012, 0013 ×2, 0016, 0024, 0025, 0026, 0027 ×2, and 0033's own.

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Claude proposes these for Jérôme Wacongne (engineer, and tech lead for the high risk) to approve with this plan. The ones marked **to confirm** are still open.

- **E1. The limits file (PA-03 B)** (**to confirm**: its path, format and owner, and what a bad file does).
  - Path and owner: `/etc/c4-app/limits`, owned `root:root`. It must be a regular file (not a symbolic link), writable by root only (no group or other write bit), in a directory that is root's too. Anything else is refused.
  - Format: lines `ITEM_TIMEOUT=<s>`, `RESTORE_TIMEOUT=<s>` and `NIGHTLY_TIMEOUT=<s>`, plus blank lines and `#` comments. Each value matches `^[1-9][0-9]*$` and is at most 86400 (a `0` would turn GNU `timeout` off). A key left out keeps its default. `c4-app` reads the file line by line as data and never sources it.
  - Who reads it: `backup`, `restore` and `nightly`, before they change anything. `up`, `pull`, `down` and `register` never read it.
  - A bad file refuses those three commands, naming the file and the line (`c4-app: /etc/c4-app/limits, line 2: 'ITEM_TIMEOUT=0': <KEY>=<seconds>, 1 to 86400`), with exit 1. `nightly` writes that refusal into each application's log.
  - When the file is absent, the defaults apply (E2). `vps-bootstrap.sh` doesn't write it: the defaults live in `c4-app` only, and the operator creates the file when a night needs more time (`docs/demo-setup.md`).
  - Rejected:
    - `/etc/default/c4-app`: by Debian's convention it is a shell file that gets sourced.
    - The defaults written by `vps-bootstrap.sh`: two places for one value, and a later default would never reach a host that has the file.
    - A bad file ignored with a warning: the operator meant another limit, and a night would run with one he didn't choose.
    - One line per application: PA-03 C, not decided.
- **E2. The values.**
  - Defaults: `ITEM_TIMEOUT=1800`, `RESTORE_TIMEOUT=3600` (PA-01 B) and `NIGHTLY_TIMEOUT=7200`.
  - Fixed in `c4-app`, not in the file:
    - the 60 s of RQ-01, RQ-03 and RQ-05;
    - within those, 40 s for `c4-app`'s own stops (`STOP_WAIT`), so that it has ended before a nightly KILL;
    - `--kill-after=5` on the docker CLI.
- **E3. One runner for every item and every restore step:** `bounded <limit> <what> <command>…`.
  - **How it runs.**
    - The command runs in the background as `timeout --kill-after=5 <limit> …`, in GNU timeout's own process group, with fd 9 closed (`9>&-`). No CLI then holds the application's lock, whatever ends `c4-app` (RQ-04).
    - Its stdin and stdout are explicit, as today; a backup item still goes through `head -c <room>`.
    - Its statuses come back as today (`PIPESTATUS`), through a root-only file in the run's temporary directory (`mktemp -d`, removed by `leave`).
  - **Waiting.** `c4-app` `wait`s for the command. Bash runs a trapped signal's handler as soon as the signal arrives during `wait`, not when the command ends (bash manual, "Signals"), so the nightly's TERM reaches `leave` at once.
  - **A cut** is a 124, or a 137 (the kill-after fired). It is handled by the item's stop (E4, E5), then today's refusal (`fail`, then `leave`).
  - **The item recorded.** While the command runs, `c4-app` records it (`current_*`: the timeout's pid, the container, the marker, the cidfile, what it is). `leave` stops a recorded item first (E6).
  - Rejected:
    - The item in the foreground, as today: a TERM waits for it to end.
    - `timeout --foreground`: the group would be `c4-app`'s, but the command's children aren't timed out.
    - A `sleep` watchdog with `wait -n`: more code for the same effect.
- **E4. A command run in a database's container** (a dump, reading a dump whole, recreating a database, restoring a dump) (**to confirm**).
  - **The marker.** The command runs as `PGAPPNAME=<marker> docker exec -e PGAPPNAME [-i] <container> …`. The marker is `c4-app.<app>.<16 random hex digits>`, a new one per item. It sits in the CLI's environment, not on its command line, so it reaches the exec'd processes' environment. It also becomes the `application_name` of every session they open: libpq reads `PGAPPNAME` before the programs' own `fallback_application_name`.
  - **The stop**, in this order:
    1. **Its sessions:** `pg_terminate_backend` of every session whose `application_name` is the marker. `psql` sends it in the same container, as its `POSTGRES_USER`, through the local socket, on its maintenance database (as `RECREATE` does).
    2. **Its processes:** root lists the host PIDs with `docker top <container> -eo pid` and keeps those whose `/proc/<pid>/environ` holds the exact entry `PGAPPNAME=<marker>` (NUL-separated). It reads that file again just before the kill, then runs `kill -KILL`.
    3. **Confirmation:** no such process and no such session remain (polled) within `STOP_WAIT`.
  - **KILL rather than TERM.** `pg_dump` and `pg_restore` answer a TERM by cancelling their own query. The sessions would then end anyway, so no test could guard their termination (removing it would pass every test). The item is discarded anyway, and a restore cut midway is already handled as "after data replaced" (0027).
  - Rejected:
    - `timeout` inside the container: not in every image, and it can't serve the nightly's cut, which comes before the item's limit.
    - `pkill` or `ps` in the container: the official image has no `procps`.
    - Sessions found by `application_name = 'pg_dump'`, or processes found by their name: both would reach the application's own (IV-01).
- **E5. A throwaway container** (copying a volume, reading an archive whole, refilling a volume).
  - It runs with `--cidfile <the run's temporary directory>/<n>.cid` and the label `c4-infra.c4-app=<app>`.
  - The stop: `docker rm -f <id>`, then confirmed gone (`docker inspect` fails) within `STOP_WAIT`. "No such container" (its `--rm` won the race) counts as a success.
  - The label lets the operator and the tests find a throwaway (`docker ps -a --filter label=c4-infra.c4-app`). `select_items` never sees one, since it carries no compose label.
  - Rejected:
    - `--init`: `tar` would then answer TERM, but `rm -f` is needed anyway for a paused or stuck container.
    - A name chosen by `c4-app`: container names have prefix rules, and a label says the same.
- **E6. A signal** (the nightly's TERM, an INT).
  - `leave` first ignores TERM and INT. Sudo may relay the nightly's TERM a second time, and an `exit` from a trap inside `leave` would cut the cleanup short.
  - It then stops the recorded item: it TERMs the item's timeout, which KILLs the CLI 5 s later, then runs E4 or E5.
  - Then it does what it does today: the `.partial` is removed, and the stopped containers are started with `docker start` (under `timeout 20`), or, once data has been replaced, left stopped with the safety backup named.
  - `stop_mounters`' `docker stop` and `cmd_restore`'s (`:903`) also run in the background and are `wait`ed for, so an application's `stop_grace_period` doesn't hold the trap back. `leave` lets such a stop finish within `STOP_WAIT`.
- **E7. Messages (PA-02 A)**: one line each, with exit 1.
  - A backup item: `c4-app: db.dump didn't end within 15 s: stopped (pg_dump in faito.db, 1 session of its database), no backup of faito kept`, or `c4-app: files.files_data.tar didn't end within 15 s: stopped (its copy's container), no backup of faito kept`.
  - A restore step: `c4-app: restore of backup <stamp>: <step> didn't end within <n> s: stopped (<what>)`, then 0027's line for a restore that failed before or after replacing data.
    - The steps are named `reading db.dump whole`, `reading files.files_data.tar whole`, `recreating faito.db's database`, `restoring db.dump into faito.db` and `refilling faito_files_data`.
  - A signal: `c4-app: stopped by a signal during <file or step>: stopped (<what>)`, then the refusal. The nightly's own line reads `== exit 124: stopped after <NIGHTLY_TIMEOUT> s`, with the value from the file.
  - A stop not confirmed:
    - `c4-app: pg_dump (pid <n>) in faito.db didn't stop within 60 s`;
    - `c4-app: a session of faito.db's database (<marker>) didn't stop within 60 s`;
    - `c4-app: the copy's container <id> didn't stop within 60 s`.
- **E8. No sweep by `nightly` after a KILL.** `c4-app`'s stops are bounded well under the KILL's 60 s, and it names whatever it can't confirm (RQ-05). Rejected: a root-only file recording the current item, which `nightly` would read to stop it.
- **E9. The tests** (**to confirm**: the devices and the fixtures).
  - **Three stand-in tests.**
    - `0033-dump-limits` (Faito and Hurura'a): AC-01, AC-04, AC-06, a cut while restoring a dump, and the limits file's refusals.
    - `0033-copy-limits` (Faito): AC-02, AC-03, AC-05.
    - `0033-backup-paths` (Faito): AC-07, AC-08, AC-09.
    - The first two are step 1's failing tests, frozen. The third passes on today's code, since its paths exist, and is frozen too.
    - Rejected: a single file (one long test holding a lane), and these cases added to 0027's tests (the reproduction must be committed alone).
  - **The limits** are set in `/etc/c4-app/limits`, as PA-03 decides: `ITEM_TIMEOUT=15` and `RESTORE_TIMEOUT=15`; for AC-05, `NIGHTLY_TIMEOUT=30` with `ITEM_TIMEOUT=600`.
  - **AC-01's device.** A session of Faito's own: `psql`, exec'd with `PGAPPNAME=pg_dump` (the name a dump's session gets by default), holding `ACCESS EXCLUSIVE` on `item` (`begin; lock table item in access exclusive mode; select pg_sleep(600)`). The dump waits for its `ACCESS SHARE` lock: its `--lock-wait-timeout=120s` is longer than the 15 s limit. That session and its `psql` must survive the stop (IV-01).
  - **AC-06's device.** A `psql` of Hurura'a's own, with `PGAPPNAME=pg_dump`, running `pg_sleep`.
  - **AC-02 and AC-05's device.** 1 GiB in `faito.files`' volume (step 0 sets the size). A watcher in the stand-in pauses the copy's container as soon as it starts (`docker events --filter event=start --filter image=<keycloak-db's image id>`, then `docker pause`). The test checks that the pause landed: a missed pause is its own KO, never a pass.
  - **AC-03, AC-04 and the dump restore's device.** A copy of a backup whose file is a FIFO, written by the test in the stand-in:
    - AC-04: nothing is ever written to `db.dump`, so reading it whole stalls.
    - AC-03: `files.files_data.tar` gets the whole file at its first opening, then all but its last bytes at the second, so the refill stalls.
    - The dump restore: `db.dump`, the same way.
  - **The bound and the cleanup.**
    - Each `c4-app` command that a cut should end runs under the test's own bound (`timeout` in the stand-in, the limit plus 90 s).
    - A helper then cleans up: the processes holding `.faito.lock`, the throwaways (found by the image), the FIFOs' writers, and Faito's containers, started.
    - On the code before the fix, the tests then fail instead of hanging, and the next case starts from a known state.
    - A case's checks come before its cleanup.
  - **The timing.** "Ends within the limit plus 60 s" is measured with `date +%s` in the stand-in, around the command.
  - **Fixtures.** `tests/fixtures/0027/data.yml` and `hururaa.yml` are reused; `tests/fixtures/0033/` adds `no-volume.yml`, `shared-volume.yml` and `layers.yml`. The FIFO writers and the watcher are written inline, so no new script needs a covering test.

## Files

| File | Change | For |
| --- | --- | --- |
| `demo/c4-app` | modified: the limits file (E1, E2); `bounded` (E3) for each item and each restore step; the stop of a database command (E4) and of a throwaway (E5); `leave` on a signal (E6); `stop_mounters`' and the restore's `docker stop`, interruptible; messages (E7); `nightly`'s limit and log line from the file; header and `usage` (the limits, the file) | RQ-01 to RQ-05, RQ-07, IV-01, IV-04, IV-05; AC-01 to AC-06, AC-10 |
| `README.md` | modified: "Backups" (each limit and its default; the file and who changes it; what a cut stops and what it says; a restore's limit per step and its two outcomes; a stop not confirmed); "Accounts" (one line on the limits) | RQ-07, AC-10 |
| `docs/demo-setup.md` | modified: step 8 (the limits, and how to change one: the file, from `ubuntu`); step 9.7 (the limits an application's backups run under) | RQ-07, AC-10 |
| `tests/0033-limits-facts.stand-in.sh` | new: step 0's facts, on a bare stand-in; `# covers: compose.yml tests/stand-in-host/` | step 0 |
| `tests/0033-dump-limits.stand-in.sh` | new, frozen after step 1: accounts faito and hururaa; `# covers: demo/ registry.sh networks.sh tests/fixtures/0027/ tests/fixtures/0033/ tests/stand-in-host/` | AC-01, AC-04, AC-06; RQ-02 (restoring a dump), IV-05 |
| `tests/0033-copy-limits.stand-in.sh` | new, frozen after step 1: account faito; the same `covers` | AC-02, AC-03, AC-05 |
| `tests/0033-backup-paths.stand-in.sh` | new, frozen after step 2: account faito; the same `covers` | AC-07, AC-08, AC-09 |
| `tests/fixtures/0033/` | new: `no-volume.yml` (data.yml plus `bare`, labelled `volumes`, with a `tmpfs` and no named volume); `shared-volume.yml` (`db`, labelled `postgres`, and `files`, labelled `volumes`, both mount `shared`); `layers.yml` (data.yml plus `l1`, `l2`, `l3`, each healthy 5 s after its start, `l2` `service_healthy` on `l1`, `l3` on `l2`) | AC-07, AC-08, AC-09 |
| `tests/0033-docs.sh` | new: README, `c4-app`'s usage (read from the file) and `docs/demo-setup.md` name `/etc/c4-app/limits`, `ITEM_TIMEOUT`, `RESTORE_TIMEOUT`, `NIGHTLY_TIMEOUT`, `1800`, `3600`, `7200`; `# covers: README.md demo/c4-app docs/demo-setup.md` | AC-10 |
| `tests/stand-in-host/Dockerfile` | only if step 0 finds no `ps` in the stand-in: `procps` (a deviation) | AC-01 |
| `docs/intent/0033-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

**Batch** (the product owner, 2026-10-28): 0032, 0034 and 0033 are verified together. 0032 is committed on `main` itself, which stays local until the batch's push; 0034 and 0033 are merged in that order into `batch-0032-0034-0033`, from `main`. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the three in the batch's order, then one push of `main`, validated by the product owner.

**Implemented by an agent** (the product owner, 2026-10-28), in a worktree of this branch (`.env` and `certs/` copied from the main tree, removed with the worktree), its stand-in tests on `c4-infra-stand-in` (`STAND_IN_NAME=c4-infra-stand-in STAND_IN_VOLUME=c4-infra-stand-in-docker`). It never starts or changes the dev stack from the worktree and never runs `tests/run.sh`. A deviation that changes the scope, a risk or a proof stops it, reported, until the engineer decides.

**Bootstrap mode** (the intent's `Mode`): no PR, one `sdlc-verify` round, pushes without confirmation. The work stays on the intent's own branch, since 0032 is in progress on `main`. Every test runs with `TMPDIR=~/.cache/c4-infra-tests` (Docker Desktop). If an agent implements the plan in a worktree, its stand-in tests use one named stand-in host (`STAND_IN_NAME`, `STAND_IN_VOLUME`), it never touches the dev stack from the worktree, and a deviation that changes the scope, a risk or a proof stops it until the engineer decides.

0. **Setup and facts.** — skill: none.
   - `git switch 0033-backup-timeout-leaves-dump-running && git pull --ff-only && git merge main`. Check: `git status --short` is empty; `bash -n demo/c4-app`.
   - Write `tests/0033-limits-facts.stand-in.sh`: a bare stand-in, `compose.yml`'s `postgres:18.6`, as 0027's facts test. Check: it passes, and each fact is recorded under *Deviations* with its lines. A fact that differs is a deviation before the step it concerns (the change it brings is named below). Commit `test(0033): the facts the time limits are built on`.
   - **(a) The bug's mechanism.** A `docker exec … sh -c "$DUMP"` waits for a lock that a session holds. Its CLI is ended by `timeout`, once with TERM and once with KILL. After the CLI's end, `docker top` still lists `pg_dump`, and `pg_stat_activity` still shows its session waiting (`wait_event_type` `Lock`).
     - If `pg_dump` and its session end with the CLI, the spec's premise for a dump is wrong: tell the product owner (spec v2 on RQ-01's wording). E4 stays anyway, for the nightly's TERM.
   - **(b) The marker.** `ps` is in the stand-in, and `docker top <c> -eo pid` gives host PIDs whose `/proc/<pid>/environ` root reads. `PGAPPNAME`, given by `-e PGAPPNAME` from the CLI's environment, is in that environment. It is also the session's `application_name`, for `pg_dump`, `pg_restore` and `psql` alike.
     - If `ps` is missing: `procps` goes into the stand-in's image.
     - If a program overrides the name: E4 finds its sessions another way before step 4 (for example `PGOPTIONS='-c application_name=…'`).
   - **(c) The stop.**
     - `pg_terminate_backend` of the sessions bearing that `application_name`, run as `POSTGRES_USER` through the local socket, ends the waiting session within 2 s.
     - `kill -KILL` of the marked PIDs ends them within 2 s, and their CLI exits.
     - Without the termination, a KILLed `pg_dump`'s session keeps waiting until its lock wait ends. That is why E4 terminates the sessions.
     - A TERMed `pg_dump`'s session ends by itself, through its cancel. That is why E4 sends KILL.
     - A session named `pg_dump` and a process exec'd without the marker are untouched.
     - If the KILLed dump's session ends by itself, AC-01 can't guard the termination: its mutation check moves to the dump restore's case, or the verifier reads that path.
   - **(d) The throwaway.**
     - `tar` as PID 1 ignores a TERM proxied by the CLI: the CLI runs on, and `timeout` without `--kill-after` waits for it.
     - With `--kill-after=5`, `timeout` returns 137 and the container runs on.
     - `docker rm -f` of the cidfile's id ends and removes the container, running or paused, within 5 s.
     - If `rm -f` refuses a paused container, E5 runs `docker unpause` first.
   - **(e) The signals.** A stub stands for `c4-app` at `/usr/local/sbin/c4-app-stub`, with `vps-bootstrap.sh`'s sudo rule pointed at it (as 0027's fact f). It holds a lock on fd 9, runs an item (`timeout --kill-after=5 600 sleep 600`) in the background with fd 9 closed, and `wait`s; its TERM trap records the time and stops the item.
     - Run as the nightly runs `c4-app` (`timeout --kill-after=60 20 runuser -u fact-app -- sudo -n …`): the trap runs within 2 s of the limit, the item, in its own group, is stopped, and once the stub ends, `flock -n` on its lock succeeds. The number of TERMs the stub gets (sudo's relay) is printed.
     - The same stub with its item in the foreground: no trap runs before the KILL at 80 s, and the item is still alive afterwards, holding the lock (the spec's reading).
     - If the trap doesn't run during `wait` (sudo without a terminal, the process groups), the signal path of E3 and E6 changes before step 7: for instance, `nightly` passes the deadline through a root-only file.
   - **(f) The test devices.**
     - A FIFO in place of a backup's file: whole at its first opening, stalled at its second, opened by a background job's redirection, then read through `docker exec -i` and `docker run -i`.
     - The pause at start lands before a copy of N GiB ends. The unpaused duration and the bytes copied before the pause are printed, and N is chosen so that the window is at least 5 times the pause's latency.
     - If the pause can't land reliably: send SIGSTOP to the copy's `docker run` CLI instead (its stream then fills up), measured the same way. Failing that, AC-02's and AC-05's "given" goes back to the spec (v2).
1. **Failing tests**: `tests/0033-dump-limits.stand-in.sh` and `tests/0033-copy-limits.stand-in.sh`. — skill: none.
   - Check: each exits 1 on the code as it is. The expected KOs are the limits not honoured:
     - AC-01 ends after about 120 s, on `pg_dump`'s own lock timeout (`db.dump failed`), not `didn't end within 15 s`;
     - AC-02, AC-03, AC-04 and AC-05 reach the test's bound, and leave the copy's container, `faito.files` stopped and the lock held;
     - the limits file's refusals are missing.
   - The KO lines go under *Deviations*. Commit `test(0033): a backup or a restore cut by its time limit leaves what it started running` alone, then freeze both paths in `.claude/frozen-tests.local`.
2. **The three paths 0027's review round only read**: `tests/0033-backup-paths.stand-in.sh` and `tests/fixtures/0033/`. — skill: none.
   - Check: `every check passed` on today's code.
   - Mutation checks now, each in a throw-away worktree:
     - `:610-611` removed: KO (AC-07);
     - `stop_mounters` limited to the declaring service's containers: KO (AC-08, `faito.db`'s `StartedAt` unchanged);
     - `start_again` in one layer: KO (AC-09).
   - Commit `test(0033): the three backup paths no test covered`, then freeze it. This step changes no code: it could ship alone, ahead of the rest.
3. **The limits file** (E1, E2): read by `backup`, `restore` and `nightly`; `RESTORE_TIMEOUT` defined; `nightly`'s limit and log line from it. — skill: none.
   - Check: `bash -n demo/c4-app`.
   - Check: `bash tests/0033-dump-limits.stand-in.sh` exits 1, now for the bug's own reasons. After the refusal at about 15 s, `docker top` lists `pg_dump` in `faito.db` and `pg_stat_activity` holds its session: that is the reproduction for the right reason, recorded under *Deviations*. The limits file's checks pass.
   - Check: `bash tests/0027-backup.stand-in.sh` passes (the defaults).
   - Commit `fix(0033): the time limits from /etc/c4-app/limits, their defaults when it is absent`.
4. **The runner and a database command's stop** (E3, E4): the backup's dumps go through the runner, and `leave` stops a recorded item (E6's first part). — skill: none.
   - Check: `bash tests/0033-dump-limits.stand-in.sh`: AC-01's and AC-06's checks pass (AC-04 and the dump restore's case wait for step 6).
   - Commit `fix(0033): a dump cut by its limit is stopped in its container, its session ended`.
5. **The throwaway's stop** (E5): the volume copies go through the runner. — skill: none.
   - Check: `bash tests/0033-copy-limits.stand-in.sh`: AC-02's checks pass.
   - Commit `fix(0033): …`.
6. **The restore's steps** (RQ-02): reading whole, recreating, restoring and refilling go through the runner at `RESTORE_TIMEOUT`, with the safety backup's items at `ITEM_TIMEOUT`; plus their messages. — skill: none.
   - Check: `bash tests/0033-dump-limits.stand-in.sh` (`every check passed`), then `bash tests/0033-copy-limits.stand-in.sh` (AC-03's checks), then `bash tests/0027-backup.stand-in.sh`.
   - Commit `fix(0033): each step of a restore bounded`.
7. **The nightly's cut** (E6): `leave` ignores further signals and runs within its budget; `docker stop` becomes interruptible. — skill: none.
   - Check: `bash tests/0033-copy-limits.stand-in.sh && bash tests/0027-isolation.stand-in.sh` (`every check passed`).
   - Commit `fix(0033): …`.
8. **Docs**: `README.md`, the header and `usage` of `demo/c4-app`, `docs/demo-setup.md`; `tests/0033-docs.sh`. — skill: none.
   - Check: `bash tests/0033-docs.sh && bash tests/0027-docs.sh`, plus a reread against RQ-07's list.
   - Commit `docs(0033): …`.
9. **Verification.** — skill: sdlc-verify.
   - Run `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`. It is nearly a full run (Starting point) and should end `verification passed`.
   - Mutation checks, in throw-away worktrees, split over the two stand-in hosts:
     - `main`'s `demo/c4-app`: `0033-dump-limits` and `0033-copy-limits` exit 1 (step 1);
     - step 3's `demo/c4-app` (the limits read, nothing stopped): `0033-dump-limits` exits 1 on the `pg_dump` and the session it leaves;
     - E4's session termination removed: KO (AC-01, the KILLed dump's session still waiting);
     - E4's process kill removed: KO (AC-04, `pg_restore` still in `faito.db`);
     - E4's marker match replaced by the program's name: KO (AC-01, Faito's own session and `psql` gone: IV-01);
     - E5's `docker rm -f` removed: `0033-copy-limits` KO (AC-02);
     - `leave`'s stop of the recorded item removed: KO (AC-05);
     - the limits file's owner and mode check removed: `0033-dump-limits` KO (IV-05).
   - Then `/sdlc-verify 0033`: bootstrap mode, so one round; high risk, so the security pass too. Check: `verification passed`.
   - Its evidence block goes into `## Verification`; commit `plan: verification of 0033`. Then `/sdlc-ship 0033`.
10. **After deployment.** — skill: sdlc-ship.
    - The push deploys the demo host, which installs the new `c4-app` (`c4-app installed` in the deploy-demo run's log).
    - `/etc/c4-app/limits` is absent there, so the defaults apply. No application runs on the host yet, so there is no backup to observe.
    - Check: recorded under `### After deployment`.

## Risks

- **Root kills processes in an application's container and ends sessions in its database (IV-01, high risk).** → It acts only on the PIDs `docker top` lists for the container `c4-app` selected, and only when their environment holds this item's random marker, read again just before the kill. It ends only the sessions that carry that marker. AC-06 checks the other application; AC-01 checks the application's own session and `psql`, named like a dump; a mutation check replaces the marker with the name. A PID reused between that last read and the kill is a window of microseconds, accepted.
- **Root's kill can crash the application's database (step 0, fact c).** A process orphaned into the container's first process (`postgres`, PID 1 in the official image) and ended by a signal is taken by the server for a crash: every session ends, the application's own too. → Every command `c4-app` runs in a database's container is the exec'd process itself (`DUMP` execs `pg_dump`, as `RECREATE` and `RESTORE` exec theirs), and E4 never kills a marked process whose parent is the container's first process: its session's termination ends it (it exits 1, which the server only logs), or it is named as not stopped (RQ-05). AC-01 and AC-06 would see a crash (the application's own session, Hurura'a's).
- **The marker is visible to the application** (`pg_stat_activity`, and the exec'd process's environment in its container). → An application that copies it into a session of its own before a cut gets that session ended: its own doing, never another application's. Every item has a new marker.
- **`pg_terminate_backend` can fail**: no free connection (`max_connections`), or an image whose `POSTGRES_USER` may not signal the session. → The stop is then not confirmed: it is named, with exit 1 (RQ-05). The README says that `c4-app` relies on the official image's `psql` and its local socket.
- **A cut leaves no chance to cancel cleanly** (KILL). → The session's termination takes the cancel's place. A restore cut once data has been replaced is already "after" (0027): the containers stay stopped and the safety backup is named.
- **Commands outside the runner delay the trap.** `docker stop` waits for the application's own `stop_grace_period`. → It runs in the background and is `wait`ed for (E6). `leave` lets it end within its budget, then starts the containers; past that budget, it names them. On a cut, the containers start at once, without `depends_on`'s order, as 0027's trap does today: `start_again`'s waits (300 s per layer) can't fit in 60 s.
- **The test devices race**: the pause at start, the FIFO. → Step 0's fact (f) measures them first. The test checks that its device worked (the container was paused, the FIFO was opened), so a miss shows as a KO, never as a pass. If they prove unreliable, that is a deviation, with SIGSTOP as the fallback and a spec v2 as the last resort.
- **A bad limits file blocks every backup**, the nightly's included. → It is refused, naming the file and the line, in each application's log. `up`, `pull`, `down` and `register` don't read it. A `0` (which would turn `timeout` off) and anything over 86400 are refused.
- **`timeout` returns 137, not 124, when its kill-after fires.** → Both count as a cut, as `nightly` already does.
- **Bash gives a background command `/dev/null` as stdin.** → Each item's stdin stays explicit, as today.
- **The time taken.** Three stand-in tests of about 6 to 10 minutes each, and the `--changed --all` run covering `demo/` (nearly every stand-in test). → They split across two lanes; the mutation checks run on both stand-in hosts.
- **0027's paths change** (`write_item`, `cmd_restore`, `leave`). → 0027's tests run in step 9, its AC-08 among them (the floor: IV-02).
- **0032 is in progress on `main`** (`docs/migration.md`). → `main` is merged at step 0, and again before step 9 if it has moved.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test (stand-in) | `tests/0033-dump-limits.stand-in.sh`, with `ITEM_TIMEOUT=15` and Faito's own `psql` (named `pg_dump`) holding `ACCESS EXCLUSIVE` on `item`. `sudo c4-app backup` exits 1 within 75 s, saying `db.dump didn't end within 15 s: stopped (`. `docker top faito.db` lists no `pg_dump`; on `fixture-db`, `pg_stat_activity` holds only Faito's session (its pid), and Faito's `psql` still runs. No new stamp and no `.partial`. Once Faito's session has ended, the next backup prints no `waiting for another` line and exits 0. It fails on `main`'s code and on step 3's (mutation checks) |
| AC-02 | automated test (stand-in) | `tests/0033-copy-limits.stand-in.sh`: the copy's container is paused at its start (checked). The backup exits 1 within 75 s, naming `files.files_data.tar` and 15 s. No container carries the label `c4-infra.c4-app`, and the paused one is gone. `faito.files` runs; the entries are as before; the next backup doesn't wait and exits 0 |
| AC-03 | automated test (stand-in) | the same test: a copy of a backup whose `files.files_data.tar` stalls at its second opening. `restore <it> --yes` exits 1 within 75 s, naming `refilling faito_files_data` and 15 s. No throwaway is left; `faito.files` and `faito.other` are stopped, `faito.db` runs. The safety stamp is named, and restoring it, then `sudo c4-app up`, bring back the rows, the files and the three running containers |
| AC-04 | automated test (stand-in) | `tests/0033-dump-limits.stand-in.sh`: a copy of a backup whose `db.dump` is a FIFO nobody writes. `restore <it> --yes` exits 1 within 75 s, naming `reading db.dump whole` and 15 s. `faito.db` runs no `pg_restore`. The rows, the files, the backups' entries (no safety backup) and the `StartedAt` of `faito.files` and `faito.other` are unchanged |
| AC-05 | automated test (stand-in) | `tests/0033-copy-limits.stand-in.sh`, with `NIGHTLY_TIMEOUT=30`, `ITEM_TIMEOUT=600` and the copy paused: root runs `c4-app nightly`, and it ends within 90 s. Faito's `backup.log` holds the cut's line, then `== exit 124: stopped after 30 s`. Faito's containers run; no throwaway and no `.partial` are left; the next `sudo c4-app backup` prints no `waiting for another` line |
| AC-06 | automated test (stand-in) | `tests/0033-dump-limits.stand-in.sh`: across AC-01's cut, the `StartedAt` of Hurura'a's containers and its session (pid, named `pg_dump`) are unchanged |
| AC-07 | automated test (stand-in) | `tests/0033-backup-paths.stand-in.sh`: with `no-volume.yml` deployed, the backup is refused, naming `service bare` and `mounts no named volume of faito`. The entries and every container's `StartedAt` are unchanged. `restore <an earlier stamp> --yes` is refused the same way, and the rows, files, entries and `StartedAt` are unchanged. Mutation check at step 2 |
| AC-08 | automated test (stand-in) | the same test, with `shared-volume.yml`: the stamp holds exactly `db.dump files.files_data.tar files.shared.tar`. The `StartedAt` of `faito.db` and of `faito.files` changed, and both run. After the rows and files change, `restore --yes` brings back the rows and both volumes' files, with every container running. Mutation check at step 2 |
| AC-09 | automated test (stand-in) | the same test, with `layers.yml`: after `restore --yes`, `l2` started at least 4 s after `l1`, and `l3` at least 4 s after `l2` (each healthy 5 s after its start). All of them run, each one restarted (`StartedAt` changed). Mutation check at step 2 |
| AC-10 | automated test, plus a reread | `tests/0033-docs.sh`; a reread of README "Backups", the usage and `docs/demo-setup.md` against RQ-07: each limit, what a cut stops and says, who may change a limit |
| The bug reproduced | mutation checks | step 1's runs (`main`'s code); step 3's code (`pg_dump` and its session left); step 9's list |
| IV-02, IV-03 | automated tests (stand-in) | `tests/0027-backup.stand-in.sh` (its AC-08, the floor) and AC-03 above (the safety backup named and restored), in step 9's run |
| IV-05 | automated test (stand-in) | `tests/0033-dump-limits.stand-in.sh`: a group-writable file, `ITEM_TIMEOUT=0` and `ITEM_TIMEOUT=$(touch /tmp/limits-ran)` each refuse the backup, naming the file. Nothing is written, and `/tmp/limits-ran` doesn't exist |
| RQ-05, a stop not confirmed | read by the verifier | no device makes `docker rm -f`, `kill -KILL` or `pg_terminate_backend` fail in the stand-in: the verifier reads that path of the code and its message |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — Step 0's facts, measured by `tests/0033-limits-facts.stand-in.sh` on `c4-infra-stand-in` (Docker 29.1.3, sudo 1.9.15p5, bash 5.2.21, runuser from util-linux 2.39.3; `postgres:18.6`, read from `compose.yml`): `STAND_IN_NAME=c4-infra-stand-in STAND_IN_VOLUME=c4-infra-stand-in-docker bash tests/0033-limits-facts.stand-in.sh` ends `every check passed` (158 s). Its lines are quoted below. Two earlier runs failed on the test's own errors (`docker top -eo comm`, refused without a PID column; `docker events --format '{{.ID}}'`, gone from Docker 29, then `--until` without `--since`, which replays past events); they showed the two differences of (c) and (e), then reproduced by hand on the same stand-in.
  - (a) As assumed: `ok - (a) timeout -s TERM 5 ends the dump's docker exec CLI: 124`, `ok - (a) once its CLI is ended, docker top facts-db still lists pg_dump`, `ok - (a) and its session still waits for the lock (named pg_dump, wait_event_type Lock)`; the same with KILL (`137`). The spec's premise holds.
  - (b) As assumed: `ok - (b) ps is in the stand-in`, `ok - (b) docker top facts-db -eo pid gives host PIDs whose environ root reads`; `PGAPPNAME`, given by `docker exec -e PGAPPNAME`, is in the exec'd process's environment and is the session's `application_name` for `pg_dump`, `pg_restore` and `psql` (`ok - (b) … its session's application_name is the marker`, three times). The official image has procps and `timeout` after all (`command -v ps timeout pkill` in this workstation's `postgres:18.6`), unlike the spec's reading: no impact, E4 runs the host's `ps` (`docker top`); the stand-in's image is unchanged.
  - (c) As assumed for a `pg_dump` that the container's shell execs (`sh -c 'exec pg_dump …'`, its parent outside the container): `ok - (c) kill -KILL of the PID marked … (pg_dump:other): none left within 2 s`, `ok - (c) and its docker exec CLI exits within 2 s`, `ok - (c) 3 s later, the KILLed pg_dump's session still waits for the lock` (AC-01 can guard the termination), `ok - (c) pg_terminate_backend of the sessions bearing … ends it within 2 s`, `ok - (c) kill -TERM of its marked PID: its session ends by itself within 2 s (pg_dump's cancel)`, `ok - (c) the holder and pg_dump's namesake keep their sessions`, `ok - (c) and their psql processes (818 883)`.
    - **Differs, in the first risk's own area.** With `DUMP` as it is (`sh -c 'pg_dump …'`, not exec'd), two processes bear the marker, `sh` and `pg_dump` (first run: `… PGAPPNAME=…: sh pg_dump`). KILLed in `docker top`'s order, `sh` goes first: `pg_dump` is reparented to the container's first process, `postgres` (PID 1 in the official image), which takes its death by a signal for a crash of its own: every session ends, the application's own too, and the server recovers. `ok - (c) KILLed, that orphan ends every session of the server within 5 s, the holder's too`; the server's log: `untracked child process (PID 417) was terminated by signal 9: Killed|terminating any other active server processes|all server processes terminated; reinitializing`. Ended through its session instead, such an orphan exits 1, which the server only logs: `ok - (c) and the holder keeps its session; the server logged the orphan's end: untracked child process (PID 382) exited with exit code 1`. (Not measured: an orphaned `psql` exits 2 on a lost connection, which the server's rule, any end but an exit 0 or 1 is a crash, would take for one.)
    - → Proposed, for the engineer: every command `c4-app` runs in a database's container is the exec'd process itself (`DUMP` gets `exec`, as `RECREATE` and `RESTORE` have it), and E4's kill skips a marked process whose parent is the container's first process (`docker inspect -f '{{.State.Pid}}'`): its session's termination ends it, or it is named as not stopped (RQ-05). The first risk gains that line. AC-01 (Faito's own session and `psql`) and AC-06 (Hurura'a's) already catch a crash: the tests and the proofs are unchanged.
  - (d) As assumed: `ok - (d) timeout 5 around a throwaway's tar (PID 1), 12 s later: timeout waits, the container runs`; `ok - (d) paused, timeout --kill-after=5 5 around it, 12 s later: ended 137, the container still paused`; `ok - (d) docker rm -f of its cidfile's id: gone within 5 s`, and of the paused one too: E5 needs no `docker unpause`. Not assumed: a running throwaway that reads its stdin ends once its CLI is KILLed (the daemon closes its stdin, `--rm` removes it: `# (d) running, its CLI KILLed: ended 137 error: no such object: …`); a paused one stays. → E5 unchanged.
  - (e) The trap runs during `wait`, as assumed: `ok - (e) the item in the background: the stub's trap runs within 2 s of the limit (exit, trap, end: 124 20 22)`, `ok - (e) its item (sleep, pid 3764) is stopped`, `ok - (e) once the stub has ended, flock -n takes its lock`. The stub got one TERM in this run, two in the second (`term 1793221166,term 1793221166,end 1793221168`): E6's ignoring of further signals is needed.
    - **Differs.** `runuser` answers the nightly's TERM by relaying it, then KILLs its child, `sudo`, 2 s later (`runuser and sudo said: Session terminated, killing shell... ...killed.`). The nightly's `timeout` returns 124 about 2 s after the limit (`end: 22`), not 137 after 60 s more: that KILL never comes, and `c4-app`, orphaned, runs on. With the item in the foreground: `ok - (e) the item in the foreground: no trap runs before the nightly's timeout returns (exit, trap, end: 124 none 22)`, `the stub, afterwards: still runs`, `ok - (e) its item (sleep, pid 3836) is still alive`, `ok - (e) and holds the lock: flock -n fails`: the spec's reading holds, by another path.
    - → Proposed, for the engineer: `c4-app`'s trap does E6's work as planned, and nothing of the nightly cuts it; after a cut, `nightly` waits (60 s at most) for the application's lock before its line `== exit 124: stopped after <n> s`, so that `c4-app`'s own lines come first in the log (AC-05), and says in the log when `c4-app` still runs then. E8 stands (no sweep). The other way, not measured: `setpriv` in place of `runuser`, so that the 60 s KILL comes; whether it reaches `c4-app` then depends on sudo's process groups.
  - (f) As assumed: `ok - (f) a FIFO served for db.dump, read by docker exec -i facts-db pg_restore -f /dev/null: whole, then stalled`, `ok - (f) a FIFO served for it, read by a throwaway's tar -tf - (docker run -i): whole, then stalled (first 0 second 137)`. The pause at start lands and holds: `# (f) paused at its start: 292 48277504 48277504 paused` (292 ms after `docker run`, 48 MB copied, none afterwards), against `# (f) the unpaused copy: 2147491840 2440` (2.4 s for 2 GiB, 8 times the latency; by hand, 1 GiB took 1.4 to 1.7 s, only 5 times). → N = 2 GiB; the watcher writes `docker events --filter image=<id> --format '{{.Actor.ID}}'` into a file and polls it. AC-02's and AC-05's "given" holds: no spec v2.
- 2026-10-28 — Stopped after step 0, as the plan's rule says: fact (c) changes the first risk's mitigation (root's kill can end every session of the application's database), fact (e) the nightly's path to RQ-03 (no KILL reaches `c4-app`). The engineer decides on both proposals before step 1.
- 2026-10-28 — The engineer and product owner's decisions on step 0 (Jérôme Wacongne): (1) fact (c), as proposed: `DUMP` execs `pg_dump`, and E4 never kills a marked process whose parent is the container's first process; that one is stopped by its session's termination, or named as not stopped (RQ-05); the line is added to *Risks*. (2) Fact (e), as proposed: after a cut, `nightly` waits for the application's lock (60 s at most) before writing `== exit 124: stopped after <n> s`, so that `c4-app`'s own lines come first in the log (AC-05). (3) In 0033 too, approved by the product owner: an item refused because it reached the room above the floor (its CLI ended by SIGPIPE) has what it started stopped the same way as a cut (the same harm: a dump running on and holding its locks after the refusal); the floor's test gains a check that the item's `pg_dump` or throwaway container is gone after that refusal. (4) A stop not confirmed names the real wait, `STOP_WAIT` (40 s), not the 60 s of E7's examples.
- 2026-10-28 — Step 1, on the code before the fix (`main`'s `c4-app`, merged into the branch at 6905d23), on `c4-infra-stand-in`: `tests/0033-dump-limits.stand-in.sh` ends `18 check(s) failed`, `tests/0033-copy-limits.stand-in.sh` `21 check(s) failed`, every KO a limit not honoured.
  - The limits file isn't read: `KO - a group-writable /etc/c4-app/limits (0664): the backup refused, naming it, nothing written` (`exited 0`, a new stamp), the same for `ITEM_TIMEOUT=0` and `ITEM_TIMEOUT=$(touch /tmp/limits-ran)` (`ok - and /tmp/limits-ran doesn't exist`: it was never sourced).
  - AC-01: `KO - sudo c4-app backup exits 1 within 75 s (105 s)` (`exit 137 after 105 s`: the test's bound, `pg_dump`'s own lock timeout being 120 s), `KO - faito.db runs no pg_dump` (`actual: 12249`), `KO - fixture-db holds Faito's own session only (191)` (`actual: 191 227`), `KO - no stamp, no .partial` (`….partial`), `KO - nothing holds Faito's lock` (`held by: c4-app timeout head docker`); AC-06's `ok`: nothing of Hurura'a's moved.
  - AC-04: `KO - its restore exits 1 within 75 s (105 s)`, `KO - faito.db runs no pg_restore` (`actual: 18075`), `KO - nothing holds Faito's lock` (`held by: c4-app docker`), while `ok - nothing changed: the rows, the files, the backups (no safety backup), …`. The dump's restore: the same three KOs (`actual: 23821`), the safety backup taken (`c4-app: backup 20261028-212330 of faito`) but never named.
  - AC-03: `KO - its restore exits 1 within 75 s (105 s)`, `KO - no throwaway container is left` (`actual: 22ebfb5c…`), `KO - nothing holds Faito's lock` (`held by: c4-app docker`). AC-02: the pause landed (`ok - the copy's container was paused at its start (the device worked: fed4f317…)`), then `KO - the backup exits 1 within 75 s (106 s)`, `KO - the paused one is gone`, `KO - faito.files runs again` (`actual: faito.files false`), `KO - nothing holds Faito's lock` (`held by: c4-app timeout head docker`), `KO - it doesn't wait for another c4-app command` (`c4-app: waiting for another c4-app command of faito (600 s at most)`). AC-05: `KO - root's c4-app nightly ends within 90 s (121 s)`, Faito's log holding only its header, `faito.files false`, the paused throwaway left, the lock held.
  - Beyond the plan, in the tests: each cut case checks that nothing holds Faito's lock (`flock -n`) before the cleanup (RQ-04), since the cleanup would hide a holder; the devices (the FIFOs' writers, the watcher, the cleanup) are one file, `tests/fixtures/0033/devices.sh`, copied into the stand-in, frozen with the two tests (a script under `tests/` needs no covering test; `tests/fixtures/0027/facts/fill-volume.sh` is the precedent). The watcher polls a file `docker events` writes (fact f); the 2 GiB leave the volume by a `mv` into `faito.files`' own layer before the next backup, and come back for AC-05.

## Verification

<!-- sdlc-verify's evidence block (bootstrap mode), then `### After deployment` -->
