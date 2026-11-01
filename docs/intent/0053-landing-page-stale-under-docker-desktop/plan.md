# Plan: On the Linux workstation, the landing page keeps showing what an earlier registration wrote

- Spec: [v1](spec.md) (approved 2026-10-31, PA-01 A, PA-02 A)
- Status: approved
- Branch: `0053-landing-page-stale-under-docker-desktop` (on `origin` at b501e2a)
- Approved: 2026-10-31, Jérôme Wacongne (engineer and tech lead, ExitPlanMode)

## Context

On the product owner's Linux workstation (Docker Desktop), `tests/0048-landing-page.sh` fails on AC-10 "shows it" and AC-04 "lists no account": after a registration, the proxy keeps serving the page an earlier one wrote. `write_index` (`register-app.sh:201`-`:216`) writes a temporary file then `mv`s it over `caddy/html/index.html`; the proxy reads `./caddy/` through a bind mount (`compose.yml:71`) and serves the file with `file_server` (`caddy/Caddyfile:107`-`:112`). The defect doesn't show on the Windows workstation, so this plan is written here and **implemented, verified and delivered on the Linux workstation** (the product owner, 2026-10-31), from the handover note this session pushes. The spec's PA-01 A: a facts test measures the cause first, and the fix is the way it shows fresh; by default the page rewritten in place (same inode) under a lock; PA-02 A: a request during the write may see a partial page.

## Design

- **The facts test** `tests/0053-mount-facts.sh` (a `*-facts.sh`: runs with `--all`; RQ-03, AC-04). A throwaway container of the stack's proxy image (`c4-infra/reverse-proxy`, `PROXY_IMAGE` as `tests/0015-proxy-facts.sh` does), with the run's labels (`mapfile -t C4_LABELS < <(docker_labels c4-infra)`), a `mktemp -d` directory bind-mounted read-only as its `/srv/html` (`host_path`: `cygpath -w` under Git Bash, as 0015), a Caddyfile serving it with `file_server`. For each way, five times: write page N, then read it inside the container right away and after 1 s, by `wget -qO-` against the container's own port (what the proxy serves) and by `cat` (what the mount shows):
  - (r) a new file renamed over the old one (today's `write_index`): the result **recorded, not asserted** (`fact: rename fresh at once: yes|no`, per read), since it is the platform's behaviour (fresh on Windows, stale on the Linux workstation);
  - (a) the new content written into the existing file (`cat "$tmp" > index.html`): asserted fresh at once, every time;
  - when (a) is stale on Linux, the step stops there (a deviation for the PO, PA-01): (b) a mount of its own, (c) a proxy action are measured next.
  Container removed with `docker rm -f -v`, whatever happens.
- **The writer** (`write_index`, RQ-01, RQ-02, PA-02 A): the page still built in `mktemp caddy/html/.index.XXXXXX`; then, under a lock, its content written into `caddy/html/index.html` (`cat "$page" > …`: the inode the mount knows is kept), `chmod 644`, the temporary file removed, `own` as today. The lock: `mkdir caddy/html/.index.lock` (atomic on both systems; `flock` isn't in Git Bash), retried every 0.2 s for 30 s, a lock older than 60 s taken over (a killed writer), released by a `trap` on the function's return; a lock never taken in 30 s stops the registration with a line naming the lock directory. The comment on line 205 says why the lock replaces the rename's atomicity.
- **The writers' test** `tests/0053-index-writers.sh` (AC-03, no Docker): `tests/0004-registry.sh`'s throwaway stack (`cp registry.sh routes.sh networks.sh register-app.sh registration-account.sh tlds-alpha-by-domain.txt`, a `.env`, `caddy/apps/*.caddy`, `keycloak-import/simulated-*`), two `register-app.sh --index-only` started at once, ten times, the second's site list differing: each time the file starts with `<!doctype html>`, ends with `</body></html>`, holds one `<!doctype`, and is one of the two pages; no `.index.*` nor `.index.lock` left. `# covers: register-app.sh`.

## Files

| File | Change | For |
| --- | --- | --- |
| `tests/0053-mount-facts.sh` | new: the facts of a page replaced under the proxy's bind mount | RQ-03, AC-04 |
| `tests/0053-index-writers.sh` | new: two writers at once leave one whole page | RQ-02, AC-03 |
| `register-app.sh` | `write_index`: the page written in place under a lock (or the way the facts choose) | RQ-01, RQ-02, IV-01 |
| `docs/intent/HANDOVER.md` | the handover entry for the Linux workstation; then, at delivery, 0053 among the delivered | PA-01 |
| `docs/intent/0053-…/plan.md`, `intent.md`, `docs/intent/README.md` | the plan, `planned`, then the evidence | |

`tests/0048-landing-page.sh` is the bug's reproduction and is **not changed** (frozen from step 1).

## Order of work

Steps 1 to 6 on the Linux workstation, in a worktree of the branch; the stack-dependent tests from the main checkout detached at the step's commit (the proxy serves that checkout's `caddy/html`: 0048-landing-page's header); its locale as is; `TMPDIR=~/.cache/c4-infra-tests`; no other run on that Docker.

1. **Failing test** — skill: none — check: from the main checkout detached at the branch's head, `bash tests/0048-landing-page.sh` → `2 check(s) failed` (AC-10 "shows it", AC-04 "lists no account"), its lines into *Deviations*; then freeze it (`.claude/frozen-tests.local`). No commit of code; commit `plan: 0053, the bug reproduced on the Linux workstation`.
2. **The facts** — skill: none — check: `bash tests/0053-mount-facts.sh` on the Linux workstation, its `fact:` lines and verdict into *Deviations* (and on the Windows workstation later, AC-02's session). (a) fresh → go on; (a) stale → stop, a deviation for the PO (PA-01). Commit `test(0053): the facts of a page replaced under the proxy's bind mount`.
3. **The writers' test** — skill: none — check: `bash tests/0053-index-writers.sh` green on today's writer (the rename already keeps one page: it guards RQ-02 through the change). Commit `test(0053): two writers of the landing page leave one whole page`.
4. **The fix** — skill: none — check: `bash -n register-app.sh`; `bash tests/0053-index-writers.sh` green; from the main checkout detached at the commit, `bash tests/0048-landing-page.sh` three times in a row, each `every check passed` (the PO's three); `bash tests/run.sh --changed origin/main` → `verification passed`. Commit `fix(0053): the landing page is written in place, under a lock`.
5. **Verification** — `/sdlc-verify 0053` (bootstrap: the bugs pass, one fix round; standard risk): its run `bash tests/run.sh --changed --all` from the main checkout detached at the head (the stand-in tests for AC-05, the facts test, 0048-landing-page a fourth time); the mutation check: 0048-landing-page KO at step 1's commit is step 1's; the verifier; the evidence block into `## Verification`, naming the machine. Commit `plan: verification of 0053`.
6. **Delivery** — `/sdlc-ship 0053`: `delivered`, `merge(0053): …` into `main`, pushed; deploy-demo follows (`register-app.sh` is deployed): its run green, then `https://infra.c4-soft.com/` 200 with Tickee's link (0048's check after deployment). HANDOVER's entry moves to the delivered list. AC-02 (Windows) is asked of the Windows session after delivery: `bash tests/0048-landing-page.sh` and `bash tests/0053-mount-facts.sh` there, recorded under *After deployment*; a KO is a bug intent.

This session (Windows): writes `plan.md`, sets 0053 `planned`, writes HANDOVER's entry (steps 1 to 6 above, the prerequisites, the frozen test, PA-01's stop), commits `plan: …` and pushes the branch. No code here.

## Risks

- The in-place write is stale too under Docker Desktop on Linux → the facts test (step 2) stops before any fix; the PO decides among (b) and (c) (PA-01).
- A killed registration leaves `.index.lock` → taken over after 60 s; the writers' test checks nothing is left; the lock's directory named in the refusal line.
- `cat >` truncates first: a reader sees a partial page for the write's few milliseconds → accepted (PA-02 A).
- The demo host runs the same writer as root → `chmod 644` and `own` as today; AC-05's stand-in tests (`0048-accounts.stand-in`, `0003-demo-edge`) in step 5's run; deploy-demo's check in step 6.
- 0048-landing-page run from a worktree reads the main checkout's page → every stack-dependent run from the main checkout detached at the commit (step preamble).

## Proof

| Criterion | How | Test, command or check |
| --- | --- | --- |
| AC-01 | automated test, three times + full run, Linux | `tests/0048-landing-page.sh` (KO at step 1, green ×3 at step 4, in step 5's `--changed --all`) |
| AC-02 | automated test, Windows, after delivery | `tests/0048-landing-page.sh` on the Windows workstation |
| AC-03 | automated test | `tests/0053-index-writers.sh` |
| AC-04 | automated test (facts), Linux and Windows | `tests/0053-mount-facts.sh`, its `fact:` lines in *Deviations* |
| AC-05 | automated test (stand-in) | `tests/0048-accounts.stand-in.sh` (the page fresh after a deployment, mode 644, owned as the registrations left it) in step 5's run; deploy-demo's check |

## Deviations

- 2026-10-31, Linux workstation (Ubuntu, Docker Desktop), step 1: `bash tests/0048-landing-page.sh` from the main checkout detached at 09480d3 (the branch's head), locale as is, `TMPDIR=~/.cache/c4-infra-tests`, twice, the same result each time:

  ```
  KO - AC-10: shows it
  KO - AC-04: lists no account
  2 check(s) failed
  ```

  The test is frozen from here (`.claude/frozen-tests.local`).
- 2026-10-31, Linux workstation, step 2: `bash tests/0053-mount-facts.sh` (15 s); the directory is mounted as the stack mounts `./caddy/` (its `html/index.html` under it), and (a) runs on the file (r)'s renames left, as the fix's first write will:

  ```
  fact: (r) page 1, at once: served no, mounted no; after 1 s: served no, mounted no
  … (pages 2 to 5 the same)
  fact: (r) rename fresh at once: no, 5 of 5 stale
  fact: (a) page 1, at once: served yes, mounted yes; after 1 s: served yes, mounted yes
  … (pages 2 to 5 the same)
  fact: (a) in place fresh at once: yes
  ok - (a) the content written into the existing file: served and mounted fresh at once, every time
  every check passed
  ```

  Verdict: the rename is the cause (the mount keeps showing the replaced file, 1 s later too, whatever the stack's age: this container was new); the page written in place is fresh at once, so the plan's default (a) holds and PA-01's stop doesn't apply.
- 2026-10-31, step 3: `bash tests/0053-index-writers.sh` on today's writer (the rename), 6 s: `every check passed` (31 checks). The two pages differ by the registry each writer reads (`REGISTRY_FILE`, the fixture's six applications or its first three), since both read the same `caddy/apps/`.
- 2026-10-31, step 4 (9c48b1e): the lock is released by the script's `cleanup` on exit (`index_lock`, beside the admin CLI's session) rather than a `trap … RETURN`, which bash keeps set after the function returns. Without the lock, the writers' ten rounds still pass (mutation tried: two `cat >` of a few kB never overlapped enough to mix), so `tests/0053-index-writers.sh` checks the lock on its own: one held makes the next writer wait, one older than 60 s is taken over, nothing left; those checks are KO on the rename (`KO - a held lock: the next writer waits`, `KO - a lock older than 60 s: nothing left`) and green on the fix. Checks: `bash -n register-app.sh` ok; `bash tests/0053-index-writers.sh` → `every check passed`; from the main checkout detached at 9c48b1e, `bash tests/0048-landing-page.sh` three times in a row → `every check passed` each (29 s, 30 s, 30 s); `bash tests/0004-registry.sh` → `every check passed`; `bash tests/0053-mount-facts.sh` → `every check passed`.
- 2026-10-31, step 4: `bash tests/run.sh --changed origin/main` **not run**: the tests the change selects include `tests/0005-themes.sh` (its `INFRA_ENV=demo` part restarts the dev Keycloak) and `tests/0006-account.sh` (it runs Faito's `deploy-dev.sh`, which runs `up.sh`), and the shared stack mustn't be restarted while another project's agent uses it (the PO, 2026-10-31). It runs with step 5, in the quiet window.
- 2026-10-31: step 4's `bash tests/run.sh --changed origin/main`, steps 5 (`/sdlc-verify 0053`, its `bash tests/run.sh --changed --all`) and 6 (delivery) wait for a quiet window on the Linux workstation's Docker, another project's agent using the shared dev stack (the PO, 2026-10-31). Steps 1 to 4 ran without restarting any shared service.
- 2026-10-31, step 5, the review round (3 Important, 7 details): the lock is taken before the page is built, not only around the copy (a page built before another registration would drop it); a lock older than 60 s is removed under a second lock, `.index.lock.takeover`, so that two waiting writers can't both take it over, and a killed writer's takeover lock older than 60 s is removed too; the wait is 90 s, longer than the 60 s after which a lock is stale; the lock's release can't fail the script; the page being built is removed on exit. `tests/0053-index-writers.sh` gains the checks of these (red on b18154a: the page built once the lock is held, the takeover left to its holder, a stale takeover lock removed), and its waiting writer is judged after twice the time a page takes to build. `tests/0053-mount-facts.sh` keeps its `mktemp` directory and says when its proxy doesn't start. `docs/intent/HANDOVER.md` updated. A failed `cat` into `index.html` still leaves the page truncated until the next write: the price of writing in place (PA-02 A).
- 2026-10-31, step 5, the verifier's KO on AC-05: no test asserted the demo page's mode and owner, and `tests/0003-demo-edge.sh` writes a page of its own, never through `register-app.sh`; `tests/0048-accounts.stand-in.sh` now checks, after the deployment, mode 644 and the owner the registrations left, and the Proof names it alone.

## Verification
