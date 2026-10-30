# Plan: what Tickee's and immo's migrations left for c4-infra (0040 to 0045, one pass, one delivery)

- Intents: [0040](intent.md), [0041](../0041-brute-force-settings-replaced-silently/intent.md) (spec [v1](../0041-brute-force-settings-replaced-silently/spec.md)), [0042](../0042-migration-guide-tickee-section-stale/intent.md), [0043](../0043-registration-fails-without-another-apps-network/intent.md), [0044](../0044-registry-test-pins-live-entries/intent.md), [0045](../0045-registry-demands-a-demo-host/intent.md) (spec [v1](../0045-registry-demands-a-demo-host/spec.md))
- Status: approved
- Branch: `0040-shared-services-recreated-after-first-registration`, carrying the six intents (worktree `D:/workspaces/c4-infra-0040`)
- Approved: 2026-10-30, Jérôme Wacongne (product owner, engineer and tech lead; in the session: the six handled outside the stages' gates, their documents kept for traceability, built and verified in one pass)

## Context

The reading of Tickee and poc-immo-pf of 2026-10-30 (handover, "Tickee and poc-immo-pf") left five points for c4-infra and three minor ones; the product owner kept the five but the Keycloak dump after a first registration (no change, the finding stays in the handover), and the minor ones but the test of a front end's own headers, which 0031 already added (`tests/0015-headers.sh:169-174`).

## Decisions (the product owner, 2026-10-30)

- 0040: measure on a stand-in and document; no change of behaviour.
- 0041: the export decides literally, the detection's switch included (spec PA-01: A).
- 0045: `-` as a demo host, used for immo.
- One pass: the stages' gates skipped; one review round on the whole diff (bugs, and security for 0041's high risk); one `bash tests/run.sh --all`, the proof and the milestone before the push; no `verifier` agent.

## Design

- **0043, the primary network.** Compose gives a container the network of its highest `priority`, then of the first key by name, as its `NetworkMode` (measured on a throwaway project, intent 0043): the applications' keys `c4-infra.<app>` sort before `default`, so the first application's network became the five shared services' primary one. In `compose.yml`, each of them takes `default: {priority: 100}`; Keycloak keeps `keycloak-db`. The test checks the model (the dev and demo compose files with a fake `compose.apps.yml` whose application key sorts first: `default` wins for each of the five) and the live dev stack (`NetworkMode` `c4-infra`).
- **0041, the export decides.** `register-app.sh` keeps the stack's ten values as one list; per realm file, the keys its JSON holds with a non-null value (`jq` on stdin) are left to the export, the others get `-s key=value`; the lines of spec 0041's design. `tests/0010-brute-force.sh` follows the spec's AC-01 to AC-03: the fixture as it is (three settings of its own, detection off), then `--reset-realms` with a copy without the ten, whose user locks after its 10th failure.
- **0045, no demo host.** `registry.sh check` accepts `-` in the demo-host column (no claim), `registry_entry` turns it into an empty `REG_DEMO_HOST`, `register-app.sh` refuses it on the demo host right after the entry is read; immo's line says `-`.
- **0044, no real entry pinned.** `tests/0004-registry.sh`'s checks of an entry's fields, `entry` and `upstream` run on a fixture, `tests/fixtures/0004/entries.txt` (the four first applications' lines as of today, renamed nowhere, plus two lines with `-` as their demo host for 0045); on `registry.txt`, only `check` passing.
- **0042, the guide.** `docs/migration.md`: Tickee's section as Tickee runs today; the port table's row for a service of the application's own.
- **0040, the measure.** A one-off script on a stand-in (`tests/lib/stand-in-host.sh`, as `tests/0007-isolation.stand-in.sh`): the stack deployed, the containers' ids read; an application (the fixture `tests/fixtures/0007/faito/`) registered by `sudo c4-app register`; `demo/deploy.sh` again, twice, the ids compared each time, and each shared service's `NetworkMode`. Then the README says what it measured.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0043-primary-network.sh` | new: the model and live checks | 0043 |
| `compose.yml` | the five shared services' `default` network with `priority: 100` | 0043 |
| `register-app.sh` | the export's brute-force settings kept, the stack's filling the others, the lines printed (0041); the refusal of `-` on the demo host (0045) | 0041 RQ-01 to RQ-04; 0045 RQ-03 |
| `tests/0010-brute-force.sh` | AC-01 to AC-03 of spec 0041 | 0041 |
| `registry.sh`, `registry.txt` | `-` as a demo host; immo's line | 0045 RQ-01, RQ-02, RQ-04, RQ-05 |
| `tests/0004-registry.sh`, `tests/fixtures/0004/entries.txt` | the entry's checks on the fixture (0044); `-` accepted, `entry` printing `demo_host=`, the refusal on the demo host (0045) | 0044; 0045 AC-01 to AC-03 |
| `README.md` | "Brute-force protection" (0041); the first deployment after a registration (0040) | 0041 RQ-05; 0040 |
| `docs/migration.md` | the brute-force line (0041); the registry's `-` (0045); Tickee's section and the port table (0042) | 0041 RQ-05; 0045 RQ-05; 0042 |
| the six intents' folders, `docs/intent/README.md`, `docs/intent/HANDOVER.md` | intents, the two specs, this plan and its pointers; statuses; the handover at delivery | — |

## Order of work

Runs: `TMPDIR=~/.cache/c4-infra-tests` always. The tests that read `.env` or write where they run (0010, 0017, the `--all`) go from the main checkout detached at the commit; the others from the worktree.

1. **Failing test (0043).** — check: `bash tests/0043-primary-network.sh` KO on the model and on the live stack. Commit `test(0043): …`.
2. **Primary network (0043).** — check: the test's model part `ok`; the live part waits for step 7's `up.sh`.
3. **Brute force (0041).** — check: `tests/0010-brute-force.sh` from the main checkout, `every check passed`.
4. **Registry (0044, 0045).** — check: `bash tests/0004-registry.sh`, `every check passed`.
5. **Guide (0042), README (0041).** — check: `bash tests/0004-registry.sh docs`, and the tests declaring `docs/migration.md` and `README.md` in step 7's run.
6. **Measure (0040).** — the stand-in script; the README's paragraph from its figures.
7. **Verification.** — one review round (`code-review` high, `security-review`) on the branch's diff, its fixes; from the main checkout detached at the head: `bash up.sh` (the shared services recreated with their new primary network), then `bash tests/run.sh --all`; the evidence into this plan's `## Verification`.
8. **Delivery.** — the six `delivered`, one merge into `main`, the handover, the push; the deployment that follows recreates the five shared services once (0043's model change), checked on its log.

## Risks

- A test of `--all` relying on `register-app.sh` imposing the stack's settings → the run says it; fixed under the spec, never loosened.
- The live check of 0043 before `up.sh` → `up.sh` first, at step 7.
- The stand-in's measure confused by a deployment that changed something else → the same tree for the three deployments, the ids compared one deployment to the next.
- The demo host's next deployment recreates the shared services (0043) → expected, said at delivery.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| 0040 | command, stand-in | the measure: second deployment recreates the five, not `keycloak-db`; third none; README |
| 0041 AC-01 to AC-04 | automated test | `tests/0010-brute-force.sh` |
| 0041 AC-05 | automated test, reading | the docs' checks of the run; README, `docs/migration.md` read |
| 0042 | reading | `docs/migration.md`'s Tickee section and port table |
| 0043 | automated test, mutation | `tests/0043-primary-network.sh`: KO at step 1, `ok` after step 7's `up.sh`; the stand-in's `NetworkMode` |
| 0044 | automated test | `tests/0004-registry.sh` on the fixture; `registry.txt` with immo's changed line passing it |
| 0045 AC-01 to AC-04 | automated test | `tests/0004-registry.sh` |
| No regression | command | `bash tests/run.sh --all`, `verification passed` |

## Deviations

## Verification
