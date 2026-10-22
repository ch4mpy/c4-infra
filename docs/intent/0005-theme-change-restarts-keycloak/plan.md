# Plan: A theme change restarts the Keycloak every application uses

- Spec: [v1](spec.md)
- Status: approved
- Branch: main (grouped pass of 2026-10-21)
- Approved: 2026-10-22, Jérôme Wacongne (engineer, product owner and tech lead), after two rounds of cross-plan coherence review
- Builds on: 0003 (Caddy in both environments, `compose.dev.yml` / `compose.demo.yml`, **`INFRA_ENV` in `.env`**, which 0003 introduced, so REQ-5 is already met by the setting and this plan only uses it), 0004 (registry: themes owned per entry; `REGISTRY_FILE` for fixtures), 0001 (`tests/lib/`)

## Starting point

- `register-app.sh` copies a new or changed theme into `keycloak/themes/` and runs `docker restart c4-infra.keycloak` when anything changed, in both environments; an unchanged theme restarts nothing.
- Keycloak 26.7 (`keycloak/Dockerfile`), started with `start --optimized`; its theme cache is on (production default). Theme options are runtime options, so the dev override can set them without rebuilding the image. Documented names (Keycloak 26 "Working with themes"): `--spi-theme--static-max-age=-1 --spi-theme--cache-themes=false --spi-theme--cache-templates=false`, i.e. the environment variables `KC_SPI_THEME__STATIC_MAX_AGE`, `KC_SPI_THEME__CACHE_THEMES`, `KC_SPI_THEME__CACHE_TEMPLATES` (`--` → `__`).

## Files

| File | Change | For |
| --- | --- | --- |
| `compose.dev.yml` | modified: on `keycloak`, `KC_SPI_THEME__STATIC_MAX_AGE: '-1'`, `KC_SPI_THEME__CACHE_THEMES: 'false'`, `KC_SPI_THEME__CACHE_TEMPLATES: 'false'` (comment: dev only; the demo host keeps Keycloak's caching) | REQ-1, AC-1 |
| `register-app.sh` | modified: themes are installed as today; Keycloak is restarted only when `INFRA_ENV=demo` and a theme changed (once per registration, whatever the number of themes); in dev the message says "Theme <name> installed: reload the login page (Keycloak doesn't cache themes in dev)" | REQ-2, REQ-3, REQ-4, REQ-5, AC-1, AC-3, AC-4 |
| `README.md` | modified: "What an application provides" / `register-app.sh` paragraph: in dev a theme change shows on reload after a new registration, no restart; on the demo host a changed theme restarts Keycloak once | REQ-3, REQ-4 |
| `docs/migration.md` | modified: Tickee's section: iterate on its theme with `bash ../c4-infra/register-app.sh --app tickee --themes keycloak/themes` (or `deploy-dev.sh`), then reload | REQ-3 |
| `tests/fixtures/0005/registry.txt` | new: the real entries plus `35 verif-theme verif-theme verif-theme-api verif-theme verif-theme.dev.localhost verif-theme.c4-soft.com` | AC-1 to AC-4 |
| `tests/fixtures/0005/verif-theme-realm.json` | new: `{"realm":"verif-theme","enabled":true,"loginTheme":"verif-theme"}` | AC-1 |
| `tests/fixtures/0005/themes/verif-theme/login/theme.properties`, `login.ftl`, `resources/css/verif.css` | new: `parent=base`; a minimal `login.ftl` printing `VERIF-STAMP-@STAMP@` and `${url.resourcesPath}`; one CSS rule | AC-1, REQ-1 |
| `tests/lib/keycloak.sh` | new: `kc_admin <kcadm args…>` (the bootstrap administrator of `.env`, read as data, `KC_CLI_PASSWORD` in the environment as `register-app.sh` does; 0006 adds a helper for its registration account next to it), `kc_started_at` (`docker inspect -f '{{.State.StartedAt}}' c4-infra.keycloak`), `kc_wait_healthy` | AC-1 to AC-4 |
| `tests/0005-themes.sh` | new: below | AC-1 to AC-4 |
| `docs/intent/0005-theme-change-restarts-keycloak/plan.md` | new: this plan (`approved` at the gate) | bookkeeping |
| `docs/intent/0005-theme-change-restarts-keycloak/intent.md` | modified: status `planned` at approval | bookkeeping |
| `docs/intent/README.md` | modified: index row 0005 → `planned` | bookkeeping |

## Order of work

1. **No theme cache in dev**: the three variables in `compose.dev.yml`; `bash up.sh` (recreates Keycloak once, with the new environment: expected). — skill: none — check: `docker compose config --format json | jq -r '.services.keycloak.environment | keys[]' | grep -c KC_SPI_THEME` prints `3`; `docker compose -f compose.yml -f compose.demo.yml --env-file tests/fixtures/0003/demo.env config | grep -c KC_SPI_THEME` prints `0`; `docker logs c4-infra.keycloak 2>&1 | grep -i 'spi-theme'` shows no "unknown option" warning; `docker inspect -f '{{.State.Health.Status}}' c4-infra.keycloak` is `healthy`.
2. **No restart in dev, as today on the demo host**: `register-app.sh`, and `tests/lib/keycloak.sh`, `tests/fixtures/0005/`, `tests/0005-themes.sh`. The test (`REGISTRY_FILE=tests/fixtures/0005/registry.txt`, the fixture theme copied to a temporary directory with `@STAMP@` replaced):
   - **dev** (AC-1, AC-2): register the realm and the theme with stamp A; record `kc_started_at`; `curl --ssl-no-revoke -s 'https://host.docker.internal/auth/realms/verif-theme/protocol/openid-connect/auth?client_id=account-console&response_type=code&scope=openid&redirect_uri=https%3A%2F%2Fhost.docker.internal%2Fauth%2Frealms%2Fverif-theme%2Faccount%2F'` holds `VERIF-STAMP-A`; stamp B, register `--themes` again while a background loop polls `https://host.docker.internal/auth/realms/faito/.well-known/openid-configuration` every 0.2 s and records any status other than 200; the page holds `VERIF-STAMP-B`, `kc_started_at` is unchanged, the loop recorded nothing; the CSS's `Cache-Control` (path printed by the page) holds no `max-age` of days (REQ-1, browsers);
   - **`INFRA_ENV=demo`** (AC-3, AC-4): `.env` backed up and restored by a `trap` (no `up.sh` nor `docker compose up` meanwhile); stamp C registered → `kc_started_at` changed (one restart), `kc_wait_healthy`; stamp C registered again (unchanged) → `kc_started_at` unchanged; back to `dev`, stamp D registered → unchanged start time;
   - cleanup: `kc_admin delete realms/verif-theme`, `rm -rf keycloak/themes/verif-theme`.
   — skill: none — check: `bash tests/0005-themes.sh`.
3. **Docs**: README, `docs/migration.md` (Tickee). — skill: none — check: `bash tests/run.sh`.
4. **AC-2 with a real session** (manual). Start Faito, each in its own Git Bash terminal (until Faito 0020 its gateway doesn't start from its jar):
   - `bash ../faito/deploy-dev.sh`;
   - gateway: `export JAVA_HOME=~/.sdkman/candidates/java/25.4.4.1+1-graalce; set -a; source ../faito/.env; set +a; cd ../faito/backend && ./mvnw -q -pl gateway -am install -DskipTests && ./mvnw -pl gateway spring-boot:run`;
   - REST API: the same with `-pl faito-api`;
   - front end: `cd ../faito/frontend/angular && npm start`.

   Then AC-2's manual line. — skill: none — check: AC-2's manual line, result in the PR.

## Risks

- Keycloak's gzip cache of static resources (`data/tmp/kc-gzip-cache`) could serve an old CSS despite `cache-themes=false` → AC-1 edits a template (`.ftl`, reloaded with `cache-templates=false`); the CSS check only asserts the browser headers. If a changed CSS shows stale in practice, it is a deviation (the spec's AC-1 still holds).
- A new theme directory has to be visible to the running Keycloak without restart → the bind mount is the directory `keycloak/themes/` (not each theme), and the test's first registration installs a theme Keycloak has never seen.
- `INFRA_ENV=demo` set on the workstation by the test while Caddy runs with dev snippets → the test never starts compose and restores `.env` in a `trap`.
- The demo restart drops every application's logins for about a minute (unchanged behaviour, REQ-4) → only when a theme actually changed, once per registration.
- Recreating Keycloak in step 1 → once, with Faito's processes stopped.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-1 | automated test | `bash tests/0005-themes.sh` — dev part: `VERIF-STAMP-B` on reload after re-registering, same `State.StartedAt` |
| AC-2 | automated test + manual check | `bash tests/0005-themes.sh` — no non-200 answer from realm `faito` while the theme changes. Manual: logged into Faito (`https://faito.dev.localhost/fr/`), run the dev part of the test (or `register-app.sh --themes` with a changed theme), reload Faito: still logged in, no new login asked |
| AC-3 | automated test, then first demo deployment | `bash tests/0005-themes.sh` — `INFRA_ENV=demo` part: changed theme → one restart, unchanged → none; `docker compose -f compose.yml -f compose.demo.yml --env-file tests/fixtures/0003/demo.env config` holds no `KC_SPI_THEME` (caching stays on). Not verifiable here — first demo deployment of an application with a theme (Tickee): `docker inspect -f '{{.State.StartedAt}}' c4-infra.keycloak` changes on the deployment that changes the theme, not on the next one |
| AC-4 | automated test | `bash tests/0005-themes.sh` — `dev`: no restart with Caddy as the proxy; `demo`: restart |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
