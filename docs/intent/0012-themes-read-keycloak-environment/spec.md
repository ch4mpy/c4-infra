# Spec: An application's Keycloak theme may read the shared Keycloak's environment

- Intent: [0012](intent.md)
- Status: draft
- Version: 1
- Risk: high (rules: secrets, the isolation between applications; tech lead's agreement required)
- Policies applied: none yet; standing constraints: README design, `CLAUDE.md` (no password on a command line), 0003 (dev and the demo host alike), 0007 (one network per application), 0009 (the master realm's creation), 0011 (its accepted risk)
- Approved: —

## Summary

Measured on Keycloak 26.7.4 and 26.8.1: a theme brings Keycloak's environment into public pages in two ways. Keycloak resolves `${env.NAME}` and Java system properties in a theme's `theme.properties`, and a login theme shows them in the login page's HTML with no template of its own. A symbolic link among a theme's resources serves Keycloak's whole environment (`/proc/self/environ`) as a public file. A registration now refuses both, in dev and on the demo host, before anything changes. Themes without them register as before. Whether Keycloak's running environment should also lose the secrets it only needs to create the master realm is PA-2.

## Requirements

- REQ-1 A registration (`register-app.sh --themes` in dev, `sudo c4-app register --themes` on the demo host) refuses a theme whose `theme.properties`, of any theme type, has a value containing `${` as Keycloak reads it: `\uXXXX` escapes decoded, continuation lines joined. (intent: outcome, criterion)
- REQ-2 A registration refuses a theme that holds a symbolic link or a special file, in dev as on the demo host (where `c4-app` already refuses them in everything an application sends). (intent: outcome)
- REQ-3 A refused theme registers nothing: no realm imported, no theme installed or replaced, no route, no RabbitMQ change, no Keycloak restart. The message names the theme's file and the line or link, and why. (intent: outcome; the registration's other refusals)
- REQ-4 A theme with neither registers as before: its templates' `${…}` (`${msg(…)}`, `${url.resourcesPath}`) and its messages' `{0}` are untouched; Tickee's `tickee` theme registers unchanged. (intent: constraint)
- REQ-5 The README states what a theme may not hold and why. (intent: outcome)
- REQ-6 Depending on PA-2: the running Keycloak's environment no longer holds the master realm administrator's password nor Mailpit's SMTP password, which only the master realm's creation needs (0009); the master realm is still created with 0009's settings. (intent: suggested solution)

## Out of scope

- A theme's scripts and styles: they run in the visitors' browsers, on the pages of the realms that choose the theme, the application's own.
- Placeholders in a realm export: the registration imports realms through Keycloak's admin API, which resolves none (measured below).
- Keycloak providers (jars): no application installs any; the registration has no option for them.
- Rotating the secrets: no application has registered a theme yet, in dev or on the demo host (below), so none has leaked this way.

## Design

### Current behaviour

Measured in throwaway containers (`quay.io/keycloak/keycloak:26.7`, which is 26.7.4, and `26.8.1`, `start-dev`), with `PROBE_SECRET`, `KC_DB_PASSWORD` and a system property `probe.sys` set, and a realm whose login theme is the probe:

| Path | Result on 26.7.4 and 26.8.1 |
| --- | --- |
| `theme.properties` (parent `keycloak`): `kcHtmlClass=… ${env.PROBE_SECRET} ${env.KC_DB_PASSWORD} ${probe.sys} ${kc.home.dir}` | **resolved**, in the login page's `<html class="…">`: `PROPENV[probe-env-value-4711]`, `PROPDB[probe-db-password-0815]`, `PROPSYS[probe-sysprop-value]`, `PROPKCHOME[/opt/keycloak/bin/..]` |
| `theme.properties`: `${quarkus.datasource.password}`, `${kc.db-password}` (Keycloak's own options) | not resolved |
| A login template (`login.ftl`): `"freemarker.template.utility.Execute"?new()`, `?api`, `statics` | refused (`Instantiating … is not allowed`, `api_builtin_enabled … false`); a template reads the resolved `properties` only |
| A message bundle: `probeMsg=${env.PROBE_SECRET}` | not resolved |
| A link `resources/leak.txt -> /proc/self/environ` in the theme | **served**: `GET /auth/resources/<v>/login/probe-link/leak.txt` → `200`, Keycloak's whole environment |
| A realm created through the admin API with `displayName` `${env.PROBE_SECRET}` | not resolved (shown as written) |

Keycloak documents this resolution (since 8.0: "system properties and environment variables support in `theme.properties`"; its example, `unixHome=${env.HOME:…}`): a theme written from Keycloak's documentation can trigger it without any hostile intent.

- Keycloak's environment on the stack (`compose.yml:104-122`): `C4_MASTER_ADMIN_PASSWORD` (the master realm's administrator, permanent since 0009), `KC_DB_PASSWORD`, `MAILPIT_SMTP_PASSWORD`, `MAILPIT_SMTP_USER`, `C4_MASTER_ADMIN_USERNAME`, `INFRA_HOST`. `KC_DB_PASSWORD` opens a database that only Keycloak reaches (0007).
- `register-app.sh:166-171` checks a theme's name against the registry entry, then `cp -r` installs it (`:286-300`), keeping symbolic links. On the demo host, `c4-app` refuses symbolic and special files in everything the application sends (`demo/c4-app:133-155`), themes included.
- Installed themes: none (`keycloak/themes/` holds `.gitkeep` only, in the repository and in dev; no application has deployed to the demo host yet). Tickee's theme, the only one in the registry, has no `${`, `\u` escape, continuation line or link in its `theme.properties` files.

### Behaviour per persona

- Application: a theme whose `theme.properties` names an environment variable or a system property, or that holds a link, is refused at registration with the file and the reason; the application fixes its theme and deploys again. Other themes: no change.
- Demo visitor: no page of the shared Keycloak shows a value of its environment.
- Developer and demo operator: the same refusal in dev and on the demo host.

### API and contracts

- `register-app.sh --themes <dir>` and `sudo c4-app register --themes <dir>`: new refusals, with a non-zero exit and nothing registered (REQ-3), messages such as `<theme>/login/theme.properties:3: '${' is resolved by Keycloak from its environment and system properties: refused` and `<theme>/login/resources/x: a symbolic link: refused`.

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| README design (one Keycloak for every application; an application reaches its own resources only) | REQ-1 to REQ-3 |
| 0003: dev and the demo host alike | the same refusals in both (REQ-1, REQ-2) |
| 0009: the master realm created from `keycloak-import/master-realm.json` | unchanged, or created by a one-shot import → PA-2 |
| 0011: a leaked deployment key is an accepted risk | → PA-1 |
| No password on a command line (`CLAUDE.md`) | no password involved; PA-2's option B gives them as environment to a one-shot process |

## Points of attention

### PA-1 Inside or outside 0011's accepted risk

- Issue: 0011 accepts that a leaked deployment key isn't contained. This path needs a file in an application's deployment too, but the leak is public (any visitor of a login page) and needs no hostile intent: Keycloak's own documentation shows `${env.HOME}` in a theme.
- Options: A outside: fixed by this spec / B inside: recorded as accepted, the intent closed with the measurements
- Recommendation: A: the value shown opens every application's realm, a careless theme is enough, and the fix is a static check at registration.
- Decides: product owner
- Decision: to decide

### PA-2 Keycloak's running environment keeps the master realm's secrets

- Issue: REQ-1 and REQ-2 close the two measured paths. Any other path to Keycloak's environment (a Keycloak change, a path not measured here) would still find the master administrator's password, permanent since 0009, and Mailpit's, which only the master realm's creation reads.
- Options: A the refusals only / B also: the master realm created by a one-shot import that runs before Keycloak, with these two secrets, which the running Keycloak no longer gets (REQ-6); 0009's creation path changes, and its tests run again / C B, and the database password read from a file rather than the environment
- Recommendation: B: a second line for the most valuable secret, at the cost of one short-lived process; C adds little, the database being reachable from Keycloak only (0007).
- Decides: product owner and tech lead
- Decision: to decide

## Acceptance criteria

- AC-1 Given a theme whose `login/theme.properties` has `kcHtmlClass=${env.KC_DB_PASSWORD}`, when an application registers with it in dev, then the registration fails naming the file and line, and its realm isn't imported, no theme is installed, its site and RabbitMQ user are unchanged. (REQ-1, REQ-3)
- AC-2 Given the same value written `${env.KC_DB_PASSWORD}`, or split by a continuation line between `$` and `{`, or a system property (`${java.version}`) in an `email/theme.properties`, when registered, then refused likewise. (REQ-1)
- AC-3 Given a theme holding a symbolic link in its resources, when registered in dev, then refused naming the link, nothing registered. (REQ-2, REQ-3)
- AC-4 Given the stand-in demo host, when an application runs `sudo c4-app register --themes` with AC-1's theme, then refused, nothing registered and Keycloak not restarted; with a link, refused by `c4-app`. (REQ-1, REQ-2, REQ-3)
- AC-5 Given Tickee's `tickee` theme, and a theme whose templates use `${msg(…)}` and whose messages use `{0}`, when registered, then installed as before. (REQ-4)
- AC-6 Given the test of AC-1, run on the code before this change, then it fails (the theme is installed): the test guards the fix. (REQ-1)
- AC-7 (PA-2 B) Given a stack started on an empty database, in dev and on the stand-in demo host, then the master realm has 0009's settings (0009's tests pass), and the running Keycloak's environment (`/proc/1/environ` in `c4-infra.keycloak`) holds neither the administrator's password nor Mailpit's. (REQ-6)
- AC-8 The README's themes section states REQ-1 and REQ-2's rules and their reason. (REQ-5)

## Intent questions

- Does Keycloak 26 resolve `${env.NAME}`, or system properties, in `theme.properties`, templates or message bundles? → In `theme.properties`, yes, both, on 26.7.4 and 26.8.1, and a login theme shows them with no template; not in message bundles; templates can't reach the environment otherwise. Plus a second path: a symbolic link among the resources (Current behaviour).
- Is this path inside 0011's accepted risk? → PA-1.
- *Suggested solutions*: refusal at registration → REQ-1, REQ-2; the administrator's password out of Keycloak's running environment → PA-2.

## Change log

- v1 — 2026-10-23 — first version
