# Plan: A Developer's workstation can't be a Mac: up.sh stops on host.docker.internal, then on BSD sed, then on bash 3.2

- Spec: [v1](spec.md) (approved 2026-11-03: PA-01 A, PA-02 A)
- Status: approved
- Branch: `main` (bootstrap mode, no other intent in progress)
- Approved: 2026-11-03, Jérôme Wacongne (engineer, product owner and tech lead, recorded once; the gate being ExitPlanMode in the drafting session)

## Context

A Developer on a Mac cannot start the shared stack at all: `up.sh` refuses on a name it cannot resolve (macOS has neither `getent` nor `powershell.exe`), then `env.sh` fails under BSD sed, then Apple's bash 3.2 breaks `local -A`. Each failure hides the next, and no message names a platform or a missing tool — about an hour of diagnosis on 2026-11-03. Intent 0055 makes macOS a third supported platform; spec v1 keeps one GNU userland (a Mac installs bash >= 4, GNU sed and coreutils; the scripts go on writing GNU) and asks for refusals that name what is missing, the documentation a Mac needs, and a measured verdict of the suite. PA-01 was decided **A** (the workstation carries the PATH, its limit documented) and PA-02 **A** (a full `--all` run on this Mac is the verdict).

## Files

| File | Change | For |
| --- | --- | --- |
| `up.sh` | modified: a `dscacheutil` branch in the resolution of `host.docker.internal` (already in the working tree); a prerequisite refusal before the resolution guard, naming bash >= 4 | RQ-01, RQ-02, RQ-03, AC-01, AC-02, AC-03, AC-04 |
| `env.sh` | modified: the two in-place edits in the form both seds accept (already in the working tree) | RQ-07, AC-06 |
| `tests/run.sh` | modified: a prerequisite refusal before its `uncovered` check and before the suite lock, naming bash >= 4, GNU `sed` and GNU coreutils | RQ-02, RQ-03, AC-05 |
| `tests/lib/stubs.sh` | modified: a `dscacheutil` stub (already in the working tree) | AC-02, AC-03 |
| `tests/0001-loopback-ports.sh` | modified: the `dscacheutil` branch's variant, and each branch run only where no earlier one's command is real (already in the working tree) | AC-02, AC-03 |
| `tests/0055-prerequisites.sh` | new: four parts, `refusals` (AC-04, AC-05), `sed` (AC-06), `trust` (AC-07), `docs` (AC-08, AC-09); its `# covers:` line declares `up.sh env.sh tests/run.sh certs/make-certs.sh README.md CLAUDE.md` | AC-04 … AC-09 |
| `certs/make-certs.sh` | modified: the CA's macOS trust command beside the Windows one, printed as unconditionally as that one | RQ-05, AC-07 |
| `README.md` | modified: macOS in the prerequisites (packages, install command, the PATH rule and the limit PA-01 records), and the suite's verdict on macOS | RQ-04, RQ-08, AC-08, AC-09 |
| `CLAUDE.md` | modified: the platforms line names macOS, and states the rule future scripts keep (they write GNU; a Mac brings the GNU userland) | RQ-06, AC-08 |
| `docs/intent/0055-stack-does-not-run-on-macos/plan.md` | new: this plan, then its `## Verification` section | bookkeeping |
| `docs/intent/0055-stack-does-not-run-on-macos/intent.md` | modified: status `planned` | bookkeeping |
| `docs/intent/README.md` | modified: the index row's status | bookkeeping |

## Order of work

Estimates: `step-durations.sh` answers `no measured step` on this repository, so every estimate below is **not measured**, by judgement, with the machine time named apart.

1. **The resolver branch and `env.sh`'s portable edits, already in the working tree** — skill: none — (code, not measured; machine 1 min) — check: `bash tests/0001-loopback-ports.sh resolution`.
   The four files are uncommitted from the unblocking of 2026-11-03 (`up.sh`, `tests/lib/stubs.sh`, `tests/0001-loopback-ports.sh`, and `env.sh` as the product owner wrote it). The step commits them as they are; their test is already green here (13 checks, the PowerShell branch skipped with its reason).

2. **The prerequisite refusals** — skill: none — (code, not measured; machine 2 min) — check: `bash tests/0055-prerequisites.sh refusals`.
   Detection is **behavioural**, not `command -v`, so that stubs prove it on every platform and a tool present under the wrong flavour is caught: bash by `${BASH_VERSINFO[0]}`, GNU `sed` by `sed --version` naming GNU (BSD sed has no `--version`), GNU coreutils by `stat -c %a` and `timeout --version` succeeding (macOS ships a `stat` without `-c` and no `timeout` at all). Each refusal names the tool, its minimum version where there is one, and what installs it — `brew install …` plus the PATH rule, without naming one installation prefix. A prerequisite that is present is silent.
   `up.sh`'s refusal sits before the resolution guard; `tests/run.sh`'s before its `uncovered` check (`tests/run.sh:84`) and before the suite lock, so a refused run takes nothing. Verified for this step: `/bin/bash -n` parses `up.sh`, `env.sh`, `registry.sh`, `tests/run.sh`, `register-app.sh` and `registration-account.sh` under bash 3.2, so the refusal is reached instead of a syntax error.

3. **The CA's trust command for macOS** — skill: none — (code, not measured; machine 1 min) — check: `bash tests/0055-prerequisites.sh trust`.
   `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <ca.crt>`, beside `certs/make-certs.sh:30`'s Windows line.

4. **The documentation** — skill: none — (docs, not measured; machine 1 min) — check: `bash tests/0055-prerequisites.sh docs`.
   `README.md`'s prerequisites (`README.md:121`) gain macOS and the PA-01 limit: the PATH rule lives in the Developer's interactive shell, so a non-interactive `zsh -c` has none of the GNU tools and meets step 2's refusal. `CLAUDE.md`'s "Scripts run under Git Bash on Windows and bash on Ubuntu" names macOS and the one-GNU-userland rule. The verdict's own assertion stays pending until step 6.

5. **The verdict's measurement** (PA-02's decision) — skill: none — (verification, not measured; machine 35 min at least, the first ever run on this platform) — check: the run's summary line.
   `bash tests/run.sh --all`, with the dev stack up and `TMPDIR=~/.cache/c4-infra-tests` (Docker Desktop shares neither `/tmp` nor `/private/tmp` by default, and the tests bind-mount their `mktemp` directories). Each failure is triaged, not patched blind: a one-line fix lands here; anything larger becomes its own bug intent, named under *Deviations*, as `tests/0050-preflight-locale.sh`'s SIGPIPE failure already is.

6. **The verdict in `README.md`** — skill: none — (docs, not measured; machine 1 min) — check: `bash tests/0055-prerequisites.sh docs`.
   What runs on macOS and what cannot, each with its reason and the platform to run it on, from step 5's actual output.

Closing, not a code step: `/sdlc-verify 0055` (bootstrap mode: one round, the bugs pass, no simplify pass, no security pass at standard risk), its evidence block pasted into this plan's `## Verification`, commit `plan: verification of 0055`, then the diff checked against this plan and pushed.

## Risks

- Step 5 finds macOS-only failures beyond `tests/0050`'s → the triage rule bounds this change: a one-liner here, its own bug intent otherwise. RQ-08 writes the run's actual outcome, never a promise.
- A refusal that fires on a machine that is fine would block every run → the `refusals` part checks the silent case too, and the detection being behavioural, Git Bash and Ubuntu keep passing it (their tools are GNU).
- Changing `tests/run.sh` makes every later run a full run (its own coverage rule) → that is PA-02's run anyway; `tests/0017-run.sh`, `tests/0022-lanes.sh` and `tests/0049-docker-preflight.sh` declare it and will run.
- AC-04's proof needs a bash older than 4, which only macOS has (`/bin/bash` 3.2.57) → the part runs `/bin/bash ./up.sh` where that bash is older than 4 and skips elsewhere with a printed reason, as `tests/0001`'s PowerShell branch does.
- `tests/0049-docker-preflight.sh:132` runs `timeout 300 bash "$repo/tests/run.sh"`: step 2's refusal must not fire inside it → it will not, the tools being present; and that very `timeout` is one of the coreutils calls the refusal now names.
- Two stand-in lanes need 10 GiB on Docker's VM; this one has 11.7 GiB, with no margin for another session's load → the run says which it uses, and step 5 reports it.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | command | `bash up.sh` on this Mac: exit 0, then `docker compose ps` all healthy and `curl -sk -o /dev/null -w '%{http_code} %{remote_ip}' https://host.docker.internal/` answering `200 127.0.0.1` |
| AC-02 | automated test | `tests/0001-loopback-ports.sh resolution`: each branch's `192.168.1.20` variant (stops, names the address, the hosts-file line, Docker Desktop's option, calls no docker) |
| AC-03 | automated test | `tests/0001-loopback-ports.sh resolution`: the `getent` branch's variants, and the printed skip naming why a later branch isn't reachable here |
| AC-04 | automated test | `tests/0055-prerequisites.sh refusals`: `/bin/bash ./up.sh` where `/bin/bash` is older than 4 — refusal naming bash and its minimum version, no `docker` call (its fake docker's log empty); skipped with its reason elsewhere |
| AC-05 | automated test | `tests/0055-prerequisites.sh refusals`: `tests/run.sh` with a stub `sed` without `--version`, then a stub `stat` rejecting `-c` and a stub `timeout` failing `--version` — a refusal naming the missing tool and what installs it, before any test and before the lock |
| AC-06 | automated test | `tests/0055-prerequisites.sh sed`: a `.env` holding `PROXY=`, `env.sh` run with `/usr/bin/sed` first on the PATH (or a BSD-like stub where there is none) — the line gone, no `.env.bak`, exit 0 |
| AC-07 | automated test | `tests/0055-prerequisites.sh trust`: `certs/make-certs.sh`'s creation path prints the macOS command as well as the Windows one |
| AC-08 | automated test | `tests/0055-prerequisites.sh docs`: `README.md` holds macOS's prerequisites, its install command, the PATH rule, its hosts file, its CA trust and the PA-01 limit; `CLAUDE.md` holds macOS and the one-GNU-userland rule |
| AC-09 | automated test + command | `tests/0055-prerequisites.sh docs` for the verdict section's presence and shape; the verdict itself from step 5's `bash tests/run.sh --all` output, pasted into this plan's `## Verification` |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

## Verification

<!-- filled at the end of the implementation: sdlc-verify's evidence block, as is -->
