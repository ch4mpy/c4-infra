# Handover — 2026-10-28

Where the intents stand, for whoever resumes the work, here or on another workstation; delete this file once they are all delivered. The index ([README.md](README.md)) and each intent's `plan.md` (*Deviations*, *Verification*) hold the details.

- **Mode:** bootstrap since 2026-10-27 (the project context's `Mode` line, and each open intent's `Mode` field): no PR, gates decided in the session, each intent on its own branch on `origin`, merged into `main` by `/sdlc-ship`.
- **Delivered and deployed** this session: 0013, 0018, 0017, 0022, then 0023 and 0020 (their milestone: `--changed --all`, every test, `46 of 46`, 2026-10-28). 0021 abandoned (superseded by 0023).
- **Proof of a change** (product owner, 2026-10-28, CLAUDE.md): `bash tests/run.sh --changed --all`; a full `bash tests/run.sh --all` at each milestone below, before pushing `main`.

## Next, in this order

1. **0011** — planned (spec v2; plan approved 2026-10-23, step 1 done). Next: `/sdlc-plan implement 0011` on its branch, its step 0 merging `main`.
2. **0015** — planned (plan approved 2026-10-27). Next: `/sdlc-plan implement 0015`.
3. **0016** — planned (plan approved 2026-10-27). Next: `/sdlc-plan implement 0016`.
   - **Milestone:** 0011, 0015 and 0016 merged, then a full `--all`, then push.
4. **0019** — the stand-in deployment test fails on a workstation whose locale isn't C. Accepted, no spec. Until it is delivered, run the proofs with `LC_ALL=C`.

## The workstation

- CLAUDE.md "Verification" lists what a run needs: the dev stack (`bash up.sh`), Faito registered from `../faito` (its `deploy-dev.sh`), Docker Desktop given at least 10 GiB for two stand-in lanes, a `TMPDIR` Docker Desktop shares; and `LC_ALL=C` until 0019.
- **Not measured under Git Bash:** the suite's lock (0017) and its lanes (0022: `set -m`, a process group's `TERM`, Ctrl-C in a Windows console). If the lanes misbehave there, `SUITE_DOCKER_MEMORY=0` forces one stand-in lane; `docker rm -f c4-infra.suite-lock` frees a lock left behind.
- The split of the stand-in tests reads the durations of earlier runs from `.git/c4-infra-test-durations`, local to each clone: a new clone starts without it.

## Left open, not intents yet

- `tests/0007-dev.sh`'s `fails` takes docker's "network not found" for "can't be reached": its negative checks pass when `c4-infra.faito` doesn't exist (the part `tickee` run alone, Faito unregistered; 0023's evidence).
- The stand-in's nested DNS fails now and then (0020's step 0: 1 lookup in 20), cause not established; three fixture compose files still say the probe is built in the stand-in (0020's evidence).

- 0013, on the demo host: the master realm's settings (SMTP, Verify email, Forgot password, no brute-force detection) not checked one by one after the upgrade.
- `tests/0004-registry.sh` still pins other live data of `registry.txt` (Tickee's line, `entry faito`): an edit of an existing line would fail it as a new line did (0018's evidence).
- 0013's round-4 details, 0017's verifier details (a stray `# covers:` pattern in `tests/0017-run.sh`'s heredoc, among others): in their `plan.md`.
- Docker Desktop stopped starting any container once (2026-10-27 21:06 UTC; restarted, cause unknown).
