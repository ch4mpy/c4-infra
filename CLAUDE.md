# CLAUDE.md

c4-infra: the infrastructure the c4-soft applications share on one machine (development workstation, demo VPS). [README.md](README.md) holds the design, the port registry and what an application provides; [docs/migration.md](docs/migration.md) how a former project moves onto it.

## Repository layout

- Intent home: `docs/intent/`, one sub-folder per change (`NNNN-<slug>/`), see [docs/intent/README.md](docs/intent/README.md).
- One stack at the root for both environments: the compose base `compose.yml` with `compose.dev.yml` (workstation, `up.sh`) or `compose.demo.yml` (demo host), named by `COMPOSE_FILE` in `.env`; the shared Caddy configuration `caddy/` (`env/dev.caddy` or `env/demo.caddy`, picked by `INFRA_ENV` in `.env`); `register-app.sh`, which generates each application's site with `routes.sh` from its routes file (`examples/routes/`) and its `registry.txt` entry.
- `demo/` holds the demo host's scripts (`write-env.sh` on the workflow's runner, `deploy.sh` and `backup.sh` on the host, `vps-bootstrap.sh`); `.github/workflows/deploy-demo.yml` sends the files of `demo/deploy-files.txt`.
- The two images built here: `keycloak/` (Keycloak, pinned, and its features) and `reverse-proxy/` (Caddy with its rate-limit module); in dev `up.sh` builds them (`KC_IMAGE`, `PROXY_IMAGE` in `.env`), the demo workflow pushes them to GHCR tagged by the content of their directory.
- Scripts run under Git Bash on Windows and bash on Ubuntu: container paths need `MSYS_NO_PATHCONV=1`, host paths given to the docker CLI need `cygpath -w` under Git Bash, and no password goes on a command line.

## Verification

The proof of a change before review is `bash tests/run.sh --changed --all`, with the dev stack running (`bash up.sh`) and `jq` installed: every test the change concerns since the base branch, the `*-facts.sh` ones (Keycloak's and Caddy's behaviour, in throwaway containers) and the `*.stand-in.sh` ones (a stand-in demo host, `tests/lib/stand-in-host.sh`: a privileged Ubuntu container running its own Docker, whose volume keeps the pulled images) included. `bash tests/run.sh --all`, every test (about an hour), runs at the milestones the product owner sets: once a batch of intents is merged, before it is pushed, and before a release (product owner, 2026-10-28). `bash tests/run.sh` runs every test but the stand-in and facts ones. For an intermediate check, `bash tests/run.sh --changed [<base>]` runs only the tests the changes concern, the stand-in ones aside: committed since `<base>` (`origin/main` by default; `HEAD` for a step not committed yet), staged, unstaged and untracked. Each test's duration follows it, the slowest are listed at the end.

Each test declares what it covers in its header, e.g. `# covers: routes.sh registry.sh examples/routes/ tests/fixtures/0003/` (paths, a trailing `/` for a directory, globs; several lines allowed); a test covers its own file. A change to `tests/run.sh`, `tests/lib/` or a file no test declares runs every test; `docs/intent/` concerns none. A run refuses a tracked script no test declares (`uncovered: <script>`) before any test: a new script comes with a test that covers it.

A run whose tests include stand-in ones runs them in lanes, beside the others: lane 1 runs every other test, one after the other; the stand-in tests run on two stand-in hosts (`c4-infra-stand-in` and `c4-infra-stand-in-2`, each with its own volume), split by the durations of earlier runs (`c4-infra-test-durations` in the git directory). The run prints each test's start (`== <test> started (lane <n>…), its output in <file>`), then its output whole when it ends; Ctrl-C stops every lane. Two stand-in lanes need Docker Desktop given at least 10 GiB (Settings, Resources); with less, the run says so and uses one.

One run at a time per Docker: a second run waits, naming the first one's worktree and start time (`waiting for the run of …`). A run frees the stack however it ends; `docker rm -f c4-infra.suite-lock` frees it from a run that hangs.

Prerequisites beyond the stack: Faito registered from `../faito` (its `deploy-dev.sh`), which several tests use as the sample application; with Docker Desktop, a `TMPDIR` it shares (e.g. `mkdir -p ~/.cache/c4-infra-tests && TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh`), since the tests bind-mount their `mktemp` directories and `/tmp` isn't shared by default.
