# Handover — 2026-10-28

Where the intents stand when work moves to another workstation; delete this file once work has resumed. The index ([README.md](README.md)) and each intent's `plan.md` (*Deviations*, *Verification*) hold the details.

- **Mode:** bootstrap since 2026-10-27 (the project context's `Mode` line, and each open intent's `Mode` field): no PR, gates decided in the session, each intent on its own branch on `origin`, merged into `main` by `/sdlc-ship`.
- **Delivered and deployed** this session: 0013, 0018, 0017, 0022.
- **Proof of a change** (product owner, 2026-10-28, CLAUDE.md): `bash tests/run.sh --changed --all`; a full `bash tests/run.sh --all` at each milestone below, before pushing `main`.

## Next, in this order

1. **0021** — the dev isolation test's LDAP control check fails now and then. Accepted, no spec. Next: `/sdlc-plan draft 0021`, in plan mode. Measured cause (2026-10-28): `osixia/openldap:1.5.0` opens port 389 about 2 s after it starts, closes it a second later and opens it again (its first-start configuration, then a restart); the control can fall in that gap.
2. **0020** — the isolation test's probe image fails to build in the stand-in, now and then. Accepted, no spec. Next: `/sdlc-plan draft 0020`, in plan mode. Seen since: the workstation's own resolver failed once too (`lookup registry-1.docker.io on 127.0.0.53:53: server misbehaving`, building the stand-in image).
   - **Milestone:** 0021 and 0020 merged into `main`, then a full `--all`, then push.
3. **0011** — planned (spec v2; plan approved 2026-10-23, step 1 done). Next: `/sdlc-plan implement 0011` on its branch, its step 0 merging `main`.
4. **0015** — planned (plan approved 2026-10-27). Next: `/sdlc-plan implement 0015`.
5. **0016** — planned (plan approved 2026-10-27). Next: `/sdlc-plan implement 0016`.
   - **Milestone:** 0011, 0015 and 0016 merged, then a full `--all`, then push.
6. **0019** — the stand-in deployment test fails on a workstation whose locale isn't C. Accepted, no spec. Until it is delivered, run the proofs with `LC_ALL=C`.

## The workstation

- CLAUDE.md "Verification" lists what a run needs: the dev stack (`bash up.sh`), Faito registered from `../faito` (its `deploy-dev.sh`), Docker Desktop given at least 10 GiB for two stand-in lanes, a `TMPDIR` Docker Desktop shares; and `LC_ALL=C` until 0019.
- **Not measured under Git Bash:** the suite's lock (0017) and its lanes (0022: `set -m`, a process group's `TERM`, Ctrl-C in a Windows console). If the lanes misbehave there, `SUITE_DOCKER_MEMORY=0` forces one stand-in lane; `docker rm -f c4-infra.suite-lock` frees a lock left behind.
- The split of the stand-in tests reads the durations of earlier runs from `.git/c4-infra-test-durations`, local to each clone: a new clone starts without it.

## Left open, not intents yet

- 0013, on the demo host: the master realm's settings (SMTP, Verify email, Forgot password, no brute-force detection) not checked one by one after the upgrade.
- `tests/0004-registry.sh` still pins other live data of `registry.txt` (Tickee's line, `entry faito`): an edit of an existing line would fail it as a new line did (0018's evidence).
- 0013's round-4 details, 0017's verifier details (a stray `# covers:` pattern in `tests/0017-run.sh`'s heredoc, among others): in their `plan.md`.
- Docker Desktop stopped starting any container once (2026-10-27 21:06 UTC; restarted, cause unknown).
