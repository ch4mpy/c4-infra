# Plan: The stack still documents and tests an LDAP user federation no application needs

- Spec: [v1](spec.md)
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

- The stand-in: `caddy:2.11.4-alpine` running `caddy respond --listen :7080 tickee.gateway-standin`, as `tickee.gateway-standin` on `c4-infra.tickee` (a name no real Tickee container takes); Keycloak's reach retried for 30 s at most while it starts.
- No new test: the part `tickee` of `tests/0007-dev.sh` changes in place; its checks keep their places and their AC-07 label.

## Files

| File | Change | For |
| --- | --- | --- |
| `README.md` | modified: "One network per application": the example becomes an application's gateway (Keycloak's back-channel logout); one sentence: a realm may federate its users with a directory the application runs and maintains itself on its network, the stack providing none | RQ-01, RQ-04, AC-01 |
| `docs/migration.md` | modified: the generic step (`:120`) names the containers the shared services reach (a gateway, a directory a realm federates) as the project's own, which it maintains; `:145`'s list without "an LDAP server"; Tickee's section: `ldap2` is Tickee's own container on `c4-infra.tickee`, which Tickee runs, monitors and upgrades; its demo line likewise | RQ-02, AC-01 |
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
| AC-01 | command + review | `git grep -n -i 'ldap\|federat' README.md docs/migration.md`: README's example is a gateway and its federation sentence; the guide's generic step and Tickee's `ldap2` as Tickee's; reread |
| AC-02 | automated test + mutation check | `bash tests/0007-dev.sh tickee` five times; step 1's two mutations; `grep -c osixia tests/0007-dev.sh` → 0 |
| AC-03 | command | `git grep -n -i ldap -- . ':!docs/intent'`: README's and the guide's lines only |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
