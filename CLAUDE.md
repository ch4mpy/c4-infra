# CLAUDE.md

c4-infra: the infrastructure the c4-soft applications share on one machine (development workstation, demo VPS). [README.md](README.md) holds the design, the port registry and what an application provides; [docs/migration.md](docs/migration.md) how a former project moves onto it.

## Repository layout

- Intent home: `docs/intent/`, one sub-folder per change (`NNNN-<slug>/`), see [docs/intent/README.md](docs/intent/README.md).
- Dev stack at the root (`compose.yml`, `up.sh`, `register-app.sh`…), demo stack in `demo/`, deployed by `.github/workflows/deploy-demo.yml`.
- Scripts run under Git Bash on Windows and bash on Ubuntu: container paths need `MSYS_NO_PATHCONV=1`, host paths given to the docker CLI need `cygpath -w` under Git Bash, and no password goes on a command line.
