# STATUS — where tailbell stands

Hand-written intent. Everything computable (branch, dirty files, commits behind)
comes from the session-start hook instead — never restate it here.

Last reviewed: 2026-08-19

## Now

**Release 8 (`v8-parity`) is code-complete and untested on macOS.** All four
workstreams are built, committed and covered by `tests/run-tests.sh`; what is
missing is the half of the verification that needs a Mac and a phone, and one
measurement that needs an interactive terminal CLI. The list is in *Open* below —
it is short and specific, and nothing merges to `main` until it is worked through.

Scope and guardrails: [v8-brief.md](v8-brief.md). How it was built, and the
measurements taken first: [v8-design.md](v8-design.md).

## Execution order — deliberately not the numeric order

    v8-parity  →  v7-any-os  →  v5-claude-and-codex  →  v6-any-agent

Other agents come **last** by decision, not by accident: releases 5–6 force an
agent-neutral event schema, and every earlier release changes what that schema
has to carry. Release 8 added `kind` to the event record for exactly the reason
that argument predicted. Releases 2, 3 and 4 are small remainders folded in
wherever they touch.

## Which file answers which question

| question | file |
| --- | --- |
| why is it built this way, what was tried and rejected | [architecture.md](architecture.md) — every claim is a measurement |
| what are the releases and where do the branch boundaries sit | [roadmap.md](roadmap.md) |
| what does release 8 contain, and what is out of scope | [v8-brief.md](v8-brief.md) |
| how release 8 is built, and why each piece is shaped that way | [v8-design.md](v8-design.md) |
| how does the field compare, what did release 8 close | [competitors.md](competitors.md) |
| why is there no two-way remote control | [two-way-control.md](two-way-control.md) |
| why does tailbell not warn about quota | [usage-quota.md](usage-quota.md) |
| what broke before, and what must never break again | `tests/run-tests.sh` |
| where did this repo come from | [MIGRATION.md](MIGRATION.md) |

## Open — release 8's remaining verification

Everything here needs hardware or a session this branch was written without.

1. **Every macOS path is unverified.** Sound per event kind, the Focus/DND check,
   the spoken alert, and the doctor's sound self-test were all written on the
   cluster. `docs/MIGRATION.md` records that this exact blindness shipped three
   real bugs last time.
2. **`PermissionRequest` has never been seen to fire for a tool permission
   prompt.** Headless `claude -p` auto-approves and never prompts, so the hook
   cannot be provoked without an interactive terminal CLI session. The approval
   path is *designed* against the documented contract and *tested* against a fake
   phone; it is not yet known to work against the real event.
3. **No channel has been delivered to a real phone.** The sinks are tested
   against a recorded fake `curl`; a real ntfy/Slack/Discord/Feishu round trip,
   and the compute-node-through-`http_proxy` case, still need doing.
4. **Nothing is published.** No git push, no tag, no brew tap, no npm publish. The
   formula is deliberately HEAD-only until a tag exists.

## Open — older, still true

- **Never exercised, still:** ⌥Esc bulk clear · `StopFailure` · `Elicitation` ·
  permission prompts in the terminal CLI · alert stack compression · click-to-focus
  for anything other than VS Code.
- The prototype this grew out of still sits in `~/.claude/hooks/` (`cc-notify.sh`,
  `cc-hammerspoon.lua`, `gl-listen.py`, …). It is dead code on a live machine —
  easy to edit by mistake. One part of it is **not** dead: `probe.sh` is still
  registered on `Notification` and `PermissionRequest`, and its log is where
  release 8's correction to architecture.md §1 came from. Leave it registered.

## Settled, do not reopen without new evidence

- Two-way remote control: **declined** — [two-way-control.md](two-way-control.md).
- Reading `~/.claude/.credentials.json` for quota: **declined** —
  [usage-quota.md](usage-quota.md).

Each page names what would change the answer. That is the bar for reopening.
