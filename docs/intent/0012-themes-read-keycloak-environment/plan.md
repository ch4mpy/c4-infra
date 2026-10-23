# Plan: An application's Keycloak theme may read the shared Keycloak's environment

- Spec: [v1](spec.md)
- Status: approved
- Branch: 0012-themes-read-keycloak-environment
- Approved: 2026-10-23, Jérôme Wacongne (engineer, and tech lead for the high risk)
- Builds on: `main` `0697208` (`bash tests/run.sh --all` → `verification passed`, 2026-10-23)

## Starting point

- `register-app.sh`: every check before a change ends at `:181` (`not_assigned`) and `:185-202` (routes); the first change is `networks.sh ensure` (`:216`); themes are copied by `cp -r` (`:290-294`), which keeps links inside a theme and follows a theme directory that is itself a link. Refusals: stderr, `…; nothing was registered.`, exit 1; `tests/0002-register-scope.sh` asserts they come before any docker call.
- `demo/c4-app` runs `register-app.sh` as root on a snapshot (`:389`); `stage()` already refuses links and special files (`:143-147`).
- Keycloak's service holds `C4_MASTER_*`, `MAILPIT_SMTP_*` and `INFRA_HOST` only for `keycloak-import/master-realm.json`'s placeholders (`compose.yml:104-122`, `compose.dev.yml:33-35`, `compose.demo.yml:22-24`).
- `kc.sh import` (26.8.1's help): `--dir`, `--file`, `--override` (default **true**); placeholders replaced since 26.0 (upgrading guide). Not measured yet: that `import` on an empty database creates master from the file, and how `docker compose up --wait` treats a completed one-shot dependency (step 2).
- Tests bound to today's layout: `tests/0009-master-realm.sh:34-41` (Keycloak's five `C4_MASTER_*` keys), `tests/0009-master-realm.stand-in.sh` (Keycloak's log "Realm 'master' imported", process samples), `tests/0003-compose.sh:32-38` (`same_images` excludes only `keycloak`), `tests/0007-listeners.sh:28` (each demo service started by name).
- Git Bash's `ln -s` copies (`core.symlinks=false`): the link cases run on the stand-in, in Linux. Tickee's theme files end lines with CRLF.

## Files

| File | Change | For |
| --- | --- | --- |
| `register-app.sh` | modified: before any change, after the assignment check, for each theme of `--themes`: refused when the theme directory is a link, when it holds a link or a special file (`find ! -type f ! -type d`), or when one of its `theme.properties` (any type, any case) holds `${` once read as Java reads it — logical lines (CRLF, CR or LF; continued by an odd number of trailing backslashes, the next line's leading blanks dropped; `#`/`!` comment lines never continued), escapes decoded (`\uXXXX`, `\X` → `X`); pure bash; messages relative to the themes directory (`<theme>/<type>/theme.properties:<line>: '${' is resolved by Keycloak from its environment and system properties`, `<theme>/<path>: a symbolic link`), then `…; nothing was registered.` | REQ-1–REQ-4 |
| `compose.yml` | modified: a one-shot service `keycloak-import` (image `${KC_IMAGE}`, `import --optimized --dir /opt/keycloak/data/import --override false`, `restart: "no"`, network `keycloak-db` only, the `keycloak-import/` mount, `C4_MASTER_*`, `MAILPIT_SMTP_*`, `INFRA_HOST` and the database settings, `depends_on: keycloak-db` healthy); `keycloak`: `start --optimized` without `--import-realm`, without that mount and those variables, `depends_on: keycloak-import: service_completed_successfully` | REQ-6 |
| `compose.dev.yml`, `compose.demo.yml` | modified: `C4_MASTER_SMTP_HOST`, `C4_MASTER_SMTP_STARTTLS`, `C4_MASTER_RESET_PASSWORD_ALLOWED` move to `keycloak-import` | REQ-6 |
| `up.sh`, `demo/deploy.sh` | modified only if step 2 shows `--wait` refuses a completed one-shot (then they wait for the long-running services by name) | REQ-6 |
| `tests/0012-themes.sh` | new: with a stubbed docker, refusals before any docker call: `kcHtmlClass=${env.KC_DB_PASSWORD}`, `\u0024{env.X}`, `\$\{env.X}`, `$` and `{` split by a continuation, `${java.version}` in `email/theme.properties`, `Theme.Properties`, CRLF lines (AC-1, AC-2); must-not-fire twins: `${` in a comment line, `{0}` in messages, `${msg(…)}` in a template; on the dev stack: Tickee's theme and the twins registered and installed, then removed (AC-5) | AC-1, AC-2, AC-5 |
| `tests/0012-themes.stand-in.sh` | new: as `tickee` through `sudo c4-app register --themes` with AC-1's theme → refused, theme not installed, Keycloak's `StartedAt` unchanged (AC-4); as root, `register-app.sh` with `resources/leak.txt -> /proc/self/environ`, and with a theme directory that is a link → refused, nothing registered (AC-3); on the fresh stand-in, master created by `keycloak-import` with 0009's settings, and `/proc/1/environ` of `c4-infra.keycloak` holds neither password (AC-7) | AC-3, AC-4, AC-7 |
| `tests/0012-import-facts.sh` | new: throwaway containers (as `tests/0009-master-import-facts.sh`): `import --db=dev-file --dir … --override false` on an empty volume creates master from the file with its placeholders resolved (the administrator logs in, SMTP set), a second run changes nothing, `start-dev` on that volume serves it; `docker compose up -d --wait` on a scratch project whose service depends on a completed one-shot | REQ-6 |
| `tests/fixtures/0012/**` | new: `registry.txt` (the real entries plus `32 verif-themes verif-themes - <its themes> verif-themes.dev.localhost verif-themes.c4-soft.com`), the themes, `verif-themes-realm.json` | AC-1–AC-5 |
| `tests/0009-master-realm.sh`, `tests/0009-master-realm.stand-in.sh` | modified: the master realm's variables are `keycloak-import`'s, Keycloak has none; "Realm 'master' imported" read in `keycloak-import`'s log; the recreation also removes its container | AC-7 |
| `tests/0003-compose.sh`, `tests/0007-listeners.sh` | modified: `keycloak-import` runs `${KC_IMAGE}` like Keycloak; a one-shot isn't a listener | REQ-6 |
| `README.md`, `docs/demo-setup.md` | modified: "The master realm" (created by `keycloak-import`; what Keycloak's environment holds); a theme's rules and why (REQ-1, REQ-2); demo-setup §11–§12 (recreating the master realm) | REQ-5, AC-8 |
| `docs/intent/0012-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan, status planned, index row | — |

## Order of work

0. **Setup**: the scratch worktree removed, `git switch 0012-themes-read-keycloak-environment` in `D:\workspaces\c4-infra`, `git merge origin/main`. — skill: none — check: `git status --short` empty.
1. **Failing tests**, committed alone by path as `test(0012): a theme reads Keycloak's environment, which holds the master realm's secrets`, then frozen (`.claude/frozen-tests.local`): `tests/0012-themes.sh`, `tests/0012-themes.stand-in.sh`, `tests/fixtures/0012/**`. — skill: none — check: `bash tests/0012-themes.sh; echo "exit=$?"` → `KO` at AC-1 (the theme is installed), `exit=1`; `bash tests/0012-themes.stand-in.sh` → `KO` at AC-4 and AC-7.
2. **Facts of the one-shot import**: `tests/0012-import-facts.sh`, committed as `test(0012): facts …`. — skill: none — check: the test passes, with local compose v5.6.0 and on the stand-in's; a fact that fails is a deviation decided before step 4.
3. **The theme checks** in `register-app.sh`. — skill: none — check: `bash tests/0012-themes.sh` (refusals and twins), `bash tests/0002-register-scope.sh && bash tests/0005-themes.sh`.
4. **The one-shot import**, the compose files, tests 0009, 0003-compose, 0007-listeners. — skill: none — check: `bash up.sh` on the existing dev database (import skipped, Keycloak healthy), `bash tests/0009-master-realm.sh && bash tests/0003-compose.sh && bash tests/0007-dev.sh && bash tests/0012-themes.sh`.
5. **Docs**. — skill: none — check: `git grep -n 'C4_MASTER_ADMIN_PASSWORD' -- 'compose*.yml'` only under `keycloak-import`; review against AC-8.
6. **Verification**: `bash tests/run.sh --all`; mutation checks: AC-6 (`git show origin/main:register-app.sh > register-app.sh; bash tests/0012-themes.sh; echo "exit=$?"; git checkout -- register-app.sh` → `KO`, `exit=1`), AC-7 (`compose.yml` from `origin/main`, the stand-in test's environment check → `KO`); then `/sdlc-verify 0012`. — skill: sdlc-verify — check: `verification passed`.
7. **Workstation re-creation** at delivery (product owner's decision; confirmed with the developer just before, as it wipes the dev Keycloak): `docker compose rm -sf keycloak keycloak-import keycloak-db && docker volume rm c4-infra_keycloak_db && bash up.sh`, then Faito's `deploy-dev.sh`. — skill: none — check: 0009's master realm settings (its step 6 and 0010's), `/proc/1/environ` of `c4-infra.keycloak` without the passwords, a login on `https://faito.dev.localhost/`.

## Risks

- `kc.sh import` lets Keycloak create a default master before importing, or resolves no placeholder → step 2 shows it before any change; the fallback (a one-shot that runs `start --import-realm` until ready, then stops) is a deviation, asked first.
- `up --wait` refuses a completed one-shot → step 2; `up.sh` and `deploy.sh` then wait for the long-running services by name.
- The one-shot runs at every `up` (20–30 s, decided); on a Keycloak image change it would migrate the database while the old Keycloak runs → 0013 stops Keycloak before an image change (0012 changes no image).
- A Java Properties form the parser misses → variants (escapes, continuation, CRLF, case) and their must-not-fire twins.
- Links can't be made on this workstation → the link cases run on the stand-in.
- Recreating the dev Keycloak drops Faito's dev users not in its export → Faito re-registers from its export; confirmed before step 7.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-1 | automated test | `tests/0012-themes.sh`: `${env.KC_DB_PASSWORD}` refused naming file and line, before any docker call; nothing registered |
| AC-2 | automated test | `tests/0012-themes.sh`: `\u0024{…}`, `\$\{…}`, a continuation split, `${java.version}` in an email theme, `Theme.Properties`, CRLF refused |
| AC-3 | automated test (stand-in, Linux) | `tests/0012-themes.stand-in.sh`: a link to `/proc/self/environ` and a linked theme directory refused, nothing registered |
| AC-4 | automated test (stand-in) | `tests/0012-themes.stand-in.sh`: through `sudo c4-app register`, refused, theme not installed, `StartedAt` unchanged |
| AC-5 | automated test (dev stack) | `tests/0012-themes.sh`: Tickee's theme and the twins registered and installed |
| AC-6 | mutation check | step 6: `tests/0012-themes.sh` with `origin/main`'s `register-app.sh` → `KO`, `exit=1` |
| AC-7 | automated tests + check at delivery | `tests/0012-themes.stand-in.sh` and `tests/0009-*` (master from `keycloak-import`, Keycloak's environment without the passwords); step 7 on the workstation |
| AC-8 | review | README's themes section states REQ-1 and REQ-2 and why |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

- 2026-10-23 — step 3: the twin `verif-ok`'s line `verifTwin=x$\\` (an even number of backslashes: the line ends there) was committed at step 1 with a single backslash (the shell that wrote the fixture collapsed `\\`), which continues the line into `${env.KC_DB_PASSWORD}`: the new check refused it, rightly (Java reads it that way). — The fixture now holds the two backslashes its own comment describes; the test script is unchanged. — `tests/fixtures/0012/themes/verif-ok/login/theme.properties`; proof unchanged (AC-5's must-not-fire twin).
