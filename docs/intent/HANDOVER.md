# Handover — 2026-10-28

Where the intents stand, for whoever resumes the work, here or on another workstation; delete this file once they are all delivered. The index ([README.md](README.md)) and each intent's `plan.md` (*Deviations*, *Verification*) hold the details.

- **Mode:** bootstrap since 2026-10-27 (the project context's `Mode` line, and each open intent's `Mode` field): no PR, gates decided in the session, each intent on its own branch on `origin`, merged into `main` by `/sdlc-ship`.
- **Delivered and deployed** before the night: 0013, 0018, 0017, 0022, 0023, 0020. 0021 abandoned (superseded by 0023).
- **Delivered during the night, validated, pushed and deployed** (the product owner, 2026-10-28): 0024, 0011, 0015, 0016; deploy-demo run 40684696927 on fc47b85, success; their after-deployment checks in each `plan.md`. The night's decisions validated as recorded. Milestone before the push: `bash tests/run.sh --all` at e01c40e, `verification passed`, 59 tests.
- **Proof of a change** (product owner, 2026-10-28, CLAUDE.md): `bash tests/run.sh --changed --all`; a full `--all` at each milestone, before pushing `main`.

## Next

- **0019** and **0025** delivered (2026-10-28).
- **0026 to 0031** delivered on 2026-10-28, as one batch (the product owner's decision): planned together; 0026 and 0027 implemented by two agents in worktrees, each on its own stand-in host; one review round per intent; one `bash tests/run.sh --all` on the integration commit 205b8eb, `verification passed` (72 tests, 1764 s), the milestone before the push; the verifiers' documentation fixes rerun at 13474a8 (`--changed 205b8eb --all`, 8 tests); merged into `main` in the batch's order (0031, 0030, 0028, 0026, 0027, 0029). Each `plan.md` holds its evidence.
- 0026 to 0031 pushed and deployed (deploy-demo run 40755169273 on 4bae619); 0029's steps 7 to 9 done (the package public, the anonymous checks); its last check passed at deploy-demo run 40808682088 (the tag step skipped, the same digest twice): 0029 complete. `/etc/cron.d/c4-apps-backup` is written by the first application's `vps-bootstrap.sh`.
- **0032, 0034 and 0033** delivered on 2026-10-28, as one batch (the product owner's decision): 0033 implemented by an agent in a worktree; one review round per intent; the integration commit 24e6481 run twice with `bash tests/run.sh --all`, `run.sh exit 1` both times (run 1: six tests failing on the environment; run 2, one stand-in lane: 0024-db-image-change on Docker Hub's DNS, 0033-limits-facts on its timing margin), every failed test passing alone at 24e6481, the product owner accepting it; merged into `main` in the batch's order (0032 on `main`, then 0034, then 0033). Each `plan.md` holds its evidence, KOs first.
- **Follow-ups found on the way** (not intents yet):
  - GitLab projects (immo) will be deployed on a Kubernetes cluster at Scaleway, by a pipeline still to define (the product owner, 2026-10-28); the demo host deploys GitHub projects only, as README and the guide now say (0032).
  - Faito's `demo` profile doesn't set the OTLP endpoints (Faito's repository; `docs/migration.md` step 3 says how).
  - 0030: `new-realm-ids.sh` lists the users of an export in Keycloak's layout only (pre-existing).
  - 0026: no test of `demo/deploy.sh` replacing a changed `c4-app` since the review round.
  - 0032: `docs/demo-setup.md` step 9.5 and the guide's step 5 say the `demo` environment is restricted to the branch it deploys from, but the `gh api` command creates it without a `deployment_branch_policy`.
  - 0033: the kill of a marked process (E4) is guarded by no test; `tests/0033-limits-facts.stand-in.sh`'s fact (f) can fail under load (its 5× margin, 3.8× in a full run; accepted as it is); the paths checked by reading only, listed in its `plan.md`; a nightly cut's way out can reach about 62 s.

## Tickee and poc-immo-pf on c4-infra (analysed 2026-10-28, read only; to resume later)

- **Tickee**: its intent 0001 (accepted) and its plan (approved 2026-10-23) are on `origin/0001-tickee-sur-l-infra-partagee`, not implemented; the plan follows `docs/migration.md` and needs deviations for c4-infra 0015, 0016, 0023, 0024 (`logging:` refused by `c4-app`, the `demo` profile's ports 7080/8080). Its tenant2 LDAP stays its own container; c4-infra already lets the shared Keycloak reach it (`networks.sh`, `tests/0007-dev.sh`). The product owner's questions: resume 0001 with deviations; keep `osixia/openldap:1.5.0` (unmaintained) or replace it; the LDAP's dev port; its 5-minute sync while Tickee is stopped; the legacy `gateway` client; Tickee as the first application deployed by `sudo c4-app`; archive `tickee_demo`.
- **poc-immo-pf (immo)**: nothing blocks it in dev. To do: `headers=app` and its own CSP with a nonce (unblocks its Te Fenua tiles and YouTube frames; its policy on every response); its test Keycloak from 26.7 to 26.8.1 with the stack's features (0029); stale docs; its Apple step (c4-infra 0014 rejected); its intent 0021 (MCP) on a separate MCP origin (c4-infra 0013). The product owner's questions: Apple; the simulated providers in its dev realm (`trustEmail: false`); immo on the demo host or not; the separate MCP origin; brute force 5 vs 10.

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
- Tickee's registration fails while Faito's network `c4-infra.faito` is gone (`networks.sh`, seen at 0034's AC-03).
- The stand-in's nested DNS, and alpine's package index from the workstation, fail now and then (0020's step 0; a 0004-upload run of 2026-10-28), cause not established.
- 0013, on the demo host: the master realm's settings not checked one by one after the upgrade.
- `tests/0004-registry.sh` still pins other live data of `registry.txt` (Tickee's line, `entry faito`).
- 0013's round-4 details, 0017's verifier details: in their `plan.md`.
- Docker Desktop stopped starting any container once (2026-10-27 21:06 UTC; restarted, cause unknown).
- During a two-lane `--all` (2026-10-28), the dev Keycloak was found stopped, then recreated by a `docker compose up` from the main tree that no test of the run made; a few hours later the workstation froze during two parallel stand-in lanes (no OOM logged on the host). Causes unknown; one stand-in lane (`SUITE_DOCKER_MEMORY=1`) since.
