# Architecture — and the measurements behind it

Every decision here was forced by something measured, not chosen on taste. This
file records the measurement so a future change does not undo it by accident.

Environment the numbers come from: Claude Code extension `2.1.220`
(`CLAUDE_CODE_ENTRYPOINT=claude-vscode`) on `gl-login6.arc-ts.umich.edu`, reached
by VS Code Remote-SSH from macOS 15.5 on Apple Silicon. Measured 2026-07-25 to
2026-07-30.

## 1. Which hooks actually fire in the extension's chat panel

Method: register a probe on every event, log each invocation with its payload, use
Claude Code normally for a while, count.

| event | fires | note |
| --- | --- | --- |
| `PreToolUse` | 787 | ✅ |
| `PostToolUse` | 787 | ✅ |
| `SubagentStop` | 10 | ✅ |
| `UserPromptSubmit` | 2 | ✅ |
| `Stop` | 1 | ✅ fires on turn completion |
| `Notification` | **0** | ❌ |
| `PermissionRequest` | **0** | ❌ |

All invocations carried `ENTRYPOINT=claude-vscode`, confirming these are the
panel's own process and not a stray terminal session.

**Consequence.** The two events that mean *"Claude is waiting for you"* are
unavailable in the panel, so the signal has to be assembled from the others.
Upstream root cause is [#80110](https://github.com/anthropics/claude-code/issues/80110):
the extension passes `--permission-prompt-tool stdio` and handles permission UI
itself, bypassing the event. The same hooks work in the terminal CLI, which is why
`Notification` is still wired up — it is the only source for the permission case,
and it costs nothing when it never fires.

**Also measured:** `~/.claude/settings.json` is **hot-reloaded**. A hook added
mid-session fired on the next event, no restart.

**Payloads are richer than documented.** Every event carries `session_id`, `cwd`,
`transcript_path`, `permission_mode`, and `agent_id`/`agent_type` on subagent
calls. ⚠️ `Stop` also carries `last_assistant_message` — the entire reply text.
Anything that forwards a payload verbatim to an external service leaks the whole
conversation. tailbell never reads that field.

## 2. Why `AskUserQuestion` as a proxy for "blocked on a question"

Multiple-choice questions are asked through the `AskUserQuestion` **tool**, so
`PreToolUse` with `matcher: AskUserQuestion` catches them exactly and with no
delay. This is a known workaround, not an invention here — see
[#20169](https://github.com/anthropics/claude-code/issues/20169),
[#15872](https://github.com/anthropics/claude-code/issues/15872),
[#28273](https://github.com/anthropics/claude-code/issues/28273).

## 3. Why a log file plus `tail -F`, and not the alternatives

The agent host is headless and shared; it has no route to the user's screen. Four
routes were evaluated.

### Rejected: OSC escape sequences (`OSC 9` / `OSC 777`)

Doubly dead here. VS Code's integrated terminal does not translate OSC 9/777 into
desktop notifications, and the chat panel is a webview with **no PTY at all** — no
VT parser, so the bytes are simply discarded. No terminal setting can fix it.

### Rejected: the remote `code` CLI

`code --help` on the remote lists only file/diff/extension/status operations —
there is no notification verb. A lower-level path does exist (`$BROWSER` →
`--openExternal`), but of the 27 `vscode-ipc-*.sock` files on the node, all were
stale, and `code` **hangs rather than erroring** against a dead socket.

### Rejected: SSH `RemoteForward` to a local listener

Attractive, and genuinely unsafe on a shared login node:

1. `RemoteForward` accepts **no tokens** (checked OpenSSH 8.0 `TOKENS`), so a fixed
   port cannot be made per-window. Many editor windows collide.
2. The loopback interface is **shared across all users of the node** — roughly 30
   listeners were present, only ~12 ours. If another user holds your port, your
   notifications are POSTed to a stranger's laptop. That is an information leak,
   not merely a reliability problem.
3. Unix-domain sockets would dodge the collision, but `StreamLocalBindUnlink`
   defaults to `no` and is decided **server-side**; without root on the cluster a
   stale socket permanently breaks the forward.
4. `greatlakes.arc-ts.umich.edu` round-robins across **six** login nodes, so a
   tunnel only exists on whichever node you happened to land on.

### Rejected as the default: ntfy (kept as an option)

Works — the login node reaches `ntfy.sh` directly, and compute nodes reach it
through ARC's preset `http_proxy`. But it puts a third party in the path, and
measurement killed the obvious mitigation: `curl https://ntfy.sh/v1/account`
reports `"basis": "ip"` for a free account exactly as for an anonymous one — same
250 messages/day, same zero reserved topics. **A free account does not move the
quota off the shared login-node IP.** Only a paid tier does. At the time of
measuring, that IP had 249/250 remaining, so the shared quota is a theoretical
problem, not a live one.

Also: never use `ntfy subscribe TOPIC COMMAND`. It splices message text into a
shell command — an unfixed RCE
([ntfy #1721](https://github.com/binwiederhier/ntfy/issues/1721)). tailbell's
listener parses JSON and dispatches through `argv`, where a message can never
become a command.

### Chosen: append to a log on the shared NFS `$HOME`, tail it over the existing SSH connection

`/home` is one mount — `arcts-gl-home.turbo.storage.umich.edu` — shared by all six
login nodes and by the compute nodes. So:

- every session, wherever it runs, appends to the same file;
- **one** listener sees all of them;
- `sbatch` jobs on compute nodes can ring the same bell, which no outbound-network
  approach manages without proxy configuration.

The obvious objection is that `inotify(7)` does not see writes made by other hosts
on a network filesystem. **Tested, and it is not a problem:** a compute node
(`gl3046`, then `gl3033` running the real hook) appended while `tail -F` watched
from `gl-login6`, and the line arrived. GNU `tail` detects a remote filesystem and
polls instead of using inotify. Confirmed again in production — a listener attached
to `gl-login6` delivered an event raised on `gl-login4`.

The listener reuses whichever SSH master is already open (`ControlMaster`), so it
needs no login of its own and never triggers 2FA. The cost, stated plainly: **with
no master alive there is silence rather than an error.**

## 4. Why notifications name the host

`greatlakes` round-robins across six login nodes, so two editor windows can be on
different hosts with no visible difference. `hostname -s` goes into every message
for that reason alone.

## 5. Why an unknown duration must notify

The first version treated "no start marker" as `elapsed = 0`, which fell below the
60 s gate, so the notification was dropped **silently**. A missing marker is
common: the turn began before the hook was installed, or the session was resumed,
or `SessionEnd` cleared it. Unknown duration now notifies and says
`时长未知`. Regression-tested in `tests/run-tests.sh`.

## 6. Why every decision is logged

Hooks must never break a session, so every path ends in `exit 0` — which makes
silent failure the default and cost real debugging time. `~/.tailbell/debug.log`
records what each invocation decided and why, so *"why didn't it notify me"* has an
answer on disk rather than requiring a re-run.

## 7. macOS rendering

`osascript` is the guaranteed path: it ships with the OS. Its two traps are
documented rather than worked around — notifications are attributed to **Script
Editor** and are dropped silently without permission, and there is no way to
reposition a Notification Center banner.

Two opportunistic upgrades are used if already present, and neither is installed
or required by this version:

- **alerter** — maintained; `terminal-notifier` was rejected because it has been
  unmaintained since 2017 with open reports of failing on Sequoia.
- **Hammerspoon** — the only way to get a centered, clickable overlay, since macOS
  offers no API to move a banner, add a button to one, or run code on click. Driven
  through its `hammerspoon://` URL scheme, **not** the `hs` CLI: that tool cannot
  detect a running Hammerspoon on 1.1.1
  ([#3847](https://github.com/Hammerspoon/hammerspoon/issues/3847), open) and
  hardcodes `/usr/local`, the wrong prefix on Apple Silicon
  ([#3088](https://github.com/Hammerspoon/hammerspoon/issues/3088)).

Shipping and supporting the Hammerspoon renderer is release 1's job; see
[roadmap.md](roadmap.md).
