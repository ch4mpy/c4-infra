# Plan: The migration guide misleads a project on its demo ports, the images it may run and its CI's platform

- Spec: none, the [intent](intent.md) (change, spec needed: no)
- Status: approved
- Branch: 0028-migration-guide-misleads-on-demo-ports-images-ci
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the batch and the agents, product owner)

## Starting point

At `main` 75d2809; the branch is at c47782a (the intent only), based on 27d7343. Merging `main` conflicts in one place: the index row of 0025 (`accepted` on the branch's base, `delivered` on `main`), next to the row the branch adds.

- **Ports.** `docs/migration.md:44` says "Every port of the project moves into its block:", and `:56-58` lists the files to change (`application.yml`'s `server.port`, `management.server.port`, `rest-api-v1`…). The guide says nothing about the `demo` profile. The demo ports appear only later, at `:228-233` (demo step 5), and in the README's "Routes file" (`README.md:506-511`) and "What an application's deployment does" (`:641-645`). `README.md:66-68` and "Port registry" (`:166-177`) mention only the block. What c4-infra fixes is `registry.sh:318-320` (`registry_upstream`): `http://<app>.gateway:7080`, `http://<app>.frontend:80`, `http://<app>.mcp:9080`. The trap is real. Tickee's gateway (`backend/gateway/src/main/resources/application.yml:10`, at Tickee 285c7e6) sets `server.port: 7080` in its default profile. Its `demo` profile (`:217-231`) doesn't set it and inherits it, and names `rest-api-v1: http://tickee-api:8080`. A project following step 1 to the letter moves its demo gateway to `13080`, where Caddy doesn't reach it.
- **Images.** `docs/migration.md:153-154` says "Every service runs an `image:` the project's CI built and pushed to a registry (GHCR)". `README.md:610-611` says the same ("the demo host runs the images the application's CI builds and pushes"). `demo/c4-app` refuses `build` (`:221`, its message at `:257-258`) and has no rule on where an image comes from. The stand-in tests already run public images through `sudo c4-app pull` and `up`: Faito's and Hurura'a's fixtures run `caddy:2.11.4-alpine` (`tests/fixtures/0002/*/compose.yml`).
- **CI platform.** `docs/migration.md:176-225` is GitHub Actions only: `permissions: packages: read`, `ghcr.io`, `github.actor`, `secrets.GITHUB_TOKEN`. `docs/demo-setup.md:214-222` gives the application's secrets with `gh` only. `cmd_pull` (`demo/c4-app:324-354`) runs `docker login "$registry" -u "$user" --password-stdin` in a temporary configuration, so it works with any registry. It accepts a host name with an optional `:port` and no path (`^[A-Za-z0-9.-]+(:[0-9]+)?$`), and a user of `[A-Za-z0-9._-]+`. Without `--registry` it logs in nowhere. `up` pulls an image the host lacks without any login (`pull_missing`, `:158-164`, 0025). Two tests read the GitHub example verbatim:
  - `tests/0002-accounts.stand-in.sh:88-94,149-154` (AC-08): the first `ssh "$VPS" sudo c4-app pull ` line must equal the GHCR one, and the rsync, register and up lines are run as the document writes them;
  - `tests/0002-workflow.sh:48,99-125`: every `uses:` is pinned; the host-key lines (the sed range from `if [ -z "${VPS_KNOWN_HOSTS:-}" ]` to `>> "$HOME/.ssh/known_hosts"`) must appear exactly once, as the script's; they must come before the agent and before the first `rsync|ssh … $VPS` line.

  immo (`poc-immo-pf`, on a GitLab instance) has no CI for its monorepo yet (0029's spec says so too). Its only pipeline is `legacy/.gitlab-ci*.yml`, the former application's Kubernetes pipeline built from included templates, with its registry named `${CI_REGISTRY}` and no login visible. Nothing there to model a GitLab job on.
- **Status.** `README.md:554` says "Not set up yet (postponed on 2026-10-21)", and `docs/demo-setup.md:3-4` says the same. `docs/migration.md:133-134` (demo step 1) still says "Deploy `c4-infra` on the VPS first". The first successful `deploy-demo.yml` run is 2026-10-23T05:32:18Z (`gh run list -R ch4mpy/c4-infra --workflow deploy-demo.yml`). `docs/demo-setup.md:247` says "the first one, deployed on 2026-10-23". In the same document, `:225-226` (step 9.6) puts an application's compose project "on the `c4-infra` network", which has been wrong since 0007: it is `c4-infra.<app>`, never `c4-infra`, as `docs/migration.md:146-148` says.
- **Tests that read these documents** (their `# covers:`):
  - `docs/migration.md`: `tests/0002-workflow.sh`, `tests/0004-registry.sh` (`part_docs`: `bash registry.sh next`, the columns), `tests/0016-no-real-provider.sh`, `tests/0002-accounts.stand-in.sh`;
  - `README.md`: `0004` (the "Port registry" section names `registry.txt` and `bash registry.sh next`, and holds no table of numbers) and `0016`;
  - `docs/demo-setup.md`: `0002-accounts.stand-in.sh`, `0008-certificate-scripts.sh`, `0009-master-realm.stand-in.sh`, `0016`.

  `deploy-demo.yml` ignores `**/*.md`, but `tests/0004-registry.sh` isn't Markdown: the merge's push redeploys the stack, unchanged.

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Proposed by Claude, for Jérôme Wacongne (engineer) to approve with this plan:

1. **Another CI platform: a paragraph, not a second example.** The GitHub example stays byte for byte, since two tests run or compare its lines. After it, one paragraph gives the same job on another platform (immo's GitLab, any other) in the same order:
   - the host key pinned from `VPS_KNOWN_HOSTS` before anything connects (`demo/trust-host-key.sh`'s lines, named, not repeated);
   - `VPS_SSH_KEY` in an ssh agent;
   - what the job runs is pinned, as the actions are: an image by digest, anything it includes by commit;
   - the `rsync`, then `sudo c4-app pull --registry <registry host> --registry-user <user>` with the registry's token on stdin, from a secret variable of the platform (never on a command line);
   - `register`, then `up`.

   It gives the forms `c4-app` accepts: a host name with an optional `:port` and no path, and a user of letters, digits, `.`, `_`, `-`. Without `--registry`, `pull` logs in nowhere, which is enough when every image is public. The three `VPS_*` values become secret variables of that platform. No GitLab specifics: no predefined variable, no job syntax.
   - Rejected: a full GitLab job. There is no GitLab deployment in immo to base it on. Nothing here could run it. It would repeat the host-key lines, which `tests/0002-workflow.sh` requires once (its sed range would print them twice).
   - Rejected: a platform-neutral rewrite of the example. It would break AC-08's exact lines and lose the pinned actions.
2. **Demo ports: said where the ports move.** In dev step 1, after the table, the guide says that only what runs on the workstation moves. The containers keep their ports: the demo host's Caddy reaches `<project>.gateway:7080`, `<project>.frontend:80` and `<project>.mcp:9080`, and no container port is published. So the `demo` profile (whatever the containers run) sets `7080` back if the default profile held it. The same goes for the REST API's `8080`, which the demo `rest-api-v1` names, and for the management ports the compose healthchecks name. `:56-58` gets "the default and dev profiles', not the `demo` one's". The README's "Port registry" gets one sentence: the block is the workstation's, and on the demo host the containers keep the ports "Routes file" fixes. The demo step 5 text (`:228-233`) stays.
3. **Images.**
   - `docs/migration.md:153-154`: every service runs an `image:` that `sudo c4-app pull` pulls. It is either the project's own, built and pushed by its CI to its registry (GHCR, GitLab's, any registry `docker login` accepts), or a public one as is (`postgres`, `osixia/openldap`). An image behind a login needs `pull --registry` before `up`, because `up` pulls a missing image without one. No `build:`, which `c4-app` refuses.
   - `README.md:610-611`: the reason `build` is refused becomes "the demo host builds no image; it pulls each `image:`".
   - `c4-app`'s message (`:258`) is code: unchanged. It still points to "Accounts".
4. **Stale status: dated facts, not states that go stale again.**
   - `README.md:554` becomes "Deployed since 2026-10-23", with no "no application yet".
   - `docs/migration.md:133-134` (demo step 1) says that c4-infra runs there and its Caddy holds ports 80 and 443: a project's own Caddy can't run beside it.
   - **To confirm: `docs/demo-setup.md`**, outside the intent's listed modules but the Demo operator's document, which the guide sends a project to (demo step 2):
     - its status (`:3-4`), the same stale fact as `README.md:554`;
     - step 9.5 (`:214`): "the application's repository on GitHub; on another platform, the same three values as its CI's secret variables";
     - step 9.6 (`:225-226`): `c4-infra.<app>`, not `c4-infra`.

     The cost is two more tests in the proof run (`0008`, a few seconds; `0009-master-realm.stand-in.sh`, a few minutes). Recommended: yes. Otherwise it is left for a new intent.
5. **A guard, since it is cheap: the demo upstreams in the guide's dev section.** `tests/0004-registry.sh`'s `part_docs` already checks the guide's statements about `registry.sh` and covers `registry.sh`, `README.md` and `docs/migration.md`. It gets three checks, about ten lines. For `gateway`, `fr` and `mcp`:
   - run `REGISTRY_FILE=tests/fixtures/0004/taken-1-4.txt bash registry.sh upstream faito <role> demo` (a fixture, not the live `registry.txt`, which the handover notes 0004 already pins);
   - replace `http://faito.` with `<project>.`;
   - find the result in the section of `docs/migration.md` from `## In dev` to the next `## `.

   A change of `registry_upstream`'s demo ports then fails the run until the guide follows. These checks fail before step 2, which proves them. Rejected: checking the whole guide, because demo step 5 already names the ports, so the check would pass before the change.

## Files

| File | Change | For |
| --- | --- | --- |
| `docs/migration.md` | modified: dev step 1 (`:44`, `:56-58`) and the sentence after the table (choice 2); demo step 1 (`:133-134`, choice 4); demo step 3 (`:153-154`, choice 3); demo step 5: its lead-in (`:176-181`, "a GitHub Actions workflow, below; another platform: after it") and a paragraph after the example (choice 1). Lines `183-225` are unchanged. | the outcome: ports, images, CI, status |
| `README.md` | modified: "Port registry" gets one sentence (choice 2); "One-time setup" (`:554`, choice 4); "Accounts" (`:610-611`, choice 3) | the outcome: ports, status, images |
| `docs/demo-setup.md` | modified, if choice 4 is confirmed: status (`:3-4`), step 9.5 (`:214`), step 9.6 (`:225-226`) | the outcome: status, CI |
| `tests/0004-registry.sh` | modified: `part_docs`, three checks, and the header's `docs` line ("its dev section names the demo upstreams registry.sh derives, 0028") | the outcome: ports |
| `docs/intent/0028-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan; status `planned`, then `delivered`; the index row (0025's row `delivered` kept at the merge of `main`) | — |

## Order of work

**Batch** (the product owner, 2026-10-28): 0026 to 0031 are delivered in one batch, merged in this order into `batch-0031-0030-0028-0026-0027-0029`, from `main`: 0031, 0030, 0028, 0026, 0027, 0029. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the six in the batch's order, with one push of `main`, validated by the product owner.

0. **Branch**: `git switch 0028-migration-guide-misleads-on-demo-ports-images-ci` (local = `origin`, c47782a), then `git merge main`. Resolve the index by keeping `main`'s 0025 row (`delivered`) and adding the 0028 row. — skill: none — check: `git diff main --stat` lists only `docs/intent/0028-…/` and `docs/intent/README.md`; `grep -n 'Not set up yet' README.md` → `554`; `grep -n 'Every port of the project' docs/migration.md` → `44` (the starting point holds; a moved line is noted under *Deviations*). Commit `merge main into 0028`.
1. **Failing check**: choice 5 in `tests/0004-registry.sh`. — skill: none — check: `REGISTRY_FILE=tests/fixtures/0004/taken-1-4.txt bash registry.sh upstream faito gateway demo` prints `http://faito.gateway:7080` (the fixture passes `check`); `bash tests/0004-registry.sh docs` reports 3 failed checks (the dev section names none), the others passing. Commit `test(0028): the guide's dev section names the demo upstreams registry.sh derives`.
2. **Ports**: `docs/migration.md` dev step 1 and the README's "Port registry". — skill: none — check: `bash tests/0004-registry.sh docs` → `every check passed` (the "no table of numbers" check included). Commit `docs(0028): …`.
3. **Images**: `docs/migration.md:153-154` and `README.md:610-611`. — skill: none — check: `grep -n "the project's CI built and pushed" docs/migration.md` and `grep -n 'runs the images the application' README.md` print nothing; reread against `demo/c4-app:215-258`. Commit `docs(0028): …`.
4. **CI platform**: the lead-in of demo step 5 and the paragraph after the example. — skill: none — check:
   - `git diff main -- docs/migration.md` touches none of the example's lines;
   - `grep -nE '^[[:space:]]*ssh "\$VPS" sudo c4-app pull ' docs/migration.md | head -n 1` is still the GHCR line;
   - `grep -c 'if \[ -z "\${VPS_KNOWN_HOSTS:-}" \]' docs/migration.md` → `1`;
   - `bash tests/0002-workflow.sh` → `every check passed`;
   - the paragraph's forms match `cmd_pull`'s regular expressions (`demo/c4-app:345-346`).

   Commit `docs(0028): …`.
5. **Status**: `README.md:554`, `docs/migration.md:133-134`, and `docs/demo-setup.md` if choice 4 is confirmed. — skill: none — check: `grep -rniE 'not set up yet|postponed on 2026-10-21' README.md docs/*.md` prints nothing; `grep -n 'on the `c4-infra` network' docs/demo-setup.md` prints nothing. Commit `docs(0028): …`.
6. **Intermediate**: `bash tests/run.sh --changed` (no stand-in), which runs `0002-workflow`, `0004-registry` and `0016-no-real-provider` (and `0008` with choice 4). — skill: none — check: `verification passed`.
7. **Verification**:
   - `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all`, with the dev stack up and Faito registered. It adds `0002-accounts.stand-in.sh` (and `0009-master-realm.stand-in.sh` with choice 4).
   - `/sdlc-verify 0028`. Standard risk: documentation, no code, and the token guidance repeats `c4-app`'s existing contract (stdin, never a command line). Bootstrap: one round, the bugs pass only. The verifier reads each new statement against `demo/c4-app` and `registry.sh`.

   — skill: sdlc-verify — check: `verification passed`. Then `/sdlc-ship 0028`. The full `--all` stays the product owner's milestone (CLAUDE.md).

## Risks

- **The tests that read the GitHub example verbatim.** AC-08 compares the first pull line, `0002-workflow` diffs the host-key lines once, and every `uses:` must be pinned. Mitigation: the example is unchanged; the new paragraph comes after it, holds no `uses:` and doesn't repeat the host-key lines. Step 4's checks catch any of these before the stand-in run.
- **Parallel intents touch the same documents.** 0026 (`logging`, migration.md demo step 3, README "Accounts"), 0027 (backups, migration.md demo step 7, README "Backups", demo-setup.md) and 0029 (tests' Keycloak, a migration.md step). 0027's spec also cites `README.md:554` as "not set up yet". Mitigation: 0028 changes only the lines named here; whichever branch lands second merges `main` and resolves. 0027's plan notes the status fixed by 0028 if 0028 lands first.
- **Nothing proves another registry's login here.** The stand-in has no registry with a login (`tests/0002-accounts.stand-in.sh:188` runs the pull without `--registry`). Mitigation: the paragraph states only what `cmd_pull`'s code does (`docker login <host> --password-stdin`) and the forms it accepts. The evidence says "not verifiable here: a login to a registry other than GHCR". A registry or user outside those forms is refused by `c4-app` and named by the guide; widening them would be code, so a new intent.
- **A sentence that overstates what c4-infra does.** For example "any registry" without the forms, or "the `demo` profile must" where a project sets ports otherwise. Mitigation: each statement is checked against the code it describes (steps 3 to 5); the wording is "whatever the containers run", not a profile name only.
- **The guard pins a fixture's line.** `faito` in `taken-1-4.txt`, not the live registry. If the fixture fails `check`, the step 1 check shows it, and falling back to the live `registry.txt` is a deviation.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| Ports: the guide's dev step says the containers keep their ports and names the demo upstreams c4-infra derives | automated test | `tests/0004-registry.sh docs`: the three new checks (`<project>.gateway:7080`, `<project>.frontend:80`, `<project>.mcp:9080` in the "In dev" section, from `registry.sh upstream … demo`), failing at step 1 and passing at step 2 |
| Images: the guide and the README let a public image run, and refuse only `build:` | command, automated test | step 3's greps print nothing. `tests/0002-accounts.stand-in.sh`: the document's `sudo c4-app pull` and `up` run Faito's fixture on `caddy:2.11.4-alpine`, a public image no CI built (`AC-02: the document's sudo c4-app pull exits 0`, `AC-02: faito.gateway runs`). `demo/c4-app:221` refuses `build`, with no rule on an image's origin. |
| CI: the guide gives the registry and the job whatever the platform, the GitHub example kept | manual check, automated tests | the paragraph read against `cmd_pull` (`demo/c4-app:324-354`: `docker login "$registry" -u "$user" --password-stdin`, the forms of `:345-346`, no login without `--registry`). The example is checked by `tests/0002-workflow.sh` and by `tests/0002-accounts.stand-in.sh` AC-08 (its pull line still the GHCR one). |
| Status: no stale status | command | `grep -rniE 'not set up yet\|postponed on 2026-10-21' README.md docs/*.md` prints nothing. The date matches the first successful `deploy-demo.yml` run (`gh run list -R ch4mpy/c4-infra --workflow deploy-demo.yml`: 2026-10-23T05:32:18Z) and `docs/demo-setup.md:247`. |
| The tests reading these documents still pass | automated tests | `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed --all` → `verification passed` (`0002-workflow`, `0004-registry`, `0016-no-real-provider`, `0002-accounts.stand-in`; `0008`, `0009-master-realm.stand-in` with choice 4) |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
