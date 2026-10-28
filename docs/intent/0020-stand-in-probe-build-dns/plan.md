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
