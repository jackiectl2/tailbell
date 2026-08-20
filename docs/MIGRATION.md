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

Verified end to end, Great Lakes -> macOS:

- turn finished (>60 s), question asked, cross-login-node delivery
- centered alert, persists until dismissed, click focuses the VS Code window that
  raised it, both displays get a copy, Option+Esc clears the stack
- fallback to a top-right banner when Hammerspoon is not handling
- release 8's per-kind sounds: all three play and are audibly distinguishable
- `mac/install.sh` and `tailbell-doctor --test` both run clean on a real Mac

`bash tests/run-tests.sh` — 24 cases when this file was first written; release 8
took it to 128. CI runs them on `ubuntu-latest` and `macos-latest` on every push.

Never exercised: `StopFailure` · `Elicitation` · alert stack compression ·
click-to-focus for anything other than VS Code · the spoken alert · a real phone
subscribed to an ntfy topic · Slack/Discord/Feishu against real endpoints.

## How to migrate, now that the repository is on GitHub

This section replaced an earlier one that described copying the directory. Do
**not** `scp` the folder: that loses the history, loses every branch, and drags
along untracked scratch files. The repository is the migration.

```bash
# on the Mac
git clone git@github.com:jackiectl2/tailbell.git ~/dev/tailbell
```

Two things that have to be true first:

1. **An SSH key on the Mac that GitHub knows.** A key belongs to exactly one
   account, but an *account* takes any number of keys — so generate a fresh one
   on the Mac (`ssh-keygen -t ed25519`) and paste it into
   github.com/settings/keys while signed in as `jackiectl2`. Do not copy the
   cluster's private key across. Verify with `ssh -T git@github.com` answering
   *"Hi jackiectl2!"*.
2. **Nothing under `~/.tailbell` moves.** Runtime state — `config`,
   `events.log`, `debug.log`, `state/`, `cluster-id` — is per machine and is
   created by the installer. The Mac already has its own from `mac/install.sh`.
   Copying the cluster's `cluster-id` over would make the listener think the two
   machines are the same cluster and drop one of them.

**No paths need editing.** This was checked, not assumed: every script resolves
its own location from `$0`, and all state hangs off `$TAILBELL_HOME`, which
defaults to `$HOME/.tailbell`. The only host-specific strings in the repository
are `mac/install.sh`'s suggested SSH-config pattern and
`TAILBELL_HOST_PATTERN`, and both are *configuration*, not code.

## What the move actually buys

Everything here was written by a session running **on the cluster**, which has no
macOS. Every macOS behaviour therefore went out untested, and three real bugs
shipped because of it:

1. A renderer gated on `pgrep Hammerspoon`, which proves the app runs but not that
   the handler is registered — a failed config load swallowed every notification
   with no fallback and no trace.
2. Canvases were created at `(0,0)` — the primary screen's origin — then moved to
   the target display. With "Displays have separate Spaces" that move silently
   fails, so alerts landed on a seemingly random screen.
3. `install.sh` required `flock`, which does not exist on macOS, so it exited 1 on
   **every** Mac. This one was caught by CI rather than by a user, which is the
   argument for the macOS runner and for this move in the same breath.

The Mac is also the only machine present in *every* scenario tailbell is supposed
to cover. `$HOME` is not shared between clusters — Great Lakes, Lighthouse and
Armis2 each have their own — so a repository living on Great Lakes is invisible
to the other two, and invisible to the local Claude Code desktop app, which never
touches a cluster at all. The workstation is the hub by elimination.

**What the move does not change:** Claude Code reads the filesystem of the machine
it runs on, so a session on a cluster still needs `bin/` **on that cluster**. The
Mac becomes the source of truth and the deployment origin, not the only location.
`mac/deploy.sh` exists for that.

## What is left

Done since this file was first written: the multi-cluster listener (one stream
per cluster, independent reconnect, `fake-ssh` tests), cluster labelling via
`~/.tailbell/cluster-id`, `mac/deploy.sh`, and the roadmap update.

Still open, and **both need the Mac** — which is the point:

1. **The bundle ids in `mac/tailbell.lua` are guesses.** `DESKTOP` lists
   `com.anthropic.claudefordesktop`, `com.anthropic.claude`,
   `com.anthropic.claudecode`, `com.anthropic.claude-code`; nobody has checked
   any of them against a running app. Run `tailbellApps()` in the Hammerspoon
   Console with the desktop app and the terminal open, read the real ids, and fix
   the lists. Then verify click-to-focus for all three frontends.
2. **Two rendering defects seen on 2026-08-19 and never diagnosed:** the message
   line appeared truncated (`… · gl-` cut off), and stacked alerts overlapped
   each other and the text behind them.

## Ground rules

- Never a bare `python3`; use `/usr/bin/python3`. The cluster's system Python is
  3.6.8, so nothing running there may use 3.7+ syntax. The Mac's is current —
  which makes it *easier* to write something the cluster cannot run. Watch for it.
- macOS is missing things the cluster has: `flock`, GNU `stat -c`, `timeout`,
  `readlink -f`. That asymmetry is why every one of those already has a fallback.
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

## Suggested first prompt on the Mac

> Read `docs/MIGRATION.md`, `docs/STATUS.md` and `docs/architecture.md` before
> writing anything — architecture.md rules out several obvious-looking changes
> with measurements, so do not re-propose them.
>
> This repository just arrived from a cluster, where it was written by sessions
> that had no macOS and therefore could not test half of it. You are the first
> session that can. Start there:
>
> 1. Run `bash tests/run-tests.sh` and `bin/tailbell-doctor --test` and tell me
>    what this machine reports that the cluster could not.
> 2. Fix the two rendering defects in *What is left* — the truncated message line
>    and the overlapping stacked alerts.
> 3. Resolve the bundle ids: run `tailbellApps()` in the Hammerspoon Console with
>    the Claude Code desktop app and my terminal open, and correct the `DESKTOP`
>    and `TERMINALS` lists in `mac/tailbell.lua`. Then verify click-to-focus for
>    the editor, the desktop app and the terminal.
> 4. Check `mac/deploy.sh` against my other clusters. My aliases are in
>    `~/.ssh/config`; ask me if one is missing. Verify first whether they share a
>    Turbo volume, because that decides whether the listener needs one stream or
>    three.
>
> Add a test for anything you fix, commit after each step, and do not push.
