# Plan: No test proves that a front end's own Permissions-Policy reaches the browser unchanged

- Spec: none, the [intent](intent.md) (change, spec needed: no)
- Status: approved
- Branch: 0031-front-end-own-permissions-policy-untested
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the batch and the agents, product owner)

## Starting point

- `tests/0015-headers.sh` (at `main` 1e7e40c) runs two throwaway proxies of the stack's image on `caddy/` as it is, `INFRA_ENV=dev` and `demo` (`:69-81`), in front of one front end answering by path (`tests/fixtures/0015/frontend.caddy`), and loops over both (`:133`). On `headers=app` routes it checks:
  - `/fr/x` (`:137-142`, route `verif.routes:4`): the front end's Content-Security-Policy once (`:139`), its `X-Frame-Options: SAMEORIGIN` once (`:140`), and the **shared** Permissions-Policy once (`:141`), since `/fr/*` sends no Permissions-Policy (`frontend.caddy:11-16`);
  - `/en/x` (none sent: the three shared values), `/report-only/x`, and the proxy's own `413` and `502` (`:144-158`).
- What it doesn't check:
  - a front end's **own** Permissions-Policy: no path of `frontend.caddy` sends one, so a default that doubled or replaced it would pass;
  - a **`ui`** route with `headers=app`: the `ui` routes of the fixtures have no option (`verif.routes:7-8`, `verif-down.routes:3`); `/ui/x` checks today's duplicates (`:160-164`).
- `tests/0015-proxy-facts.sh`'s `own` upstream sends no Permissions-Policy either (`:51-55`): its fact (b) (`:191-194`) proves the default of a missing one, not that a sent one is kept.
- 0015's evidence names the gap: "no automated check that a front end's own Permissions-Policy passes unchanged (the fixture sends none, per the plan; the verifier saw it pass)" (`docs/intent/0015-proxy-imposes-front-end-headers/plan.md:102`); the verifier's run by hand, `:99`.
- The code under test, unchanged by this plan:
  - `caddy/Caddyfile:24-28`: `(spa-header-values)`, one `header {args[0]}<field>` per field;
  - `:34-37`: `(spa-headers-app)` imports it with `?`;
  - `:52-60`: `handle_errors` gives the proxy's own errors the same defaults on the marker.
  - `routes.sh:180-188` accepts `headers=app` on `fr`, `en` and `ui`; `:297-304` prints `import spa-headers-app` for any of the three.
- Expected on `main`'s code: the new checks pass. Each field is its own `?` directive, and fact (b) shows a `?` field keeps a value the upstream sent, once. Permissions-Policy is written as the other two, and `ui` goes through the same lines of `routes.sh`. Not measured for this draft (no container in plan mode): step 2 measures it.
- The branch (503bfbe, on 27d7343) is behind `main` (1e7e40c). `git merge-tree main origin/0031-…` gives one conflict, `docs/intent/README.md`: the index's 0025 row (`accepted` on the branch's base, `delivered` on `main`) next to the branch's new 0031 row. `HANDOVER.md` merges clean.

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Proposed by Claude, for Jérôme Wacongne (engineer) to confirm with this plan:

- **Extend `tests/0015-headers.sh` and its fixtures, no new test file (A).** The two throwaway proxies (dev, demo), the generated sites and the front end are already there; one more front-end path and two routes cost a few seconds. A new file would duplicate about 80 lines of setup, its ports and its container names. The `# covers:` line stays as it is (`caddy/ routes.sh … tests/fixtures/0015/`).
- **Two new routes, one path of the front end sending all three (A):**
  - `/own/*  fr  headers=app` and `/ui-own/*  ui  headers=app` in `verif.routes`;
  - in `frontend.caddy`, one handle for both (`@own-three path /own/* /ui-own/*`): the `/fr/*` policy, `X-Frame-Options: SAMEORIGIN`, and a Permissions-Policy of its own.
  - `/fr/*` stays as it is: it proves the default of the one field a front end leaves out, which a front end sending all three can't prove.
  - Set aside: `/fr/*` sending Permissions-Policy too (loses that partial case).
- **The front end's Permissions-Policy has a quoted origin (A):** `geolocation=(self "https://tiles.verif.example"), fullscreen=(self)`, as a real policy has (immo's tiles and frames). It differs from the shared value in every field. In `frontend.caddy` it is a backtick token, since it holds double quotes. Its origin is under `.example` (reserved): no real host in a fixture (`tests/0016-no-real-provider.sh` reads `tests/fixtures/`). Set aside: a value without quotes, simpler but less like an application's.
- **No check of the proxy's own `413`/`502` on the `ui` route with `headers=app` (A).** The intent asks for the headers a front end sends. The proxy's own errors on a `headers=app` route are proven on `fr` (AC-03 of 0015), and `routes.sh` writes the same directive for `ui`.
- **`tests/0015-proxy-facts.sh` unchanged (A).** `tests/0015-headers.sh` covers `reverse-proxy/` and runs on the stack's image, so a Caddy upgrade that drops or doubles a sent Permissions-Policy fails it.
- **Two mutation checks (A).**
  - M1, the intent's gap: Permissions-Policy set instead of defaulted.
  - M2: `routes.sh` ignoring `headers=app` on `ui`, which shows that the `ui` checks hold the option.
  - M1 is also run with `main`'s test, which passes on it: the gap the intent names.
  - Set aside: M1 only.
- Commits of the test steps typed `test(0031): …`: the change is a test only.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/fixtures/0015/frontend.caddy` | modified: `@own-three path /own/* /ui-own/*` sending its Content-Security-Policy (the `/fr/*` one), `X-Frame-Options: SAMEORIGIN` and its Permissions-Policy (backtick token); header comment names the path | the outcome: what the front end sends |
| `tests/fixtures/0015/verif.routes` | modified: `/own/*  fr  headers=app` (after `/report-only/*`), `/ui-own/*  ui  headers=app` (after `/ui/*`); header comment | the outcome: a `headers=app` route, the `ui` one included |
| `tests/0015-headers.sh` | modified: the header comment (0031's line); `OWN_PERMISSIONS`; in the dev/demo loop, after AC-05's `/ui/x`, for `/own/x` and `/ui-own/x`: `200` (`$env, 0031: <path> (headers=app, sending all three): answered by the front end`), then each of Content-Security-Policy, `X-Frame-Options`, Permissions-Policy `once` with the front end's value (one `check` per header, `$env, 0031: <path>: its <header>, once`); no existing check changed | the outcome: once, its value, dev and demo |
| `docs/intent/0031-front-end-own-permissions-policy-untested/plan.md` | new: this plan; its evidence in *Verification* (bootstrap) | — |
| `docs/intent/0031-front-end-own-permissions-policy-untested/intent.md` | modified: status `planned` (approve), then `delivered` (`/sdlc-ship`) | — |
| `docs/intent/README.md` | modified: step 0's merge (main's rows, 0025 `delivered`, and the 0031 row), then the 0031 row's status | — |

No file of `caddy/` or `routes.sh` changes (the intent's constraint). Should step 2 fail on `main`'s code, the fix is a deviation (Risks).

## Order of work

**Batch** (the product owner, 2026-10-28): 0026 to 0031 are delivered in one batch, merged in this order into `batch-0031-0030-0028-0026-0027-0029`, from `main`: 0031, 0030, 0028, 0026, 0027, 0029. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the six in the batch's order, with one push of `main`, validated by the product owner.

0. **Setup.**
   - `git switch 0031-front-end-own-permissions-policy-untested` (local = `origin`, 503bfbe), then `git merge main`. Resolve its conflict in the index: `main`'s rows, plus the 0031 row.
   - The dev stack running (`bash up.sh`: the image `c4-infra/reverse-proxy`, `certs/tls.crt`).
   - Then `sdlc-plan approve` commits this plan (`plan: …`).
   - skill: none.
   - Check:
     - `git status --short` empty;
     - `git diff --name-only main` lists only the intent's folder and `docs/intent/README.md`;
     - `TMPDIR=~/.cache/c4-infra-tests bash tests/0015-headers.sh` ends `every check passed` (the baseline).
1. **The fixture.** `frontend.caddy` and `verif.routes` as in *Files*.
   - skill: none.
   - Check:
     - `REGISTRY_FILE=$PWD/tests/fixtures/0015/registry.txt bash routes.sh generate tests/fixtures/0015/verif.routes verif demo | grep -A1 -E 'handle /(own|ui-own)/\*' | grep -c 'import spa-headers-app'` prints `2`;
     - `TMPDIR=~/.cache/c4-infra-tests bash tests/0015-headers.sh` ends `every check passed` (the existing checks are unchanged by the additions; the front end parses, else `ready` fails).
   - Commit `test(0031): a front end sending its three headers on a fr and a ui route with headers=app`.
2. **The checks** in `tests/0015-headers.sh`, as in *Files*.
   - skill: none.
   - Check: `TMPDIR=~/.cache/c4-infra-tests bash tests/0015-headers.sh` ends `every check passed`, with `grep -c '^ok - .*0031'` on its output = `16` (2 environments × 2 paths × status and 3 headers).
   - A KO on a header here is the finding the intent allows for: stop, write the deviation, and ask before fixing `caddy/` (or `routes.sh` for `ui`). See Risks.
   - Commit `test(0031): each header a front end sends on a headers=app route reaches the browser once, with its value, dev and demo`.
3. **Mutation checks**, in a throw-away worktree; nothing committed.
   - skill: none.
   - Setup:

     ```bash
     git worktree add --detach ../c4-infra-0031-mutation HEAD
     cp .env ../c4-infra-0031-mutation/
     cp certs/tls.crt certs/tls.key ../c4-infra-0031-mutation/certs/
     cd ../c4-infra-0031-mutation
     export TMPDIR=~/.cache/c4-infra-tests
     ```

   - Unmutated: `bash tests/0015-headers.sh` ends `every check passed`, so a KO below is the mutation's, not the worktree's.
   - **M1**, Permissions-Policy set instead of defaulted:

     ```bash
     sed -i 's/header {args\[0\]}Permissions-Policy/header Permissions-Policy/' caddy/Caddyfile
     ```

     - `git diff -U0` shows that one line changed;
     - the test ends `4 check(s) failed`, exactly `{dev,demo}, 0031: {/own/x,/ui-own/x}: its Permissions-Policy, once` (two values: the shared one and the front end's).
   - **The gap**, M1 with `main`'s test: `git checkout main -- tests/0015-headers.sh tests/fixtures/0015/`. The test ends `every check passed`: the test before 0031 doesn't see M1. Then `git checkout HEAD -- caddy/ tests/`.
   - **M2**, `ui` ignoring `headers=app`:

     ```bash
     sed -i 's/if \[ "${headers\[$i\]}" = app \]; then/if [ "${headers[$i]}" = app ] \&\& [ "$target" != ui ]; then/' routes.sh
     ```

     - `git diff -U0` shows that one line changed;
     - the test ends `6 check(s) failed`, exactly `{dev,demo}, 0031: /ui-own/x: its {Content-Security-Policy,X-Frame-Options,Permissions-Policy}, once`.
   - Clean-up: `cd -`, then `git worktree remove --force ../c4-infra-0031-mutation`.
   - Check: the four results above, recorded for the evidence; `git worktree list` without the throw-away worktree.
4. **Verification.**
   - `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed main --all` gives `verification passed (--changed: 3 of … tests)`: `tests/0015-headers.sh`, plus `tests/0019-collation.sh` (covers `tests/`) and `tests/0016-no-real-provider.sh` (covers `tests/fixtures/`).
   - `/sdlc-verify 0031`: bootstrap, one round, the bugs pass; standard risk (a test only), no security pass. Its evidence block, with step 3's results as the mutation check, goes into *Verification*, committed `plan: verification of 0031`.
   - Then `/sdlc-ship 0031`.
   - skill: sdlc-verify.
   - Check: `verification passed`.

## Risks

- **The new checks fail on `main`'s code** (a sent Permissions-Policy doubled or dropped, or `ui` not honouring the option). Mitigation:
  - step 2 measures it before anything else;
  - stop, write a dated deviation, and ask: the fix of `caddy/` (or `routes.sh`) comes into scope;
  - the mutation check becomes "the fix reverted: the new checks `KO`";
  - the 0003 and 0015 tests that cover `caddy/` and `routes.sh` join step 4's run through `--changed`.
- **Caddyfile quoting of a value with double quotes.** Mitigation: a backtick token, and step 1's check (`ready` fails if `frontend.caddy` doesn't parse); else `\"` escapes. The test compares the value the browser receives, so a mis-quoted value is a KO, not a silent pass.
- **A vacuous mutation** (a `sed` that matches nothing): the test then passes and proves nothing. Mitigation: `git diff -U0` after each `sed` shows the one line changed.
- **The throw-away worktree lacks the gitignored `.env` and `certs/tls.*`.** Without them, AC-06 and the dev proxy fail there: 0015's mutation check met the `.env` case. Mitigation:
  - both are copied from the main worktree and removed with the worktree (`git worktree remove --force`); they are the workstation leaf's, not the CA's key (0008);
  - the unmutated run comes first, so an environment KO isn't read as the mutation's.
- **Another session runs the same test meanwhile.** The test uses fixed container names and ports (`c4-infra-test-0015-headers-*`, 48451-48452), and the parallel intents 0026-0030 run on this workstation; the test's start removes another run's containers. Mitigation:
  - run the direct test commands of steps 0-3 one at a time, only while no suite run holds the lock (`docker ps -q -f name=c4-infra.suite-lock` empty);
  - rerun a KO on "the throwaway proxy answers" before reading it.
- **Step 0's merge conflict on the index.** Mitigation: keep `main`'s rows (0025 `delivered`) and the 0031 row; step 0's `git diff --name-only main` shows nothing else.
- **The new routes add the redirects `/own` → `/own/` and `/ui-own` → `/ui-own/` to the fixture's site.** Nothing asserts that site verbatim: `tests/0003-routes.sh` reads `tests/fixtures/0003/` only.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| A front end sending all three on a `fr` route with `headers=app`: each reaches the browser once, with its value, in dev and in the demo's configuration | automated test | `tests/0015-headers.sh`: `ok - {dev,demo}, 0031: /own/x: its Content-Security-Policy, once`, `… its X-Frame-Options, once`, `… its Permissions-Policy, once` |
| The same on a `ui` route with `headers=app` | automated test | `tests/0015-headers.sh`: `ok - {dev,demo}, 0031: /ui-own/x: its …, once` (three headers) |
| The test guards it | mutation check | step 3: M1 gives `4 check(s) failed` (the Permissions-Policy checks), while `main`'s test passes on M1; M2 gives `6 check(s) failed` (the `/ui-own/x` checks) |
| 0015's behaviour doesn't change (the intent's constraint) | command + automated test | `git diff --name-only main...HEAD` lists only `tests/0015-headers.sh`, `tests/fixtures/0015/{frontend.caddy,verif.routes}` and the intent's files; `git diff main -- tests/0015-headers.sh` removes header-comment lines only; its existing checks pass in step 4's run |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->

## Verification

### Verification — f6b4e3a (integration 205b8eb; rerun 13474a8, which contains it)

- Verification command (batch `batch-0031-0030-0028-0026-0027-0029`, the product owner's decision of 2026-10-28): `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` at the integration commit 205b8eb → `verification passed` (`total: 1764.0 s for 72 test(s)`, 2026-10-28; also the milestone before the push); after the verifiers' documentation fixes, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed 205b8eb --all` at 13474a8 → `verification passed (--changed: 8 of 72 tests)`.
- Risk tier: standard (a test only).
- Reviews: bootstrap mode: 1 round, on 0031's own commits; bugs (`code-review high`) 0 fixed / 3 answered; no security or quality pass (bootstrap, standard risk).
  - no check of the proxy's own 413/502 on a `ui` route with `headers=app` (`tests/0015-headers.sh:169`): the plan's choice; the intent asks for the headers a front end sends, and `routes.sh` writes the same import for `ui` (M2 shows the `ui` checks hold the option);
  - `/own/x` repeats AC-01's CSP and X-Frame-Options checks (`:171`): one loop for both paths, as planned;
  - `tests/0015-proxy-facts.sh` unchanged (`:194`): the plan's choice; `0015-headers.sh` runs on the stack's image and covers `reverse-proxy/`.
- Mutation checks (throw-away worktree at f6b4e3a): unmutated → `every check passed`; M1 (`caddy/Caddyfile:27`, Permissions-Policy set instead of defaulted) → `4 check(s) failed`, {dev,demo} × {/own/x,/ui-own/x}: its Permissions-Policy, once; M1 with `main`'s test → `every check passed` (the gap the intent names); M2 (`routes.sh`, `headers=app` ignored on `ui`) → `6 check(s) failed`, {dev,demo}, /ui-own/x, three headers.
- Verifier: 4/4 criteria OK — table below (its own run of `tests/0015-headers.sh` at 205b8eb: `every check passed`, 16 checks of 0031).
- Not verifiable here: none.
- Files outside the plan: none.
- Pre-existing findings: none.
- Details left (not KO): the Proof row 4 says the test removes comment lines; it removes none, each fixture replaces one; the "answered by the front end" checks read the status only (the front end's exact header values identify it).

| Criterion | Result | Evidence |
| --- | --- | --- |
| A front end sending all three on a `fr` route with `headers=app`: each reaches the browser once, with its value, dev and demo | OK | `ok - {dev,demo}, 0031: /own/x: its Content-Security-Policy / X-Frame-Options / Permissions-Policy, once`, `… answered by the front end` (batch log; the verifier's run) |
| The same on a `ui` route with `headers=app` | OK | the same four checks on `/ui-own/x`, dev and demo; the generated site imports `spa-headers-app` for `/ui-own/*` |
| The test guards it | OK | M1 → `4 check(s) failed`; M1 with main's test → `every check passed`; M2 → `6 check(s) failed` |
| 0015's behaviour doesn't change | OK | no file of `caddy/` or `routes.sh` changed; the 63 earlier checks pass (79 = 63 + 16) |
