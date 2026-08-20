# STATUS — where tailbell stands

Hand-written intent. Everything computable (branch, dirty files, commits behind)
comes from the session-start hook instead — never restate it here.

Last reviewed: 2026-08-20

## Now

**Release 8 is merged to `main`** (PR #1, 37 commits) and CI is green on
`ubuntu-latest` and `macos-latest`. The repository now lives on the MacBook as
well, which is what `docs/MIGRATION.md` was written for — **a session running
there is the one that can finish this**, and it has started.

**The live problem, being worked on the Mac:** stray notifications keep
appearing on the workstation — `oneliner · 完成`, `proj-v0 · 完成`,
`t · 完成 / 1秒 · x (#1)`. Every one is a **test fixture**: `400` seconds is the
suite's fake turn length and renders as `6m40s`, and `t`/`x`/`#1` are its
placeholder project, node and session.

Two causes, one fixed here and one still on the Mac:

- **Fixed (PR #2, main).** `tests/run-tests.sh` called the real `osascript` and
  `afplay` on macOS, and its one-liner case ran `packaging/get-tailbell.sh`,
  which on Darwin runs `mac/install.sh` — writing a LaunchAgent and
  `launchctl load`ing it, with `HOME` pointed at a throwaway directory. Running
  the suite on a Mac therefore drew real alerts *and* installed a listener into
  the tester's own login session. The temp directory was cleaned up; the loaded
  job was not.
- **Not fixed.** `mac/install.sh` hardcodes the label `dev.tailbell.listen`, so
  the rogue registration collides with the real one — only one can hold the
  label. `KeepAlive` is `true`, so `pkill` is useless; it takes
  `launchctl bootout gui/$(id -u)/dev.tailbell.listen`. And the rogue job's
  dedup state lived in the deleted directory, so every reconnect re-delivered
  the same event. **The label needs a `TAILBELL_HOME` fingerprint, or
  `mac/install.sh` must refuse to load when `HOME` is not the real one.**

**Also open: sound is inconsistent** — sometimes all three per-kind sounds play
and are distinguishable, sometimes an alert is silent. The two renderers differ in how
they make sound (Hammerspoon draws a silent canvas and `play_sound` calls
`afplay`; the osascript path hangs the sound on the notification, which the
Script Editor notification settings can mute). `focus_active()` reads
`~/Library/DoNotDisturb/DB/Assertions.json`, which is **TCC-denied** on that
machine — whether that failure is being misread as "Focus is on" and swallowing
the sound is unverified.

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
| what still needs a Mac, a phone or a real webhook, and exactly how to check it | [verify-release-8.md](verify-release-8.md) |
| what broke before, and what must never break again | `tests/run-tests.sh` |
| where did this repo come from | [MIGRATION.md](MIGRATION.md) |

## Open — release 8's remaining verification

Everything here needs hardware or a session this branch was written without.

1. **The macOS install and the sounds are verified; two renderer questions are
   not.** Confirmed on the user's Mac on 2026-08-20: `mac/install.sh` completes,
   `tailbell-doctor --test` runs green on the workstation side, and the doctor's
   sound self-test plays all three per-kind sounds — **and they are audibly
   distinguishable without looking at the screen**, which was the whole point of
   choosing per-kind sounds rather than one bell. That closes the largest part of
   the blindness `docs/MIGRATION.md` warns about, and it is why macOS is now in
   CI rather than trusted.

   Still unverified on macOS: the Focus/DND check (needs Focus actually on) and
   the spoken alert (off by default, so nobody has heard it).

   *Verified incidentally on 2026-08-19:* the live chain does work — an event
   raised on `gl-login4` reached the Mac and rendered as a centered Hammerspoon
   overlay, and Option+Esc bulk clear was exercised for the first time — it
   works, and it is now documented in troubleshooting.md rather than left as a
   symbol nobody can name. **Two renderer defects seen that day are still
   unfixed and unreproduced:** the message line appeared **truncated**
   (`… · gl-` cut off), and stacked alerts overlapped each other and the text
   behind them. Both are in `mac/tailbell.lua`, both need the Mac to diagnose,
   and neither blocks the merge.
2. **Approval is verified against a real session — except the phone itself.**
   Driving a terminal CLI session inside a pty showed that `PermissionRequest`'s
   decision is ignored and `PreToolUse`'s is applied; the path was moved and then
   verified end to end (request pushed, button pressed, decision applied, no
   prompt drawn). What remains untested is the literal last hop: a real ntfy app
   rendering the action buttons and posting back.
3. **No channel has been delivered to a real phone.** Half of this is now done:
   a Slurm job on `gl3009` published to ntfy through ARC's proxy and the message
   came back off the topic intact (architecture.md §7). What is untested is the
   last hop — an actual phone subscribed to the topic — and the Slack, Discord
   and Feishu webhooks, which need real endpoints to point at.
4. **Published to GitHub, but not released.** `main` and `v8-parity` are pushed
   to `github-jackiectl2:jackiectl2/tailbell.git`, and CI is green on both
   `ubuntu-latest` and `macos-latest`. What does not exist yet is a *release*:
   no tag, no brew tap, no npm publish. The formula is deliberately HEAD-only
   until a tag exists, so nothing downstream is waiting on this.

   The macOS half of CI paid for itself on its first run, catching two bugs the
   cluster could never have shown: `install.sh` required `flock`, which does not
   exist on macOS, so it exited 1 on *every* Mac — a break sitting directly on
   release 4's goal — and a test asserted the Linux default channel on both
   platforms.

5. **The project lives on a second GitHub account, `jackiectl2`.** The original
   `jackiectl` is flagged: invisible to anonymous requests (profile, user API and
   numeric-id lookup all 404 while `torvalds` resolves from the same host) and
   its API quota is zero, so `gh` cannot act on it. Plain git still works there,
   which is why its other repositories keep pushing.

   Every published URL points at `jackiectl2`, the whole history was rewritten to
   that account's noreply address (GitHub attributes commits by email, and
   nothing had ever been pushed, so this was free), and `user.email` is set
   **repo-locally** so the account's other repositories keep their own identity.
   The pre-rewrite commits are still in `refs/original/`; to undo the whole
   thing, `git reset --hard refs/original/refs/heads/<branch>` per branch.

   Do **not** add a `Host github.com` block to `~/.ssh/config` here — Rocky 8's
   `Match final all` re-parses against the resolved `HostName`, so it leaks the
   old key into the alias and authenticates as the wrong account. Verify identity
   with `ssh -T github-jackiectl2`, never over HTTP.

   Left to the user, and deliberately not automated: the About description and
   ~20 topics on the repository page.

## Open — older, still true

- **Never exercised, still:** `StopFailure` · `Elicitation` · alert stack
  compression · click-to-focus for anything other than VS Code.
- **Permission prompts in the terminal CLI: verified 2026-08-20.** A CLI session
  on `gl-login4` was made to edit a tracked source file, `Notification` fired with
  `notification_type=permission_prompt`, the event reached `events.log`, and the
  Mac drew the 🔑 alert. That is release 2's one distinct capability — the chat
  panel has no event for this — confirmed end to end for the first time.

  **Two earlier attempts failed and both were the test's fault, not the code's.**
  `uptime` and `touch /tmp/…` are auto-approved by Claude Code without raising a
  permission event at all, so nothing fired and the run looked like a tailbell
  bug. Anyone re-testing this must pick an action Claude Code will genuinely
  stop on — editing a tracked file works.
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
