# Plan: The stack still documents and tests an LDAP user federation no application needs

- Spec: [v2](spec.md)
- Status: approved
- Branch: 0023-ldap-leaves-the-stack
- Approved: 2026-10-28, Jérôme Wacongne (engineer; standard risk)

## Starting point

Spec v1 (approved 2026-10-28): LDAP leaves the stack, which provides, runs and monitors no directory; a realm may still federate its users with a directory its application runs and maintains itself, on its own network (PA-01; Tickee's `tenant2` keeps its `ldap2`, Tickee's); 0007's AC-07 proven with an HTTP stand-in (PA-02 A); risk standard (PA-03 B).

Facts read (2026-10-28):
- `README.md:81-83`, `docs/migration.md:120`, `:145`, `:278-284`: the only mentions of an LDAP server or a user federation in the docs (`:99`'s `federatedIdentities` is another subject).
- `tests/0007-dev.sh:13-16` (the header of part `tickee`) and `:157-185` (the part): the LDAP stand-in, Keycloak's `testLDAPConnection`, the control and the two negative checks; `fails` (`:95`) and `holds_shared` (`:82`) are reused.
- `tests/0007-isolation.stand-in.sh:161-163`: Keycloak's reach of a container, `exec 3<>/dev/tcp/<host>/<port>` in Keycloak's container (bash is in its image).
- `caddy:2.11.4-alpine`, the stack's Caddy, is on the workstation; `caddy respond --listen :7080 <text>` answers at once (the probe image of 0007 uses it).

## Engineer's choices

- The stand-in: `caddy:2.11.4-alpine` running `caddy respond --listen :7080 <its name>`, as `tickee.network-standin` (v2; `tickee.gateway-standin` at first) on `c4-infra.tickee` (a name no real Tickee container takes); Keycloak's reach retried for 30 s at most while it starts.
- No new test: the part `tickee` of `tests/0007-dev.sh` changes in place; its checks keep their places and their AC-07 label.

## Files

| File | Change | For |
| --- | --- | --- |
| `README.md` | modified: "One network per application": the example becomes a directory the application runs itself (Tickee's `ldap2`; v2: in dev the gateways run on the host); one sentence: a realm may federate its users with a directory the application provides itself (its container, or one outside the stack), the stack providing none | RQ-01, RQ-04, AC-01 |
| `docs/migration.md` | modified: the workstation step (`:120`) names the containers the shared services reach in dev (a directory a realm federates; v2: the gateway runs on the host) as the project's own, which it maintains; `:145`'s list without "an LDAP server"; Tickee's section: `ldap2` is Tickee's own container on `c4-infra.tickee`, which Tickee runs, monitors and upgrades; its demo line likewise | RQ-02, AC-01 |
| `tests/0007-dev.sh` | modified: the header of part `tickee`, and the part: the HTTP stand-in instead of the LDAP one; Keycloak reaches it (`/dev/tcp`); the control from `c4-infra.tickee`; the two negative checks from `c4-infra.faito`, on port 7080; the stand-in removed | RQ-03, RQ-05, AC-02 |
| `docs/intent/0023-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status planned, then delivered; the index row | — |

## Order of work

0. **Setup**: on the branch (`main` merged at the spec), the dev stack up, Faito registered. — skill: none — check: `git status --short` empty; `docker ps` shows `c4-infra.keycloak` healthy.
1. **The test**: part `tickee` with the HTTP stand-in. — skill: none — check: `bash tests/0007-dev.sh tickee` five runs out of five `every check passed`; mutations: the stand-in on `c4-infra.faito` instead → the two negative checks `KO`; on a network of its own, which Keycloak isn't on → the reach and the control `KO`. Commit `feat(0023): …`.
2. **The docs**: README and the migration guide. — skill: none — check: `git grep -n -i 'ldap\|federat' README.md docs/migration.md`, every line reread against AC-01. Commit `docs(0023): …`.
3. **Verification**: `git grep -n -i ldap -- . ':!docs/intent'` (AC-03); `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` (the tests that declare `README.md`, `docs/migration.md` or `tests/0007-dev.sh`); `/sdlc-verify 0023` (bootstrap: one round), its evidence into `## Verification`. — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0023`, merged into `main` without a push: the milestone (with 0020) runs a full `--all` first.

## Risks

- A real Tickee container named like the stand-in → `tickee.gateway-standin` isn't one of Tickee's names; the part removes it before and after.
- Keycloak's image loses bash → `0007-isolation.stand-in` would fail too; the check says so.
- A negative check passing because the stand-in isn't up yet → the reach and the control pass first, in the same part, before the negative checks.
- The docs still read as if the stack ran a directory → AC-01's reread, line by line.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | command + review | `git grep -n -i 'ldap\|federat' README.md docs/migration.md`: README's example is a directory the application runs (v2) and its federation sentence; the guide's workstation step and Tickee's `ldap2` as Tickee's; reread |
| AC-02 | automated test + mutation check | `bash tests/0007-dev.sh tickee` five times; step 1's two mutations; `grep -c osixia tests/0007-dev.sh` → 0 |
| AC-03 | command | `git grep -n -i ldap -- . ':!docs/intent'`: README's and the guide's lines only |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-28 — the bug review: in dev, the gateways run on the host (`compose.dev.yml:35`, `docs/migration.md:87`), so the README's and the guide's example (a gateway) and the stand-in's name and label (`tickee.gateway-standin`, "as back-channel logout does") were wrong for dev. Spec v2 (product owner, the same day): the example is a directory the application provides itself (Tickee's `ldap2`, or one outside the stack), the stand-in `tickee.network-standin`, a container of Tickee's; the reach check shows docker's last error and uses `KC_CONTAINER`. Mutations run again: on a network of its own, `KO - AC-07: Keycloak reaches …`, `no answer in 30 s: bash: line 1: tickee.network-standin: System error`. Impact: AC-01 and AC-02 as in spec v2.

## Verification

### Verification — 38ff282

- Verification command: `LC_ALL=C TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` → `verification passed (--changed: 4 of 45 tests)` (2026-10-28, on 0aeeccf, which adds only `plan.md` to 38ff282; `total: 185.2 s for 4 test(s)`: `0002-workflow`, `0004-registry`, `0007-dev`, `0002-accounts.stand-in`, the tests that declare `README.md`, `docs/migration.md` or `tests/0007-dev.sh`); the full `--all` comes at the milestone with 0020 (CLAUDE.md), before `main` is pushed
- Risk tier: standard (spec, PA-03)
- Reviews: bootstrap mode: 1 round; bugs (`code-review`, high): 9 findings, 4 fixed in 38ff282 (and spec v2), 5 answered; no security pass (standard risk), no quality pass (bootstrap mode)
  - fixed: in dev the gateways run on the host (`compose.dev.yml:35`, `docs/migration.md:87`), so README's and the guide's example (a gateway) and the stand-in's name and label were wrong for dev (spec v2: a directory the application provides itself; `tickee.network-standin`, a container of Tickee's); README's sentence ruled out a directory outside the stack (now "or one outside the stack"); the reach check hid docker's error (shown) and named Keycloak's container itself (`KC_CONTAINER`)
  - answered: `/dev/tcp` from Keycloak's container checks the network topology, not Keycloak's JVM (PA-02, as `0007-isolation.stand-in` does); the same probe in two tests rather than `tests/lib/` (a `tests/lib/` change runs every test); the intent's title and outcome not updated after PA-01 (an accepted intent isn't rewritten; the departure is recorded in PA-01)
- Mutation checks: the stand-in on `c4-infra.faito` → `KO - control: from c4-infra.tickee, …`, both negative checks `KO` (`3 check(s) failed`, the verifier's copy too); on a network of its own → `KO - AC-07: Keycloak reaches …` (`no answer in 30 s: bash: line 1: tickee.network-standin: System error`) and the control `KO`
- Verifier: 3/3 criteria OK, 0 KO (its five runs of the part `tickee`: `every check passed`; its mutations: as above, and `--listen :7081` → the reach and the control `KO`)
  - answered: it read CLAUDE.md's proof as `--all`; the branch's `CLAUDE.md:15` says `bash tests/run.sh --changed --all` (the product owner, 2026-10-28)
  - the plan's Files and Proof rows written for v1, updated in this commit
- Not verifiable here: the reach check under Git Bash (`MSYS_NO_PATHCONV=1` kept; Linux only here); the demo-host side of the docs (Tickee isn't deployed there)
- Files outside the plan: none (`spec.md` is the change's spec)
- Pre-existing findings (not fixed, out of scope): `fails` in `tests/0007-dev.sh` takes docker's "network not found" for "can't be reached", so the negative checks pass when `c4-infra.faito` doesn't exist (the part `tickee` run alone where Faito isn't registered; in the suite, the part `networks` registers Faito first) → bug intent suggested

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK | `README.md:82-87`: "in dev, where the gateways run on the host, those the shared services must reach, such as a directory its realm federates: Tickee's `ldap2`", "The stack provides, runs and monitors no directory: … a directory its application provides itself, one of its containers on that network, which it maintains, or one outside the stack"; `docs/migration.md:119-121` (workstation step), `:146` (demo step: the gateway kept), `:279-284` (Tickee's own LDAP server, Tickee runs, monitors and upgrades it), `:287` |
| AC-02 | OK | `tests/0007-dev.sh` in the run above: `ok - AC-07: Keycloak reaches tickee.network-standin:7080, a container on Tickee's network`, `ok - AC-07: from c4-infra.faito, tickee.network-standin:7080 can't be reached by name`, `ok - AC-07: from c4-infra.faito, <address>:7080 can't be reached`; the mutations above; `grep -c osixia tests/0007-dev.sh` → 0 |
| AC-03 | OK | `git grep -n -i ldap -- . ':!docs/intent'` → `README.md:84` and `docs/migration.md:279`, `:280`, `:287` (Tickee's own directory), `tests/0007-dev.sh:13` (the comment "without LDAP since 0023"): nothing starts, configures or depends on an LDAP server |

