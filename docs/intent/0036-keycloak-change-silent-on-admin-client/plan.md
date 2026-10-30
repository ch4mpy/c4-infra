# Plan: A change of the stack's Keycloak doesn't say that an application's generated admin client moves with it

- Spec: none ([intent 0036](intent.md), "Spec needed: no")
- Status: approved
- Branch: 0036-keycloak-change-silent-on-admin-client
- Approved: 2026-10-29, Jérôme Wacongne (engineer, also PO and tech lead; in the session, the open question and the first entry decided as recommended)

## Starting point

Read on 2026-10-29, `main` at 8f0a090; the branch `origin/0036-…` is at 66b6674 (the intent and its index row, on top of 3f66abe). `main` is one commit ahead (0037's intent and index row): the merge of step 0 conflicts on the index's last rows.

- **README, "Keycloak in an application's tests"** (`README.md:471-520`): the bullet "**A change**" (`:512-514`) says the description shows a change and the changelog says what it asks; nothing on an admin client. The changelog (`:516-520`) has one entry, `2026-10-28 — \`26.8.1-33909cd89858\``: first published, "Asks nothing of an application already on 26.8.1 with these features."
- **`tests/0029-description.sh`** already reads that section (`section()`, `:131-133`) and checks (f) a dated entry for the current tag (`changelog_entry()`, `:134-136`, with a copy without it: named) and (g) the names the section holds (`:169-172`). It covers `README.md` (`:24`). Its pattern for a refusal on a copy is `refused_naming` (`:137-140`); copies go in `$work`.
- **What the skills do** (their intent 0111, spec approved 2026-10-29, not implemented): `create-spring-rest-api` ships Keycloak 26.7.2's admin API description today; after 0111 a generated build fetches `org.keycloak:keycloak-api-docs-dist:<KC_VERSION>` by the project's pin. Either way the client is generated for one version. 0111's PA-01 C puts this line in c4-infra (spec `:53`).
- **26.7.2 → 26.8.1, for the client** (0111's spec `:42`, measured there): two operations added (`PUT …/organizations/{org-id}/identity-providers/{alias}`, `PUT …/members/{member-id}/membership-type`); the organizations' list and count (`identityProvider`), an organization group by path (`briefRepresentation`) and the invitation (`client_id`) take a new optional parameter; `IdentityProviderRepresentation` gains `organizationLinks`, its `organizationId` becomes write-only and deprecated; `OrganizationDomainRepresentation` gains `identityProviderAlias` and `autoRedirect`; a role's groups are read as `GroupRepresentation`. No operation removed. Tickee hit the `organizationLinks` one on 2026-10-28.
- **Tests that cover `README.md`**: 0004-registry, 0016-no-real-provider, 0027-docs, 0029-description, 0032-demo-github-only, 0033-docs; no stand-in test. The demo workflow ignores `**/*.md` only (`.github/workflows/deploy-demo.yml:9-11`): the change of `tests/0029-description.sh` triggers it, a redeployment of the same files.

## Decisions (PO, 2026-10-29, in the session)

- The intent's open question: `tests/0029-description.sh` checks the convention (h), on the entries of a version change only (an entry whose version differs from the entry below it, or the oldest one, the first publication).
- The first entry names the 26.7.2 → 26.8.1 differences for a generated client, not only "unchanged".

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0029-description.sh` | modified: (h) in the header; `entries()` (one line per changelog entry: its tag, its text joined, no awk interval expression for mawk), `admin_client_named()` (each version change's entry holds `Generated admin client:`, else `<tag>: a version change whose entry doesn't name the generated admin client`), `change_bullet()` (the "**A change**" bullet's text); checks: the bullet names the generated admin client; every version change's entry names it; copies: an entry of another version without it, named; an entry of the same version without it, passes | success criterion (both parts) |
| `README.md` | modified: the "**A change**" bullet (an application that generates its Keycloak admin client from the admin API's description, as the skills' `create-spring-rest-api` does, gets another client with each version: moving to it regenerates the client, the application rebuilds and follows its changed signatures and fields, a call that passes arguments by position first; each version change's entry says what changes for it, `Generated admin client: …`, or `unchanged`; `tests/0029-description.sh` refuses one without it); the changelog's lead-in names the convention; the first entry's `Generated admin client:` sentence (from 26.7.2, the differences above) | success criterion |
| `docs/intent/0036-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan, then its *Deviations* and `## Verification`; status `planned`, then `delivered`; the index row | — |

Unchanged on purpose (the intent's constraints): `keycloak/`, `keycloak-image.properties`, the image; `docs/migration.md` (it points to the section, `:136`).

## Order of work

**Bootstrap mode** (the intent's `Mode`): no PR, one `sdlc-verify` round, pushes without confirmation; the work stays on the intent's branch (0035 was in progress when 0036 opened). If the PO batches it with 0035, the batch's integration run replaces step 3's run.

0. **Setup.** — skill: none — check: `git status --short` empty after the merge; `grep -c '^| 003[4-7] ' docs/intent/README.md` gives 3 (0034, 0036, 0037).
   - `git switch -c 0036-keycloak-change-silent-on-admin-client --track origin/0036-keycloak-change-silent-on-admin-client` (no local branch yet), `git merge origin/main`: the index's conflict resolved by keeping both rows, 0036 then 0037.
   - `plan.md` written from this plan (status approved), the intent's status `planned`, its index row; commit `plan: A change of the stack's Keycloak doesn't say that an application's generated admin client moves with it`; push.
1. **The check, before the README says it.** — skill: none — check: `bash tests/0029-description.sh` exits 1, its only KO lines the bullet's check and `26.8.1-33909cd89858: a version change whose entry doesn't name the generated admin client`; the two copies' checks `ok` (the same-version copy passes, the other-version copy is named). The KO lines go under *Deviations*.
   - Commit `test(0036): each version change's changelog entry names the generated admin client`.
2. **The README.** — skill: none — check: `bash tests/0029-description.sh` ends `every check passed`; `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed HEAD` passes.
   - The first entry's differences rechecked before writing: keycloak.org's `docs-api/26.7.2/rest-api/openapi.json` and `docs-api/26.8.1/…` fetched into a `mktemp -d`, compared with `jq` (operations and their parameters' names; the properties of `IdentityProviderRepresentation`, `OrganizationDomainRepresentation`); a difference from 0111's list is a deviation (the entry says what is measured). The commands and their lines under *Deviations*.
   - The wording holds today and after 0111 (the client is generated for one version in both): no claim about the pin's mechanism.
   - Commit `feat(0036): the README tells an application that its generated admin client moves with Keycloak's version`.
3. **Verification.** — skill: sdlc-verify — check: `verification passed`.
   - `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`, with the dev stack running: the six tests that cover `README.md` (no stand-in one).
   - `git diff --stat origin/main...HEAD -- keycloak/ keycloak-image.properties .github/ docs/migration.md` prints nothing.
   - `/sdlc-verify 0036`: bootstrap, standard risk (no authentication, secret or isolation touched: documentation and a test): one round, the bugs pass. Its evidence block into `## Verification`, commit `plan: verification of 0036`, push.
4. **Delivery.** — skill: sdlc-ship — check: `/sdlc-ship 0036`; the push's deploy-demo run succeeds (the same files, the Keycloak image's tag unchanged: `keycloak/` untouched). Recorded under `### After deployment`.

## Risks

- The parser of (h) misreads an entry (wrapped lines, the em dash, mawk on Ubuntu) and passes on nothing → the check also counts the entries read and fails on zero; the copies prove a KO and a pass; no interval expression in awk.
- The README describes the skills' mechanism ahead of 0111's implementation → wording on "a client generated for one version", true before and after 0111; no `keycloak-api-docs-dist` claim beyond "as the skills generate it".
- The first entry's differences copied from another repository's spec could be wrong → rechecked at step 2 from keycloak.org's two descriptions, the measure under *Deviations*.
- A future same-version entry (themes, features) asked for the sentence by mistake → the must-not-fire copy (same version, no sentence: passes).
- The merge of `origin/main` conflicts again at delivery if 0035 lands first (its index row) → resolved by keeping every row in number order.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| Success criterion, part 1: the README says it in the section | automated test | `tests/0029-description.sh`, "(h) the bullet on a change names the generated admin client"; failing at step 1, passing at step 2 |
| Success criterion, part 2: the convention asks each version change's entry to name what changes (or that nothing does) | automated test | `tests/0029-description.sh`, "(h) each version change's entry names the generated admin client", its copies "(h) an entry of another version without it: named" and "(h) an entry of the same version without it: passes"; step 1's KO on the real README |
| The first entry's differences are Keycloak's | command | step 2's `jq` comparison of keycloak.org's 26.7.2 and 26.8.1 descriptions, under *Deviations* |
| Constraint: the image, `keycloak/` and `keycloak-image.properties` unchanged | command | step 3's `git diff --stat … -- keycloak/ keycloak-image.properties .github/ docs/migration.md` empty; (c) to (e) of `tests/0029-description.sh` pass |
| No regression | command | `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`, `verification passed` |

## Deviations

- 2026-10-29 — step 0: `git merge origin/main` didn't conflict, git kept both index rows (0036, then 0037) — no impact.
- 2026-10-29 — step 1, `TMPDIR=~/.cache/c4-infra-tests bash tests/0029-description.sh` before the README changes, exit 1, as planned: `KO - (h) the bullet on a change names the generated admin client`; `KO - (h) each version change's entry names the generated admin client` / `26.8.1-33909cd89858: a version change whose entry doesn't name the generated admin client`; `ok - (h) an entry of another version without it: named`; `ok - (h) an entry of the same version without it: not named`.
- 2026-10-29 — step 1, pre-existing, not this change's: under Git Bash on the Windows workstation, `KO - (a) the description's lines are comments or KEY=value, no CR`, every line listed. `main` (8f0a090, a detached worktree) fails it the same way. Cause: Git Bash's bash drops the CR of `$'\r'` written inside `$(…)` (`form()`, `tests/0029-description.sh:42`), so `grep -n ''` lists every line; `cr=$'\r'` built outside the substitution gives 0 lines, and Linux's grep gives 0 lines on the same file (`ubuntu:24.04`). Not fixed here (another bug, outside this plan's files' scope): reported first in the verification, and a bug intent for the morning. Impact: the verification's run shows this KO on the Windows workstation.

## Verification
