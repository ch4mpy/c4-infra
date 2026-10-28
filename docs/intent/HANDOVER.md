# Handover — 2026-10-28

Where the intents stand, for whoever resumes the work, here or on another workstation; delete this file once they are all delivered. The index ([README.md](README.md)) and each intent's `plan.md` (*Deviations*, *Verification*) hold the details.

- **Mode:** bootstrap since 2026-10-27 (the project context's `Mode` line, and each open intent's `Mode` field): no PR, gates decided in the session, each intent on its own branch on `origin`, merged into `main` by `/sdlc-ship`.
- **Delivered and deployed** before the night: 0013, 0018, 0017, 0022, 0023, 0020. 0021 abandoned (superseded by 0023).
- **Delivered during the night, validated, pushed and deployed** (the product owner, 2026-10-28): 0024, 0011, 0015, 0016; deploy-demo run 40684696927 on fc47b85, success; their after-deployment checks in each `plan.md`. The night's decisions validated as recorded. Milestone before the push: `bash tests/run.sh --all` at e01c40e, `verification passed`, 59 tests.
- **Proof of a change** (product owner, 2026-10-28, CLAUDE.md): `bash tests/run.sh --changed --all`; a full `--all` at each milestone, before pushing `main`.

## Next

- **0025** — a refused `sudo c4-app up` or `pull` still copies the refused files where the application's running containers read them (0011's verifier). Accepted, no spec. Next: `/sdlc-plan draft 0025`, in plan mode.
- **0019** — the stand-in deployment test fails on a workstation whose locale isn't C: being delivered (2026-10-28).

## The workstation

- CLAUDE.md "Verification" lists what a run needs: the dev stack (`bash up.sh`), Faito registered from `../faito` (its `deploy-dev.sh`), Docker Desktop given at least 10 GiB for two stand-in lanes, a `TMPDIR` Docker Desktop shares.
- **Not measured under Git Bash:** the suite's lock (0017) and its lanes (0022: `set -m`, a process group's `TERM`, Ctrl-C in a Windows console). If the lanes misbehave there, `SUITE_DOCKER_MEMORY=0` forces one stand-in lane; `docker rm -f c4-infra.suite-lock` frees a lock left behind.
- The split of the stand-in tests reads the durations of earlier runs from `.git/c4-infra-test-durations`, local to each clone: a new clone starts without it.
- A run stopped from outside (not Ctrl-C) may leave a facts test's throwaway containers behind (`c4-infra.0009-facts-*` once, 2026-10-28): `docker ps -a` before rerunning.

## Left open, not intents yet

- 0024: `register-app.sh` reports a Keycloak that doesn't answer as "the registration account … doesn't log in" (single attempt); a compose `depends_on: {restart: true}` could cover dev's `up.sh` too (to measure).
- 0011: the header comments of `tests/fixtures/0007/hostile/build-*.yml` give their former reasons.
- 0015: no automated check that a front end's own Permissions-Policy passes unchanged (the verifier saw it pass by hand).
- 0016: the 0016 tests repeat a curl browser; a shared helper in `tests/lib/keycloak.sh` would hold it once.
- `tests/0007-dev.sh`'s `fails` takes docker's "network not found" for "can't be reached": its negative checks pass when `c4-infra.faito` doesn't exist (0023's evidence).
- The stand-in's nested DNS, and alpine's package index from the workstation, fail now and then (0020's step 0; a 0004-upload run of 2026-10-28), cause not established.
- 0013, on the demo host: the master realm's settings not checked one by one after the upgrade.
- `tests/0004-registry.sh` still pins other live data of `registry.txt` (Tickee's line, `entry faito`).
- 0013's round-4 details, 0017's verifier details: in their `plan.md`.
- Docker Desktop stopped starting any container once (2026-10-27 21:06 UTC; restarted, cause unknown).
