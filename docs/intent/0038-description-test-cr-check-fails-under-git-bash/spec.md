# Spec: tests/0029-description.sh's carriage-return check fails under Git Bash on a description without one

- Intent: [0038](intent.md)
- Status: approved
- Version: 1
- Risk: standard (no risk rule applies: a check of the test suite on a description file; no authentication, secret, isolation between applications, network exposure or personal data)
- Policies applied: none yet; standing constraints: CLAUDE.md (the scripts run under Git Bash on Windows and bash on Ubuntu; a script with its test and its `# covers:`), 0029's RQ on the description's form (`tests/0029-description.sh` (a))
- Approved: 2026-10-30, Jérôme Wacongne (PO, also tech lead; in the drafting session, every point of attention decided)

## Summary

Check (a) of `tests/0029-description.sh` must refuse a carriage return in `keycloak-image.properties` and accept a description without one, under Git Bash as under Linux. Today, under Git Bash, it refuses every description, and once that is fixed it would still let the most likely carriage return through: a CRLF line end, which Git Bash's `grep` doesn't see. For the Developer: a verification on the Windows workstation without a false KO, and a check that holds there.

## Requirements

- **RQ-01:** Check (a) refuses a description holding a carriage return, wherever it is: before a line feed (a CRLF line end), as a line end on its own, inside a line; under Git Bash on the Windows workstation and under bash on Ubuntu. Its message names each line that holds one. (intent: proposed outcome; success criterion, "still refuses a copy with a carriage return")
- **RQ-02:** Check (a) accepts a description without a carriage return: the repository's `keycloak-image.properties` passes it on both systems. (intent: success criterion)
- **RQ-03:** The check's other rules hold unchanged: each line a comment, blank, or `KEY=value` of the safe characters; a line of another form is refused and named, as today. (intent: constraint, "fixed, not weakened nor skipped")
- **RQ-04:** The test proves check (a) on copies of the description, on both systems: a copy of each form of RQ-01 refused, the repository's description accepted. A check that can't see a carriage return then fails the test. (intent: success criterion, "and still refuses a copy…; the same on Linux")
- **RQ-05:** No tracked script writes a carriage return as an ANSI-C quote (`$'\r'`, `$'\x0d'`, `$'\015'`…) inside a command or process substitution, and none relies on Git Bash's `grep` to see a carriage return before a line feed. How this is kept: PA-01. (intent: open question, other escapes inside a command substitution)

## Out of scope

- The other scripts' handling of CRLF files (`registry.sh`, `routes.sh`, `register-app.sh`, `tests/lib/keycloak.sh` strip it by parameter expansion, outside any substitution): unchanged.
- The four Keycloak tests that fail on the same workstation: intent 0039.
- Which Git for Windows a workstation must run: nothing pinned.

## Design

### Current behaviour

Measured on 2026-10-30 on the Windows workstation, Git for Windows 2.56.0(4) (installed again on 2026-10-29 at 18:16), `bash` 5.3.15 (`$BASH_VERSION`; the intent's "5.2" was not measured), GNU `grep` 3.0, `igncr` off:

- `form()` (`tests/0029-description.sh:36-40`) runs two `grep` inside `bad=$(…)`: the lines not of the safe form, then `grep -n $'\r'`.
- Inside a command substitution (`$(…)`, written on one line or several) or a process substitution (`<(…)`), a carriage return written as an ANSI-C quote is dropped, whatever its spelling (`\r`, `\x0d`, `\015`), in a parameter expansion too: `$(printf %s $'\r' | od -An -tx1)` prints nothing, while `$'\t'`, `$'\n'` and `$'\e'` keep their byte. The loss is where the quote is written: a function defined outside the substitution and called inside keeps it, a substitution written inside a function body loses it. A carriage return held in a variable (`cr=$'\r'`, then `"$cr"` inside), through `eval`, or inside backquotes, keeps its byte. So `grep -n $'\r'` becomes `grep -n ''` and lists every line: the intent's KO.
- Git Bash's `grep` strips a carriage return before a line feed from a file it reads as text: on a file `A=1\r\nB=2\n`, `grep -c "$cr"` gives `0`, `grep -cU "$cr"` gives `1`; and the safe-form `grep` passes `A=1\r` as `A=1`. So a CRLF line end escapes both of today's `grep`, the substitution fixed or not. A carriage return inside a line, or as a line end on its own, is still seen by both.
- Check (a) passed in the `--all` of 2026-10-28 (HANDOVER.md, 205b8eb), `form()` unchanged since 2026-10-28 05:09 (8b4f87b); 0036's step 1 saw the KO at 2026-10-29 22:17, after the reinstall. The version installed before is not known here: the reinstall is a lead, not a proven cause, and the requirements don't depend on it.
- The repository: `$'\r'` inside a substitution only at `tests/0029-description.sh:38` (`git grep`, 2026-10-30); the other `$'\r'` (`register-app.sh:188`, `:217`, `:320`, `:489`, `registry.sh:90`, `:143`, `routes.sh:108`, `tests/0002-workflow.sh:32`, `tests/lib/keycloak.sh:44`) are outside any substitution. No other script looks for a carriage return with `grep`.
- Linux (intent, 2026-10-29, `ubuntu:24.04`): `grep` gives no line on the repository's description. Linux's `grep` doesn't strip a carriage return; that its safe-form `grep` refuses `A=1\r` is to be measured at the plan's first step.

### Behaviour per persona

- **Developer**: on the Windows workstation, a run that selects `tests/0029-description.sh` reports (a) `ok` on the repository's description. A description saved with CRLF line ends (an editor, a checkout with `core.autocrlf=true`) is refused under Git Bash as under Linux, its lines named, before an application's tests read it with a stray `\r` in each value.

### API and contracts

- Check (a)'s name unchanged: `(a) the description's lines are comments or KEY=value, no CR`. Its message on a refusal: `lines:`, then each refused line by its number.

### User interface, Data

None.

## Policies applied

| Rule | How it is satisfied |
| --- | --- |
| — | No policy yet. Standing constraints: Git Bash and bash on Ubuntu → RQ-01, RQ-02, RQ-04, AC-01 to AC-03, PA-02; a test not weakened → RQ-03, AC-04 |

## Points of attention

### PA-01: How the repository keeps away from the two traps (RQ-05)

- Issue: the measured traps (an ANSI-C carriage return dropped inside a substitution; Git Bash's `grep` blind to a CR before LF) can come back in any script the agent or the Developer writes. CLAUDE.md's Git Bash line names `MSYS_NO_PATHCONV` and `cygpath -w`, not these.
- Options:
  - A: CLAUDE.md's Git Bash line names both traps, in this change; no test of the whole repository.
  - B: A, plus a test over the tracked scripts refusing a carriage-return ANSI-C quote on a line that opens a substitution (it sees only a substitution written on one line).
  - C: the fix of `:38` only; the traps left to the memory of the session that met them.
- Recommendation: A. One line where the other Git Bash traps already are, read before any script is written; today's count is one occurrence, and B's check would miss a multi-line substitution while adding a test to keep. It touches CLAUDE.md, the agent's configuration: the project has no evals, so no eval report.
- Decides: PO
- Decision: A (2026-10-30, Jérôme Wacongne)

### PA-02: How check (a) is proven on Ubuntu (RQ-01, RQ-04)

- Issue: the success criterion asks for Linux too; there is no Ubuntu workstation, and 0035's AC-07 stayed "not verifiable here" for that reason.
- Options:
  - A: the plan's verification runs `tests/0029-description.sh` once in an `ubuntu:24.04` container, on a copy of the checkout, as a command proof (its output in `plan.md`).
  - B: a permanent stand-in test running it on the stand-in host (Ubuntu), in every `--all`.
  - C: Linux not checked; the requirement stays for the human reviewer.
- Recommendation: A. The test needs bash, `grep`, `git` and the files only, no Docker inside: a container gives the same bash and `grep` as Ubuntu for a minute's run; a permanent stand-in test (B) costs every `--all` for a check this small.
- Decides: PO
- Decision: A (2026-10-30, Jérôme Wacongne)

## Acceptance criteria

- **AC-01:** Given the Windows workstation under Git Bash, when `bash tests/0029-description.sh` runs on the repository, then check (a) is `ok`. (RQ-02)
- **AC-02:** Given copies of the description with a CRLF line end, with a carriage return as a line end on its own, and with one inside a line, when check (a) runs on each under Git Bash, then each is refused, its message naming the line that holds it; and the copy checks are part of the test. (RQ-01, RQ-04)
- **AC-03:** Given bash on Ubuntu, when the same test runs, then AC-01 and AC-02 hold there too. (RQ-01, RQ-02, RQ-04; how: PA-02)
- **AC-04:** Given a copy with a line of another form (a space in a value, a lowercase key), when check (a) runs, then it is refused and the line named, as today. (RQ-03)
- **AC-05:** Given the tracked scripts, when they are searched for a carriage-return ANSI-C quote inside a substitution, or a `grep` relied on to see a CR before LF, then none is found; and the traps are written down as PA-01 decides. (RQ-05)

## Intent questions

- Whether a check of the whole suite looks for other `$'…'` escapes inside a command substitution → only a carriage return is dropped (every spelling); `$'\t'`, `$'\n'`, `$'\e'` keep their byte; the only occurrence is `:38` (Current behaviour) → RQ-05, PA-01.
- Spec needed → yes (the PO, 2026-10-30, at the intent's acceptance).

## Change log

- v1 — 2026-10-30 — first version; approved by the PO in the drafting session (PA-01 A, PA-02 A)
