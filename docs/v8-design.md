# Release 8 design — how the parity features are built

The *what* and the guardrails are in [v8-brief.md](v8-brief.md); the field being
matched is in [competitors.md](competitors.md). This file is the *how*, written
before the code so the shape can be argued with rather than reverse-engineered.

Everything here is additive. With an empty config the v0 path — hook appends a
JSON line, the Mac tails it over SSH — executes exactly the same instructions it
did before, and no new process is spawned.

## 0. Two measurements taken before designing

**`PermissionRequest` does fire in the chat panel — but only for
`AskUserQuestion`.** 16 fires, all `ENTRYPOINT=claude-vscode`, 2026-07-30 to
2026-08-12, from the probe still registered at `~/.claude/hooks/probe.sh`.
Every one carries `tool_name: "AskUserQuestion"`; not one is a tool permission
prompt. `Notification` fired 0 times in the same window.
[architecture.md](architecture.md) §1 has been corrected. The conclusion it drew
survives — the panel still cannot report "Claude is waiting for permission" — but
the hook itself is alive there, so if the extension ever routes tool permissions
through it, tailbell inherits them without a change.

Two consequences for this release:

- Workstream 2 is still **terminal CLI only**, as the brief scoped it.
- `PermissionRequest`'s payload carries `tool_input`, which for `AskUserQuestion`
  is **the full text of the questions**. That is a second place conversation
  content is handed to a hook, alongside `Stop.last_assistant_message`. Both are
  now guarded by a canary test.

**`PermissionRequest` can decide.** The bundled hook reference in Claude Code
`2.1.160` lists it as *"Run before permission prompt"*, and the runtime carries
the strings `Permission denied by PermissionRequest hook`, `PermissionRequest
hook allowed … with updatedInput`, and a decision enum
`"allow" | "deny" | "ask" | "defer"`. So the approval path does not need a
`PreToolUse` matcher on `*` — which would mean ~787 process spawns per session —
and it fires only when a prompt is genuinely about to appear, i.e. after the
allowlist has already been consulted.

Not yet exercised live: headless `claude -p` auto-approves and never prompts, so
the hook cannot be made to fire without an interactive terminal CLI session. Until
that test is run, treat the decision path as **designed but unverified**.

## 1. Channels: one table, many sinks

### Shape

`emit` stops branching on a single `TAILBELL_TRANSPORT` and instead walks a list:

    TAILBELL_CHANNELS="file,ntfy,slack"

Each name resolves to a shell function `sink_<name>`, all with one signature:

    sink_<name> <kind> <title> <message> <tags> <priority>

Adding Teams or Matrix later is a function plus one row in the doctor's table,
not a new branch in the event logic.

`TAILBELL_CHANNELS` unset keeps every existing install byte-identical:

| platform | default | why |
| --- | --- | --- |
| Linux (agent host) | value of `TAILBELL_TRANSPORT`, itself defaulting to `file` | the v0 path, unchanged |
| macOS (local session) | `desktop` | today's behaviour: draw it here, there is nothing to transport |

So `TAILBELL_TRANSPORT=ntfy` in an existing config keeps working, and nobody has
to migrate.

### The sinks

| name | needs | body |
| --- | --- | --- |
| `desktop` | macOS | hands off to `tailbell-show` |
| `file` | nothing | one JSON line, `flock`-serialised, into `$TAILBELL_LOG` |
| `ntfy` | `TAILBELL_NTFY_TOPIC` | POST, title/tags/priority as headers |
| `slack` | `TAILBELL_SLACK_WEBHOOK` | `{"text": …}` |
| `discord` | `TAILBELL_DISCORD_WEBHOOK` | `{"content": …}` |
| `feishu` | `TAILBELL_FEISHU_WEBHOOK` | `{"msg_type":"text","content":{"text": …}}`, optionally signed |

Every body is built by `jq`, never by string interpolation, for the same reason
the `file` sink already does: a project name containing a quote must not be able
to produce malformed JSON — or, on a webhook, a malformed request.

### Decisions inside the sinks

- **`curl` is invoked through `$TAILBELL_CURL`.** That is the seam the test suite
  substitutes a recorder for, which is how every channel gets covered without the
  suite ever touching the network — a guardrail from the brief.
- **Network sinks run in the background** unless `TAILBELL_SYNC=1`. Three channels
  × an 8 s timeout is 24 s of stalled `Stop` hook otherwise. Children get their
  stdin/stdout/stderr closed first, so the hook's own exit is never held open by a
  pipe Claude Code is still reading. The doctor and the tests set `TAILBELL_SYNC=1`.
- **The proxy is honoured, not fought.** `curl` reads `http_proxy` on its own,
  which is what makes a compute node work under `sbatch`; `TAILBELL_HTTP_PROXY`
  overrides it for the case where the preset one is wrong.
- **A failing channel never stops another.** Each sink's outcome — sent, failed
  with status N, skipped because unconfigured — is its own `debug.log` line.
- **Secrets are never printed.** A webhook URL *is* the credential, so the doctor
  redacts everything after the host and the first path segment.

### Feishu signing

Feishu bots can be set to "signed request", which needs
`base64(HMAC-SHA256(key = "<timestamp>\n<secret>", message = ""))`. That needs
`openssl`. If `TAILBELL_FEISHU_SECRET` is set and `openssl` is missing, the sink
aborts with a logged reason rather than sending an unsigned request that the
server will reject anyway.

## 2. Approval from the phone

### What it is

A `PermissionRequest` hook on the agent host that pushes an *Allow / Deny* pair of
ntfy action buttons, waits up to `TAILBELL_APPROVE_TTL` seconds for the answer,
and prints a decision back to Claude Code. Off unless
`TAILBELL_APPROVE=1` **and** a reply topic is configured.

### Why there is no inbound port

The same reason `RemoteForward` lost, recorded in architecture.md §3: on a shared
login node the loopback interface belongs to everybody. So the return path is
**outbound polling** — the hook long-polls
`GET $NTFY_SERVER/$REPLY_TOPIC/json?poll=1&since=<t>`, which is one more HTTPS
request out of the machine and nothing listening on it.

### Threat model, stated plainly

The reply topic name is a bearer credential: anyone who can publish to it can
answer. Four things narrow that down, and one thing does not.

1. **The reply topic is not the notify topic.** Your day-to-day "turn finished"
   pushes travel on `TAILBELL_NTFY_TOPIC`; approvals travel on
   `TAILBELL_APPROVE_TOPIC`. Someone who learns the notify topic — from a
   screenshot, from a config, from this repo's docs — gets your project names and
   **cannot approve anything**.
2. **Every request carries a fresh 128-bit token.** A reply is accepted only if it
   quotes the token for the request currently in flight.
3. **Tokens expire and are single-use.** Past `TAILBELL_APPROVE_TTL` the token is
   dead; a reply naming a request that already resolved is dropped and logged.
   This is the "a decision arriving late must be inert" requirement.
4. **Silence is never approval.** A timeout prints nothing at all, so Claude Code
   shows its normal prompt. There is no path where a missing answer becomes yes.

What that does **not** buy: the action buttons must contain the reply topic and
the token, and they travel in the push. An attacker subscribed to your *approval*
topic at the moment a request is live can answer it before you do. On free
ntfy.sh, where topics cannot be read-protected, the confidentiality of that topic
is the whole boundary — which is why the feature is opt-in, defaults off, and the
README says to point it at an authenticated or self-hosted ntfy.

### What is deliberately not sent

The push says which **tool** is being requested (`Bash`, `Write`) and the project
and host. It does **not** send `tool_input` — that is the command line, the file
contents, the question text. Approving without seeing the command is a weaker
guarantee than the terminal gives you, and it is the deliberate trade: this
release does not put the contents of your work on a third-party server. The
README says so at the point of configuration.

### Where it must not fire twice

`PermissionRequest` fires for `AskUserQuestion` in the chat panel, and
`PreToolUse:AskUserQuestion` already notifies for exactly that. The approval hook
therefore ignores `tool_name = AskUserQuestion` entirely.

## 3. Sound and voice

Rendering is the workstation's job, so this lives in `tailbell-show`, keyed on the
new `kind` field:

| kind | sound | raised by |
| --- | --- | --- |
| `done` | `Glass` | `Stop` |
| `question` | `Ping` | `AskUserQuestion`, `Elicitation` |
| `permission` | `Sosumi` | `Notification:permission_prompt`, approval requests |
| `error` | `Basso` | `StopFailure` |
| `idle` | `Tink` | `Notification:idle_prompt` |

All five ship in `/System/Library/Sounds`, so this adds no dependency. Each is
overridable (`TAILBELL_SOUND_DONE=Submarine`), and `TAILBELL_SOUND=0` silences
every one of them.

`TAILBELL_VOICE` is **off by default** — a machine that talks in a shared office
is a different product. When on it speaks only "project, kind" through `say`;
message text is never spoken, for the same reason it is never POSTed.

**Focus/DND:** `osascript` notifications already respect Focus, but `afplay` and
`say` do not — they would be the one thing that routes around a mode the user
switched on deliberately. `TAILBELL_RESPECT_FOCUS=1` (default) checks
`~/Library/DoNotDisturb/DB/Assertions.json` for an active assertion and, on older
systems, `com.apple.notificationcenterui doNotDisturb`. **Untested — written on
the cluster, no macOS in reach.**

## 4. Packaging, and the quota question

### One entry point

`bin/tailbell` is a dispatcher: `tailbell install | doctor | listen | channels |
approve | register`. Both packages become thin wrappers over it rather than
re-implementations, which is what keeps the packaged install honest: it runs the
same scripts, and still produces a working notification with no third-party
service configured.

- **Homebrew:** `Formula/tailbell.rb`, installing `bin/` and printing the same
  next steps. Ships with `head` support so `brew install --HEAD` works from the
  repo; a versioned bottle needs a tag and a checksum, which `packaging/release.sh`
  computes at release time rather than being guessed here.
- **npm:** `package.json` exposing the dispatcher as `bin`, so `npx tailbell
  install` works. No postinstall script — a package that edits
  `~/.claude/settings.json` on install is exactly the kind of surprise this
  project exists to avoid.

Both are conveniences. `git clone && bash install.sh` stays the supported path and
the one the tests exercise.

### Usage and quota warnings: we do not read your credentials

Rivals warn at 20% and 10% remaining by reading `~/.claude/.credentials.json`.
tailbell will not. The reasoning is in [usage-quota.md](usage-quota.md); the
short version is that a file holding an OAuth refresh token has no business being
opened by the same script that POSTs to third-party webhooks, and that the data
is not reliably there anyway. This is written into the README as a position, not
left as a silent gap.

## 5. Schema change

Every emitted record gains `kind`, and approval requests add `req`. `kind` is what
sound selection, and eventually per-channel routing, key on. The listener passes
it through to `tailbell-show` as a seventh argument; an older `tailbell-show`
ignores it, so a half-updated pair degrades to today's behaviour rather than
breaking.

This is the schema churn [roadmap.md](roadmap.md) predicted, and the reason
releases 5–6 wait: `kind` is exactly the kind of field an agent-neutral schema has
to carry, and it would have been written twice.

## 6. Test plan

`tests/run-tests.sh` keeps its rule — every case is something that broke or could
break — and must still run with the network unplugged. New coverage:

- **per channel:** the URL, the method and the body shape each sink produces,
  asserted against a recorded fake `curl`
- **fan-out:** one event reaching three channels; one channel failing while the
  others still send; an unknown channel name logged and skipped
- **unconfigured:** a named channel with no webhook set makes no request at all
- **v0 regression:** with no channel config, `curl` is never invoked and the log
  line is what it always was
- **privacy:** the canary test extended to every channel, plus a second canary for
  `PermissionRequest.tool_input`
- **approval:** a good token decides; an expired one does not; a token for another
  request does not; a replayed one does not; a timeout prints nothing
- **sound:** the right sound per kind, `TAILBELL_SOUND=0` silences, voice off by
  default — through a fake `afplay`/`say`
- **async:** the hook returns before a slow sink finishes, and `TAILBELL_SYNC=1`
  makes it wait

## 7. Order of work

Each lands as its own commit, tests included, `bash -n` first.

1. channel table + `desktop`/`file`/`ntfy` sinks — behaviour-preserving refactor
2. `slack`, `discord`, `feishu`
3. doctor: per-channel diagnosis, redaction, `--test` through every channel
4. `kind` through the schema, the listener and `tailbell-show`
5. sound and voice
6. approval (`tailbell-approve`, `PermissionRequest` wiring, `--approve` registration)
7. `bin/tailbell` dispatcher, brew formula, npm package, one-line installer
8. docs: README, architecture correction, the two decision pages, STATUS

## 8. What changed while building it

Kept here rather than edited into the sections above, so the design as argued and
the design as built can be compared.

**Added, not designed:**

- **CI, with `macos-latest` in the matrix.** Not in the plan, and the most useful
  thing in the release. A runner cannot see a banner or hear a sound, but it runs
  these scripts under the same `/bin/bash` 3.2 and the same BSD userland — which
  is where the bugs below actually lived.
- **`tests/fake-ssh`.** The listener had no coverage at all because everything it
  does goes through `ssh`. Writing that stand-in immediately turned up a bug.

**Four bugs found by writing the tests, none of which release 8 introduced:**

- `install.sh` registered five events where `tailbell-register` registers seven,
  and never wrote `~/.tailbell/cluster-id` — so the install the README documents
  produced silence with every other check green.
- `tailbell-listen` passed `text=True`, which is Python 3.7+, and `watch()`
  swallowed the TypeError. The host was simply never streamed.
- `stat -c` is GNU only, so neither log ever rotated on a Mac.
- `flock` does not exist on macOS, so the `file` sink could not work there at all.

The pattern in the last three is the same one `docs/MIGRATION.md` is about, and it
is why the CI job exists now rather than in release 7.

**Changed from the design:**

- The Focus check tries `data.0.storeAssertionRecords` *and* the bare key, and
  treats an empty list as "no Focus", rather than betting on one shape of a plist
  nobody here can open.
- `tailbell-register` sources the config, because the hook timeout it writes has
  to follow `TAILBELL_APPROVE_TTL`; without that, raising the TTL produced a hook
  Claude Code kills before it can answer.
- `get-tailbell.sh` clones and then checks out, rather than `clone --branch`,
  which accepts only a branch or a tag — not a commit.

**Not built, deliberately:** a generic `webhook` sink. It would be ten lines and
would cover Teams, but Teams' Power Automate endpoint wants an Adaptive Card, not
a text field, so "generic" would have been a fifth shape rather than one fewer.
Each channel also costs a doctor row and test cases. Adding it is a table entry
whenever somebody actually wants it.
