# Plan: A refused `sudo c4-app up` or `pull` still copies the refused files where the application's running containers read them

- Spec: none, the [intent](intent.md) (bug, spec needed: no)
- Status: approved
- Branch: 0025-refused-deployment-still-staged
- Approved: 2026-10-28, Jérôme Wacongne (engineer, and tech lead for the high risk), in plan mode

## Starting point

- `demo/c4-app` (at `main` 4bbbc3b): `stage()` copies `~/<app>/<app>/` as the application into the root-owned `/var/lib/c4-apps/.<app>.incoming/`, refuses a link or a special file, makes it `root:<app>`, then `rsync -a --delete` into `/var/lib/c4-apps/<app>/` (the containers' mount sources) and removes it. `up` and `cmd_pull` call `stage`, `read_model` (`docker compose config` as the application, `--project-directory` the staging directory), `check_model`; `cmd_register` calls `stage`, `snapshot_src` (`cp -a` of the staging directory into the root-only snapshot), then `register-app.sh`, whose refusals come after. So `up`, `pull` and `register` all change the running application's files before anything may refuse them (the intent's open question on `register`: yes, the same gap).
- The in-place `rsync` is what a passing `up` relies on: a container's directory mount sees the new files (same directory); swapping directories would leave running containers on the old one.
- `pull` needs no staging copy (compose pulls the model's images); `register` reads only the snapshot.

## Engineer's choices

- Proposed by Claude, approved by Jérôme Wacongne (engineer) with this plan, 2026-10-28:
  - The copy into `.<app>.incoming` and its checks (links, special files, `root:<app>`) come first, as today; the model is read **from that copy** (`--project-directory` the incoming directory), then its paths under the incoming directory are rewritten to the staging directory's (`jq` `walk`, exact prefix): the model names the paths the containers will mount, and a path the rewrite would miss stays outside the staging directory, which `check_model` refuses — it fails closed.
  - Only a passing `up` copies the checked files into `/var/lib/c4-apps/<app>/` (the `rsync` as today). `pull` never touches it (it creates it, empty, when missing: compose's project directory). `register` takes its snapshot from the incoming copy and never touches it either.
  - Rejected: a bind mount of the incoming copy over the staging path in a private mount namespace for `docker compose config` (exact paths without a rewrite, but a mount in a root script for what a data rewrite does); restoring the staging directory after a refusal (the containers would see the new files in between).

## Files

| File | Change | For |
| --- | --- | --- |
| `demo/c4-app` | modified: `stage()` split into the copy and its checks (into the incoming directory, kept until the command ends) and the copy into place (`up` only, after `check_model`); `read_model` reads the incoming copy and rewrites its paths; `snapshot_src` copies the incoming copy; `cmd_pull` and `cmd_register` no longer write the staging directory; the incoming directory removed on every exit (a trap); header comment | the outcome |
| `tests/0025-refused-stage.stand-in.sh` | new, frozen after step 1: Faito deployed with `tests/fixtures/0025/mounted.yml` (a directory of its own mounted read-only, `content/page.txt` = `v1`); then `content/page.txt` = `v2` with a refused `compose.yml` (a published port): `sudo c4-app up` and `pull` refused, `/var/lib/c4-apps/faito/content/page.txt` and the running container's `/srv/content/page.txt` still `v1`, the staging `compose.yml` the former one; `sudo c4-app register` with a theme not Faito's refused, the staging directory unchanged; then the valid file again: `up` exits 0 and the container reads `v2`; the model's and the container's mount source is `/var/lib/c4-apps/faito/content` | the outcome |
| `tests/fixtures/0025/` | new: `mounted.yml`, `refused.yml`, a `themes/hururaa/` directory | the outcome |
| `README.md` | modified: "Accounts" — a command copies `~/<app>/` into `/var/lib/c4-apps/<app>/` only once `up`'s checks pass; a refused command leaves it as it was; `pull` and `register` never write it | the outcome |
| `docs/intent/0025-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

0. **Setup and facts**: the branch `0025-refused-deployment-still-staged` from `main` (after 0019's merge); on the stand-in (`stand_in_accounts faito`), `docker compose config --format json` of a file with a bind mount, an `env_file` and a `secrets` file, run with `--project-directory` another directory: each such path is absolute under that directory, the `env_file`'s values read from it. — skill: none — check: recorded under *Deviations*; a path the rewrite can't reach is a deviation before step 2.
1. **Failing test**: `tests/0025-refused-stage.stand-in.sh` and its fixtures. — skill: none — check: exits 1 on "still v1" (up, pull) and on register's unchanged staging. Commit `test(0025): …` alone, freeze it.
2. **Fix** `demo/c4-app`. — skill: none — check: `bash -n demo/c4-app`; `bash tests/0025-refused-stage.stand-in.sh`, `bash tests/0007-compose-check.stand-in.sh`, `bash tests/0011-demo-host.stand-in.sh` `every check passed`. Commit `fix(0025): …`.
3. **Docs**: README. — skill: none — check: reread. Commit `docs(0025): …`.
4. **Verification**: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` (without `LC_ALL`, 0019 delivered); mutation check: step 1's `demo/c4-app` in a throw-away worktree → the test `KO`; `/sdlc-verify 0025` (bootstrap: one round; high risk: what the demo host runs as root, so the security pass too). — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0025`.

## Risks

- The rewrite misses a path form of the model → it stays under the incoming directory, outside the staging one: `check_model` refuses the deployment (fails closed), and step 0 measures the forms first.
- The model now reads the incoming copy, which the application may read (`root:<app>`, as the staging directory): it can't write it; the per-application lock already serialises the commands.
- `register` no longer refreshes the staging directory: nothing reads it there (its inputs come from the snapshot); the next `up` copies the files.
- A command interrupted between the check and the `rsync` → the incoming copy removed by the trap, the staging directory as it was (the `rsync` itself is today's).

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| A refused `up` leaves `/var/lib/c4-apps/<app>/` as it was; the running containers read the same files | automated test (stand-in) | `tests/0025-refused-stage.stand-in.sh`: `page.txt` still `v1` in the staging directory and in the container, the former `compose.yml` |
| The same for a refused `pull`, and a refused `register` | automated test (stand-in) | the same test |
| A passing `up` still brings the new files, mounted from the staging directory | automated test (stand-in) | the same test: `v2` in the container; the model's and the container's mount source under `/var/lib/c4-apps/faito/` |
| The other `c4-app` behaviours are kept | automated tests (stand-in) | `tests/0007-compose-check.stand-in.sh`, `tests/0011-demo-host.stand-in.sh`, `tests/0002-accounts.stand-in.sh`, `tests/0007-isolation.stand-in.sh` in step 4's run |
| The bug is reproduced | mutation check | step 1's `demo/c4-app` → the test `KO` (step 1, and in a worktree at step 4) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
