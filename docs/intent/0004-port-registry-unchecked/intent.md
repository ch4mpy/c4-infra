# Intent: Nothing prevents two applications from taking the same port block

- Author: Jérôme Wacongne (product owner, tech lead)
- Kind: change
- Source: conversation (quality review of the shared stack, 2026-10-21)
- Spec needed: yes
- Status: delivered
- Opened: 2026-10-21
- Decided: 2026-10-21
- Delivered: 2026-10-23 (deployed with 0697208; PR #6)
- Supersedes: —

## Problem

Each application owns a block of 1 000 ports, recorded in a Markdown table of the README. An agent running the `create-dev-infra` skill reads that table to pick "the next free number" and adds a row, uncommitted, in this repository; `register-app.sh` never looks at it.

- Two projects created before the row is committed (two sessions, two machines) get the same block, and nothing notices: the second application's reverse-proxy server routes to the first one's processes, or its gateway fails to bind a port with an unclear message.
- An application registered under a name absent from the registry, or with ports outside its block, is accepted as well.

## Proposed outcome

An application can't be registered with a block, or ports, that another application owns, and the next free block is known without reading prose. Success criterion: registering a second application with an existing application's number, or a server block pointing at another block's ports, is refused with a message naming the owner.

## Affected users and systems

- Developer, Application.
- Port registry, registration, the `create-dev-infra` skill.

## Constraints

- Applications on several machines must agree on the same numbers: the registry stays in this repository.

## Open questions

- None.
