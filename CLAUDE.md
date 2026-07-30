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
  the chat panel (measured, extension 2.1.220).
- Do **not** replace the log transport with SSH `RemoteForward`. On a shared login
  node the loopback interface is shared across users, so a port collision sends
  your notifications to a stranger's machine.
- Do **not** read `last_assistant_message` from the `Stop` payload. It is the whole
  reply text; emitting it would leak the conversation.
- Do **not** treat a missing start marker as `elapsed = 0`. That silently dropped
  notifications and is the bug `tests/run-tests.sh` guards against.

## Layout

| path | what |
| --- | --- |
| `bin/tailbell-notify` | runs as a hook on the agent host: decide, then emit |
| `bin/tailbell-listen` | runs on the workstation: tail the remote log over SSH |
| `bin/tailbell-show` | runs on the workstation: choose how to draw the alert |
| `bin/tailbell-doctor` | check every link; works on either side |
| `hooks/hooks.json` | plugin hook registration (`${CLAUDE_PLUGIN_ROOT}` paths) |
| `install.sh` | agent side, for use without the plugin system |
| `mac/install.sh` | workstation side |
| `docs/roadmap.md` | the eight releases and where the branch boundaries sit |

Runtime state lives entirely outside the repo, in `~/.tailbell/`
(`config`, `events.log`, `debug.log`, `state/`). Nothing in `~/.tailbell` is ever
committed.

## Conventions

- **Code and comments in English**, chat with the user in 中英混杂. Comments explain
  *why*, never *what* — most of the non-obvious code exists to work around a
  specific upstream bug, so name the bug.
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
- Commit after each change; **do not push** unless the user asks.

## Branch convention

`main` holds the current stable. Each release in
[docs/roadmap.md](docs/roadmap.md) gets its own top-level branch
(`v0-ssh-vscode-chatbox`, `v1-rich-presentation`, …); small experiments branch off
whichever release they belong to.

**Release 0 owns the zero-dependency guarantee.** If a later release makes a
third-party component load-bearing on the v0 path, that is a regression.

## Verify

```bash
bash tests/run-tests.sh          # 20 cases, no side effects
bin/tailbell-doctor --test       # end to end; run on BOTH sides
claude plugin validate .         # manifest and hook schema
```
