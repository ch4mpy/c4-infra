# Plan: The isolation test's probe image fails to build in the stand-in, now and then, on a DNS error

- Spec: none, the [intent](intent.md) (bug, spec needed: no)
- Status: approved
- Branch: 0020-stand-in-probe-build-dns
- Approved: 2026-10-28, Jérôme Wacongne (engineer; standard risk)

## Starting point

`tests/0007-isolation.stand-in.sh:196-199` and `tests/0013-mcp.stand-in.sh:76-79` build the probe image (`tests/fixtures/0007/probe/`: `FROM caddy:2.11.4-alpine`, `apk add curl nmap netcat-openbsd`) with the stand-in's own Docker; on this workstation the `apk` step failed on `DNS: transient error` in two runs out of three (2026-10-27, 28), and a fresh stand-in then fails 35 more checks. Read (2026-10-28):
- the stand-in (`tests/stand-in-host/`) starts a plain `dockerd` (no DNS setting): its build containers use the stand-in's resolver (Docker Desktop's, `192.168.65.7`) through the stand-in's NAT and firewall;
- `demo/vps-bootstrap.sh:119-123`, run in the stand-in by `stand_in_accounts`, enables `ufw` (`default deny incoming`, `allow outgoing`) while that `dockerd` runs: `ufw`'s forward policy and the order of its rules against Docker's may drop a bridge container's traffic now and then, which is the likeliest cause, to measure (it would concern the demo host too, for any container that leaves its host);
- the stack's images reach the stand-in with `stand_in_load_image` (`docker save | docker load`, `tests/lib/stand-in-host.sh:96-102`), which needs no DNS in the stand-in.

## Engineer's choices

- The probe no longer depends on the stand-in's DNS: built on the workstation (when missing, or when `tests/fixtures/0007/probe/` changed: a label holding its content's hash) and loaded with `stand_in_load_image`, in one helper `stand_in_probe` of `tests/lib/stand-in-host.sh` that both tests call.
- A probe that can't be had stops its test at once, one `KO` naming the cause, instead of failing every later check.
- The root cause is measured (step 0); when it is the demo host's firewall, it becomes a bug intent of its own, out of this one's scope (it changes the demo host).

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/lib/stand-in-host.sh` | modified: `stand_in_probe` (step 1: the build in the stand-in, as both tests do today; step 2: built on the workstation when needed, then loaded) | the outcome |
| `tests/0020-probe.stand-in.sh` | new, frozen after step 1: a stand-in whose resolver answers nothing (its `/etc/resolv.conf` pointed at `127.0.0.1`), then `stand_in_probe`; the probe image is in the stand-in's Docker and a probe container answers on `:7080` | the outcome |
| `tests/0007-isolation.stand-in.sh`, `tests/0013-mcp.stand-in.sh` | modified: their `build_probe` replaced by `stand_in_probe` (step 1), and the test stopped at once when it fails (step 3); nothing else | the outcome ("says so once") |
| `docs/intent/0020-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

0. **Setup and facts**: `git merge main` (the local `main`, 0023 included); in a stand-in, before and after `stand_in_accounts faito hururaa`: 20 lookups of `dl-cdn.alpinelinux.org` from a container of its Docker, its `/etc/resolv.conf`, `iptables -S FORWARD` (the backend: `iptables-legacy`, `iptables-nft`), `ufw status verbose`. — skill: none — check: the measurements written into the deviations; a cause in `vps-bootstrap.sh`'s firewall → a bug intent suggested to the product owner, this plan unchanged.
1. **Failing test**: `stand_in_probe` as both tests build today (they call it), and `tests/0020-probe.stand-in.sh`. — skill: none — check: `bash tests/0020-probe.stand-in.sh` exits 1 on the probe (the build fails on the stand-in's resolver), three runs out of three. Commit `test(0020): …` (the helper moved unchanged with it), freeze the test.
2. **Fix**: `stand_in_probe` builds on the workstation when needed, then loads. — skill: none — check: `bash tests/0020-probe.stand-in.sh` → `every check passed`, three runs out of three. Commit `fix(0020): …`.
3. **The tests stop at once**: both tests end after a probe that can't be had, with its one `KO`. — skill: none — check: a mutation, `tests/fixtures/0007/probe/Dockerfile` broken in a throwaway copy → `tests/0007-isolation.stand-in.sh` prints that one `KO` and stops (`1 check(s) failed`); then both tests whole, `every check passed`. Commit `fix(0020): …`.
4. **Verification**: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` (a `tests/lib/` change: every test; with `main` merged at step 0 it also stands as the milestone's full run once 0020 is merged, `main` unchanged meanwhile); mutation check: step 1's helper in a worktree → `tests/0020-probe.stand-in.sh` `KO`; `/sdlc-verify 0020` (bootstrap: one round), its evidence into `## Verification`. — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0020`, then the milestone's push of `main` (0023 and 0020).

## Risks

- The workstation's own build fails (its resolver failed once, 2026-10-28) → built only when the image is missing or its fixture changed, so most runs need no network; a failure stops the test with docker's message.
- A probe image left from an older fixture → the label holds the fixture's hash; a mismatch rebuilds.
- Breaking the stand-in's resolver in the new test leaks into the next stand-in test → the stand-in is recreated by each test's `stand_in_up`, and the test restores `/etc/resolv.conf` before it ends.
- Step 0 finds the demo host's firewall at fault → reported, not fixed here; the probe's fix holds either way.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| The probe image is had on every run where the workstation has network access | automated test | `tests/0020-probe.stand-in.sh`: the stand-in's resolver answering nothing, the probe still in its Docker and answering |
| When it can't be had, the test says so once, with the cause | mutation check | step 3: a broken probe fixture → one `KO` with docker's message, the test stopped |
| The isolation checks themselves stay | review + automated test | `git diff main -- tests/0007-isolation.stand-in.sh tests/0013-mcp.stand-in.sh`: the probe's lines only; both tests `every check passed` |
| The bug is reproduced | mutation check | step 1's helper → `tests/0020-probe.stand-in.sh` exits 1 on the probe (step 1, and in a worktree at step 4) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — step 0, measured in a stand-in (`nslookup -timeout=3 dl-cdn.alpinelinux.org` from a container of its Docker): fresh, `ufw` inactive, `FORWARD` policy `ACCEPT`: 20 ok, 0 failed; after `stand_in_accounts faito hururaa`, `ufw` active (`deny (routed)`), `FORWARD` policy `DROP`, Docker's chains (`DOCKER-USER`, `DOCKER-FORWARD`) before `ufw`'s: 19 ok, 1 failed; from the workstation's own Docker (the same resolver, `192.168.65.7`, then the router `192.168.178.1`): 50 ok, 0 failed. The demo host's firewall lets a container's DNS through (Docker's chains come first): no bug intent for the demo host; the failures happen on the stand-in's nested path, cause not established. The reproducing test points the stand-in's resolver at `192.0.2.1` (TEST-NET-1, which answers nothing), not `127.0.0.1`, which Docker drops for 8.8.8.8. No impact on files or proof.
- 2026-10-28 — the bug review's fixes (0c6d151): `tests/fixtures/0007/probe/Dockerfile`'s comment says where the probe is built (outside *Files*: its comment only, which changes its hash once); both tests ask for the probe right after `stand_in_up`, before `stand_in_accounts` (a probe that can't be had stops them before minutes of setup; `deploy.sh`'s `docker image prune -f`, without `-a`, keeps a tagged image); `stand_in_probe` copies the image only when the stand-in's copy lacks the fixture's label. *Risks* said the new test restores `/etc/resolv.conf`: it relies on `stand_in_down`, which removes the stand-in container, the file with it (its header says so). No impact on proof.

## Verification

### Verification — 0c6d151

- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` → `verification passed (--changed: 46 of 46 tests)` (2026-10-28, 1313 s, `== --changed: tests/lib/stand-in-host.sh is the suite's own: every test runs`, the stand-in and facts tests included); the branch holds the local `main` with 0023, so it also stands as the milestone's full run of 0023 and 0020
- Risk tier: standard (a test's fixture and helper; no risk rule applies)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high): 10 findings, 5 fixed in 0c6d151, 5 answered; no security pass (standard risk), no quality pass (bootstrap mode)
  - fixed: the comments that said the probe was built in the stand-in (the fixture's Dockerfile, both tests' headers); the copy repeated though the stand-in's volume held the image (its label compared first); a probe that can't be had found only after minutes of setup (asked right after `stand_in_up`); the usage block's alignment
  - answered: two checkouts sharing the tag `c4-test/probe` (the suite's lock runs one suite at a time per Docker); the stop block in both tests (a test keeps its helpers); the content hash rather than Docker's build cache (a build asks the registry for its base image, which the workstation's resolver failed once); the stand-in's nested DNS left as it is (out of scope, cause not established at step 0) → a bug intent if another nested lookup fails
- Mutation checks: the frozen `tests/0020-probe.stand-in.sh` at a38723e (before the fix) → `KO - the probe image reaches the stand-in's Docker (stand_in_probe)` (`DNS: transient error (try again later)`), `KO - a container of it answers on :7080`, `2 check(s) failed` (three runs at step 1, and the verifier's); a broken probe fixture (`RUN false`) → `tests/0007-isolation.stand-in.sh` and `tests/0013-mcp.stand-in.sh`: `KO - the probe image is in the stand-in (c4-test/probe)` with docker's message, `no probe: stopped`, `1 check(s) failed`; the workstation's image unchanged
- Verifier: 4/4 criteria OK, 0 KO
  - details it raised, not fixed (one fix round): three fixture compose files' comments (`tests/fixtures/0007/faito/compose.yml:3`, `…/hururaa/compose.yml:3`, `tests/fixtures/0013/turu/compose.yml:3-4`) still say the probe is built in the stand-in; an empty hash if the fixture's directory were missing; `tr -d '\r'` on the stand-in's label, not the workstation's (a CRLF would rebuild every time, under Git Bash only)
- Not verifiable here: Git Bash (`cygpath` through `_stand_in_host_path`, `MSYS_NO_PATHCONV` kept); two lanes building the probe at once after a fixture change
- Files outside the plan: `tests/fixtures/0007/probe/Dockerfile` (its comment; *Deviations*)
- Pre-existing findings (not fixed, out of scope): the stand-in's nested DNS path fails now and then (step 0: 1 lookup out of 20 after `stand_in_accounts`), cause not established

| Criterion | Result | Evidence |
| --- | --- | --- |
| The probe image is had on every run where the workstation has network access | OK | `tests/0020-probe.stand-in.sh` in the run above: `every check passed`, the stand-in's resolver answering nothing (`192.0.2.1`), its old probe removed first; 0007-isolation 48 `ok`, 0013-mcp 15 `ok` |
| When it can't be had, the test says so once, with the cause | OK | the broken-fixture mutation above: one `KO` with docker's `exit code: 1`, `no probe: stopped` |
| The isolation checks themselves stay | OK | `git diff main -- tests/0007-isolation.stand-in.sh tests/0013-mcp.stand-in.sh`: the headers' probe lines and the probe's block, moved before `stand_in_accounts`; no isolation check changed; both `every check passed` |
| The bug is reproduced | OK | the frozen test at a38723e: `DNS: transient error`, `2 check(s) failed` |

