# Plan: Nothing prevents two applications from taking the same port block

- Spec: [v1](spec.md)
- Status: approved
- Branch: main (grouped pass of 2026-10-21)
- Approved: 2026-10-22, Jérôme Wacongne (engineer, product owner and tech lead), after two rounds of cross-plan coherence review
- Builds on: 0001 (implemented first: `tests/lib/assert.sh`, `tests/lib/stubs.sh`, `tests/run.sh`, up.sh's `host.docker.internal` check)

## Starting point

- The registry is the README's "Port registry" table (Turu 1, Hurura'a 2, Tickee 3, Faito 4); `register-app.sh` never reads it; the demo workflow sends `demo/` and `register-app.sh` only (`rsync -az --exclude 'caddy/apps/*' demo/ register-app.sh "$VPS:~/c4-infra/"`).
- The routes file of RQ-03 doesn't exist yet: it is 0003's (implemented right after this one). This plan delivers the registry and the derivation of a role's upstream from an entry (`registry_upstream`); 0003's routes-file parser calls it and refuses a host or a port. **AC-02 is proven by 0003's plan** (its `tests/0003-routes.sh`, case "host or port"), and 0004 isn't complete until that step passes.
- What each application owns, read in their repositories on 2026-10-21: realms `turu`; `public-facing`; `tickee`, `brasserie`, `tenant2`, `tenant3`; `faito`. RabbitMQ users `<app>-api`. Theme `tickee` only. Demo hosts `<app>.c4-soft.com` (Turu has no demo deployment yet: its demo host is reserved all the same).

## Files

| File | Change | For |
| --- | --- | --- |
| `registry.txt` | new: header comment (columns, rules, "a new application takes `bash registry.sh next` and adds its line first"), then one line per application: `n app realms rabbitmq-user themes dev-host demo-host`, columns separated by spaces, lists by commas, `-` for none | RQ-01, AC-06 |
| `registry.sh` | new, sourced by `register-app.sh` and `up.sh`, and a command: `registry_check` (field count, `n` in 1–38, names' character sets, reserved names refused as an application's name (`c4-infra`, `keycloak`, `keycloak-db`, `mailpit`, `rabbitmq`, `grafana-lgtm`, `reverse-proxy`: the shared services' names, which 0002 uses for accounts and 0007 for networks such as `c4-infra.keycloak-db`); then duplicates of number, name, realm, theme, RabbitMQ user or host name, each reported with both applications and their line numbers), `registry_entry <app>` (sets `REG_N REG_APP REG_REALMS REG_RABBITMQ_USER REG_THEMES REG_DEV_HOST REG_DEMO_HOST`), `registry_next`, `registry_upstream <role> <dev\|demo>` (below); CLI `bash registry.sh check\|next\|entry <app>\|upstream <app> <role> <env>` (its output contract below); `REGISTRY_FILE` (default: `registry.txt` next to it) for the tests | RQ-01 to RQ-05 |
| `register-app.sh` | modified: sources `registry.sh`; runs `registry_check`; refuses an `--app` absent from the registry, naming `registry.txt` and `bash registry.sh next` (before any `docker` call); `--index-only` unchanged | RQ-02, RQ-04, AC-01 |
| `up.sh` | modified: `bash ./registry.sh check` right after 0001's resolution check, before `env.sh` and any `docker` call | RQ-04, AC-03 |
| `.github/workflows/deploy-demo.yml` | modified: the upload sends `registry.txt` and `registry.sh` next to `register-app.sh` (`rsync -az --exclude 'caddy/apps/*' demo/ register-app.sh registry.txt registry.sh "$VPS:~/c4-infra/"`) | RQ-06, AC-05 |
| `README.md` | modified: "Port registry" keeps the block rule (`(10 + n) × 1000`, the offsets, the 49152 limit) and points to `registry.txt` and `bash registry.sh next`; the table is removed; "What an application provides" names the registry entry | RQ-07, AC-07 |
| `docs/migration.md` | modified: step 1 ("Port block") states the contract a project (and the `create-dev-infra` skill, skills 0014) relies on: `bash registry.sh next` gives the number; the entry is one line of `registry.txt`, `n app realms rabbitmq-user themes dev-host demo-host`, spaces between columns, commas inside a list, `-` for none (Faito's line as the example), added in a commit of its own before anything registers; what each column then allows (0002, 0003, 0007) | RQ-05, RQ-07 |
| `tests/0004-registry.sh` | new: AC-01, AC-03, AC-04, AC-06, AC-07 and the derivation table (below) | AC-01, AC-03, AC-04, AC-06, AC-07 |
| `tests/fixtures/0004/` | new: `duplicate-number.txt` (two entries numbered 4), `duplicate-realm.txt` (two owning `public-facing`), `duplicate-theme.txt` (two owning `tickee`), `taken-1-4.txt`, `taken-1-2-4.txt`, `bad-fields.txt` (a line with 6 columns, `n` = 39), `reserved-name.txt` (an entry named `keycloak-db`) | AC-03, AC-04 |
| `tests/0004-upload.sh` | new: runs the workflow's own upload command against a scratch directory (below) | AC-05 |
| `docs/intent/0004-port-registry-unchecked/plan.md` | new: this plan (`approved` at the gate) | bookkeeping |
| `docs/intent/0004-port-registry-unchecked/intent.md` | modified: status `planned` at approval | bookkeeping |
| `docs/intent/README.md` | modified: index row 0004 → `planned` | bookkeeping |

The command's output contract (stdout for data, stderr for messages; the skills, e.g. skills 0014, rely on it):

| Command | Output (stdout) | Exit code |
| --- | --- | --- |
| `bash registry.sh check` | nothing; each problem on stderr | `0` valid, `1` a problem |
| `bash registry.sh next` | the number, e.g. `5` | `0`; `1` when 1–38 are all taken |
| `bash registry.sh entry <app>` | the entry's named fields, one `key=value` per line, in this order: `n=4`, `prefix=14`, `app=faito`, `realms=faito`, `rabbitmq_user=faito-api`, `themes=`, `dev_host=faito.dev.localhost`, `demo_host=faito.c4-soft.com` (lists comma-separated as in the file, empty for `-`) | `0`; `1` when `<app>` isn't in the registry (nothing on stdout, stderr names `registry.txt` and `bash registry.sh next`); `2` when the registry itself is invalid (`check`'s problems on stderr) |
| `bash registry.sh upstream <app> <role> <dev\|demo>` | the URL, e.g. `https://host.docker.internal:14080` | `0`; `1` unknown application or role; `2` no upstream for that role in that environment (demo `mcp`, message on stderr) |

`registry_upstream` (RQ-03, 0003 RQ-04), with `p = 10 + n`:

| Role | dev | demo |
| --- | --- | --- |
| `gateway` | `https://host.docker.internal:<p>080` | `http://<app>.gateway:7080` |
| `mcp` | `https://host.docker.internal:<p>280` | refused (exit 2): "the README fixes no container port for the MCP server role yet (README.md, 'What an application's deployment does')" |
| `fr`, `ui` | `http://host.docker.internal:<p>200` | `http://<app>.frontend:80` |
| `en` | `http://host.docker.internal:<p>205` | `http://<app>.frontend:80` |

## Order of work

1. **The registry file**, `registry.txt`, with the four entries (Tickee: `3 tickee tickee,brasserie,tenant2,tenant3 tickee-api tickee tickee.dev.localhost tickee.c4-soft.com`). — skill: none — check: `grep -E '^3 +tickee +tickee,brasserie,tenant2,tenant3 +tickee-api +tickee +tickee\.dev\.localhost +tickee\.c4-soft\.com$' registry.txt` and `grep -cE '^[0-9]+ ' registry.txt` prints `4`.
2. **`registry.sh`** and `tests/0004-registry.sh` + fixtures: `check` on each fixture fails, naming both applications of a duplicate (e.g. `realm public-facing: hururaa (line 14) and verif (line 15)`) or the reserved name (`reserved-name.txt`: `keycloak-db is reserved for the shared stack`), `next` prints `5` and `3`, `upstream` matches the table above for Faito (`14080`, `14280`, `14200`, `14205`, `faito.gateway:7080`, `faito.frontend:80`), demo `mcp` exits 2 naming the README section; `bash registry.sh entry faito` prints exactly the eight lines of the contract above and exits 0, `entry tickee` prints `realms=tickee,brasserie,tenant2,tenant3` and `themes=tickee`, `entry verif` prints nothing on stdout and exits 1, `entry faito` with `REGISTRY_FILE=tests/fixtures/0004/duplicate-number.txt` exits 2; `check` passes on `registry.txt`. — skill: none — check: `bash tests/0004-registry.sh`.
3. **`up.sh` and `register-app.sh` read it.** In the test: `REGISTRY_FILE=tests/fixtures/0004/duplicate-number.txt` with 0001's stubs in `PATH` (`STUB_ADDRESS=127.0.0.1`, so that up.sh's resolution check passes): `up.sh` exits ≠ 0 naming both entries and `$STUB_LOG` is empty; `bash register-app.sh --app verif` exits ≠ 0 with `registry.txt` in its message, before any `docker` call (stub log empty). — skill: none — check: `bash tests/0004-registry.sh` and `bash ../faito/deploy-dev.sh` (Faito still registers: `faito` is in the registry; its `.conf` is still installed by nginx until 0003).
4. **The demo upload sends the registry.** `tests/0004-upload.sh` extracts the `rsync` line of the "Upload the deployment files" step (`grep -m1 'rsync -az' .github/workflows/deploy-demo.yml`), replaces `"$VPS:~/c4-infra/"` with `/dest/`, and runs it in `alpine:3` (`apk add --no-cache rsync`, the repository mounted read-only at `/src` with `cygpath -w`, working directory `/src`); `registry.txt`, `registry.sh` and `register-app.sh` must be in `/dest/`. — skill: none — check: `bash tests/0004-upload.sh`.
5. **Docs**: README "Port registry" and "What an application provides"; `docs/migration.md` step 1, the registry's contract (entry notation, `bash registry.sh next`, its own commit first). — skill: none — check: `bash tests/0004-registry.sh` (its AC-07 part: the README's section holds `registry.txt` and no line matching `^\| *[0-9]+ *\| *[a-z]`; and `docs/migration.md` holds `bash registry.sh next` and the column line `n app realms rabbitmq-user themes dev-host demo-host`) and `bash tests/run.sh`.

## Risks

- The `create-dev-infra` skill reads and writes the README's table today → the README keeps a pointer to `registry.txt` and `bash registry.sh next`, which an agent following the skill finds; the skill itself changes in the skills follow-up (skills 0014/0015).
- A registry edited by two branches at once (two new applications) → each line carries its number; a merge conflict on adjacent lines, or `registry.sh check` failing in `up.sh` after the merge, names both.
- `REGISTRY_FILE` lets a caller point at another registry → it is a test seam only: on the demo host, registrations run through 0002's root-owned command, which clears the environment; documented in `registry.sh`'s header.
- AC-02 depends on 0003 → stated in the Starting point and in the proof; both are implemented in the same pass, 0003 right after.
- A space-separated format breaks on a value with a space → every field is checked against a character set without spaces (`registry_check`).

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test | `bash tests/0004-registry.sh` — case `unknown app`: `bash register-app.sh --app verif` exits ≠ 0, stderr names `registry.txt`, stubbed `docker` never called |
| AC-02 | automated test, in 0003 | `bash tests/0003-routes.sh` — case `host or port`: Faito's routes file with a line `/gateway/* host.docker.internal:12080` is refused, the message naming the token and the line (0003, step 2) |
| AC-03 | automated test | `bash tests/0004-registry.sh` — cases `duplicate number`, `duplicate realm`, `duplicate theme`: `REGISTRY_FILE=<fixture> bash up.sh` exits ≠ 0 naming both entries, no `docker` call |
| AC-04 | automated test | `bash tests/0004-registry.sh` — `REGISTRY_FILE=tests/fixtures/0004/taken-1-4.txt bash registry.sh next` prints `5`; `taken-1-2-4.txt` prints `3` |
| AC-05 | command, then first demo deployment | `bash tests/0004-upload.sh` (the workflow's rsync command, run against a scratch destination, delivers `registry.txt` and `registry.sh` next to `register-app.sh`). Not verifiable here — first demo deployment: `ssh c4-infra@<vps> ls ~/c4-infra/registry.txt ~/c4-infra/registry.sh` (account name from 0002) |
| AC-06 | automated test | `bash tests/0004-registry.sh` — case `entries`: four entries with seven fields each, Tickee's line exactly as in step 1 |
| AC-07 | automated test | `bash tests/0004-registry.sh` — case `README`: the "Port registry" section names `registry.txt` and holds no table row of numbers |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
