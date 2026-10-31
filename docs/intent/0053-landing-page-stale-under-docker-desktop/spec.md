# Spec: On the Linux workstation, the landing page keeps showing what an earlier registration wrote

- Intent: [0053](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: the dev landing page's freshness; the page's content, its escaping and its headers don't change. The demo host runs the same writer: RQ-04)
- Policies applied: none (the project has no policy yet)
- Approved: 2026-10-31, Jérôme Wacongne (in the drafting session; every point of attention decided)

## Summary

On the product owner's Linux workstation (Docker Desktop), the reverse proxy keeps serving the landing page an earlier registration wrote: `register-app.sh` renames its new page over `caddy/html/index.html`, and the proxy reads `caddy/` through a bind mount that, there, kept the old file seconds later. Once a registration has written the page, the proxy serves that page, on Linux and on Windows, and two writers at once still leave one whole page. The cause is confirmed on the Linux workstation before the fix is chosen (PA-01).

## Requirements

- **RQ-01:** When `register-app.sh` returns (a registration, `--index-only`, `up.sh`'s first page), the reverse proxy serves the page it has just written, on the Linux workstation (Docker Desktop) and on the Windows one. (intent: proposed outcome)
- **RQ-02:** Two writers of the page at once (two registrations, a registration and a deployment) still leave the file holding one whole page, one or the other, never a mix. (`register-app.sh:205`, the reason of today's temporary file; intent: constraints)
- **RQ-03:** The cause is established by a reproduction on the Linux workstation, kept in the suite as a facts test (the proxy's image, a bind-mounted directory, a page replaced by rename and by the chosen way, read through the container right after the write), and the fix is the way that test shows fresh. (intent: open questions; PA-01)
- **RQ-04:** The demo host's behaviour holds: the page it serves after a deployment and after `sudo c4-app register` is the one just written, its content, mode and owner unchanged; the stand-in tests that read it pass. (intent: constraints, "nothing the demo host runs may change behaviour without its own check")
- **IV-01:** The page's content, its escaping, its headers (CSP, `X-Robots-Tag`) and the files a registration writes elsewhere are unchanged. (0048)

## Out of scope

- A check, at each registration, that the proxy serves the new page (the PO, 2026-10-31: fix the write only).
- The other files the proxy reads from `caddy/` (the sites, `env/*.caddy`): Caddy reads them at a reload, which no report shows stale; a defect found there by the facts test is a new intent.
- The skills' improvement log entry P-24 (`ch4mpy/claude`): theirs to close once this is delivered.

## Design

### Current behaviour

- `write_index` writes the page to `mktemp caddy/html/.index.XXXXXX`, `chmod 644`, then `mv` over `caddy/html/index.html` (`register-app.sh:203`-`:216`): a new file, a new inode, in place of the old one.
- The proxy mounts `./caddy/:/etc/caddy/:ro` (`compose.yml:71`) and serves `/` with `root * /etc/caddy/html`, `rewrite * /index.html`, `file_server` (`caddy/Caddyfile:107`-`:112`): it opens the file at each request, no cache of its own.
- On the Linux workstation, 2026-10-31 (the intent): 6 s after a rename, the container still served the old content; `tests/0048-landing-page.sh` KO on AC-10 "shows it" and AC-04 "lists no account", alone and in a full run, under `fr_FR.UTF-8` and `C`. On the Windows workstation it passes (0048's delivery; the `--all` at c6a8872).
- On the demo host, Docker runs natively (no Docker Desktop file sharing): not reported stale; not measured.

### Behaviour per persona

- **Developer**: after `bash register-app.sh … --accounts …` returns, `https://host.docker.internal/` shows the accounts it just read.
- **Demo operator / Application**: unchanged; the page after a deployment is the one written.

### API and contracts

None changes: `register-app.sh`'s options and output, the page's URL, content and headers.

The way the page replaces the old one is decided by the facts (RQ-03, PA-01). The candidates, to be measured on the Linux workstation: (a) the new content written into the existing file (same inode), from the temporary file, under a lock that serializes writers (RQ-02); (b) `caddy/html/` mounted on its own, the rename kept; (c) the proxy told to drop its view after the rename. The plan's default is (a), the smallest change that keeps the inode the mount already knows.

### User interface

The landing page, unchanged.

### Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | the project has no policy; CLAUDE.md's standing constraints hold: Git Bash and Ubuntu, host paths given to Docker with `cygpath -w` under Git Bash, the tests' labels and `rm -f -v` (0049) for the facts test's container |

## Points of attention

### PA-01: The fix is chosen by the reproduction on the Linux workstation

- Issue: the cause can't be observed on this workstation (Windows); the intent leaves open whether it is the rename, the mount's cache or the stack's age. Choosing the fix before the facts risks a fix that doesn't hold there.
- Options: A, the plan's first step on the Linux workstation is the facts test (RQ-03), which measures each candidate; the fix is the candidate it shows fresh, the plan's default (a) unless the facts say otherwise, recorded as a deviation / B, write in place (a) now, without the facts test, and prove it by `tests/0048-landing-page.sh` alone.
- Recommendation: A: the facts test costs one test and keeps the cause on record, so that a later change of the writer or of the mount doesn't bring it back unseen.
- Decides: PO (tech lead)
- Decision: A (the PO, 2026-10-31)

### PA-02: A request during a write may see the page being written

- Issue: with (a), the file is rewritten in place: a request arriving during that write (a few milliseconds, a page of a few kB) may receive a partial page; today's rename never shows one. Two writers stay serialized (RQ-02).
- Options: A, accept it: the page is a dev and demo convenience, the next request shows it whole / B, refuse it: only a candidate that never shows a partial page qualifies ((b) or (c)), whatever its cost.
- Recommendation: A, because the window is a single short write and the page carries no state.
- Decides: PO
- Decision: A (the PO, 2026-10-31)

## Acceptance criteria

- **AC-01:** Given the dev stack up on the Linux workstation (Docker Desktop) from the main checkout, when `bash tests/0048-landing-page.sh` runs three times in a row, then each run passes, AC-10 "shows it" and AC-04 "lists no account" included; and the `bash tests/run.sh --changed --all` of the verification passes it too. (RQ-01; the PO, 2026-10-31: three alone and one full run)
- **AC-02:** Given the Windows workstation, when `tests/0048-landing-page.sh` runs, then it passes. (RQ-01)
- **AC-03:** Given two writers of the page started at once, when both have ended, then the file holds one whole page (from `<!doctype html>` to `</body></html>`, the content of one of them). (RQ-02)
- **AC-04:** Given the facts test on the Linux workstation, when it replaces a bind-mounted page by rename and by the chosen way, then it records whether the container reads the new content at once for each, and passes only when the chosen way is fresh; its output is in the plan's `## Verification`. (RQ-03)
- **AC-05:** Given a stand-in demo host, when an application is deployed and registered again, then the page it serves is the one just written, mode 644 and owned as today (`tests/0048-accounts.stand-in.sh`, `tests/0003-demo-edge.sh`). (RQ-04, IV-01)

## Intent questions

- Is it the rename, the mount's cache, or the stack's age? → the facts test on the Linux workstation (RQ-03, PA-01).
- Fix in the writer, in the proxy, or both? → the candidate the facts show fresh, by default the writer (a) (Design; PA-01, PA-02).

## Change log

- v1 — 2026-10-31 — first version
- v1 — 2026-10-31 — approved by the PO in the drafting session; PA-01: A, PA-02: A
