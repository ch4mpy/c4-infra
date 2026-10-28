# Spec: tests/0007-dev.sh's isolation checks pass when the application's network doesn't exist

- Intent: [0034](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the networks, compose files and scripts that make the isolation don't change, only the verdict of the test that proves it gets stricter; the same question for 0023, which replaced this proof, was decided standard by the tech lead, 2026-10-28, its PA-03)
- Policies applied: none yet; standing constraints: CLAUDE.md "Verification" and the tests' conventions (`# covers:`, `LC_ALL=C sort`, bash and Git Bash, Faito registered as a prerequisite), 0023's RQ-03 (the dev isolation proven by name and by address)
- Approved: 2026-10-28, Jérôme Wacongne (product owner; in the drafting session; every point of attention decided)

## Summary

The negative checks of `tests/0007-dev.sh` (a container on `c4-infra.faito` can't reach Tickee's stand-in, by name and by address) pass only when the probe ran on that existing network and its connection failed; a missing network or image, or a Docker error, fails them, naming the cause. For the Developer: an `ok` of the suite again proves the dev isolation (0007 RQ-08, 0023 RQ-03). The checks it covers (PA-01) and what a missing Faito gives (PA-02) are the product owner's choices. The grep of the suite answers the intent's question.

## Requirements

- **RQ-01:** A negative reachability check of `tests/0007-dev.sh` passes only when its probe ran in a container started on the existing `c4-infra.faito` and failed to connect: by name, the name doesn't resolve or the connection is refused or times out; by address, the connection is refused or times out. (intent: proposed outcome)
- **RQ-02:** Any other failure fails the check, and its output names the cause: the network missing, the probe's image missing or not pulled, a Docker daemon error, the probe's command not found. (intent: proposed outcome, "naming the cause"; expected)
- **RQ-03:** `c4-infra.faito` missing (Faito not registered, the part `tickee` run alone) gives the verdict PA-02 decides, never an `ok` of an AC-07 negative check. (intent: steps, expected)
- **RQ-04:** The other negative checks PA-01 brings into scope pass only on the absence they assert: a failed docker command whose answer they read, or a model without the network they look into, fails them, naming it. (intent: open question)
- **RQ-05:** Where the isolation holds and the prerequisites are there, the test's verdict, parts, order, check labels and AC references are as today, and the other caller of `fails` (`:213`) keeps its meaning; the test runs under bash and Git Bash, sorts with `LC_ALL=C`, and its `# covers:` lines still cover what they cover. (intent: constraints)

## Out of scope

- The isolation itself (`networks.sh`, the compose files, the demo host): unchanged.
- The negative checks of the other tests, unless PA-01 takes them in; a helper in `tests/lib/` (a change there runs every test, CLAUDE.md "Verification"), unless PA-01 D.
- A suite-wide convention for negative checks (a CLAUDE.md line): PA-01's follow-up, its own change.

## Design

### Current behaviour

- `fails` (`tests/0007-dev.sh:94-100`) passes whenever its command exits non-zero, its output discarded; its comment reads "(a refused connection)". Its callers: `:180-181` (by name) and `:184-185` (by address), each `docker run --rm --network c4-infra.faito alpine:3 nc -z -w 3 <target> 7080`; and `:211-213`, `fails in_list host.docker.internal "$found"`, over `docker compose config`.
- The control `:178-179` runs the same image and command on `c4-infra.tickee`: a missing `alpine:3` or a daemon error makes it KO, so the test's verdict is KO for those. No positive check of the part `tickee` uses `c4-infra.faito`: without it, both negative checks pass (0023's plan, Verification, "Pre-existing findings").
- `:211-213` reads `.services["reverse-proxy"].networks["c4-infra.faito"].aliases // []` from the dev model: a failed `docker compose config`, or a model without `c4-infra.faito` (`compose.apps.yml` lists the labelled networks that exist, `networks.sh:14-17`, `:52`), gives an empty value, and the check passes.
- A full run (`tests/run.sh:191`, no argument: every part, in order) registers Faito in the part `networks` first (`:140-141`), a failed registration being a KO; `bash tests/0007-dev.sh tickee` alone, Faito not registered, passes both checks without proving anything. The part creates Tickee's network when it's missing and removes it at the end (`:44-47`, `:159`); nothing of the kind for `c4-infra.faito`.
- CLAUDE.md "Verification" lists Faito registered among the suite's prerequisites; the stand-in isolation test stops, KO, when its probe image is missing (`tests/0007-isolation.stand-in.sh:197-199`): the suite's precedent for a missing prerequisite.
- `docker run` exits 125 for an error of Docker's own (network not found, image not pulled, daemon), 126 or 127 when the command can't be run, the command's status otherwise (Docker CLI reference, `docker container run`, exit status); busybox `nc -z` exits 1 when it can't resolve or connect. Not measured at draft (no Docker): AC-02 and AC-04 measure it.

### Behaviour per persona

- **Developer**: `bash tests/run.sh --changed --all`, or `bash tests/0007-dev.sh [tickee]`: an `ok` of an AC-07 negative check means the connection failed from `c4-infra.faito`; a missing network or image, or a Docker error, is a KO naming it; a missing Faito gives PA-02's verdict.

### API and contracts

- The checks keep their labels (`AC-07: from c4-infra.faito, <target>:7080 can't be reached [by name]`); a KO prints its cause under it (`check`, `tests/lib/assert.sh:18-28`): Docker's message, or the probe's.
- The test exits 1 when a check fails (`finish`), as today.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| CLAUDE.md: scripts under bash and Git Bash, `LC_ALL=C sort` | RQ-05 |
| CLAUDE.md: each test declares what it covers | RQ-05; a new file comes with its `# covers:` |
| CLAUDE.md: a `tests/lib/` change runs every test | Out of scope, unless PA-01 D |
| 0023 RQ-03: the dev isolation proven by name and by address | RQ-01 |

## Points of attention

### PA-01: Which negative checks the fix covers

- Issue: the grep (Intent questions) finds the intent's pattern, a reachability check that takes any failure for "can't be reached", in three tests, unguarded in `tests/0007-dev.sh` only; and a wider family, 29 absence or refusal checks in 16 tests that take a failed docker, stand-in or ssh command for the absence they assert, 18 of them beside a positive check on the same container or command.
- Options: A) `tests/0007-dev.sh:181` and `:185` only / B) every negative check of `tests/0007-dev.sh`: A, plus `:187` (the stand-in removed: a failed `docker ps` reads as none) and `:213` (no alias: a failed `docker compose config`, or Faito's network missing, reads as none) / C) B, plus the reachability checks of the stand-in tests (`0007-isolation.stand-in.sh:121-127`, `0002-accounts.stand-in.sh:283`) / D) C, plus the whole family, through a helper in `tests/lib/`.
- Recommendation: B: the file the intent names, the same flaw (`:213` passes for the very cause of the intent, Faito's network missing), one test to rerun. C's checks are guarded today (the container must run, a positive check from it with the same tool), their residue a `docker exec` or ssh error, in slow stand-in tests; D is a convention rather than a bug: a line in CLAUDE.md's tests' conventions ("a negative check accepts only the failure it expects, or follows a positive check on the same path"), in its own change, and its own intent if the existing checks are to change.
- Decides: PO
- Decision: B, as recommended — Jérôme Wacongne (product owner), 2026-10-28

### PA-02: `c4-infra.faito` missing when the part `tickee` runs

- Issue: CLAUDE.md lists Faito registered as a prerequisite; the part `tickee` alone neither checks it nor creates Faito's network, as it does Tickee's.
- Options: A) a KO naming the missing network and what creates it (`bash register-app.sh --app faito`, or `../faito/deploy-dev.sh`), the test exiting 1 / B) the part skipped with a message, the test passing / C) the part registers Faito's network itself when it's missing, as the part `networks` does, and removes it at the end when it created it, as it does Tickee's.
- Recommendation: A: the intent's expected result, and the suite's precedent for a missing prerequisite (`0007-isolation.stand-in.sh:197-199`); B is the `ok` without a proof the intent removes; C hides a prerequisite the rest of the suite needs too, and changes a developer's stack from a part run alone.
- Decides: PO
- Decision: A, as recommended — Jérôme Wacongne (product owner), 2026-10-28

## Acceptance criteria

- **AC-01:** Given the dev stack running and Faito registered, when `bash tests/0007-dev.sh` runs, then every check passes, both AC-07 negative checks among them, with today's labels. (RQ-01, RQ-05)
- **AC-02:** Given a copy of the test whose negative checks name a network that doesn't exist (`c4-infra.no-such-app`), when its part `tickee` runs, then both negative checks KO, each naming the missing network, and the test exits 1. (RQ-02)
- **AC-03:** Given Faito not registered (no `c4-infra.faito`), when `bash tests/0007-dev.sh tickee` runs, then the verdict is PA-02's, and no AC-07 negative check prints `ok`. (RQ-03)
- **AC-04:** Given a copy of the test whose probe image is a tag that doesn't exist, when its part `tickee` runs, then the negative checks KO naming the image, besides the control. (RQ-02)
- **AC-05:** Given the stand-in attached to `c4-infra.faito` too (0023's mutation), when the part `tickee` runs, then both negative checks KO, saying the connection succeeded. (RQ-01)
- **AC-06:** Given PA-01 B or wider, when the docker command a negative check in scope reads fails, or its model lacks the network it looks into (a copy of the test, a fake docker on `PATH`), then that check KOs naming it. (RQ-04)
- **AC-07:** Given the change, when `bash tests/run.sh --changed --all` runs with the stack up, then it passes and reports no uncovered script; the run under Git Bash is the plan's to report. (RQ-05)

## Intent questions

- Whether other tests share the same `fails` pattern → yes. Grep of `tests/*.sh` and `tests/lib/*.sh` on `62ef9b2` (2026-10-28) for `fails`, `! docker|curl|nc|stand_in_exec`, `refused`, `unreachable`, `eval '! …'`, `bash -c '! …'`, `test -z "$(docker …)"`, `-ne 0`; each hit read in context. `tests/lib/` holds none. → PA-01.

  Reachability checks (the intent's pattern):

  | Site | A missing network, container or image passes it? |
  | --- | --- |
  | `0007-dev.sh:180-181`, `:184-185` | yes, `c4-infra.faito` missing; image or daemon: no, the control `:178-179` KOs |
  | `0007-isolation.stand-in.sh:121-127` (`unreachable`, called `:235`, `:236`, `:240`, `:245`, `:266`) | no: `faito.gateway` must run (`:122`), on `c4-infra.faito` (`:224`); no probe stops the test (`:197-199`); its `nc` answers `reachable` from the same container (`:186`, `:190`); left: a `docker exec` error after `running` |
  | `0002-accounts.stand-in.sh:282-284` (curl over ssh as `faito`, the host's firewall, no Docker network) | no: control `:280-281`, same curl and address, as `c4-infra`; left: an ssh failure as `faito` (exit 255) |

  Absence or refusal checks that read a failed docker, stand-in or ssh command as the absence they assert:
  - no positive check on the same container or command (11): `0007-dev.sh:187`, `:211-213` (Faito's network missing too); `0002-accounts.stand-in.sh:218-219` (a missing `c4-infra.rabbitmq` passes it), `:274`; `0007-compose-check.stand-in.sh:89-93`, `:94-96`; `0011-demo-host.stand-in.sh:86`, `:87`, `:118-119`; `0012-themes.stand-in.sh:51-53`; `0027-backup.stand-in.sh:173`;
  - beside one (18): `0002-accounts.stand-in.sh:287-288` (`:289-290`); `0003-caddy-config.sh:70`, `:72` (`:55-56`, `:61`, `:66`, same image); `0006-account.sh:262-263` (`:176-177`, same container); `0006-bootstrap-admin-replaced.stand-in.sh:158` (`:156-157`); `0010-brute-force.sh:115` (`:107`, `:117`); `0011-demo-host.stand-in.sh:114`, `:115` (`:116-117`); `0011-facts.sh:62`, `:94` (`:58`, `:90`); `0013-delegation.sh:124-125`, `:161-162` (`:122`, `:155`); `0013-keycloak-facts.sh:102-106`, `:121-124` (its `fetched` checks, same throwaway); `0015-headers.sh:192` (`:191`); `0024-db-image-change.stand-in.sh:67`, `:78-79` (`:66`, `:77`, same logs); `0027-backup-facts.stand-in.sh:200-201` (`:199`);
  - not concerned (the failure's message or status is checked, the failure is the fact itself, or docker is a fake): every `refused_with`, every `refused` paired with `says`, `0009-master-realm.sh:151-160`, `0016-realms.sh:131-153`, `0016-keycloak-facts.sh:138-142`, `0011-facts.sh:97`, `0003-up-reload.sh`, `0011-up.sh`, `0002-register-scope.sh`.

## Change log

- v1 — 2026-10-28 — first version; the intent's "Spec needed" set to yes in this spec's commit: the product owner asked for a spec (2026-10-28)
- v1 — 2026-10-28 — approved by the product owner in the drafting session: PA-01 B, PA-02 A, as recommended.
