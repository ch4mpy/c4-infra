# Spec: Five small defects that earlier intents left behind

- Intent: [0047](intent.md)
- Status: approved
- Version: 1
- Risk: high (secrets: the `demo` environment's branch restriction decides which branches get the demo host's secrets; the rest is standard)
- Policies applied: none (the project has none yet)
- Approved: 2026-10-30, Jérôme Wacongne (product owner, also tech lead), in the drafting session; every point of attention decided

## Summary

The demo setup guide's commands give each `demo` environment the branch restriction its text promises; `new-realm-ids.sh` lists the users' new ids whatever the export's layout; the hostile build fixtures say why they are refused today; the stand-in's HTTPS wait is bounded; Keycloak's features check fails when it reads nothing.

## Requirements

- **RQ-01:** The guide's commands create the stack's `demo` environment and an application's restricted to the one branch each deploys from (`main` for the stack, the application's own for an application), so that a workflow run from another branch gets none of its secrets; the guide also says how to read the restriction back. (intent: the demo environment's guide)
- **RQ-02:** `new-realm-ids.sh` lists `user <name>: <old id> -> <new id>` for every user of the export's `users`, in Keycloak's layout as in jq's; a file it can't read as JSON is left as it was, named, and the script exits 1, as for an id it can't renew. (intent: the users' new ids)
- **RQ-03:** Each `tests/fixtures/0007/hostile/build-*.yml` header says what the fixture holds and that it is refused because it builds, as every build since 0011, before any container starts. (intent: the hostile build fixtures)
- **RQ-04:** Each attempt of `stand_in_https`'s wait for Caddy is bounded in time, so that the whole wait ends within its bound even when a connection opens and stalls; what the wait does once Caddy answers is unchanged. (intent: the stand-in's HTTPS wait)
- **RQ-05:** `tests/0029-image-facts.sh`'s "(c) no other preview or experimental feature is enabled" fails, saying why, when it can't read Keycloak's features from the server's information. (intent: a check that passes on nothing)

## Out of scope

- The live `demo` environments' settings (already restricted, read on 2026-10-30): the guide changes, not GitHub.
- The items the triage refused (`docs/intent/HANDOVER.md`, "Refused").

## Design

### Current behaviour

- `docs/demo-setup.md:125` and `:245`: `gh api -X PUT repos/$R/environments/demo` (and `$A`), no body: no branch restriction; `:239-240` says the application's environment is "restricted to the branch it deploys from". The live ones (GitHub's API, 2026-10-30): `deployment_branch_policy` `{"custom_branch_policies":true,"protected_branches":false}`, branch policies `["main"]` (c4-infra) and `["master"]` (Tickee). GitHub's API (documentation read 2026-10-30): `PUT /repos/{owner}/{repo}/environments/{name}` takes `deployment_branch_policy` `{protected_branches: false, custom_branch_policies: true}`, then `POST …/deployment-branch-policies` `{name: <branch>}` adds the branch (404 while `custom_branch_policies` is false, 303 when the pattern exists).
- `new-realm-ids.sh:25-27`: the users are found by `grep` on `^    "id" : "<uuid>",$` followed by `"username"`, Keycloak's layout; the ids are found in both layouts (`:29`), so a jq-formatted export gets new ids and an empty list.
- `tests/fixtures/0007/hostile/build-*.yml:1-4`: "a build whose dockerfile climbs out of the context…, which sudo c4-app up refuses", "a build with network: host, which…": the reasons before 0011; since 0011, `demo/c4-app` refuses any `build` with one rule (0011's `plan.md`, *Files*), which `tests/0007-compose-check.stand-in.sh` expects for all seven.
- `tests/lib/stand-in-host.sh:283-289`: `until curl -s -o /dev/null … "https://$host/"`, retried on exit 7 or 35 up to 75 times, 0.2 s apart; no `--max-time`.
- `tests/0029-image-facts.sh:114-115`: `other=$(jq … < serverinfo.json | sort | comm -23 - <(features))`: the pipeline's status is `comm`'s, so a `jq` failure leaves `$other` empty and the check `ok`.

### API and contracts

- `new-realm-ids.sh`'s output gains no new kind of line: `user <name>: <old> -> <new>` as today, for every layout. It reads the export with `jq` (README's prerequisites already list it).

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy yet; CLAUDE.md's Git Bash rules (native `jq` fed on standard input) → RQ-02 |

## Points of attention

### PA-01: How to prove the guide's commands

- Issue: RQ-01's commands act on GitHub; running them creates or changes an environment.
- Options: **A** reading only, against GitHub's documentation and the live environments' settings / **B** A, plus running the stack's command against c4-infra's own `demo` environment, which already holds that restriction: a no-op whose settings are read before and after (the branch policy's `POST` answers 303, the pattern existing) / **C** a throwaway repository created for the proof, then deleted.
- Recommendation: B: it runs the exact commands on GitHub without changing anything; C creates and deletes a repository for a few lines of documentation.
- Decides: PO
- Decision: B (the product owner, 2026-10-30): the stack's commands run against c4-infra's own `demo` environment, its settings read before and after

## Acceptance criteria

- **AC-01:** Given `docs/demo-setup.md`, when its stack's and application's `demo` environment commands are read, then each sets `deployment_branch_policy` (`protected_branches` false, `custom_branch_policies` true) and adds its deployment branch, and the guide gives the command that reads them back; per PA-01, the stack's commands run against c4-infra's environment leave its settings as they were. (RQ-01)
- **AC-02:** Given a realm export with two users, in Keycloak's layout and the same reformatted by `jq`, when `new-realm-ids.sh` runs on each, then each output lists both users with their old and new ids, and each new id is the one the file now holds; given a file that isn't JSON, the script exits 1, names it, and leaves it unchanged. (RQ-02)
- **AC-03:** Given the seven hostile build fixtures, then each header names the 0011 rule as the reason, and `tests/0007-compose-check.stand-in.sh` still refuses each with that rule. (RQ-03)
- **AC-04:** Given a stand-in where `https://<host>/` accepts the connection and never answers, when `stand_in_https` is called, then it returns non-zero within the wait's bound instead of hanging. (RQ-04)
- **AC-05:** Given an empty or unreadable server information file, when `other_features` runs, then it fails, saying it read no feature; with Keycloak's real information, it passes as today. (RQ-05)

## Intent questions

- None.

## Change log

- v1 — 2026-10-30 — first version
- v1 — 2026-10-30 — approved: PA-01 B (the product owner)
