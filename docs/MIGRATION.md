# Migration brief — move tailbell's home from Great Lakes to the Mac

Written on Great Lakes for the session that will run on the Mac. It assumes no
memory of the conversation that produced this repo.

## What tailbell is

Desktop notifications when Claude Code finishes a turn or blocks waiting for you,
built for a case existing tools do not serve: Claude Code running over SSH on a
shared HPC cluster, reached from the VS Code extension's chat panel. The agent
side appends a JSON line to a log; the Mac tails that log over the SSH connection
the editor already holds. No third-party service, no account, no quota.

`README.md` is the user-facing description. **`docs/architecture.md` is the
important one** — it records the measurement behind every design decision and the
routes that were tried and rejected. Do not re-litigate those without reading it.

## Why the move, and why it is not cosmetic

Everything in this repo was written by a session running **on the cluster**, which
has no macOS. Every macOS behaviour therefore went out untested, and three real
bugs shipped because of it:

1. A renderer gated on `pgrep Hammerspoon`, which proves the app runs but not that
   the handler is registered — a failed config load swallowed every notification
   with no fallback and no trace.
2. Canvases were created at `(0,0)` — the primary screen's origin — then moved to
   the target display. With "Displays have separate Spaces" that move silently
   fails, so alerts landed on a seemingly random screen.
3. The click-to-focus list still hardcodes editor bundle ids. Whether it works for
   the Claude Code desktop app is **unknown**: the ids in `mac/tailbell.lua` under
   `DESKTOP` are guesses that were never checked against a running app.

Once this repo lives on the Mac and Claude Code runs there, the agent can query
`hs.application.runningApplications()`, run `osascript`, read bundle ids and
actually test the renderer. That is the point of the move: **it ends the blindness
that caused every bug so far.**

## State on arrival

Verified working, end to end, on Great Lakes → macOS:

- turn finished (>60 s), question asked, cross-login-node delivery
- centered alert, persists until dismissed, ✕ closes, click focuses the VS Code
  window that raised it
- both displays get an identical copy
- fallback to a top-right banner when Hammerspoon is not handling

Never exercised: ⌥Esc bulk clear · `StopFailure` · `Elicitation` · permission
prompts in the terminal CLI · stack compression when alerts fill the screen ·
click-to-focus for anything other than VS Code.

`bash tests/run-tests.sh` — 24 cases at the time of writing; release 8 took it to 128.

## Three problems the migration must solve

### 1. Hooks cannot live only on the Mac

Claude Code reads the filesystem of the machine it runs on. A session on Great
Lakes needs `tailbell-notify` **on Great Lakes**. The Mac becomes the source of
truth and the deployment origin, not the runtime location.

→ Needed: a deploy step that pushes `bin/` and registers hooks on each cluster,
and a way to tell which clusters are currently in sync.

### 2. `$HOME` is not shared between clusters

Measured on Great Lakes: `$HOME` is `arcts-gl-home`, specific to that cluster.
Lighthouse and Armis2 have their own. So "one listener covers everything" holds
**within** a cluster (Great Lakes' six login nodes do share a home) and **not
across** them.

→ `bin/tailbell-listen` currently calls `pick_host()` and tails **one** host. For
three clusters it must hold three concurrent streams, each reconnecting
independently. This is the single largest code change in the migration.

→ Worth checking first: Turbo (`/nfs/turbo/...`) is mounted on Great Lakes and may
be mounted on the others. If one Turbo volume is visible from all three, the event
log could live there and one stream would again cover everything. Armis2 is the
sensitive-data cluster and probably does **not** share a general Turbo volume —
verify, do not assume.

### 3. Armis2 is HIPAA-aligned

Only project directory names and host names ever leave a machine, and with the
`file` transport nothing leaves the SSH connection at all — but confirm this is
acceptable before deploying there. Do not enable the `ntfy` transport on Armis2.

## Tasks

1. Land this repo on the Mac, history intact, and make it the origin.
2. Multi-cluster listener: concurrent streams, per-cluster reconnect and backoff,
   one LaunchAgent. Add tests with a fake `ssh` on `PATH`.
3. Label events with their cluster, not just `hostname -s`.
4. `mac/deploy.sh <host>`: copy `bin/`, create `~/.tailbell`, merge hooks into
   `~/.claude/settings.json`, run `tailbell-doctor` remotely.
5. Resolve the unknown in `mac/tailbell.lua`: run `tailbellApps()` in the
   Hammerspoon Console, find the real bundle id of the Claude Code desktop app and
   of the terminal in use, and fix the `DESKTOP` / `TERMINALS` lists.
6. Verify click-to-focus for all three frontends: editor, desktop app, terminal.
7. Update `docs/roadmap.md` — this work spans releases 2, 3 and 4.

## Ground rules

- Never a bare `python3`; use `/usr/bin/python3`. The cluster's system Python is
  3.6.8, so nothing running there may use 3.7+ syntax.
- A hook must never break a session: every path ends in `exit 0`. That makes
  silence the default failure mode, which is why every decision is written to
  `debug.log`. An unlogged early return is a regression.
- `bash -n` every shell file before committing. Two syntax errors reached commits
  this way, including a doubled here-document that parses as truncation.
- Add a test for anything that breaks; `tests/run-tests.sh` is the regression
  record.
- Commit after each change. **Do not push without being asked.**
- Do not enable a third-party transport to make something easier. Release 0 owns
  the zero-dependency guarantee.

## Suggested first prompt

> Read `docs/MIGRATION.md` and `docs/architecture.md`, then carry out the
> migration described there. My clusters are Great Lakes (`gl6`), Lighthouse and
> Armis2 — check my `~/.ssh/config` for the exact host aliases and ask me if any
> is missing. Start by verifying which of the three share a Turbo volume, because
> that decides whether the listener needs one stream or three. Work through the
> task list in order, test on this Mac as you go, and commit after each step.
