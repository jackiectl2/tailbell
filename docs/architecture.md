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
| `PermissionRequest` | **0** | ❌ in this window — see the correction below |

All invocations carried `ENTRYPOINT=claude-vscode`, confirming these are the
panel's own process and not a stray terminal session.

**Correction, measured 2026-08-19 over the window 2026-07-30 to 2026-08-12.** The
probe stayed registered on `Notification` and `PermissionRequest` after the table
above was written, and `~/.claude/hooks/hook-probe.log` now records:

| event | fires | note |
| --- | --- | --- |
| `Notification` | **0** | ❌ still, over two more weeks |
| `PermissionRequest` | **16** | ⚠️ fires — but every single one is `tool_name: "AskUserQuestion"` |

So `PermissionRequest` is *not* dead in the panel; it is alive and carries exactly
one kind of event. Not one of the 16 was a tool permission prompt, which is what
#80110 predicts: the extension handles those itself and never reaches the hook.
The conclusion below is unchanged — the panel still cannot tell you *"Claude is
waiting for permission"* — but the hook is registered and live there, so if the
extension ever stops bypassing it, tailbell inherits the event without a change.

⚠️ **Privacy.** `PermissionRequest` carries `tool_input`, which for
`AskUserQuestion` is the full text of every question and option. That is a second
place a hook is handed conversation content, alongside `Stop.last_assistant_message`.
tailbell reads neither; both are guarded by canary tests in `tests/run-tests.sh`.

Also in that payload and undocumented: `prompt_id`, `permission_mode`, and
`effort.level`.

**`PermissionRequest` can return a decision.** The hook reference bundled in
Claude Code `2.1.160` describes it as *"Run before permission prompt"*, and the
runtime contains `Permission denied by PermissionRequest hook`, `PermissionRequest
hook allowed … with updatedInput`, and the decision enum
`"allow" | "deny" | "ask" | "defer"`. That is what release 8's phone-approval path
hooks, rather than a `PreToolUse` matcher on `*` — which would cost ~787 process
spawns per session and would fire for calls the allowlist had already approved.
**Not exercised live:** headless `claude -p` auto-approves and never prompts, so
the hook cannot be provoked without an interactive terminal CLI session.

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

## 7. Release 8: channels, and answering from a phone

### Why the ntfy sink uses the JSON publishing API, and what was actually measured

The first version put the title in an HTTP `Title:` header. Titles here are CJK
(`✅ bradley · 完成`), and header values are US-ASCII/ISO-8859-1 by spec, so this
looked like a latent bug.

**Measured 2026-08-19, and it is not one.** Publishing `Title: 完成 ✅` as a raw
header to `ntfy.sh` and reading the message back gives `title=<完成 ✅>` —
byte-identical to the same title sent through the JSON API. curl transmits the
raw UTF-8 and ntfy decodes it as UTF-8. So the header form works against
ntfy.sh today.

The JSON API is used anyway, for two reasons that survive the measurement:

1. It does not depend on that leniency. The bytes pass through whatever proxy
   ARC presets on compute nodes and, for a self-hosted server, whatever reverse
   proxy sits in front of it; header sanitisation is a normal thing for those to
   do and a truncated title is a silent failure.
2. Action buttons — which the approval path needs — have no header form at all.
   One request shape for both is one thing to get right.

Recording the negative result rather than the assumption, because "we changed it
because it was broken" would have been a claim this file could not back up.

### Channels from a compute node: verified, not assumed

The trap the brief named is a channel that works in testing on a login node and
fails under `sbatch`, because compute nodes have no direct route out.

**Measured 2026-08-19.** A one-minute job on `gl3009` ran `tailbell-notify Stop`
with `TAILBELL_CHANNELS="file,ntfy"`:

- `http_proxy` is preset to `http://proxy1.arc-ts.umich.edu:3128/` inside the job,
  and `curl` picks it up with no configuration from us;
- `debug.log` recorded both sinks succeeding — the file line, then
  `EMITTED to ntfy (HTTP 200)`;
- polling the topic returned the message intact, priority and tags included.

So a `sbatch` job can ring a phone. One detail worth writing down because it cost
a rerun: **`/tmp` is node-local.** The first attempt put the config under `/tmp`
and the compute node found nothing there, silently fell back to defaults, and
sent through the file sink only. `$HOME` is the shared mount; `/tmp` is not. That
is the same fact §3 relies on, seen from the other side.

### Which hook can actually decide — measured, after getting it wrong

`PermissionRequest` is the obvious hook for phone approval: the bundled reference
calls it *"Run before permission prompt"*, and the runtime carries the strings
`Permission denied by PermissionRequest hook` and `PermissionRequest hook allowed
… with updatedInput`. tailbell was built on it. **It does not work.**

Measured 2026-08-19 on `2.1.160` by driving a real terminal CLI session inside a
pty — headless `claude -p` auto-approves and never prompts, so it cannot produce
the event at all, which is why this went untested for so long.

| hook | fires in the terminal CLI | is a *command* hook's decision applied |
| --- | --- | --- |
| `PermissionRequest` | ✅ with the real `tool_name` and `tool_input`, before the prompt | ❌ **no** — `allow` and `deny`, four output shapes, prompt shown every time |
| `PreToolUse` (with a matcher) | ✅ | ✅ **yes** — the write happened and no prompt was ever drawn |

The four shapes tried on `PermissionRequest`, all ignored:
`hookSpecificOutput` with `hookEventName` of `PermissionRequest` or `PreToolUse`;
top-level `decision: "approve"`; top-level `permissionDecision: "allow"`. Denies
were ignored too, so this is not a "hooks may tighten but not loosen" rule. The
bundled docs note that `type: "prompt"` and `type: "agent"` hooks are available on
`PermissionRequest`; a `type: "command"` hook's verdict appears not to be.

So the approval path is registered on **`PreToolUse`**, and the whole round trip
was then verified against a real session: request pushed, button pressed, decision
applied, file written, no prompt.

**The cost, stated because it is the reason for a required setting.** `PreToolUse`
runs before *every* matching tool call, not only the ones that would have
prompted. With no matcher that is hundreds of phone pushes a session. So
`TAILBELL_APPROVE_TOOLS` is required — `tailbell-register --approve` refuses
without it — and it doubles as the hook's matcher. The hook also returns
immediately when `permission_mode` is already auto-approving.

One consequence for the plugin: `hooks/hooks.json` cannot ship this, because a
static file cannot know your matcher and a matcher-less entry would fire on all
~787 tool calls. Approval requires `tailbell-register --approve`.

### Why answering from a phone needs nothing listening on the agent host

The obvious design is an inbound channel: hold a port, let the phone reach it.
That is the same design §3 already rejected for delivery, and it fails for the
same reason — **the loopback interface of a shared login node belongs to every
user of that node.** A port is not yours; a neighbour can hold it; and here the
consequence is worse than a leaked notification, because whatever answers on
that port decides whether a command runs.

So the return path is outbound only. `tailbell-approve` POSTs the request and
then polls for the answer. Two outbound HTTPS calls, no socket bound, nothing a
neighbour can take.

What that buys, and what it does not, is written out in
[v8-design.md](v8-design.md) §2 and summarised at the point of configuration.
The short version: the approval topic is deliberately not the notification
topic, so the topic that ends up in screenshots grants nothing; each request
carries a 128-bit token from `/dev/urandom`; a late reply is refused against the
timestamp the message itself carries; and no answer never becomes yes.

### Why `/dev/urandom` and not `$RANDOM`

`$RANDOM` is 15 bits from a seeded PRNG. It is the only thing standing between
someone on the topic and an approved command, so it is not a place to save a
subprocess.

### Why log rotation must not rewrite the log

Rotation was `tail -n 200 log > tmp && mv tmp log`. That is a notification storm,
and it took an accident to see it.

The workstation follows the file with `tail -F`, which tracks it **by name**.
Replacing the file makes tail reopen it and read **from the beginning** — so all
200 retained lines are delivered again as fresh alerts. The listener's duplicate
suppression is a 120-second window and does not touch events that old.

Observed live: rewriting `~/.tailbell/events.log` by hand replayed the entire
history to a connected listener, dozens of stacked alerts for turns that had
finished days earlier. Reproduced deterministically afterwards — with `tail -F`
watching, a `mv`-replacement re-delivered lines it had already emitted.

Two fixes, because one of them lives on the wrong machine to be trusted:

1. Rotation moves the old file aside and leaves a fresh **empty** one. tail still
   reopens by name and still reads from the start, and finds nothing. Truncating
   in place has the same replay problem for the same reason.
2. The listener refuses any record whose `ts` is more than `TAILBELL_MAX_AGE`
   (300 s) old, and says so on stderr. The sender is on another machine and may
   be an older version, so the receiver does not get to assume it was fixed.

### Why network sinks are backgrounded

Three channels at an 8 s timeout is 24 s of stalled `Stop` hook. Backgrounding
them has one trap worth naming: the child must have stdout closed first.
Claude Code reads the hook's pipe, and a child that inherits it keeps the pipe
open after the parent exits — so the hook appears to hang for exactly as long as
`curl` does, which is the thing backgrounding was supposed to fix.

### A test suite that installed itself into the tester's login session

Recorded because the failure was invisible where it was written and loud where
it was not, which is the shape of every macOS bug this project has had.

`packaging/get-tailbell.sh` branches on `uname`. On Darwin it runs
`mac/install.sh`, which writes `~/Library/LaunchAgents/dev.tailbell.listen.plist`
and `launchctl load`s it. The one-liner's test case ran that unguarded with
`HOME` pointed at a `mktemp -d` directory. Three properties then compounded:

1. **The label is hardcoded.** `dev.tailbell.listen` is the same string the real
   install uses, and a label is unique per session — so the throwaway
   registration *replaced* the real one rather than sitting beside it.
2. **`KeepAlive` is `true`**, so killing the process is not removal; launchd
   restarts it. Only `launchctl bootout` unloads it.
3. **Its dedup state lived in the temp directory**, which the suite deleted on
   exit. With nowhere to record what it had already shown, every reconnect
   re-delivered the same fixtures — the suite's 400-second fake turn, rendering
   as `跑了 6m40s`, over and over onto a real screen, for days after the test run
   that created it had finished.

On the cluster none of this is observable: `tailbell-show` is macOS code and the
desktop sink is unreachable, so every one of those paths is dead code and the
suite looked clean.

The fix in `tests/run-tests.sh` is the rule the repo already had rather than a
new one — `uname` is faked to Linux for that one call, and `osascript`, `afplay`
and `say` go through `tests/fake-desktop` for the whole run, the same seam
`TAILBELL_CURL` provides for the network. **The label collision itself is not
fixed**; the label needs a `TAILBELL_HOME` fingerprint, or `mac/install.sh`
should refuse to load when `HOME` is not the real one.

## 8. macOS rendering

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
