# STATUS — where tailbell stands

Hand-written intent. Everything computable (branch, dirty files, commits behind)
comes from the session-start hook instead — never restate it here.

Last reviewed: 2026-08-19

## Now

Release 0 is done and verified end to end; release 1 is shipped bar two untested
paths; releases 2 and 4 are partly wired. The next piece of work is **release 8,
`v8-parity`**: build the things comparable tools have and tailbell does not.

Scope, guardrails and the reasoning behind that release live in
[v8-brief.md](v8-brief.md). Read it before touching anything on that branch.

## Execution order — deliberately not the numeric order

    v8-parity  →  v7-any-os  →  v5-claude-and-codex  →  v6-any-agent

Other agents come **last** by decision, not by accident: releases 5–6 force an
agent-neutral event schema, and every earlier release changes what that schema
has to carry. Doing them first means writing the schema twice.
Releases 2, 3 and 4 are small remainders folded in wherever they touch.

## Which file answers which question

| question | file |
| --- | --- |
| why is it built this way, what was tried and rejected | [architecture.md](architecture.md) — every claim is a measurement |
| what are the releases and where do the branch boundaries sit | [roadmap.md](roadmap.md) |
| what does release 8 actually contain, and what is out of scope | [v8-brief.md](v8-brief.md) |
| how does the field compare, what do rivals have that we don't | [competitors.md](competitors.md) |
| what broke before, and what must never break again | `tests/run-tests.sh` |
| where did this repo come from | [MIGRATION.md](MIGRATION.md) |

## Open

- **Never exercised, still:** ⌥Esc bulk clear · `StopFailure` · `Elicitation` ·
  permission prompts in the terminal CLI · alert stack compression · click-to-focus
  for anything other than VS Code.
- **Undecided:** whether two-way remote control (reply to a message to issue a new
  instruction) belongs in this project at all. It requires forwarding conversation
  content off the machine, which release 0 exists to avoid. See v8-brief.md.
- The prototype this grew out of still sits in `~/.claude/hooks/` (`cc-notify.sh`,
  `cc-hammerspoon.lua`, `gl-listen.py`, …). Nothing references it any more except
  `probe.sh`. It is dead code on a live machine — easy to edit by mistake.
