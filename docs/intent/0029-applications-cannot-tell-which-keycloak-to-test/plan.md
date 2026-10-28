# Plan: An application can't tell which Keycloak its tests should run

- Spec: [v1](spec.md)
- Status: approved
- Branch: 0029-applications-cannot-tell-which-keycloak-to-test
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the batch and the agents, product owner)
- Builds on: `main` at 75d2809 (0025 delivered), merged into the branch at step 0

## Starting point

- `keycloak/Dockerfile`: `:4` `ARG KC_VERSION=26.8.1`, `:6` `FROM quay.io/keycloak/keycloak:${KC_VERSION}`, `:10-14` `ENV KC_DB=postgres`, `KC_HTTP_RELATIVE_PATH=/auth`, `KC_HEALTH_ENABLED=true`, `KC_METRICS_ENABLED=true`, `KC_CACHE=local`, `:19` `ENV KC_FEATURES=token-exchange-delegation,parameterized-scopes,cimd`, `:24-26` the stack's themes as a JAR among the providers, `:28` `kc.sh build`, `:32-33` the healthcheck. No `LABEL`. Read on quay.io on 2026-10-28 (the registry API, the amd64 manifest's config): the upstream image already carries `org.opencontainers.image.version=26.8.1` and `version=26.8.1` in its labels, which `FROM` passes on to the stack's image. Its environment holds no credential (`PATH`, `LANG`, `KC_RUN_IN_CONTAINER`).
- `.github/workflows/deploy-demo.yml`: `:6-12` runs on a push to `main` (not for `**/*.md` nor `.claude/**` alone) and on `workflow_dispatch`; `:39-43` the hash tag `ghcr.io/${owner,,}/c4-infra-keycloak:$(git rev-parse --short=12 HEAD:keycloak)`; `:51-62` `docker manifest inspect` for each tag; `:64-65` buildx set up only when a build is due; `:67-74` `build-push-action` builds and pushes only a missing tag (`tags:` the hash tag only); `:97` the deploy job's `KC_IMAGE` is that hash tag; `:153` the host logs in to pull (private package).
- `demo/deploy.sh:40-45`: a `KC_IMAGE` other than the running Keycloak's `.Config.Image` dumps the database and stops Keycloak first. The deploy job must keep the hash reference, or every deployment would see a new image.
- `keycloak/`'s trees, each a version of the package: `3ef3c92932a3` (19096a5, Keycloak 26.7), `5c653a7874f9` (eb1ae92, 0013), `33909cd89858` (84cc955, 0016, today's `main`): `Dockerfile`, `HealthCheck.java`, `themes/.gitkeep`, `stack-themes/**`. None holds a secret. Making the package public publishes every one of them, not just the new tag.
- GHCR today: `curl "https://ghcr.io/token?scope=repository:ch4mpy/c4-infra-keycloak:pull"` → `{"errors":[{"code":"UNAUTHORIZED","message":"authentication required"}]}` (private, 2026-10-28). `ch4mpy` is a user account (`gh api /users/ch4mpy`). This session's `gh` token lacks `read:packages` (403 on the package and its versions). GitHub's docs: a linked package inherits the repository's access "but not the visibility". Visibility changes in the package's settings only (no REST endpoint), and "Once you make a package public, you cannot make it private again".
- `docker buildx imagetools create` with a single source that is an image index "performs a carbon copy" (Docker's reference), so a second tag on the same digest. `build-push-action` with a `docker-container` builder pushes an index (the image and its provenance attestation). Step 0 measures it.
- `tests/0013-keycloak-facts.sh:69` and `tests/0016-keycloak-facts.sh:75-78` already start `c4-infra/keycloak` with `start-dev --db=dev-file`: the image built for PostgreSQL starts on a file database. The spec's "not measured" is settled for the flag. The variable (`KC_DB=dev-file`, what Testcontainers' `withEnv` sets) is measured at step 0. Helpers: `kc_throwaway_ready` (`tests/lib/keycloak.sh:105-117`, `:9000/auth/health/ready`), `kc_features` (`:132-134`).
- Precedents: `tests/0004-upload.sh:24-26` runs the workflow's own command, read from the YAML. `tests/0004-registry.sh:207-209` reads one README section with `awk`. `.gitattributes`: `* text=auto eol=lf`, so a new root file checks out LF under Git Bash.
- Docs today: `README.md:51-65` (Design) gives version and features in prose; `:194` "What an application provides" and `docs/migration.md` (steps 1-8 "In dev", `:15-131`) say nothing of tests; `docs/demo-setup.md:153-155` and `CLAUDE.md:11` say the images are tagged by their directory's content.
- immo (read only): `ImmoKeycloakContainer.java:61-62` `quay.io/keycloak/keycloak:26.7`; `:129-138` `PullPolicy.defaultPolicy()`, `withContextPath("/auth")`, `KC_CACHE`, `KC_HTTP_ENABLED` by hand, no feature; testcontainers-keycloak runs `start-dev`. With the published image it would set `KC_DB=dev-file` (`withEnv`), drop what the image sets already, and never call `withFeaturesEnabled` (a `--features` would replace the image's). That alignment is immo's own intent.
- In parallel: 0028 (accepted, no spec) will rewrite parts of `docs/migration.md` and `README.md`.

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Proposed by Claude, to confirm with this plan (those marked **to confirm** have an alternative worth a word):

- **C1 — The description** (**to confirm**: its name, its place, its keys): `keycloak-image.properties` at the root of c4-infra. Its lines are comments (`#`) and `KEY=value`, with no quotes, spaces, `$` or backslash in a value, so bash, Git Bash and Java's `Properties` (Maven's `properties-maven-plugin`, Gradle) read it the same way. Its keys:
  - `KC_VERSION=26.8.1`, the Dockerfile's `ARG` name;
  - `KC_FEATURES`, `KC_DB`, `KC_HTTP_RELATIVE_PATH`, `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED` and `KC_CACHE`, Keycloak's own names, as in the Dockerfile, so an upstream container takes them as they are (`KC_DB` aside, see C7);
  - `KC_PUBLISHED_IMAGE=ghcr.io/ch4mpy/c4-infra-keycloak:26.8.1-33909cd89858`.

  Rejected:
  - inside `keycloak/`: the file names `keycloak/`'s own tree, which would be circular, and each edit would rebuild the image and restart the demo's Keycloak;
  - `.env`: it reads as secrets, `.gitignore` already ignores `.env`, and the stack's `.env` and the workflow already use `KC_IMAGE` for the stack's own reference, hence `KC_PUBLISHED_IMAGE`;
  - JSON: bash can't source it.
- **C2 — `keycloak/` doesn't change** (**to confirm**): the version label comes from upstream (Starting point), so this change builds nothing and restarts nothing. The first published reference is the digest the demo host runs today, `26.8.1-33909cd89858`. The facts test checks that the label equals `KC_VERSION`: if a later upstream version dropped it, that test would fail at the version bump, and a `LABEL` would then go into the Dockerfile. Rejected: an explicit `LABEL` now (a new tree, so a rebuild, and the demo's Keycloak dumped and restarted, for a label the image already has).
- **C3 — The version tag** is added to the hash tag's index by `docker buildx imagetools create` (a carbon copy, same digest), only when it is missing, and only after checking that the source is an index; otherwise the step refuses before tagging. Every run then prints both digests and fails if they differ. The deploy job keeps the hash tag (`demo/deploy.sh:40-45`). Rejected:
  - a second `tags:` on `build-push-action`: only new builds would get one, and today's image never would without a rebuild;
  - `docker pull`/`tag`/`push`: it loses the index, so another digest;
  - `crane` or `regctl`: one more action to pin, for what buildx does.
- **C4 — The workflow refuses a description that differs** (**to confirm**: a mismatch stops that push's deployment). "Compute the images" computes the version tag from `ARG KC_VERSION` and `HEAD:keycloak` (the hash computed as today), and fails before any login or push when `keycloak-image.properties` names another reference (`::error::` naming both). Rejected: the workflow sourcing the description, which would publish whatever it says.
- **C5 — Two tests:**
  - `tests/0029-description.sh` is static, fast, and runs in every `--changed` that touches `keycloak/`. It compares the description and the Dockerfile in both directions. Its mutations are copies it makes and edits itself (no fixtures). It computes the working tree's `keycloak/` tree through a temporary index and object directory (`GIT_INDEX_FILE`, and `GIT_OBJECT_DIRECTORY` with the repository's as an alternate), so the repository isn't written. It also runs the workflow's own "Compute the images" block, as `0004-upload.sh` runs the upload line.
  - `tests/0029-image-facts.sh [<image>]` starts a throwaway of `c4-infra/keycloak` by default. Given the published reference, it checks that image instead (step 7).

  Rejected: a `demo/` script holding the tag computation, one more script for six lines that run on the runner only.
- **C6 — The changelog** (**to confirm**: the section's name and place) goes in a new README section, `### Keycloak in an application's tests`, after "Simulated social providers". Its entries come newest first, each a list item: the date, the tag in a code span, what changed, then what it asks of an application. The first one: "2026-10-28 — `26.8.1-33909cd89858`: first published; Keycloak 26.8.1, its three features, the simulated providers' login themes (0016)." The test requires an entry naming the current tag. Rejected: a file of its own (PA-04 B says the README).
- **C7 — The start options the README gives** (and the facts test runs, nothing more): `start-dev` with `KC_DB=dev-file`, as a variable so Testcontainers' `withEnv` sets it. The image already sets `/auth`, health, metrics and the local cache. `start-dev` serves plain HTTP. The test container has a bootstrap administrator of its own. No `--features`. For upstream Keycloak: `quay.io/keycloak/keycloak:$KC_VERSION` with `KC_FEATURES`, `KC_HTTP_RELATIVE_PATH`, health, metrics, cache from the description, and no stack themes.
- **C8 — The package's older versions** (**to confirm**): `3ef3c92932a3`, `5c653a7874f9`, and any untagged one become public with the package. They are kept, and step 7 checks them like the new one. Alternative: delete them before (`delete:packages`, restorable 30 days), which is pointless if they hold nothing.
- **C9 — Verification** (**to confirm**): risk tier standard, so bootstrap mode runs the bugs pass only. Proposed: the `security-review` pass as well, because publication can't be undone.

## Files

| File | Change | For |
| --- | --- | --- |
| `keycloak-image.properties` | new: C1's keys and values, a header comment (what it is, the README section, the test that keeps it equal to `keycloak/Dockerfile` and to the published tag) | RQ-01, RQ-03, AC-01 |
| `tests/0029-description.sh` | new, `# covers: keycloak/ keycloak-image.properties .github/workflows/ README.md docs/migration.md`. (a) Form: every line a comment, blank, or `^[A-Z][A-Z0-9_]*=[A-Za-z0-9._,/:@+-]*$`, no CR. (b) Sourced in a subshell (`set -a; . ./keycloak-image.properties`): each value printed and equal to its line's text. (c) Keys = `KC_VERSION`, `KC_PUBLISHED_IMAGE` and every `ENV KC_*` of the Dockerfile, values equal, each difference named both ways (`KC_FEATURES: keycloak/Dockerfile says …, keycloak-image.properties says …`; `KC_LOG_LEVEL: in keycloak/Dockerfile, not in keycloak-image.properties`), and shown on its own copies: a feature removed from the Dockerfile, another version in the description, an `ENV` added to the Dockerfile, a key added to the description. (d) `KC_PUBLISHED_IMAGE` = `ghcr.io/ch4mpy/c4-infra-keycloak:<KC_VERSION>-<first 12 hex of the working tree's keycloak/ tree>` (another hash on a copy: named). (e) The workflow's "Compute the images" block run with `GITHUB_OUTPUT` a temp file, `REGISTRY=ghcr.io`, `GITHUB_REPOSITORY_OWNER=ch4mpy`, when `keycloak/` matches `HEAD`: `version_image` = `KC_PUBLISHED_IMAGE`, `image` the hash reference; otherwise skipped, saying so. (f) The README section's changelog holds a dated entry for (d)'s tag (a README copy without it: `no changelog entry for 26.8.1-…`). (g) The section names `keycloak-image.properties`, `start-dev`, `KC_DB=dev-file`; `docs/migration.md` links it | RQ-01, RQ-02, RQ-03, RQ-05, AC-01, AC-02, AC-07, AC-08 |
| `tests/0029-image-facts.sh` | new, `# covers: keycloak/ keycloak-image.properties`, argument `[<image>]` (default `c4-infra/keycloak`). (a) `docker image inspect`: label `org.opencontainers.image.version` = `KC_VERSION`; the environment's `KC_FEATURES`, `KC_DB`, `KC_HTTP_RELATIVE_PATH`, `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED`, `KC_CACHE` = the description's. (b) No environment variable or label whose name or value matches `pass\|secret\|token\|credential\|private` (case ignored). The files the image adds over `quay.io/keycloak/keycloak:<KC_VERSION>` are the expected ones (step 0, d): `stack-themes/**` as in `keycloak/stack-themes/`, the theme JAR, the healthcheck, `kc.sh build`'s output. No realm file, no `data/import/`. (c) A throwaway `--env-file <admin> -e KC_DB=dev-file <image> start-dev`, nothing else: ready on `:9000/auth/health/ready`; `GET /auth/realms/master` `200` over plain HTTP from inside (bash `/dev/tcp`, as 0013's `authorize`); the log's preview and experimental features = `KC_FEATURES`; `serverinfo`'s login themes include `simulated-google`, `simulated-facebook`, `simulated-apple`; removed whatever happens | RQ-03, RQ-04, RQ-06, AC-03, AC-04, AC-05 |
| `.github/workflows/deploy-demo.yml` | modified. "Compute the images" adds `version_image` (`<version>-<hash>`, version from `ARG KC_VERSION`) and refuses a description naming another (C4). "Look for the images" also checks the version tag. Buildx is set up when the version tag is missing too. A new step, "Tag c4-infra-keycloak with its version", runs only when the version tag is missing: the media type of the hash tag must be an index, then `docker buildx imagetools create --tag <version_image> <image>`. A new step, "Check the published references", runs every time: both digests printed, equal or it fails. The deploy job unchanged (hash tag); comments | RQ-03, RQ-07, AC-03, AC-06 |
| `README.md` | modified. New section `### Keycloak in an application's tests`. What to run: the public image and its reference in the description, or upstream with version and features, without the stack's themes. Reading the description: bash `source`, Maven `read-project-properties`, a workstation check comparing the application's pin with it; or the image itself (`docker image inspect`: label and environment), for a CI that can't read c4-infra. C7's start options, as a `docker run` line and in Testcontainers' terms. What the stack adds and whether a test has it (PA-03): the stack's login themes, in the image; the master realm (its administrator and SMTP), the stack's own, not in it; the simulated realms, not in it (a test imports `keycloak-import/simulated-*-realm.json` with `INFRA_HOST` set to its own host, and re-points its provider's URLs); Mailpit, the registration and the dev brute-force settings, the stack's. How a change is announced (PA-04 B): the description detects it, the changelog says what it asks, a test refuses a change of `keycloak/` without its entry; the tag never moves; the package can't go private again. The changelog (C6). "Design" (`:51`): one line pointing to it | RQ-04, RQ-05, AC-07, AC-08 |
| `docs/migration.md` | modified: under "In dev", a step for a project whose tests start a Keycloak of their own (the published image, or upstream with the description's version and features; no floating tag; the README section), placed after "Scripts", the next steps renumbered | RQ-04, AC-07 |
| `docs/demo-setup.md` | modified (`:153-155`): Keycloak's image also tagged `<version>-<hash>`, public, never moved | RQ-03 |
| `CLAUDE.md` | modified (`:11`): the version tag, the public package, `keycloak-image.properties` beside `keycloak/` | RQ-01, RQ-03 |
| `docs/intent/0029-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status `planned`, then `delivered`; the index row | — |

Not changed: `keycloak/` (C2), `compose*.yml`, `env.sh`, `demo/deploy.sh`, `demo/deploy-files.txt` (the description stays off the demo host).

## Order of work

**Batch** (the product owner, 2026-10-28): 0026 to 0031 are delivered in one batch, merged in this order into `batch-0031-0030-0028-0026-0027-0029`, from `main`: 0031, 0030, 0028, 0026, 0027, 0029. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the six in the batch's order, with one push of `main`, validated by the product owner.

0. **Setup and facts.** `git checkout 0029-applications-cannot-tell-which-keycloak-to-test`, `git merge main`, the dev stack up (`bash up.sh`: `c4-infra/keycloak` from `keycloak/` at `33909cd89858`). Then measure:
   - (a) `docker run -e KC_DB=dev-file c4-infra/keycloak start-dev` (the variable, not the flag) is ready, answers under `/auth` over HTTP, and logs the three features. The image's label `org.opencontainers.image.version` is `26.8.1`.
   - (b) `git rev-parse --short=12 HEAD:keycloak` → `33909cd89858`, so `26.8.1-33909cd89858`. The temporary index and object directory give the same tree on a clean `keycloak/`, and another one after an uncommitted edit (throw-away worktree); `.git/objects` is untouched (`git count-objects -v` before and after).
   - (c) On a throw-away registry (`registry:2` on `127.0.0.1`), an index with a provenance attestation, pushed by a `docker-container` builder, copied by `imagetools create`: the same digest; `docker manifest inspect` of a missing tag fails. With the product owner's GHCR login if available: the media type of `:33909cd89858` is an index.
   - (d) The files `c4-infra/keycloak` adds or changes over `quay.io/keycloak/keycloak:26.8.1`, and the tool that lists them (file lists, and checksums if the image has `sha256sum`).

   — skill: none — check: `git status --short` empty; each fact recorded under *Deviations*. A fact that differs is a deviation before the step that relies on it: (a) → C7; (c) not an index → the tag copied through the registry API (`PUT` of the same manifest) instead.
1. **The description.** `keycloak-image.properties`; `tests/0029-description.sh` parts (a) to (d). — skill: none — check: `bash tests/0029-description.sh` → `every check passed` (the mutated copies named). Commit `feat(0029): …`.
2. **The image's facts.** `tests/0029-image-facts.sh`. — skill: none — check: `bash tests/0029-image-facts.sh` → `every check passed`. Commit.
3. **The workflow.** `.github/workflows/deploy-demo.yml`; part (e) of `tests/0029-description.sh`. — skill: none — check: `bash tests/0029-description.sh && bash tests/0002-workflow.sh && bash tests/0004-upload.sh`. Commit.
4. **The docs.** The README section and its changelog, `docs/migration.md`, `docs/demo-setup.md`, `CLAUDE.md`; parts (f) and (g) of the test. — skill: none — check: `bash tests/0029-description.sh && bash tests/0004-registry.sh && bash tests/0016-no-real-provider.sh && bash tests/0002-workflow.sh`; the section reread against AC-07's list. Commit `docs(0029): …`.
5. **Verification.**
   - `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed main --all`.
   - Mutation checks, in a throw-away worktree:
     - `,cimd` removed from the Dockerfile's `KC_FEATURES`: `bash tests/run.sh --changed` runs `0029-description.sh`, which fails naming `KC_FEATURES`, the reference and the changelog (AC-02, AC-08);
     - a comment changed in `keycloak/HealthCheck.java`: it fails on the reference and on `no changelog entry for 26.8.1-<hash>` (AC-08);
     - another hash in `KC_PUBLISHED_IMAGE`, the workflow's block run by hand: exits 1 with its `::error::` (C4).
   - `/sdlc-verify 0029` (bootstrap: one round; C9). Its evidence goes into `## Verification`, committed as `plan: verification of 0029`.

   — skill: sdlc-verify — check: `verification passed`.
6. **Delivery.** `/sdlc-ship 0029`: the product owner's push to `main`. — skill: sdlc-ship — check, the workflow run's log:
   - "Push c4-infra-keycloak" skipped;
   - "Tag c4-infra-keycloak with its version" ran (index, `26.8.1-33909cd89858` created);
   - "Check the published references" prints one digest twice;
   - the deploy job prints no "Keycloak's image changes", and `docker compose ps` shows `c4-infra.keycloak` up since before the run.
7. **Before publication** (read only; the package still private). The product owner's GHCR login on the workstation: `gh auth refresh -h github.com -s read:packages`, then `gh auth token | docker login ghcr.io -u ch4mpy --password-stdin` (or a classic token with `read:packages`). Then:
   - every version listed: `gh api /users/ch4mpy/packages/container/c4-infra-keycloak/versions --jq '.[] | {id, tags: .metadata.container.tags, created_at}'`;
   - for each tag, its configuration and provenance: `docker buildx imagetools inspect --format '{{json .Image}}'` and `'{{json .Provenance}}'`. No credential in the environment, labels or build arguments; each version's `keycloak/` tree one of Starting point's;
   - `bash tests/0029-image-facts.sh ghcr.io/ch4mpy/c4-infra-keycloak:26.8.1-33909cd89858` → `every check passed`.

   — skill: none — check: all of it recorded in plan.md. Any finding stops here: nothing is made public, and the fix is a new intent or a deviation (versions can still be deleted).
8. **The package made public: the product owner's step, irreversible**, once step 7 is clean.
   - Path: `https://github.com/users/ch4mpy/packages/container/c4-infra-keycloak/settings`, then "Danger Zone", "Change visibility", "Public". Type `c4-infra-keycloak`, then "I understand the consequences, change package visibility". GitHub has no REST endpoint for it.
   - Every version of the package becomes public, and it can't be made private again. The repository stays private.
   - If the page refuses, because of the access the package inherits from the private repository: a deviation, reported, nothing forced.

   — skill: none — check: step 9.
9. **After publication** (no credentials).
   - `t=$(curl -s "https://ghcr.io/token?scope=repository:ch4mpy/c4-infra-keycloak:pull" | jq -r .token)`: a token, where step 0 got `authentication required`.
   - With it, `curl -sI -H "Authorization: Bearer $t" -H 'Accept: application/vnd.oci.image.index.v1+json'` on `/v2/ch4mpy/c4-infra-keycloak/manifests/26.8.1-33909cd89858` and `/manifests/33909cd89858`: the same `docker-content-digest`, the one step 6's log printed.
   - The amd64 manifest's config blob: `org.opencontainers.image.version` `26.8.1`, `KC_FEATURES` the description's.
   - The next run of the workflow on `main` (the next delivery, or `gh workflow run deploy-demo.yml -R ch4mpy/c4-infra` by the product owner): the tag step skipped, the same digest printed twice, no "Keycloak's image changes".

   — skill: none — check: recorded under `### After deployment` in plan.md, commit `plan: 0029 after deployment`.

## Risks

- **Publication can't be undone**, and it exposes every version of the package (three hash tags, untagged ones, their provenance: the repository's name and a commit, no build argument) → AC-05 is checked on every version before (step 7). The product owner alone flips it, after the review and the delivery (step 8). A finding stops it, while versions can still be deleted.
- **The deploy job switched to the version tag** would make `demo/deploy.sh` see another image, then dump and restart Keycloak → the deploy job keeps the hash tag (C3); step 6's log shows no "Keycloak's image changes".
- **`imagetools create` not making a carbon copy** (a source that isn't an index) would tag another digest, under a tag that must never move → the media type is checked before tagging, both digests are compared on every run, and step 0 (c) measures it.
- **The description names a tag that doesn't exist yet** (between the commit and step 6), **or a private one** (until step 8) → steps 6 to 8 follow each other on the delivery day. The README says the reference is pullable once its changelog entry's change has reached `main` and the package is public.
- **C4's check stops a deployment** when the description and `keycloak/` differ → `tests/0029-description.sh` fails first in any `--changed` that touches either; the `::error::` names both references; the fix is one line.
- **`--short=12` gives more than 12 hex when ambiguous** → the test takes the first 12 of the full tree hash, and the workflow's hash tag stays as computed today (RQ-07). Ambiguity at 48 bits in a shallow clone isn't expected; it would show as C4's error, not as a wrong tag.
- **Upstream drops its version label** in a later version → `0029-image-facts.sh` (a) fails at the bump; a `LABEL` goes into the Dockerfile then (C2).
- **The changelog test makes every `keycloak/` change touch `README.md` and the description**: that is the intent (PA-04 B). A dev rebuild (`up.sh`) doesn't care.
- **0028 rewrites `docs/migration.md` and the README** → this change keeps to its own section and one step; whichever lands second merges `main` and reruns its `--changed`.
- **The temporary index** writes blobs and trees → into a temporary object directory, with the repository's objects as an alternate: `.git` is left as it was (step 0, b).

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test | `tests/0029-description.sh` (a), (b): the description sourced by bash prints `KC_VERSION=26.8.1`, `KC_FEATURES=token-exchange-delegation,parameterized-scopes,cimd`, the five build options and `KC_PUBLISHED_IMAGE`, equal to the Dockerfile (c). Git Bash: the same test on the product owner's Windows workstation if there is one; otherwise *not verifiable here*, with the form check (LF by `.gitattributes`, no CR, no quote, no `$`) standing in |
| AC-02 | automated test, mutation check | `tests/0029-description.sh` (c): each difference named, both ways, on its copies; step 5: `,cimd` removed from `keycloak/Dockerfile` in a throw-away worktree → `bash tests/run.sh --changed` runs the test, `KO` naming `KC_FEATURES` |
| AC-03 | automated test, commands after step 8 | Before: `tests/0029-image-facts.sh` (a) on `c4-infra/keycloak` (suite) and on the published reference (step 7). After: step 9's anonymous token, the two tags' `docker-content-digest` equal to each other and to step 6's log (the demo host pulls by the hash tag, which never moves), and the config blob's label and `KC_FEATURES` |
| AC-04 | automated test | `tests/0029-image-facts.sh` (c): `-e KC_DB=dev-file … start-dev`, no PostgreSQL: ready, `/auth/realms/master` `200` over HTTP, the three features, the three stack login themes; on `c4-infra/keycloak` (suite) and on the published reference (step 7) |
| AC-05 | automated test, read-only check before step 8 | `tests/0029-image-facts.sh` (b) (environment, labels, the files added over upstream: no credential, no realm); step 7: every version's configuration and provenance |
| AC-06 | log of the workflow runs | Step 6 (a push that doesn't change `keycloak/`): no build, no "Keycloak's image changes", Keycloak up since before; step 9's next run: the tag step skipped, both digests unchanged. `tests/0029-description.sh` (e): the hash reference computed as before |
| AC-07 | manual check, automated presence | The README section reread against AC-07's list (what to run, start options, what the stack adds and whether a test has it, the announcement), and `docs/migration.md`'s step. `tests/0029-description.sh` (g) for the names it must hold |
| AC-08 | automated test, mutation check | `tests/0029-description.sh` (f): a README copy without the entry → named; step 5: `keycloak/HealthCheck.java`'s comment changed in a throw-away worktree → `KO`, `no changelog entry for 26.8.1-<hash>` |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
- 2026-10-28 — step 0, facts (on the workstation; `c4-infra/keycloak` built from `keycloak/` at `33909cd89858`):
  - (a) `docker run --env-file <admin> -e KC_DB=dev-file c4-infra/keycloak start-dev`: ready on `:9000/auth/health/ready`; `GET /auth/realms/master` → `HTTP/1.0 200 OK` over plain HTTP from inside; the log's `Preview features enabled: parameterized-scopes:v1, token-exchange-delegation:v1` and `Experimental features enabled: cimd:v1`. The label `org.opencontainers.image.version` is `26.8.1` (and `version`); the environment as the Dockerfile sets it, no credential. The local image also carries compose's build labels (`com.docker.compose.project`, `…service: keycloak-import`), which an image built by `build-push-action` doesn't: the facts test reads no `com.docker.compose.*` label.
  - (b) `git rev-parse --short=12 HEAD:keycloak` → `33909cd89858`. A temporary index and object directory (`GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY` created first, the repository's objects as `GIT_ALTERNATE_OBJECT_DIRECTORIES`; `git add -- keycloak`, `git write-tree --prefix=keycloak/`): `33909cd89858` on a clean `keycloak/`, `a4395e5cee63` after an uncommitted edit of `HealthCheck.java`, `33909cd89858` once restored; `git count-objects -v` identical before and after. Without the object directory created first, git refuses (`not a git repository`).
  - (c) On a throw-away `registry:2` (`127.0.0.1:50290`), an image built with `--provenance=mode=min --push`: `application/vnd.oci.image.index.v1+json`, 2 manifests (the image and its attestation); `docker manifest inspect` of a missing tag → exit 1; `docker buildx imagetools create --tag <…>:version <…>:hash` → the same digest (`sha256:dc2ba37e…`), an index. Not measured on GHCR (this session's token lacks `read:packages`): the workflow's step checks the media type before the copy and both digests after, on every run.
  - (d) Files of `/opt/keycloak` (sha256 of each) in `c4-infra/keycloak` against `quay.io/keycloak/keycloak:26.8.1` (505 files, 519): added `healthcheck/HealthCheck{.java,.class,$1.class}`, `providers/c4-infra-stack-themes.jar`, `stack-themes/**` (10 files: `META-INF/keycloak-themes.json`, and each simulated provider's `theme.properties`, `messages_en.properties`, `simulated.css`); 3 files of `lib/quarkus/` changed (`kc.sh build`). No realm file, no `data/import/`.
- 2026-10-28 — step 2: the credential check reads `token` in the names only. `KC_FEATURES`'s value names `token-exchange-delegation`, so the values are checked for `pass|secret|credential|private`. The features in Keycloak's log carry their version (`cimd:v1`), stripped before comparing with the description. compose's own labels (`com.docker.compose.*`, a local build's) are left out of the check (fact (a)). Files: none new.
- 2026-10-28 — step 4: `CLAUDE.md` changes (agent configuration): the project has no evals (`/sdlc-evals run` has nothing to run), said in the evidence.
- 2026-10-28 — the review round (bootstrap: one; `code-review high`, on 0029's commits, in the batch). Fixed:
  - `tests/0029-image-facts.sh` inspected an image it hadn't pulled (on the published reference before a pull, the credential check passed on an empty environment): it pulls one that isn't there, checks it is, and the credential check fails on an empty environment. Its file lists used `awk`, which the image lacks: both lists were empty and two checks passed on nothing; now read with bash, and a check requires both lists (505 and 519 files). The settings it checks are every key of the description, not a list of its own. The features are read from `serverinfo` (each described one enabled, whatever its type, so a promotion to supported still passes; no other preview or experimental one), no longer from the log.
  - `tests/0029-description.sh` wrote `26.8.1` and `cimd` into its negative checks: a correct version bump would have failed them; they now derive from the Dockerfile. An `ENV` line it can't read (`ENV KEY value`, several on one line) is refused, named.
  - The workflow sets buildx up on every run (the references' check uses its `imagetools`), not only when an image is missing.
  - The README said the package was public before the product owner's step: it says it is public once its owner made it so (`docs/demo-setup.md`, step 7, which now gives that step, once, for any new owner), a login with `read:packages` until then. It no longer suggests `set -a` on the description, which would export the stack's `KC_DB=postgres` into the environment that starts Keycloak.
  Answered: `host_path` defined again in the facts test, as in a dozen tests (pre-existing; a helper in `tests/lib/` would be its own change). Files: none new.

## Verification

### Verification — e52b4fd (integration 13474a8, which contains it; the full run at 205b8eb held its code, e527fe1)

- Verification command (batch `batch-0031-0030-0028-0026-0027-0029`, the product owner's decision of 2026-10-28): `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` at the integration commit 205b8eb → `verification passed` (`total: 1764.0 s for 72 test(s)`, 2026-10-28; also the milestone before the push); after the verifiers' documentation fixes, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed 205b8eb --all` at 13474a8 → `verification passed (--changed: 8 of 72 tests)`.
- Risk tier: standard; the security pass run too (C9: publication can't be undone).
- Reviews: bootstrap mode: 1 round, on 0029's own commits; bugs (`code-review high`) 9 fixed (e527fe1) / 1 answered; security (`security-review`): no finding (the workflow's triggers and permissions unchanged, outputs through `env:`, a copy only from an index; every `keycloak/` version and its provenance hold no secret).
  - answered: `host_path` defined again in the facts test (pre-existing, as in a dozen tests).
- After the verifier: `CLAUDE.md` called the package public before the product owner's step; `docs/demo-setup.md` said 0029 had checked each version (step 7 does, before publication) (e52b4fd).
- Mutation checks (the plan's; throw-away worktree): `,cimd` removed from `keycloak/Dockerfile` → `tests/0029-description.sh` `2 check(s) failed` (KC_FEATURES named both ways, the reference); a comment in `keycloak/HealthCheck.java` → `1 check(s) failed` (the reference); the same with the reference updated, no changelog entry → `no changelog entry for 26.8.1-c0e38e668069` (AC-08); another hash in the description, the workflow's block by hand → `::error::keycloak-image.properties names …-0123456789ab, keycloak/ gives …-33909cd89858`, exit 1 (C4). The verifier re-ran the AC-08 chain (and exit 0 once an entry is added).
- Verifier: 8/8 criteria OK for what runs before delivery — table below.
- Not verifiable here: AC-01 under Git Bash (no Windows workstation: the form check stands in); AC-03, AC-05 and AC-06 on the published image: after delivery, the plan's steps 6 to 9 (the push's run, the product owner's GHCR checks, the package made public, the anonymous checks).
- Files outside the plan: none (`docs/demo-setup.md`'s visibility step: Deviations, the review round).
- Pre-existing findings: none.
- Details left (not KO): whether GHCR's `:33909cd89858` is an index is seen at the first run (the tag step refuses otherwise).

| Criterion | Result | Evidence |
| --- | --- | --- |
| AC-01 | OK (bash); Git Bash not verifiable here | `ok - (a) … no CR`, `ok - (b) sourced by bash, each value is its line's text`; LF by `.gitattributes` |
| AC-02 | OK | `(c)` both ways, on copies; `,cimd` removed → named |
| AC-03 | OK before delivery (the local image); the published one after | `ok - (a) c4-infra/keycloak: org.opencontainers.image.version is 26.8.1`, its KC_* the description's |
| AC-04 | OK | `started with KC_DB=dev-file and start-dev: ready`, `/auth` 200, the three features enabled, no other preview/experimental one, the three login themes |
| AC-05 | OK before delivery; the published versions at step 7 | no credential, the files listed (505, 519), only the expected ones, no realm |
| AC-06 | OK before delivery; the run after it | the deployment keeps the tree's tag (`…:33909cd89858`); the workflow's block run as it is |
| AC-07 | OK | `(g)` and the README section read against AC-07's list; `docs/migration.md` step 7 |
| AC-08 | OK | the chain above: reference KO, then `no changelog entry for …` |
