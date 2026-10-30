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

- 2026-10-30 — step 1 (e78ffae): `tests/0043-primary-network.sh`, `15 check(s) failed`: the five shared services' primary network `got: c4-infra.aaa` in the dev and demo models, `got: c4-infra.faito` on the dev stack (`~/.cache/c4-infra-tests/0043-step1.log`); after step 2 (79379de), its `model` part `every check passed`.
- 2026-10-30 — step 3 (add065a): `tests/0010-brute-force.sh` from the main checkout detached at the commit, 19 `ok`, `every check passed`, AC-03's lockout after the 10th failure on the copy without the ten settings (`0041-step3.log`). The test's checks of `register-app.sh`'s lines match whole lines (`grep -x`): stricter than before.
- 2026-10-30 — step 4 (e0dc6a0): `tests/0004-registry.sh` from the main checkout, `every check passed`, immo's line `-` (`0044-0045-step4.log`). `entries.txt` keeps the four first applications' lines of `registry.txt` as of today: the `entry`, `upstream` and field checks read it, `registry.txt` only `check`.
- 2026-10-30 — step 6, the measure (scratchpad `measure-0040.sh`, `0040-measure.log`), on a stand-in from the worktree at fbba3e9: Faito's registration recreated nothing and left `c4-infra.faito` in `compose.apps.yml`; deployment 2, exit 0 in 45 s, recreated `grafana-lgtm keycloak mailpit rabbitmq reverse-proxy`, not `keycloak-db`, each `Healthy`; deployment 3, exit 0 in 17 s, none. The five's primary network `c4-infra` (0043 on the demo side); Faito's network removed, `docker restart c4-infra.keycloak` exit 0.
- 2026-10-30 — step 7, the review round (bootstrap: one; `code-review` high on `bf6c217...` at fbba3e9), 9 findings. Fixed in 940dbd2: `routes.sh` generated a site without an address for an empty demo host (refused now, and checked in `tests/0004-registry.sh`); with `--reset-realms`, the export's settings were read after the realm's deletion (now with the probes, before any change, one `jq` per realm that also refuses an export that isn't a JSON object, no `grep` per setting); 0004's dev case asserted only an absent message (now `exit 0`); README's "Keycloak in an application's tests" still said the brute-force settings are the stack's; `FROM_EXPORT` copied the stack's values (derived from `EXPECTED` now); 0040's README paragraph (written from the measure). Answered: `c4-app` reads the entry for `pull`, `up` and `backup` without refusing a `-` demo host: such an application has no account on the demo host unless the operator creates one against the registry, and its `register` is refused twice (`register-app.sh`, `routes.sh`); a stand-in proof would pin a real line of `registry.txt`, what 0044 removes. Left to the product owner: an export with `permanentLockout: true` registers without a word (PA-01: A names only the detection's switch).
- 2026-10-30 — step 7, the full run at 940dbd2: one test KO, `tests/0018-registry-grows.sh` (`3 check(s) failed`, `bash: routes.sh: No such file or directory`): it copies `registry.sh`, `registry.txt` and `tests/0004-registry.sh` into a scratch directory and runs 0004's `registry` part, where the review round had put the checks of `routes.sh` for an empty host. Fixed in 0de2c95: those checks moved to 0004's `scripts` part, beside the refusal of `register-app.sh` they go with, unchanged; 0004's header says so. `tests/0018-registry-grows.sh` untouched.
- 2026-10-30 — after the verification at 0de2c95, the product owner decided the review's point left open (spec 0041 v2, PA-02: C): on the demo host, `register-app.sh` refuses a realm export whose `permanentLockout` isn't `false`, with the export checks of intent 0013, before any docker call (RQ-06). Files: `register-app.sh` (its header, `lockout_check`), `tests/0004-registry.sh` (its `scripts` part, 0041 AC-06: `true`, `"TRUE"` and `1` refused, `false`, none and dev's `true` past the check), `README.md` and `docs/migration.md` (AC-05). Proof: a new row, 0041 AC-06, `tests/0004-registry.sh`, KO before the code (6 checks: the export went past, docker called). Every export of Faito, Tickee (four realms), immo and the fixtures holds `permanentLockout: false`: none refused. The verification below is redone on the new head.
- 2026-10-30 — the review of that diff (a fresh agent; 1 Important, 2 details): Keycloak, creating a realm, writes its `attributes` after its fields (26.8.1, `DefaultExportImportManager.importRealm`, `:224-233` then `:413-416`), and reads the brute-force settings from those attributes (`RealmModel.getAttribute`, `Boolean.valueOf`): an export with `attributes.permanentLockout: "true"` passed the check (Important), and a setting held there was named as the stack's (detail, 0041's code). Fixed, the spec's v2 saying so (RQ-01, RQ-06, AC-06, AC-07): `lockout_check` reads both places; the probe counts an attribute as held and as the detection's switch; `tests/0004-registry.sh`, two attribute cases refused, `null`, `"false"` and an attribute `"false"` accepted (the review's second detail), both refused cases KO at 371a378 (`… no docker call` and `… it says why`, 4 checks); `tests/0010-brute-force.sh`, 0041 AC-07 on the dev stack. No real export or fixture holds one of the ten in its `attributes`. The run of `--changed 0de2c95 --all` at 371a378, stopped after 13 tests (none KO), is replaced by the one on the new head.

## Verification

### Verification — 39783c5

- Verification command: `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all`, from the main checkout detached at 940dbd2 after `bash up.sh` there (`up.sh exit 0`, the five shared services recreated with their new primary network), one stand-in lane (Docker reports 7.6 GiB) → `total: 4432.2 s for 84 test(s)`, `FAILED: tests/0018-registry-grows.sh`, `run.sh exit 1` (2026-10-30, `~/.cache/c4-infra-tests/0040-0045-all.log`); the fix (Deviations), then `bash tests/run.sh --changed 940dbd2` from the main checkout detached at 0de2c95 → `verification passed (--changed: 4 of 84 tests)`, `run.sh exit 0` (0004, 0018, 0019-collation, 0032; `0040-0045-rerun.log`); then spec 0041 v2 (Deviations), and `bash tests/run.sh --changed 0de2c95 --all` from the main checkout detached at 39783c5 → `total: 1825.9 s for 36 test(s)`, `verification passed (--changed: 36 of 84 tests)`, `run.sh exit 0`, no `KO` line (the eight stand-in tests that cover `register-app.sh` or the docs included; `0041-c-changed-all-2.log`). Together, every test since the full run's commit. `main` hasn't moved since the branch was cut (bf6c217): the full run is the delivery's milestone as well.
- Risk tier: high (0041: the brute-force protection of the applications' realms, spec 0041's risk); the others standard.
- Reviews: bootstrap mode: 1 round, on `bf6c217...fbba3e9`; bugs (`code-review`, high) 9 findings, 7 fixed in 940dbd2, 1 answered, 1 left to the product owner (Deviations, step 7); security (`security-review`, on the worktree's diff at 940dbd2): no finding at confidence 8 or above, nine candidates examined and dismissed (`kcadm` options from an export's keys, which only subtract from the stack's ten; jq and kcadm reading a JSON differently, within PA-01 A; an empty export; one realm in two files; the realm as an array key, checked against the registry; the export replaced between read and import, a root-only snapshot on the demo host; `-` claiming or hijacking a host; `priority: 100`, no new reach; the order of the refusals); the comments the diff adds: script headers, reasons (`compose.yml`'s priority), the tests' criterion labels.
  - `register-app.sh:449-451`, whose first half says what the `jq` below computes: kept, the file's idiom for what is read before anything changes (`:156`, `:416`), its second half the reason (the attributes).
  - Left to the product owner: an export with `permanentLockout: true` registered without a word. Decided C (spec 0041 v2, PA-02): refused on the demo host.
  - The diff of that decision (371a378), reviewed once by a fresh agent (bugs and security): 1 Important, `attributes.permanentLockout` passed the check while Keycloak applies it last; 2 details, a setting held in `attributes` named as the stack's, `null` and `"false"` untested. All three fixed in 39783c5 (spec v2's RQ-01, AC-06, AC-07); the hypotheses it checked and found to hold: duplicate keys (the last wins in jq and Jackson), escaped keys, the key's case (Keycloak ignores `PermanentLockout`), odd values refused, unreadable input refused, `set -e`, the CR, the order (before `networks.sh`, the first docker call), no other import path on the demo host, `c4-app`'s snapshot.
- Mutation check (bug): 0043, `tests/0043-primary-network.sh` at e78ffae (before the fix): `15 check(s) failed`, `got: c4-infra.aaa` in both models, `got: c4-infra.faito` live (`0043-step1.log`); 0041 and 0045 are changes, their tests KO before the code by construction (new lines, new refusals); 0041 AC-06, at 371a378 before the code, 6 checks KO (the export past, docker called); its two attribute cases at 371a378 (the fix's tests in a throwaway worktree), 4 checks KO, `… it says why` and `… no docker call`.
- Verifier: not run (the product owner's decision: one pass); the table below is the session's, from the logs named.
- Not verifiable here: none.
- Files outside the plan: none.
- Agent configuration: not changed (no `CLAUDE.md`, `.claude/**`, `REVIEW.md`), no eval report.
- Pre-existing findings (not fixed, out of scope): none new.

| Criterion | Result | Evidence |
| --- | --- | --- |
| 0040 | OK | the stand-in's measure (Deviations, step 6): deployment 2 recreated `grafana-lgtm keycloak mailpit rabbitmq reverse-proxy`, not `keycloak-db`, in 45 s; deployment 3 none, in 17 s; `README.md:96-101` says so |
| 0041 AC-01 | OK | full run, `tests/0010-brute-force.sh`: `ok - 0041 AC-01: it names the seven settings the stack filled`, `… and says the realm has no detection`, `… verif-lockout has its export's three settings and RQ-01's seven others` |
| 0041 AC-02 | OK | the same run: the three `0041 AC-02` checks `ok` (all ten named, no "no detection" line, the ten values), then `AC-03: after 9 failures, the visitor isn't locked`, `after the 10th, it is locked`, `a minute later, its right password logs in` `ok` |
| 0041 AC-03 | OK | the same run: `AC-05: registered again, verif-lockout is left as it is`, `its detection stays on` `ok` |
| 0041 AC-04 | OK | the same run: `AC-01` (twice) and `AC-08 … (403)` `ok`, unchanged |
| 0041 AC-05 | OK | read: `README.md:378-399` (the export decides, the switch included, at its top level or in its `attributes`, the stack's fill the rest, an export with the detection off registers without one and says so, the demo host refuses one that locks an account for good), `:529`; `docs/migration.md:225-229`; `register-app.sh:14-16` |
| 0041 AC-06 | OK | `--changed 0de2c95 --all` at 39783c5, `tests/0004-registry.sh`: the five refused exports (`true`, `"TRUE"`, `1`, `attributes` `"true"`, `attributes` `"TRUE"` beside a top-level `false`), each `refused (exit non-zero)`, `it says why`, `no docker call` `ok`; `false`, none, `null`, `"false"`, an attribute `"false"` `past the export's checks` `ok`; `permanentLockout true, in dev: past the export's checks` `ok` |
| 0041 AC-07 | OK | the same run, `tests/0010-brute-force.sh` on the dev stack: `0041 AC-07: a copy whose attributes hold failureFactor: the nine others named as the stack's`, `verif-lockout's failureFactor is its attributes' 3` `ok` |
| 0042 | OK | read: `docs/migration.md:337-352`, Tickee as it runs today (389 Directory Server, `compose-ldap.yml` on `127.0.0.1:13389`, its own network); `:54`, the port table's row for a service of the project's own |
| 0043 | OK | full run, after `up.sh`: `tests/0043-primary-network.sh` 17 `ok`, `every check passed` (the five's primary network `default` in both models, `NetworkMode` `c4-infra` live); 15 KO at e78ffae; on the stand-in, the five's `NetworkMode` `c4-infra` and `docker restart c4-infra.keycloak` exit 0 once Faito's network was removed |
| 0044 | OK | rerun at 0de2c95: `tests/0004-registry.sh` 111 `ok`, `every check passed`, `registry.txt` checked by `check` alone, the entries' checks on `tests/fixtures/0004/entries.txt`; `tests/0018-registry-grows.sh`, one more entry, `every check passed` |
| 0045 AC-01 | OK | the same rerun: `entries: check passes on entries.txt, two of its demo hosts '-'`, `entry verif-a: demo_host= (its '-', 0045 AC-01)` `ok` |
| 0045 AC-02 | OK | the same rerun: `no demo host, on the demo host: register-app.sh --app verif-a exits non-zero`, `it says why`, `no docker call`, `in dev: registers (exit 0)` `ok`; `routes.sh`, the demo site refused, the dev site made |
| 0045 AC-03 | OK | the same rerun: `registry.txt: check passes` with immo's line `5 immo immo - immo immo.dev.localhost -` |
| 0045 AC-04 | OK | read: `registry.txt:12-13`, `docs/migration.md:41-43` |
| No regression | OK | the full run at 940dbd2, 83 of 84 tests passed, 0018 fixed in 0de2c95, the rerun `verification passed`; `--changed 0de2c95 --all` at 39783c5, 36 tests, `verification passed` |
