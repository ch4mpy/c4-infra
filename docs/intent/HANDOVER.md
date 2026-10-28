# Handover — 2026-10-28, after the night

Where the intents stand, for whoever resumes the work, here or on another workstation; delete this file once they are all delivered. The index ([README.md](README.md)) and each intent's `plan.md` (*Deviations*, *Verification*) hold the details.

- **Mode:** bootstrap since 2026-10-27 (the project context's `Mode` line, and each open intent's `Mode` field): no PR, gates decided in the session, each intent on its own branch on `origin`, merged into `main` by `/sdlc-ship`.
- **Delivered and deployed** before the night: 0013, 0018, 0017, 0022, 0023, 0020. 0021 abandoned (superseded by 0023).
- **Delivered during the night, on `main` locally, NOT pushed** (the product owner validates first; a push deploys the demo host): 0024 (`merge(0024)` 8904903), 0011 (7251fdf), 0015 (f4c3620), 0016 (e01c40e). Their branches are on `origin`; 0015's is pushed from the local branch `0015-impl` (the branch's own name is checked out in the worktree `../c4-infra-0015`, left alone).
- **Milestone:** `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` at e01c40e → `total: 1538.0 s for 59 test(s)` / `verification passed` (2026-10-28). `main` is ready to push.
- **Proof of a change** (product owner, 2026-10-28, CLAUDE.md): `bash tests/run.sh --changed --all`; a full `--all` at each milestone, before pushing `main`.

## For the product owner, to validate

1. **Push `main`** (79 commits ahead of `origin/main`): it deploys the four intents to the demo host, a new Keycloak image among them (0016's stack themes: the deployment dumps the database and restarts Keycloak once). The failed deploy-demo run 40636936869 (0024's cause) is superseded by it. After it: each plan's after-deployment checks (0024: the log's `Registration account c4-infra-registration: up to date`; 0015: `curl -sI https://faito.c4-soft.com/fr/`, one Content-Security-Policy, `X-Frame-Options: DENY`, nosniff, no Server; 0016: the three realms' issuers and banners, `master` and the applications' realms unchanged).
2. **Decisions taken during the night**, each in its plan's *Deviations*:
   - 0024: a refused login is told by kcadm's OAuth error code, not its English message; `register-app.sh` keeps its single login attempt.
   - 0011: AC-09's test asserts that c4-app's check reads no `INFRA_HOST` (`networks.sh ensure` still refuses a bad one, on purpose); fact (b) of `tests/0011-facts.sh` is measured on Linux only.
   - 0015: AC-06's `sudo c4-app register` case lives in `tests/0002-accounts.stand-in.sh`; the review found that `handle_errors` hid the cause of the proxy's own `502`s from its logs: the proxy now has **an access log of its own errors only** (Caddy redacts Cookie and Authorization). A new log stream on the demo host: confirm it suits you.
   - 0016: Keycloak 26.8.1's default user profile requires an address, so the simulated realms make it optional; the seeded passwords are `<user>-password`; every required action is disabled in the simulated realms (else a visitor could change a public account for everyone); the simulated Facebook also sends `email_verified`. **Have a look at the three login pages in dev** (an authorization request to `https://host.docker.internal/auth/realms/simulated-google/…`, or a realm brokering it) before the push: their look is deliberately sober.
3. **The worktree `../c4-infra-0015`**: its local branch is stale (dc09b4b); may it be removed?

## Next

- **0019** — the stand-in deployment test fails on a workstation whose locale isn't C. Accepted, no spec. Next: `/sdlc-plan draft 0019`, in plan mode (the engineer's gate). Until it is delivered, run the proofs with `LC_ALL=C`.

## The workstation

- CLAUDE.md "Verification" lists what a run needs: the dev stack (`bash up.sh`), Faito registered from `../faito` (its `deploy-dev.sh`), Docker Desktop given at least 10 GiB for two stand-in lanes, a `TMPDIR` Docker Desktop shares; and `LC_ALL=C` until 0019.
- **Not measured under Git Bash:** the suite's lock (0017) and its lanes (0022: `set -m`, a process group's `TERM`, Ctrl-C in a Windows console). If the lanes misbehave there, `SUITE_DOCKER_MEMORY=0` forces one stand-in lane; `docker rm -f c4-infra.suite-lock` frees a lock left behind.
- The split of the stand-in tests reads the durations of earlier runs from `.git/c4-infra-test-durations`, local to each clone: a new clone starts without it.
- A run stopped from outside (not Ctrl-C) may leave a facts test's throwaway containers behind (`c4-infra.0009-facts-*` once, 2026-10-28): `docker ps -a` before rerunning.

## Left open, not intents yet

- 0024: `register-app.sh` reports a Keycloak that doesn't answer as "the registration account … doesn't log in" (single attempt); a compose `depends_on: {restart: true}` could cover dev's `up.sh` too (to measure).
- 0011: a refused `up` or `pull` still syncs the refused files into `/var/lib/c4-apps/<app>/`, which the running containers mount (`stage()` runs before `check_model`): a `bug` intent is suggested. The header comments of `tests/fixtures/0007/hostile/build-*.yml` give their former reasons.
- 0015: no automated check that a front end's own Permissions-Policy passes unchanged (the verifier saw it pass by hand).
- 0016: the 0016 tests repeat a curl browser; a shared helper in `tests/lib/keycloak.sh` would hold it once.
- `tests/0007-dev.sh`'s `fails` takes docker's "network not found" for "can't be reached": its negative checks pass when `c4-infra.faito` doesn't exist (0023's evidence).
- The stand-in's nested DNS, and alpine's package index from the workstation, fail now and then (0020's step 0; a 0004-upload run of 2026-10-28), cause not established.
- 0013, on the demo host: the master realm's settings not checked one by one after the upgrade.
- `tests/0004-registry.sh` still pins other live data of `registry.txt` (Tickee's line, `entry faito`).
- 0013's round-4 details, 0017's verifier details: in their `plan.md`.
- Docker Desktop stopped starting any container once (2026-10-27 21:06 UTC; restarted, cause unknown).
