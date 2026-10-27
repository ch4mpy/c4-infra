# CLAUDE.md

c4-infra: the infrastructure the c4-soft applications share on one machine (development workstation, demo VPS). [README.md](README.md) holds the design, the port registry and what an application provides; [docs/migration.md](docs/migration.md) how a former project moves onto it.

## Repository layout

- Intent home: `docs/intent/`, one sub-folder per change (`NNNN-<slug>/`), see [docs/intent/README.md](docs/intent/README.md).
- One stack at the root for both environments: the compose base `compose.yml` with `compose.dev.yml` (workstation, `up.sh`) or `compose.demo.yml` (demo host), named by `COMPOSE_FILE` in `.env`; the shared Caddy configuration `caddy/` (`env/dev.caddy` or `env/demo.caddy`, picked by `INFRA_ENV` in `.env`); `register-app.sh`, which generates each application's site with `routes.sh` from its routes file (`examples/routes/`) and its `registry.txt` entry.
- `demo/` holds the demo host's scripts (`write-env.sh` on the workflow's runner, `deploy.sh` and `backup.sh` on the host, `vps-bootstrap.sh`); `.github/workflows/deploy-demo.yml` sends the files of `demo/deploy-files.txt`.
- The two images built here: `keycloak/` (Keycloak, pinned, and its features) and `reverse-proxy/` (Caddy with its rate-limit module); in dev `up.sh` builds them (`KC_IMAGE`, `PROXY_IMAGE` in `.env`), the demo workflow pushes them to GHCR tagged by the content of their directory.
- Scripts run under Git Bash on Windows and bash on Ubuntu: container paths need `MSYS_NO_PATHCONV=1`, host paths given to the docker CLI need `cygpath -w` under Git Bash, and no password goes on a command line.

## Verification

`bash tests/run.sh`, with the dev stack running (`bash up.sh`) and `jq` installed; `bash tests/run.sh --all` before a change to the demo host: it also runs the `*.stand-in.sh` tests, on a stand-in demo host (`tests/lib/stand-in-host.sh`: a privileged Ubuntu container running its own Docker, whose volume keeps the pulled images).
