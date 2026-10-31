# Intent: Five small defects that earlier intents left behind

- Author: Jérôme Wacongne (product owner, tech lead); drafted by the agent from the triage of the handover's older items
- Kind: bug
- Source: conversation (2026-10-30: the triage of `docs/intent/HANDOVER.md`'s "Follow-ups" and "Left open", validated by the product owner)
- Spec needed: yes
- Status: accepted
- Opened: 2026-10-30
- Decided: 2026-10-30
- Supersedes: —
- Mode: bootstrap

## Problem

Five defects, each found by an earlier intent's review or verifier and left out of its scope, each checked again on 2026-10-30:

- **The demo environment's guide** (0032): `docs/demo-setup.md` says the GitHub `demo` environment, the stack's and each application's, is restricted to the branch it deploys from, but its commands (`:125`, `:245`) create it without that restriction. The live environments are restricted (c4-infra's to `main`, Tickee's to `master`, read through GitHub's API): a Demo operator who follows the guide for a new application gives every branch of its repository the demo host's secrets.
- **The users' new ids** (0030): `new-realm-ids.sh` replaces the ids of an export in Keycloak's layout and in jq's alike, but lists the users' new ids, which the project must carry into its seed data, for Keycloak's layout only (`new-realm-ids.sh:25-27`): for an export jq formatted, it lists none and says nothing.
- **The hostile build fixtures** (0011): the header comments of the seven `tests/fixtures/0007/hostile/build-*.yml` give the reason each was refused before 0011, which refuses every `build` with one rule.
- **The stand-in's HTTPS wait** (0035): `stand_in_https` waits for Caddy with a `curl` that has no time limit (`tests/lib/stand-in-host.sh:285`): a connection that opens and stalls holds the test without end.
- **A check that passes on nothing** (0038, 0039): `tests/0029-image-facts.sh`'s "(c) no other preview or experimental feature is enabled" ignores `jq`'s status (`:114-115`) and says `ok` when it read nothing; the test fails anyway, through its other checks of the same file.

## Proposed outcome

The guide's commands give the `demo` environment the restriction its text promises; `new-realm-ids.sh` lists the users' new ids whatever the export's layout; each fixture's header gives the reason it is refused today; the stand-in's wait ends within its bound; the check fails when it can't read Keycloak's features.

Success criterion: each defect has a check that fails without its fix (the guide by reading and against the live environments' settings), and the suite passes with them.

## Affected users and systems

- Demo operator (the guide), Application (`new-realm-ids.sh`), Developer (the tests).
- Demo host (`docs/demo-setup.md`), registration (`new-realm-ids.sh`), the tests (`tests/fixtures/0007/`, `tests/lib/stand-in-host.sh`, `tests/0029-image-facts.sh`).

## Constraints

- A change of `tests/lib/` runs every test (CLAUDE.md, "Verification"): accepted at the triage.
- The live `demo` environments stay as they are: the guide is fixed, not GitHub's settings.

## Open questions

- None.
