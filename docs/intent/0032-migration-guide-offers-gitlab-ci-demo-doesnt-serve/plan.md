# Plan: The migration guide offers a GitLab CI job the demo host doesn't serve

- Spec: [v1](spec.md) (approved 2026-10-28: PA-01 A, PA-02 A, PA-03 B)
- Status: approved
- Branch: `main` (bootstrap: no other intent in progress, so the plan and its commits go on `main`)
- Approved: 2026-10-28, Jérôme Wacongne (engineer; the batch and the agent, product owner)

## Starting point

Read on 2026-10-28, `main` at de2be13 (the spec), level with `origin/main` as last fetched. The documents haven't changed since the spec measured them at 62ef9b2: de2be13 touches `docs/intent/` only.

- **`docs/migration.md`**:
  - `:143` `## On the demo host` goes straight into step 1 (`:145`). Nothing says which projects the host deploys.
  - Step 3, `:166-172`: "its registry (GHCR, GitLab's, any registry `sudo c4-app pull --registry` logs in to)" (`:167`), then "(step 5 below, which gives the forms it accepts)" (`:170`).
  - Step 5's lead-in, `:222-227`: "its registry's token on stdin: GHCR's here" (`:225`).
  - The GitHub example, `:229-271`. The block from its `deploy:` line (`:230`, indented by 5 spaces, the only such line of the file) to its fence (`:271`) has sha256 `a50da828…8ce6`.
  - `:273-283`, "On another platform (GitLab, any CI that runs a shell)…", and its blank line `:284`. It holds the only statement of the forms (`:279-280`), of the `pull` without `--registry` (`:280-281`) and of "never printed" (`:283`).
  - Step 7, `:300-302`: "immo: `rest_api_db` `postgres`, `rustfs` `volumes`" (`:302`).
- **`README.md`**: `:597` `## Demo host`, whose first paragraph (`:599-605`) names no CI platform. `:471-520` "Keycloak in an application's tests" (IV-03) and `:631` (`pull [--registry <host> --registry-user <user>]`) stay as they are.
- **`docs/demo-setup.md`**: `:204` `## 9. Adding an application`. The intro (`:206-209`) and `:231-232` (9.5): "in the application's repository (its own `demo` environment), read on stdin; on another platform than GitHub, the same three values as its CI's secret variables". `:235-239` are the `gh` commands; `0002-accounts.stand-in` greps `:239`.
- **What the documents promise to match**: `demo/c4-app` `cmd_pull` (`:429-460`). Without `--registry` it runs `compose pull --quiet`, with no login. With it, `--registry` must match `^[A-Za-z0-9.-]+(:[0-9]+)?$` (`:449`) and `--registry-user` `^[A-Za-z0-9._-]+$` (`:450`), and the token goes through `docker login --password-stdin` into a temporary configuration.
- **Measured**:
  - `git grep -n -i gitlab -- ':!docs/intent/'` finds `docs/migration.md:167` and `:273` only.
  - AC-03's grep (`gitlab|another platform|other platform|any CI|immo`, on `README.md docs/*.md`) finds `migration.md:167`, `:273`, `:302` and `demo-setup.md:232`.
  - `kubernetes|scaleway|k8s` finds nothing.
- **Tests that read these documents** (their `# covers:`):
  - `0002-workflow`: the example's `uses:` lines, its host-key lines once, and the first line that starts with `rsync|ssh … $VPS`.
  - `0002-accounts.stand-in`: the first lines that start with `rsync`, `ssh "$VPS" sudo c4-app pull|register|up`, and `demo-setup.md`'s bootstrap and `gh secret` lines.
  - `0004-registry` docs: the README's "Port registry", and `migration.md`'s columns and "In dev".
  - `0016-no-real-provider`, `0027-docs` (backup terms), `0029-description` (README's tests section, the guide's link to it), `0008-certificate-scripts` and `0009-master-realm.stand-in` (`demo-setup.md`).
- **Deployment**: `deploy-demo.yml:9-11` ignores `**/*.md` and `.claude/**` only, so a new test file deploys. The images are tagged by their directory's tree and not rebuilt when they exist (`docker manifest inspect`, `:65-71`). `demo/deploy-files.txt` names no test.

## Engineer's choices

- Decided by Jérôme Wacongne (engineer), 2026-10-28: every recommendation below.

Proposed by Claude, to confirm by Jérôme Wacongne (engineer) with this plan:

1. **The statement, where and how** *(to confirm)*.
   - Placement: each section's first paragraph, before what is there today, as AC-01 asks ("opens with").
   - `docs/migration.md`, after `## On the demo host`, the spec's text: "The demo host deploys GitHub projects, each from its own GitHub Actions workflow. A GitLab project (immo) isn't deployed by this stack: "In dev" applies to it, not these steps."
   - `README.md`, after `## Demo host`: the same two sentences, the end adapted, "…isn't deployed by this stack: the migration guide's "In dev" applies to it, not its demo steps ([docs/migration.md](docs/migration.md))". The section's present paragraph follows.
   - The two fixed parts, which the guard holds verbatim: `The demo host deploys GitHub projects, each from its own GitHub Actions workflow.` and `A GitLab project (immo) isn't deployed by this stack`. ASCII apostrophe, as the documents use it.
   - Rejected: in the README, the statement after the present first paragraph. It reads more smoothly, but AC-01 says "opens with", so it would take a spec v2.
   - Rejected: one identical sentence in both documents. "These steps" means nothing in the README.
2. **The guard, `tests/0032-demo-github-only.sh`**, built like `tests/0016-no-real-provider.sh` *(to confirm)*:
   - **(a) AC-01**: the first paragraph after `## Demo host` (README) and after `## On the demo host` (guide) holds both fixed parts. Whitespace and line ends are flattened to single spaces and `\r` is stripped, so a rewrap of the paragraph doesn't fail it.
   - **(b) RQ-06**: every tracked file outside `docs/intent/`, the guard itself aside (`git grep -il gitlab -- . ':!docs/intent/' ':!tests/0032-demo-github-only.sh'`), is flattened, the GitLab sentence is removed, and the rest must not name GitLab (case-insensitive). Otherwise the check is KO, naming the file's lines (`git grep -n -i gitlab`, the statement's own line aside). On `main` today that is `docs/migration.md:167` and `:273`.
   - `# covers: README.md CLAUDE.md docs/ demo/ .github/ examples/`: the places that hold deployment guidance, so `--changed` selects the guard; the full run covers the rest. It costs well under a second.
   - Rejected: a line-based grep with the statement on one unwrapped line. The documents wrap at 100 and a rewrap would break the guard.
   - Rejected: the pattern built from pieces, as 0016 does. The guard must hold the statement verbatim, so it names GitLab anyway; excluding it by path is simpler.
   - Rejected: also guarding `immo`, `kubernetes` or `scaleway`. immo is a registered application, legitimate in `registry.txt` and in its dev notes (IV-03). `kubernetes` is a value of Keycloak's own settings (its cache stack). These stay AC-01's and AC-03's one-off greps in the proof.
3. **Step 3 takes the registry rules (PA-01 A, PA-02 A)**. In `:166-172`:
   - "(GHCR, or any registry `sudo c4-app pull --registry` logs in to)";
   - "`sudo c4-app up` pulls the images the host lacks without logging in anywhere, as `sudo c4-app pull` does without `--registry`: enough when every image is public";
   - the image behind a login: "`… pull --registry <host> --registry-user <user>`, the registry's token on stdin (step 5)", one registry per pull, as now;
   - "`--registry` takes a host name, with an optional `:port` and no path; `--registry-user`, letters, digits, `.`, `_` and `-`" (`demo/c4-app:449-450`);
   - "No `build:`…" unchanged.
4. **Step 5's lead-in takes the secrets (PA-02 A, RQ-05)**:
   - "…as `<project>@<vps>`, a job of its repository's `demo` environment, which alone holds the deployment's secrets (`VPS_HOST`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS`, another registry's token), never printed";
   - "`sudo c4-app pull` (step 3; its registry's token from a secret, on stdin, never on a command line: GHCR's here, `GITHUB_TOKEN`)";
   - the rest of the lead-in unchanged, and the example (`:229-271`) byte for byte (IV-01);
   - `:273-284` deleted, so "A project without messaging…" follows the example.

   No new prose line starts with `rsync`, `ssh "$VPS"` or `uses:`, which the tests match.
5. **Step 7: immo's example dropped, not replaced** *(to confirm)*. Tickee's two examples cover both labels (`postgres`, `volumes`). Rejected: Faito's labels instead. Faito has no demo deployment yet (`demo-setup.md:256`) and nothing here gives its services.
6. **`docs/demo-setup.md` step 9** *(to confirm)*.
   - The intro ends: "For each application, a GitHub project (the host deploys no other: [README](../README.md), "Demo host"), once:".
   - 9.5 reads "in the application's GitHub repository, its own `demo` environment, read on stdin:", with the other-platform clause gone.
   - The `gh` commands are unchanged.
   - Rejected: the whole statement repeated there. RQ-01 names two documents, and step 9 points to one of them.
7. **The push that deploys** *(to confirm)*. Bootstrap's `implement` ends with a push without asking. On `main` that push carries `tests/0032-demo-github-only.sh`, so it deploys the demo host (unchanged), before `/sdlc-ship` marks the intent delivered.
   - Recommended: hold `main` local until `/sdlc-ship 0032`, one push after the status `delivered`. The deployment then follows the delivery, as for the earlier intents merged by `/sdlc-ship`.
   - Recommended: no full `--all` milestone before that push. The change is documents and a guard, and `--changed --all` selects every test that reads them. CLAUDE.md leaves the milestones to the product owner.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0032-demo-github-only.sh` | new (choice 2): checks (a) and (b), and its header (0032, RQ-06, the product owner's decision of 2026-10-28, the `covers:` line) | RQ-06, AC-06, AC-01 |
| `docs/migration.md` | modified: the statement after `## On the demo host` (choice 1); step 3 `:166-172` (choice 3); step 5's lead-in `:222-227` and `:273-284` deleted (choice 4); step 7 `:302`, immo's clause (choice 5). "In dev" (`:11-141`) and the example (`:229-271`) unchanged | RQ-01, RQ-03, RQ-04, RQ-05, IV-01, IV-02, IV-03; AC-01, AC-03, AC-04, AC-05 |
| `README.md` | modified: the statement opens "Demo host" (`:597`, choice 1); nothing else | RQ-01, IV-03; AC-01, AC-03 |
| `docs/demo-setup.md` | modified: step 9's intro (`:206-209`) and 9.5 (`:231-232`), choice 6; the `gh` commands unchanged | RQ-02, RQ-03; AC-02, AC-03 |
| `docs/intent/0032-…/plan.md`, `intent.md`, `docs/intent/README.md` | this plan, its verification; status `planned`, then `delivered`; the index row | — |
| `docs/intent/HANDOVER.md` | at `/sdlc-ship`: the follow-up "paragraph to be withdrawn or reworded" done by 0032; immo's question "on the demo host or not" answered (no) | — |

Unchanged (IV-04): `demo/`, `.github/`, `registry.txt`.

## Order of work

**Batch** (the product owner, 2026-10-28): 0032, 0034 and 0033 are verified together. 0032 is committed on `main` itself, which stays local until the batch's push; 0034 and 0033 are merged in that order into `batch-0032-0034-0033`, from `main`. This intent's review round runs on its own commits. The verification command runs once, `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --all` on the integration head, from the main tree: this intent's verification and the milestone before the push. Its verifier gets that log; the mutation checks run as written below. A failure is attributed by rerunning the failing test on this intent's branch, and fixed there. `/sdlc-ship` delivers the three in the batch's order, then one push of `main`, validated by the product owner.

0. **Starting point** — skill: none — check:
   - `git log -1 --format=%s` is this plan's `plan:` commit, on de2be13;
   - `git grep -n -i gitlab -- ':!docs/intent/'` → `docs/migration.md:167`, `:273`;
   - `sed -n '/^     deploy:$/,/^   ```$/p' docs/migration.md | sha256sum` → `a50da828…`.

   A moved line is noted under *Deviations*.
1. **Failing guard**: `tests/0032-demo-github-only.sh` (choice 2). — skill: none — check:
   - `bash -n` on it;
   - `bash tests/0032-demo-github-only.sh` exits 1 with KO on (a) for both documents and KO on (b), its output naming `docs/migration.md:167` and `docs/migration.md:273` and nothing else.

   Commit `test(0032): the demo host's documents name GitLab only to say this stack doesn't deploy it`.
2. **The statement** (RQ-01): `docs/migration.md` and `README.md` (choice 1). — skill: none — check:
   - the guard: (a) `ok` twice, (b) still KO, naming `docs/migration.md:170` and `:276` only (3 lines added above);
   - `bash tests/0004-registry.sh docs` → `every check passed`;
   - `grep -n -i -E 'kubernetes|scaleway|k8s' README.md docs/*.md` prints nothing.

   Commit `docs(0032): the demo host deploys GitHub projects; a GitLab project isn't deployed by this stack`.
3. **Step 3's registries** (RQ-04, RQ-05: PA-01 A, PA-02 A): choice 3. — skill: none — check:
   - the guard's (b) names one line only, the other-platform paragraph's `On another platform (GitLab, …` (its number moves with step 3's length);
   - `grep -n "GitLab's" docs/migration.md` prints nothing;
   - the forms read against `demo/c4-app:449-450`;
   - `bash tests/0002-workflow.sh` → `every check passed`.

   Commit `docs(0032): …`.
4. **Step 5** (RQ-03, RQ-05, IV-01): the lead-in, and the other-platform paragraph removed (choice 4). — skill: none — check:
   - `bash tests/0032-demo-github-only.sh` → `every check passed`;
   - `bash tests/0002-workflow.sh` → `every check passed`;
   - `diff <(git show de2be13:docs/migration.md | sed -n '/^     deploy:$/,/^   ```$/p') <(sed -n '/^     deploy:$/,/^   ```$/p' docs/migration.md)` prints nothing;
   - `grep -nE '^[[:space:]]*ssh "\$VPS" sudo c4-app pull ' docs/migration.md | head -n 1` is still the GHCR line;
   - `grep -n -i -E 'another platform|other platform|any CI' docs/migration.md` prints nothing.

   Commit `docs(0032): …`.
5. **Step 7** (RQ-03): immo's clause dropped (choice 5). — skill: none — check:
   - `grep -n -i immo docs/migration.md` → the statement's line only;
   - `bash tests/0027-docs.sh` → `every check passed`.

   Commit `docs(0032): …`.
6. **`docs/demo-setup.md` step 9** (RQ-02, RQ-03): choice 6. — skill: none — check:
   - `sed -n '/^## 9\. /,/^## 10\. /p' docs/demo-setup.md | grep -n -i -E 'gitlab|platform|\bCI\b'` prints nothing;
   - `grep -qF 'gh secret set VPS_KNOWN_HOSTS --env demo -R $A < c4-infra-demo.known_hosts' docs/demo-setup.md`;
   - `bash tests/0027-docs.sh` → `every check passed`;
   - AC-03's grep prints the statement's lines only (README and the guide).

   Commit `docs(0032): …`.
7. **Intermediate**: `bash tests/run.sh --changed de2be13`, with the dev stack up. It selects 7 tests, no stand-in: `0002-workflow`, `0004-registry`, `0008-certificate-scripts`, `0016-no-real-provider`, `0027-docs`, `0029-description`, `0032-demo-github-only`, about 20 s. — skill: none — check: `verification passed`.
8. **Verification** — skill: sdlc-verify — check: `verification passed`.
   - `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed de2be13 --all`, with the dev stack up, Faito registered and `jq`. The explicit base de2be13 holds whether or not the plan's commit is pushed. It runs step 7's 7 tests in lane 1, plus `0002-accounts.stand-in` (about 225 s) and `0009-master-realm.stand-in` (about 344 s) in the stand-in lanes: about 6 min with two lanes, about 10 with one (the durations of earlier runs).
   - AC-06's mutation checks, in a throwaway worktree: `git worktree add --detach "$TMPDIR/0032-mut" HEAD`, then removed. Each one reverted before the next:
     - a line naming GitLab added to `README.md` → KO naming it;
     - the statement's two lines deleted from `docs/migration.md` → KO (a);
     - the GitLab sentence moved to the section's end → KO (a);
     - `gitlab` in a comment of `demo/c4-app` → KO (b);
     - the must-not-fire twin: the statement's two lines joined into one → `every check passed`.
   - IV-03 and IV-04:
     - `git diff de2be13 -- demo/ .github/ registry.txt` is empty;
     - README's "Keycloak in an application's tests" (`/^### Keycloak in an application.s tests$/,/^### Routes file$/`) and the guide's "In dev" (`/^## In dev$/,/^## On the demo host$/`): each `diff`ed against `git show de2be13:…`, empty.
   - `/sdlc-verify 0032`: standard risk, so bootstrap's one round and the bugs pass only. The verifier reads step 3 and 5 against `cmd_pull`. Its evidence goes into `## Verification`, commit `plan: verification of 0032`.

   Then `/sdlc-ship 0032`.
9. **After deployment**: `tests/0032-demo-github-only.sh` isn't Markdown, so its push runs `deploy-demo.yml`, and that run deploys the stack unchanged:
   - the images exist under their tree's tag, so nothing is built;
   - `demo/deploy-files.txt`'s files are the same, and no test is sent;
   - `demo/deploy.sh` finds nothing to recreate.

   — skill: sdlc-ship — check: `gh run list -R ch4mpy/c4-infra --workflow deploy-demo.yml -L 1` → `success` on the pushed commit, recorded under `### After deployment`.

## Risks

- **The tests that read the example and its lines** (`0002-workflow`; `0002-accounts.stand-in` AC-08) → the example stays byte for byte (step 4's `diff`). No new prose line starts with `rsync`, `ssh "$VPS"` or `uses:`. The host-key lines aren't quoted in prose. Steps 3 and 4 run `0002-workflow` before the stand-in run.
- **A rule of the deleted paragraph lost** (RQ-05: the forms, `pull` without `--registry`, "never printed") → step 3 moves the first two and step 4 writes the third, before the paragraph goes in the same step. AC-05 finds each one, in step 3 or 5, against `cmd_pull`.
- **A statement that says more than `c4-app` does** ("any registry" without the forms) → each clause is read against `demo/c4-app:429-460`. A login to a registry other than GHCR is "not verifiable here", as in 0028: the stand-in has no registry with a login.
- **A guard that fires wrongly or misses**:
  - a rewrap → the text is flattened, and the must-not-fire twin proves it;
  - CRLF under Git Bash → `\r` is stripped;
  - the guard naming itself → excluded by path;
  - a reworded statement → it fails, as intended: the fixed parts are the decision's, and an intent that changes the decision changes the guard.
- **The guard refusing a later, legitimate GitLab mention outside the demo host** (an application's tests on GitLab, 0029's ground) → IV-03's section names no GitLab today. Such a mention is a choice for its own intent, which narrows the guard knowingly (PA-03).
- **The push deploys the demo host** → the stack is unchanged, and step 9 checks the run. Choice 7 holds `main` until `/sdlc-ship`.

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test, command | `tests/0032-demo-github-only.sh` (a): the first paragraph of README "Demo host" and of the guide's "On the demo host" holds the statement; `grep -n -i -E 'kubernetes\|scaleway\|k8s' README.md docs/*.md` prints nothing |
| AC-02 | command, manual check | step 6's `sed … \| grep` on step 9 prints nothing; 9.5 read: the application's GitHub repository, its `demo` environment; `0002-accounts.stand-in` (AC-08) still finds the `gh secret set VPS_KNOWN_HOSTS` line |
| AC-03 | command | `grep -n -i -E 'gitlab\|another platform\|other platform\|any CI\|immo' README.md docs/*.md` prints the statement's lines only (README and the guide), against 4 lines on de2be13 |
| AC-04 | manual check, commands | step 3 names "GHCR, or any registry `sudo c4-app pull --registry` logs in to" and the forms, read against `demo/c4-app:449-450`. The verifier checks each form with those regexes: `ghcr.io` and `registry.example:5000` accepted; `ghcr.io/owner` and `gitlab+deploy-token-1` refused |
| AC-05 | manual check, commands | in step 3 or 5: "on stdin", "never on a command line" and "from a secret"; "without logging in anywhere… without `--registry`… enough when every image is public"; "`demo` environment… never printed". Each is read against `cmd_pull` (`demo/c4-app:429-460`: `compose pull` without a login; `docker login --password-stdin`) |
| AC-06 | automated test, mutation checks | step 1: the guard on main's documents → KO naming `docs/migration.md:167` and `:273`. Step 4: `every check passed`. Step 8's worktree: the README line, the statement deleted or moved, `gitlab` in `demo/c4-app` → KO; the statement joined on one line → ok |
| AC-07 | automated tests, commands | `TMPDIR=~/.cache/c4-infra-tests bash tests/run.sh --changed de2be13 --all` → `verification passed`, with `0002-workflow`, `0004-registry`, `0008-certificate-scripts`, `0016-no-real-provider`, `0027-docs`, `0029-description`, `0032-demo-github-only`, `0002-accounts.stand-in`, `0009-master-realm.stand-in`. `git diff de2be13 -- demo/ .github/ registry.txt` is empty. Step 4's example `diff` and step 8's section `diff`s are empty |

## Deviations

<!-- filled during implementation: date — what — why — impact on files or proof -->
