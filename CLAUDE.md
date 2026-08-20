# CLAUDE.md — tailbell

Guidance for Claude Code (and any AI assistant) working in this repository.

## Project in one line

Desktop notifications when Claude Code finishes a turn or blocks waiting for you,
built for the case existing tools do not serve: the VS Code extension's chat panel
reached over Remote-SSH on a shared HPC cluster, with no third-party service.

## Read this before changing anything

**[docs/architecture.md](docs/architecture.md) is not background — it is the
justification for every design choice, and each claim in it is a measurement.**
Several obvious-looking "improvements" are already ruled out there with evidence:

- Do **not** switch the signal to the `Notification` hook. It fires **0 times** in
  the chat panel — measured over three weeks, not one session.
- `PermissionRequest` **does** fire in the chat panel, but only ever for
  `AskUserQuestion` (16/16 fires). It is not a source of tool permission prompts
  there, and `PreToolUse:AskUserQuestion` already covers what it does carry — so
  hooking it for notifications would only double them up.
- Do **not** replace the log transport with SSH `RemoteForward`. On a shared login
  node the loopback interface is shared across users, so a port collision sends
  your notifications to a stranger's machine.
- Do **not** read `last_assistant_message` from the `Stop` payload. It is the whole
  reply text; emitting it would leak the conversation.
- Do **not** hook `PermissionRequest` to *decide* anything. It fires, but a
  command hook's verdict is ignored there — measured, both directions, four
  output shapes. `PreToolUse` is the one whose decision is applied.
- Do **not** rotate `events.log` by rewriting it. The workstation follows it with
  `tail -F`, which tracks by name, so a replaced file is re-read from the start
  and every retained line is delivered again. Move the old file aside and leave a
  fresh empty one.
- Do **not** treat a missing start marker as `elapsed = 0`. That silently dropped
  notifications and is the bug `tests/run-tests.sh` guards against.
- Do **not** read `PermissionRequest`'s `tool_input` either. For `AskUserQuestion`
  it is the full text of every question — the same leak as above, by a second door.
- Do **not** build two-way remote control, and do **not** read
  `~/.claude/.credentials.json`. Both were evaluated and declined, in
  [docs/two-way-control.md](docs/two-way-control.md) and
  [docs/usage-quota.md](docs/usage-quota.md). Each page says what would change
  the answer; reopen it with that evidence, not with a fresh opinion.

## Layout

| path | what |
| --- | --- |
| `bin/tailbell` | the single entry point; both packages are wrappers over it |
| `bin/tailbell-notify` | runs as a hook on the agent host: decide, then emit |
| `bin/tailbell-approve` | `PermissionRequest` hook: ask a phone, answer for you |
| `bin/tailbell-listen` | runs on the workstation: tail the remote log over SSH |
| `bin/tailbell-show` | runs on the workstation: choose how to draw the alert, and which sound |
| `bin/tailbell-doctor` | check every link, including each channel; works on either side |
| `bin/tailbell-register` | merge hooks into `~/.claude/settings.json`; `--approve` adds the approval hook |
| `hooks/hooks.json` | plugin hook registration (`${CLAUDE_PLUGIN_ROOT}` paths) |
| `install.sh` | agent side, for use without the plugin system |
| `mac/install.sh` | workstation side |
| `Formula/` · `package.json` · `packaging/` | brew, npm, and the one-line installer |
| `tests/fake-curl` | records requests instead of making them, and doubles as a phone |
| `docs/roadmap.md` | the eight releases and where the branch boundaries sit |

Runtime state lives entirely outside the repo, in `~/.tailbell/`
(`config`, `events.log`, `debug.log`, `state/`). Nothing in `~/.tailbell` is ever
committed.

## Conventions

- **Code and comments in English**, chat with the user in 中英混杂. Comments explain
  *why*, never *what* — most of the non-obvious code exists to work around a
  specific upstream bug, so name the bug.
- **`flock` is optional, not required.** macOS has no `flock(1)`. Listing it as
  a hard dependency made `install.sh` exit 1 on every Mac. The file sink falls
  back to a plain append.
- **Never a bare `python3`.** It resolves to whatever virtualenv is active. Use
  `/usr/bin/python3`. Note the cluster's system Python is **3.6.8**, so no 3.7+
  syntax in anything that runs there; the Mac's is current.
- **A hook must never break the session**, so every path ends in `exit 0`. That
  makes silence the default failure mode, which is why *every* decision is written
  to `debug.log`. Keep it that way: an unlogged early return is a regression.
- **`bash -n` every shell file before committing.** Two real syntax errors got in
  this way, including a doubled here-document that parses as truncation.
- **Add a test for anything that broke.** `tests/run-tests.sh` runs against a
  throwaway `TAILBELL_HOME` and is the regression record, not just a test suite.
- **The suite must never need the network.** Anything that reaches outside goes
  through an injectable command — `TAILBELL_CURL`, `TAILBELL_OSASCRIPT`,
  `TAILBELL_AFPLAY`, `TAILBELL_SAY`, `TAILBELL_FOCUS_CMD` — and the test points
  it at a recorder. Add a channel, add its seam; do not add a live call.
- **A new delivery channel is a `sink_<name>` function plus a row in the doctor's
  table.** If you find yourself adding a branch to the event logic in
  `tailbell-notify`, the table is the thing to extend instead.
- **Optional means optional.** Every channel, sound, and the approval path are
  off with an empty config, and a test asserts that an unconfigured tailbell
  makes zero network calls. That test is the release 0 guarantee in executable
  form — do not weaken it to make something else easier.
- **Nothing but the decision JSON may reach `tailbell-approve`'s stdout.**
  Claude Code parses it; one stray `echo` turns a decision into plain text.
- Commit after each change; **do not push** unless the user asks.

## Branch convention

`main` holds the current stable. Each release in
[docs/roadmap.md](docs/roadmap.md) gets its own top-level branch
(`v0-ssh-vscode-chatbox`, `v1-rich-presentation`, …).

**A release branch is an integration branch, not a workbench.** Work in progress
gets its own topic branch off the release branch and comes back with
`git merge --no-ff`, so the merge commit records what the piece was and the
piece's own history stays readable. Name them after the work, not the release:
`v8-verify-guide`, not `v8-parity-2`.

Commit small and often. Each commit should be one reason, stated in the message —
"why", never "what", the same rule the comments follow. If a commit turns out to
carry two unrelated fixes, say both in the message rather than letting one hide.

**Release 0 owns the zero-dependency guarantee.** If a later release makes a
third-party component load-bearing on the v0 path, that is a regression.

## Verify

```bash
bash tests/run-tests.sh          # 128 cases, no side effects, no network
bin/tailbell-doctor --test       # end to end, every channel; run on BOTH sides
claude plugin validate .         # manifest and hook schema
bash -n <every shell file>       # two real syntax errors have shipped this way
```
