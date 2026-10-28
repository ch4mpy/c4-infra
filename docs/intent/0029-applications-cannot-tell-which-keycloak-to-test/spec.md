# Spec: An application can't tell which Keycloak its tests should run

- Intent: [0029](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the stack's Keycloak, its realms, accounts and networks don't change, and what c4-infra publishes holds no secret, RQ-06; it would be high if a decision put a secret or the master realm into it)
- Policies applied: none yet; standing constraints: README design (Keycloak 26.8.1 pinned with its features, 0013), the demo host's image tagged by `keycloak/`'s content (`deploy-demo.yml`, `compose.yml`), no secret in Keycloak's environment nor its image (0012), the simulated realms imported by `keycloak-import`, outside `keycloak/` (0016), CLAUDE.md (scripts under bash and Git Bash; a script comes with its test)
- Approved: 2026-10-28, Jérôme Wacongne (product owner; every point of attention decided as recommended)

## Summary

c4-infra says, in a form a script and a build read, which Keycloak an application's tests should run: the upstream version, the features, the build options, and the stack's own image when it publishes one (PA-01, PA-02); a test keeps that description equal to `keycloak/Dockerfile`. The README says what the stack adds and whether a test needs it (PA-03), and how an application learns of a change (PA-04). For an application's developers and its CI, on GitLab as on GitHub; the demo host's deployment doesn't change.

## Requirements

- **RQ-01:** c4-infra describes the Keycloak an application's tests should run in a form a script and a build read (`KEY=value`): the upstream version, the features, the build options the stack sets (`/auth`, database, health, metrics, cache), and the image reference when one is published (PA-01, PA-02). (intent: outcome; open question)
- **RQ-02:** That description never differs from `keycloak/Dockerfile`: a test of the suite fails, naming the difference, when it does. (intent: problem, immo drifted unseen)
- **RQ-03:** If the image is published (PA-01): an anonymous pull gets it, from any CI platform; its tag never moves (PA-02); it is the build the demo host runs for the same content of `keycloak/`; its version and features are read from the image itself (`docker image inspect`), without access to the repository. (intent: constraint, a CI on another platform; outcome, the same Keycloak)
- **RQ-04:** The README says, for an application's tests: what to run (the image, or the version and features), the start options to set (`/auth`, plain HTTP, a database for a container of its own), what the stack adds and whether a test reproduces it (PA-03); `docs/migration.md` adds the step for a project that tests against a Keycloak of its own. (intent: outcome; affected systems)
- **RQ-05:** An application learns of a change of the version, the features or what the stack adds through PA-04's channel, which the README names. (intent: outcome, "learn when it changes")
- **RQ-06:** Nothing c4-infra publishes for the tests holds a secret: no credential in the image's environment, labels or files; the master realm (its administrator's and SMTP placeholders) stays the stack's own. (standing constraint, 0012)
- **RQ-07:** The demo host keeps its image tagged by `keycloak/`'s content: a push that doesn't change `keycloak/` builds nothing and restarts no Keycloak; dev keeps building the image locally. (standing constraint, 0013)

## Out of scope

- An application's test design (its container class, realm import, Mailpit, administrator: immo's `ImmoKeycloakContainer`) and its alignment: each application's own intent, the skills' templates included.
- A change of Keycloak's version, features or start options; the reverse proxy's image; making the c4-infra repository public.

## Design

### Current behaviour

- `keycloak/Dockerfile:4-6` pins `quay.io/keycloak/keycloak:26.8.1`; `:10-14` PostgreSQL, `/auth`, health, metrics, local cache; `:19` `KC_FEATURES=token-exchange-delegation,parameterized-scopes,cimd`; `:24-26` the stack's themes, a JAR among the providers; `:28` `kc.sh build`. No secret. README "Design" (`README.md:51-65`) gives version and features in prose; "What an application provides" and `docs/migration.md` say nothing of tests.
- Dev builds the image locally as `c4-infra/keycloak`, never pushed (`env.sh:24`, `compose.dev.yml:31-33`). The workflow tags it `ghcr.io/ch4mpy/c4-infra-keycloak:<git tree of keycloak/, 12 hex>` (today `33909cd89858`) and builds and pushes it only when that tag is missing, on a push to `main` (`deploy-demo.yml:6-11`, `:39-74`); no other tag.
- The package is private: GHCR refuses it an anonymous pull token ("authentication required", 2026-10-28, where a public package gets one), and the deployment logs in to pull (`deploy-demo.yml:153`); the repository is private too (`gh api /repos/ch4mpy/c4-infra`). A package's visibility is its own, not its repository's; once public, it can't be made private again (GitHub docs, package access control and visibility).
- The master and simulated realms aren't in the image: `keycloak-import` imports them at each start from `keycloak-import/`, kept outside `keycloak/` so that a change there restarts nothing (`compose.yml:100-139`, `:134-135`); the simulated realms' client is tied to `https://${INFRA_HOST}/auth/realms/*` (`simulated-*-realm.json:170`), the master realm holds the administrator's and SMTP credentials (`master-realm.json:15-16`, `:35-42`).
- immo runs `quay.io/keycloak/keycloak:26.7`, a floating minor (`ImmoKeycloakContainer.java:61-62`), through testcontainers-keycloak 4.4.0 (`start-dev` by default), copies `/auth`, metrics and the cache by hand and enables no feature (`:129-138`), while its spec 0021 (EX-12) has `cimd` on in the tests' container and its `keycloak/README.md:5` says "Keycloak is c4-infra's, 26.7". Its pull policy (`:130`, Testcontainers' default) pulls a tag once, never again. Its CI is GitLab's and not written yet (no root `.gitlab-ci.yml`; its *Décisions techniques*: CI out of scope for now). Faito and Tickee run no Keycloak in their tests.
- Not measured (Docker busy at draft): whether the stack's image, built for PostgreSQL (`KC_DB=postgres` in its environment), starts in dev mode with `KC_DB=dev-file` alone; AC-04 settles it.

### Behaviour per persona

- **Application's developers**: read the version, features and image in c4-infra's description (its clone is beside the project), start their tests' container from them, and learn of a change through PA-04.
- **Application's CI on another platform** (GitLab): pulls the image without credentials and reads its version and features from it (PA-01 A or C), the repository being private; otherwise starts upstream Keycloak with the version and features the application pins.
- **Demo operator**: nothing changes (RQ-07).

### API and contracts

- Description: a `KEY=value` file at a stable, documented path of c4-infra, sourced by bash (Ubuntu, Git Bash) and read by a build (e.g. a Maven properties file): the Dockerfile's version, `KC_FEATURES`, `KC_HTTP_RELATIVE_PATH`, `KC_DB`, `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED`, `KC_CACHE`, and the image reference if PA-01 publishes one.
- Image (PA-01 A or C): `ghcr.io/ch4mpy/c4-infra-keycloak:<PA-02's tag>`, public; its configuration carries `KC_FEATURES` (already) and the label `org.opencontainers.image.version=<upstream version>`.
- A test container's start options (README): `/auth`, plain HTTP, its own database (the image is built for PostgreSQL).

### User interface

None.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| 0013: Keycloak pinned, its features listed | RQ-01, RQ-02: the description reads the pin, never a floating tag |
| Demo image tagged by `keycloak/`'s content | RQ-07: PA-02's tag is added beside it, on the same build |
| 0012: no secret in Keycloak's environment | RQ-06, AC-05 |
| 0016: simulated realms imported by `keycloak-import`, outside `keycloak/` | PA-03 |
| CLAUDE.md: bash and Git Bash; a script comes with its test | RQ-02's test; AC-01 under both |

## Points of attention

### PA-01: What c4-infra publishes for an application's tests

- Issue: the intent's open question. Only the stack's image is the same Keycloak (its themes included), but its package is private, and a public package can't go back.
- Options: A) the stack's image, its package made public (the content of `keycloak/` readable by anyone, the repository staying private) / B) the description only: the application starts `quay.io/keycloak/keycloak:<version>` with the features, without the stack's themes / C) both.
- Recommendation: C: the image gives a CI on any platform the same Keycloak with no credential and no access to the repository; the description lets a developer's check or a build read version and features without pulling. `keycloak/` holds nothing private (Dockerfile, healthcheck, the simulated themes the demo host already serves).
- Decides: PO
- Decision: C, as recommended (PO, Jérôme Wacongne, 2026-10-28)

### PA-02: The published image's tag (PA-01 A or C)

- Issue: today's tag (`33909cd89858`) says nothing and no tool orders it; a moving tag stays, under Testcontainers' default pull policy, on the copy first pulled (immo, `:130`): the silent drift again.
- Options: A) `<version>-<content hash>` (`26.8.1-33909cd89858`) beside today's: immutable, the version readable / B) a moving `<version>` and `latest`, which an application pins by digest for its dependency bot to update / C) A and B.
- Recommendation: A: an application's tests stay reproducible and its code shows the version; PA-04 says when to move; B's bot is each application's own setup.
- Decides: PO
- Decision: A, as recommended (PO, Jérôme Wacongne, 2026-10-28)

### PA-03: The stack's themes and simulated realms in an application's test Keycloak

- Issue: the themes are in the image and come with it; the simulated realms aren't: imported on the shared host, tied to `INFRA_HOST`, reached by an application's realm at the shared issuer. In the image, each change of a realm file would restart the demo's Keycloak (`compose.yml:134-135` avoid it).
- Options: A) the themes with the image, the simulated realms not: the README says how a test imports them from c4-infra's files and re-points its provider's URLs / B) both in what is published (the realm files in the image, or an artifact beside it) / C) neither (an image without the stack's themes for tests).
- Recommendation: A: the themes cost nothing and are what the stack serves; no application tests a simulated login yet; a later intent if one does.
- Decides: PO
- Decision: A, as recommended (PO, Jérôme Wacongne, 2026-10-28)

### PA-04: How an application learns of a change

- Issue: c4-infra knows no application's tests, and a GitLab CI can't read its private repository: the application pulls the news.
- Options: A) the description only: an application's check compares its pin with it on a workstation, c4-infra's clone beside the project / B) A, plus a dated changelog in the README of each change of the image (version, features, themes) and what it asks of an application (immo regenerates its admin API's client at a new version, its `keycloak/README.md:5`), a test refusing a change of `keycloak/` without its entry / C) nothing: the application watches c4-infra's commits.
- Recommendation: B: the description detects the change, the changelog says what it means, the test keeps it from being forgotten.
- Decides: PO
- Decision: B, as recommended (PO, Jérôme Wacongne, 2026-10-28)

## Acceptance criteria

- **AC-01:** Given c4-infra, when a script under bash and Git Bash reads the description, then it gets `26.8.1`, `token-exchange-delegation,parameterized-scopes,cimd`, the build options of `keycloak/Dockerfile` and, per PA-01, the image reference. (RQ-01)
- **AC-02:** Given a version or a feature changed in `keycloak/Dockerfile` and not in the description, or the reverse, when `bash tests/run.sh --changed` runs, then a test fails naming the difference. (RQ-02)
- **AC-03:** Given PA-01 A or C and the workflow run on `main`, when a machine without credentials pulls the published reference, then it gets the digest the demo host runs, and `docker image inspect` gives its version and features. (RQ-03)
- **AC-04:** Given the stack's image, when a throwaway container starts it with the README's start options and no PostgreSQL, then Keycloak is ready under `/auth`, with the three features on and the stack's themes listed. (RQ-04)
- **AC-05:** Given what c4-infra publishes, then no environment variable, label or file of the image holds a password, a secret or a realm with credentials. (RQ-06)
- **AC-06:** Given a push to `main` that doesn't change `keycloak/`, when the workflow runs, then no image is built, the published references stay, and the demo host's Keycloak isn't restarted. (RQ-07)
- **AC-07:** Given the README, then it names what an application's tests run, the start options, what the stack adds and whether a test has it (PA-03), and how a change is announced (PA-04); `docs/migration.md` has the step. (RQ-04, RQ-05)
- **AC-08:** Given PA-04 B, when `keycloak/` changes without a changelog entry for its new content, then a test fails. (RQ-05)

## Intent questions

- Publish the image the workflow pushes, a readable version and feature list, or both → PA-01 (its tag: PA-02).

## Change log

- v1 — 2026-10-28 — first version
- v1 — 2026-10-28 — approved: every point of attention decided as recommended (Jérôme Wacongne, PO)
