# Spec: A Developer's workstation can't be a Mac: up.sh stops on host.docker.internal, then on BSD sed, then on bash 3.2

- Intent: [0055](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: no authentication, authorization or secret, no isolation between applications, nothing a host exposes to the network — the loopback-only publication stays `compose.yml`'s and is untouched, the guard's subject being reachability from the workstation —, no personal data)
- Policies applied: none (project context: "Policies: none yet")
- Approved: 2026-11-03, Jérôme Wacongne (in the drafting session; every point of attention decided)

## Summary

macOS becomes a third supported workstation platform, beside Git Bash on Windows and bash on Ubuntu. The repository keeps one GNU userland: a Mac installs bash >= 4, GNU sed and GNU coreutils, and the scripts go on writing GNU. What changes here is the resolution of `host.docker.internal` (macOS has neither `getent` nor `powershell.exe`), a refusal that names a missing prerequisite instead of letting a BSD tool fail cryptically, the documentation a Developer on a Mac needs, and a measured verdict of the suite on that platform.

## Requirements

- **RQ-01:** On macOS, `up.sh` resolves `host.docker.internal` with the platform's resolver; the two branches it already has, the order it asks them in, and every string of its refusal are unchanged. (intent: outcome 1, constraint "no regression")
- **RQ-02:** Each entry point a Developer types (`up.sh`, `tests/run.sh`) refuses before its first use of a missing prerequisite, naming the tool, the minimum version where there is one, and the command that installs it. (intent: outcome 2)
- **RQ-03:** What an entry point demands is exactly what its own path needs: `up.sh`, bash >= 4; `tests/run.sh`, bash >= 4, a GNU `sed` and GNU coreutils. (intent: outcome 2; inventory under Design)
- **RQ-04:** `README.md` lists macOS's prerequisites beside Windows's and Ubuntu's: the packages, the command that installs them, and the PATH rule that puts them before the system's tools, and the limit of that rule PA-01 records. (intent: outcome 3)
- **RQ-05:** `certs/make-certs.sh` gives the CA's trust command for macOS as it does for Windows. (intent: problem, outcome 3)
- **RQ-06:** `CLAUDE.md` says the scripts run on macOS too, and states the rule future scripts keep: they write GNU, and a Mac brings the GNU userland. (intent: constraint "the route the product owner chose")
- **RQ-07:** `env.sh`'s two in-place edits work under BSD sed as under GNU sed; that exception does not extend to the repository's other `sed -i`. (product owner, 2026-11-03)
- **RQ-08:** The suite's verdict on macOS is written in `README.md`: what runs there, and whatever cannot with its reason and the platform to run it on. (intent: outcome 4)
- **RQ-09:** Git Bash on Windows and bash on Ubuntu keep their behaviour: same resolution, same refusals, same suite. (intent: constraint)

## Out of scope

- Making the files that use `mapfile`, `declare -A` or `local -A` portable to bash 3.2, and the repository's other `sed -i` portable to BSD sed (the route the product owner chose: one GNU userland).
- `tests/0050-preflight-locale.sh`'s failure on macOS (`locale -a | grep -q` under `pipefail` returning 141 by SIGPIPE): its own bug intent, opened after this one (product owner, 2026-11-03).
- Running the suite in CI on macOS: no workflow runs `tests/run.sh` on any platform (`.github/workflows/` holds `deploy-demo.yml` only), so no platform's suite has an automated proof and macOS is on the same footing.
- The session watch's blindness on macOS (`~/.claude/hooks/watch-progress.sh` reads `/proc`): another repository's tool, an improvement-log candidate.

## Design

### Current behaviour

Measured in the session of 2026-11-03 on `mc-ch4mp` (macOS 26.5, Darwin 25.5.0, Apple Silicon, Docker Desktop 29.9.2, VM at 11.7 GiB):

- `up.sh:10-19` builds the addresses of `host.docker.internal` from `getent ahostsv4` when there is a `getent`, and from `powershell.exe` otherwise. macOS has neither in a `bash` started from the user's shell, so the substitution is empty and the guard refuses with `resolves to nothing` although `/etc/hosts` holds `127.0.0.1 host.docker.internal`. The platform's resolver answers: `dscacheutil -q host -a name host.docker.internal` prints `ip_address: 127.0.0.1`, an IPv6 record coming under a distinct `ipv6_address:` key.
- `env.sh:21` and `env.sh:28` failed under BSD sed (`sed: 1: ".env": invalid command code .`, exit 1), which reads `-i`'s next argument as a backup suffix. The working tree already carries the fix the product owner chose to keep: `sed -i.bak … && rm -f .env.bak`, which both seds accept, leaving no `.bak` behind (checked on `/usr/bin/sed` and on GNU sed 4.10).
- Apple's `/bin/bash` is 3.2.57. On `up.sh`'s own path, `registry.sh:170` (`local -A`) stops it — `local: -A: invalid option`, which `up.sh` reports as an invalid registry; further on, `register-app.sh:578` (`declare -A`, reached when `caddy/html/index.html` is missing) and `registration-account.sh:250` (`mapfile`, on `up.sh`'s last step).
- **Inventory of what the host needs, GNU-side**: `up.sh`'s path needs bash >= 4 and no `sed -i` (`env.sh`'s are portable since RQ-07, and the repository's other one is `new-realm-ids.sh:64`, which `up.sh` never runs). `tests/run.sh` needs, besides bash >= 4: a GNU `sed` (`new-realm-ids.sh:64`, and `sed -i` in about thirteen tests) and GNU coreutils for two host-side calls, `stat -c %a` at `tests/0002-workflow.sh:96` and `timeout 300` at `tests/0049-docker-preflight.sh:132` (macOS ships no `timeout`). The `stat -c`, `date -d` and `timeout` of the `*.stand-in.sh` tests run inside their Ubuntu container and need nothing of the host.
- **The stand-in mechanism works on Docker Desktop for Mac**: `bash tests/lib/stand-in-host.sh selftest` passes (the stand-in starts with its dockerd, `docker info` and `docker compose` answer inside it, `sshd -t` succeeds, its host name is `vps`, it stops). The privileged Docker-in-Docker the 26 `*.stand-in.sh` tests rest on is therefore available; what each of those tests does there is RQ-08's measurement.
- `README.md:121` lists "Docker Desktop and Git Bash" as the prerequisites, and `README.md:132` gives the hosts-file path for Windows. `certs/make-certs.sh:30` prints the CA's trust command for Windows (`certutil -user -addstore Root`) and a JDK script; a Mac's browser rejects the stack's certificate with no hint, macOS wanting `security add-trusted-cert`.
- `*.dev.localhost` resolves to `127.0.0.1` on macOS (mDNSResponder), so `APPS_DOMAIN=dev.localhost` needs nothing.

### Behaviour per persona

**Developer, on a Mac prepared per `README.md`**: `bash up.sh` brings the stack up as on the two other platforms, and `bash tests/run.sh` runs the suite.

**Developer, on a Mac missing a prerequisite**: the entry point stops before the first tool that would fail, naming what is missing, the minimum version where there is one, and what installs it. The message names the package manager's command (`brew install …`) and the PATH rule, without binding the repository to one installation prefix: it says what to put before the system's tools, not where a given machine keeps it.

**Developer, on Windows or Ubuntu**: nothing changes, neither the resolution, nor the refusals, nor the suite.

### API and contracts

- The resolution guard's contract is unchanged: the addresses of `host.docker.internal` must be exactly `127.0.0.1`; any other answer, or none, stops `up.sh` before any `docker` call, with the message it already prints. Only the source of those addresses gains a platform.
- The preflight's contract: a missing prerequisite is a refusal before any work, exit non-zero, naming tool, minimum version and install command; a prerequisite that is present is silent.
- `README.md` gains macOS wherever it names a platform's tools: the prerequisites, the hosts file, the CA's trust, and the suite's verdict on macOS.

### Data

None: no schema, no realm, no port, no registry entry changes.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| none declared | The project context says "Policies: none yet". The standing constraints of `README.md`'s design section are honoured by the Design above: the stack keeps publishing on the loopback only, and the guard that protects the Developer's reach of it keeps its contract (RQ-01). |

## Points of attention

### PA-01: a non-interactive shell on macOS has none of the GNU tools

- Issue: the PATH rule of RQ-04 lives in the Developer's shell configuration. `~/.zshrc` is read by interactive shells only, so a `zsh -c` — a git hook, a cron, an IDE launcher, an agent's shell — gets Apple's `sed` and bash 3.2 again, and `.zshenv` does not fix it: `/etc/zprofile`'s `path_helper` puts `/usr/bin` back in front of what `.zshenv` prepended. Measured in this session: `zsh -ic` resolves GNU sed, `zsh -lc` does not.
- Options:
  - **A.** The Developer's setup carries it, and the limit is documented in `README.md`. A non-interactive shell then hits RQ-02's refusal, which names the cause instead of a BSD error.
  - **B.** The entry points put the GNU tools on their own PATH when they run on Darwin, and re-exec under bash >= 4, so any shell works. The repository then hard-codes a package manager's prefixes (`/opt/homebrew` on Apple Silicon, `/usr/local` on Intel) and silently overrides the Developer's PATH.
- Recommendation: **A**. It keeps the repository free of one package manager's layout, and RQ-02's refusal already turns the failure into a named cause, which is what cost an hour in this session. B buys a convenience the suite doesn't need — no entry point is run non-interactively today — at the price of a hidden PATH rewrite in every script.
- Decides: product owner
- Decision: A, 2026-11-03, Jérôme Wacongne. The Developer's shell configuration carries the PATH rule, and `README.md` states the limit (RQ-04): in a non-interactive shell the GNU tools are absent, and the entry point's refusal (RQ-02) names the cause. The entry points do not rewrite their own PATH.

### PA-02: how much proof does "supported platform" need now

- Issue: RQ-08 asks for a measured verdict. The suite's full run is the only thing that measures it, and no platform has an automated proof (no workflow runs `tests/run.sh`). A full run here is about half an hour with two stand-in lanes, which this machine's VM allows (11.7 GiB, above the 10 GiB floor), and it is the first ever on macOS: each failure it finds is work to triage.
- Options:
  - **A.** `bash tests/run.sh --all` once on this Mac as part of this change's verification. Whatever it finds that isn't a one-line fix becomes its own bug intent, as `tests/0050-preflight-locale.sh`'s failure already did, so this change stays bounded while the verdict is real.
  - **B.** A bounded measurement: `bash tests/run.sh --changed --all` for this change, plus the stand-in family sampled on top of the self-test that already passed. `README.md` then states the verdict as measured on that subset, and the full run waits for the next milestone the product owner sets.
- Recommendation: **A**. The promise this change makes is a platform, not a patch: a verdict written in `README.md` from a subset would be the "assumed" the intent's outcome rules out. The triage rule keeps the cost bounded, and the product owner already sets `--all` runs at milestones — this is one.
- Decides: product owner
- Decision: A, 2026-11-03, Jérôme Wacongne. `bash tests/run.sh --all` runs once on this Mac in this change's verification, and its verdict is what RQ-08 writes. A failure it finds that is not a one-line fix becomes its own bug intent rather than a step of this change.

## Acceptance criteria

- **AC-01:** Given a Mac whose `/etc/hosts` holds `127.0.0.1 host.docker.internal` and whose prerequisites are installed, when `bash up.sh` runs, then it exits 0 and the stack's six containers are healthy, `https://host.docker.internal/` answering 200 from 127.0.0.1. (RQ-01)
- **AC-02:** Given a machine whose resolver answers a LAN address, on each supported platform, when `bash up.sh` runs, then it stops before any `docker` call with the message it prints today, naming that address, the hosts-file line and Docker Desktop's option. (RQ-01, RQ-09)
- **AC-03:** Given a machine that has a `getent` (Ubuntu) or only a `powershell.exe` (Git Bash), when `up.sh` resolves the name, then it uses that branch as before, macOS's branch changing neither. (RQ-01, RQ-09)
- **AC-04:** Given a Mac whose PATH has no bash >= 4, when `bash up.sh` runs, then it stops before the registry check, naming bash and its minimum version and what installs it, and calls no `docker`. (RQ-02, RQ-03)
- **AC-05:** Given a Mac whose PATH has no GNU `sed` or no GNU coreutils, when `bash tests/run.sh` runs, then it stops before its first test, naming the missing tool and what installs it. (RQ-02, RQ-03)
- **AC-06:** Given a `.env` holding a `PROXY=` line and a PATH whose only `sed` is BSD's, when `env.sh` runs, then the line is gone, no `.env.bak` is left and it exits 0. (RQ-07)
- **AC-07:** Given `certs/make-certs.sh` creating a CA on macOS, when it prints how to trust it, then the macOS command is there, as the Windows one is on Windows. (RQ-05)
- **AC-08:** Given `README.md` and `CLAUDE.md`, when a Developer reads where platforms are named, then macOS's prerequisites, its install command, its PATH rule, its hosts file, its CA trust and the suite's verdict on it are there, and the one-GNU-userland rule is stated. (RQ-04, RQ-06, RQ-08)
- **AC-09:** Given this Mac, when the suite runs as PA-02's decision prescribes, then its verdict is written in `README.md`, every test that cannot run there being named with its reason and the platform to run it on. (RQ-08)

## Intent questions

- Must the scripts work in a non-interactive shell on macOS? → PA-01.
- What do the `*.stand-in.sh` tests do on Docker Desktop for Mac? → Answered by measurement: `bash tests/lib/stand-in-host.sh selftest` passes on macOS (every check, exit 0), so the privileged Docker-in-Docker they rest on is available. What each test does there is RQ-08's measurement, whose extent is PA-02.
- `tests/0050-preflight-locale.sh`'s failure on macOS → out of scope, its own bug intent (product owner, 2026-11-03); the suite's verdict (RQ-08) is read with it.

## Change log

- v1 — 2026-11-03 — first version; approved the same day in the drafting session, PA-01 decided A (the workstation carries the PATH, its limit written in `README.md` under RQ-04) and PA-02 decided A (a full `--all` run on this Mac as the verdict).
