# Intent: A Developer's workstation can't be a Mac: up.sh stops on host.docker.internal, then on BSD sed, then on bash 3.2

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent in the session held on that Mac
- Kind: change
- Source: conversation (2026-11-03, `bash up.sh` on the product owner's Mac `mc-ch4mp`: macOS 26.5 / Darwin 25.5.0, Apple Silicon, Docker Desktop 29.9.2)
- Spec needed: yes
- Status: planned
- Opened: 2026-11-03
- Decided: 2026-11-03
- Supersedes: —
- Mode: bootstrap

## Problem

The scripts assume a GNU userland: `CLAUDE.md` says they "run under Git Bash on Windows and bash on Ubuntu". On a Mac, a Developer cannot start the shared stack at all, and three failures hide one another — each one is found only once the previous is passed:

- `bash up.sh` refuses to start on a workstation whose `/etc/hosts` holds the right line: `host.docker.internal resolves to nothing, not 127.0.0.1`. `up.sh:10-19` resolves the name by `getent` (Ubuntu) or `powershell.exe` (Git Bash) only, and macOS has neither, so the command substitution comes back empty. The resolver that does read the hosts file there is `dscacheutil -q host -a name` (it answers `ip_address: 127.0.0.1`), and the message blames Docker Desktop's option instead of naming the platform;
- past that, `env.sh:21` and `env.sh:28` fail: `sed: 1: ".env": invalid command code .`, exit 1. BSD sed takes `-i`'s next argument as a backup suffix;
- past that, Apple's `/bin/bash` is 3.2.57, while `registry.sh:170` (`local -A`, where `up.sh`'s registry check stops), `register-app.sh:578` (`declare -A`, reached when `caddy/html/index.html` is missing), `registration-account.sh:250` (`mapfile`, on `up.sh`'s last step) and 33 test files need bash >= 4.

Steps to reproduce: on a Mac with Docker Desktop, a `/etc/hosts` holding `127.0.0.1 host.docker.internal` and no Homebrew bash, `bash up.sh` from a fresh clone. Expected: the stack up, as on Ubuntu and under Git Bash. Observed: the resolution message, then (once each blocker is passed) the sed error, then `local: -A: invalid option`.

What it costs: until the three are passed the Mac has no stack, so no application that depends on it runs there and `tests/run.sh` cannot run either. About one hour of diagnosis in this session for a workstation otherwise ready, with no message naming a platform or a missing tool.

The documentation sends the Developer nowhere: `README.md:121` lists "Docker Desktop and Git Bash" as the prerequisites, and `certs/make-certs.sh:30` gives the CA's trust command for Windows only, so a Mac's browser rejects the stack's certificate with no hint (macOS wants `security add-trusted-cert`).

## Proposed outcome

- A Developer following `README.md` on a Mac brings the stack up: `bash up.sh` exits 0 and the six containers are healthy, reachable at `https://host.docker.internal/`.
- A missing prerequisite is named before anything fails: the entry points say which tool and which version they need, and what installs it, instead of a BSD error or a bash syntax error.
- `README.md` lists macOS's prerequisites, and gives the CA's trust command for macOS as it does for Windows.
- The suite's verdict on macOS is known, measured and not assumed: `bash tests/run.sh --changed --all` runs there, and whatever cannot (the `*.stand-in.sh` tests and their privileged Docker-in-Docker first) is named in `README.md` with its reason and the platform to run it on.
- Windows (Git Bash) and Ubuntu keep behaving exactly as before.

Success criterion: on a Mac prepared per the README, `bash up.sh` exits 0 with the six containers healthy, and the suite's run is either green or reduced to a set `README.md` names with its reason.

## Affected users and systems

- **Developer** on a macOS workstation (new environment for a declared persona; no new persona or module).
- The shared stack (`up.sh`, `env.sh`), the registry and registration scripts (`registry.sh`, `register-app.sh`, `registration-account.sh`, `routes.sh`), the certificates (`certs/`), the test suite (`tests/run.sh`, `tests/lib/`) and the documentation (`README.md`, `CLAUDE.md`).

## Constraints

- **The route the product owner chose (2026-11-03)**: the repository keeps one GNU userland. A Mac gets bash >= 4, GNU sed and coreutils (`brew install bash gnu-sed coreutils`, their `gnubin` ahead of `/usr/bin` on the PATH), rather than the ~50 files using `mapfile`, `declare -A` or `sed -i` being made portable to bash 3.2 and BSD tools; future scripts keep writing GNU. macOS becomes a supported platform: what breaks there later is a bug of this repository.
- No regression on the two platforms already supported (0038, 0039 and 0050 are the precedents for one platform's tools differing): the resolution guard, the scripts and the suite keep their behaviour under Git Bash and on Ubuntu.
- The stack keeps publishing its ports on the loopback only (README, design), so the guard that refuses a `host.docker.internal` resolving elsewhere stays.

## Open questions

- Must the scripts work in a **non-interactive** shell on macOS? `~/.zshrc` is read by interactive shells only, so a `zsh -c` (a hook, a cron, an IDE launcher) has no `gnubin` and falls back to BSD sed; `.zshenv` does not fix it, since `/etc/zprofile`'s `path_helper` puts `/usr/bin` back in front. Either the Developer's setup carries it, and the limit is documented, or the entry points put the GNU tools on their own PATH when they run on Darwin — product owner, at the spec.
- What do the `*.stand-in.sh` tests do on Docker Desktop for Mac? To be measured before anything is promised — the spec's author.
- `tests/0050-preflight-locale.sh:56` fails on macOS (`locale -a | grep -q` under `pipefail` returns 141 by SIGPIPE, deterministic): the product owner decided on 2026-11-03 that it is its own bug intent, opened after this one, not a step of this change — recorded here so the suite's verdict on macOS reads with it.
