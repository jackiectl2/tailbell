# tailbell

Desktop notifications when Claude Code finishes a turn or blocks waiting for you —
**including when Claude Code runs over SSH on a shared HPC cluster**, with no
third-party service, no account and no quota. Optional phone channels do exist,
and each of them *is* a third party — but every one is off until you configure
it, and the sentence above describes what you get when you configure none.

```
┌──────────────── Great Lakes (headless, shared) ────────────────┐
│  Claude Code  ──hook──▶  tailbell-notify                        │
│                              │ appends one JSON line            │
│                              ▼                                  │
│                    ~/.tailbell/events.log   (shared NFS $HOME)   │
└──────────────────────────────┬──────────────────────────────────┘
                               │  tail -F, over the SSH connection
                               │  your editor already holds open
┌──────────────────────────────▼──────────────────────────────────┐
│  macOS      tailbell-listen  ──▶  tailbell-show  ──▶  notification│
└─────────────────────────────────────────────────────────────────┘
```

Nothing leaves the two machines. The only thing that crosses the network is the
SSH connection you already had.

Optional channels — a phone, Slack, Discord, Feishu — sit **alongside** that
path, never in front of it. Configure none of them and tailbell behaves exactly
as it does above.

## Why this exists

Every notifier for Claude Code that we could find hangs off the `Notification`
hook. **In the VS Code extension's chat panel that hook never fires.** Measured
on extension `2.1.220`, in one session, and again across the three weeks after:

| hook | fires in the chat panel |
| --- | --- |
| `PreToolUse` / `PostToolUse` | 787 / 787 ✅ |
| `SubagentStop` | 10 ✅ |
| `UserPromptSubmit` | 2 ✅ |
| `Stop` | 1 ✅ |
| **`Notification`** | **0** ❌ |
| `PermissionRequest` | 16 — but every one of them `AskUserQuestion`, never a tool permission prompt |

The events that would tell you *"Claude is waiting for you"* are the dead ones.
Upstream: [#80530](https://github.com/anthropics/claude-code/issues/80530),
[#26925](https://github.com/anthropics/claude-code/issues/26925),
[#11156](https://github.com/anthropics/claude-code/issues/11156),
[#59718](https://github.com/anthropics/claude-code/issues/59718) — root cause in
[#80110](https://github.com/anthropics/claude-code/issues/80110): the extension
passes `--permission-prompt-tool stdio`, which bypasses the event. They work fine
in the terminal CLI.

tailbell builds the signal from hooks that *do* fire, and adds the parts a
cluster needs. See [docs/architecture.md](docs/architecture.md) for the
measurements behind each design decision, including the routes that were tried
and rejected.

## What you get

| event | notification | sound |
| --- | --- | --- |
| turn finished, and it ran longer than 60 s | `✅ bradley · 完成` — `跑了 5m7s · gl-login4 (#b981)` | Glass |
| Claude asks a multiple-choice question | `❓ bradley · 在等你回答` (high priority) | Ping |
| Claude needs a permission decision *(terminal CLI only)* | `🔑 bradley · 需要你授权` | Sosumi |
| the turn died on an error | `⚠️ bradley · 中断` | Basso |

- **Short turns stay silent.** Under 60 s you were still watching the screen.
- **Every notification names the project, the node and the session** — with a dozen
  editor windows across six round-robin login nodes, nothing else is identifiable.
- **One listener covers the whole cluster.** `/home` is a single NFS mount shared by
  every login node *and* the compute nodes, so `sbatch` jobs can ring the same bell.
- **Each event kind sounds different**, so you can tell "it finished" from "it
  needs you" without looking. One config line silences all of it, and Do Not
  Disturb is respected rather than routed around.
- **Option + Esc dismisses every alert at once** (Hammerspoon renderer only);
  each alert's ✕ closes just that one.
- **Your reply text never leaves the machine.** The `Stop` payload contains
  `last_assistant_message` in full and `PermissionRequest` carries the whole text
  of any question; tailbell reads neither, and a test enforces it.

## Requirements

Only system tooling — no Homebrew package, no app, no service.

| side | needs |
| --- | --- |
| agent host | `bash`, `jq`, coreutils. `flock` if it exists — macOS has none, and it is only needed to serialise concurrent writes on a shared NFS home |
| workstation (macOS) | `bash`, `ssh`, `launchd`, `osascript`, `/usr/bin/python3` — all built in |

`curl` is needed only if you turn on an optional channel.

## Install

**On the machine running Claude Code** (the cluster login node):

```bash
git clone https://github.com/jackiectl2/tailbell.git ~/tailbell
bash ~/tailbell/install.sh
```

**On your Mac:**

```bash
scp -r <cluster>:~/tailbell /tmp/tailbell
bash /tmp/tailbell/mac/install.sh
ssh <cluster> true          # establishes the shared SSH master (2FA once)
```

Or, if you prefer one line — it clones the repo and runs the same installer, and
its header shows you the two commands so you can run them yourself instead:

```bash
curl -fsSL https://raw.githubusercontent.com/jackiectl2/tailbell/main/packaging/get-tailbell.sh | bash
```

Or as a Claude Code plugin, which registers the same hooks from
`hooks/hooks.json` — then you can skip `install.sh`. Or with Homebrew:

```bash
brew tap jackiectl2/tailbell https://github.com/jackiectl2/tailbell
brew install --HEAD tailbell
tailbell install
```

Homebrew and npm install the files and nothing else — neither registers a hook
or starts a daemon behind your back. `tailbell install` stays a visible step.

## Verify

```bash
tailbell doctor --test      # or ~/.tailbell/bin/tailbell-doctor --test
```

It checks every link in the chain — hooks, tools, the log, the SSH masters, and
each configured channel — then emits a real notification and reports what each
channel answered. Run it on **both** sides to localise a problem.

If the first notification never appears, it is almost always this:
**System Settings › Notifications › Script Editor → allow notifications.**
`osascript` notifications are delivered as Script Editor, and without permission
macOS drops them silently while still returning success.

## Optional: reaching your phone

The default path needs an SSH connection to be up. If you want to be reachable
with every editor closed, add a channel. They are additive — the SSH path keeps
working exactly as before, and a channel that fails never stops another.

```sh
# ~/.tailbell/config
TAILBELL_CHANNELS="file,ntfy"
TAILBELL_NTFY_TOPIC="a-long-random-string-you-generate"
```

Supported: `ntfy`, `slack`, `discord`, `feishu`. Each needs one setting, and
`tailbell doctor` checks each one end to end.

Three things to know before you turn one on:

- **A third party is now in the path.** They see project names, host names and
  event kinds. They never see your prompts, Claude's replies, file contents or
  command lines — nothing on those paths reads them.
- **The ntfy topic is the password.** Anyone who knows it reads every
  notification you send. Generate it, do not choose it:
  `head -c 18 /dev/urandom | base64 | tr -d '/+='`
- **A free ntfy.sh account buys nothing.** Measured: `limits.basis` is `ip` for a
  free account exactly as for an anonymous one — same 250/day, no reserved
  topics, still metered on your login node's shared address. Only a paid tier
  moves it.

Compute nodes reach the outside through ARC's preset `http_proxy`, which `curl`
honours on its own, so channels work from inside an `sbatch` job.

## Optional: approving from your phone

`tailbell-approve` can hold a permission prompt for up to 90 seconds, push
**Allow** and **Deny** buttons to your phone, and answer for you.

```bash
tailbell register --approve
```

```sh
# ~/.tailbell/config
TAILBELL_APPROVE=1
TAILBELL_APPROVE_TOPIC="a SECOND long random string, not the one above"
TAILBELL_APPROVE_TOKEN="an ntfy auth token"     # strongly recommended
TAILBELL_APPROVE_TOOLS="Bash,Write"             # REQUIRED — see below
```

**Terminal CLI only.** In the chat panel there is no permission event to hook —
that is the measurement in the table above, not a missing feature.

**`TAILBELL_APPROVE_TOOLS` is required, and it is not a filter — it is the
matcher.** The hook that can actually decide is `PreToolUse`, and that runs before
*every* matching tool call, not only the ones that would have prompted you. Name
the two or three tools you actually get asked about; leaving it empty would mean
a push to your phone hundreds of times a session, so `tailbell register --approve`
refuses to run without it. (`PermissionRequest` looks like the right hook and is
not: measured on 2.1.160, a command hook's decision there is ignored in both
directions. [architecture.md §7](docs/architecture.md) has the table.)

Read this before enabling it:

- **The approval topic must not be your notification topic.** Whoever can read
  the topic can answer the prompt, and the notification topic is the one that
  ends up in screenshots. tailbell refuses to run if you set them equal.
- **Anyone reading the approval topic while a request is live can answer it.**
  The buttons have to carry the token, and they travel in the push. On free
  ntfy.sh a topic cannot be read-protected, so that topic's secrecy is the whole
  boundary — point this at an authenticated or self-hosted server.
- **You are approving a tool name, not a command.** The push says `Bash`; it does
  not say which command, because sending that would put your command lines on
  someone else's server. That is a deliberate trade and it makes this weaker
  than answering at the terminal.
- **Silence is never approval.** A timeout, a wrong token, a late reply and a
  reply for another request all produce no decision at all, and Claude Code
  shows its normal prompt.
- **It holds the tool call while it waits.** That is what you want when you are
  away and not what you want when you are at the keyboard, which is why it is off
  by default. It returns immediately when the session is already in a mode that
  auto-approves.
- **The plugin cannot ship this.** `hooks/hooks.json` is static and cannot know
  your matcher, so approval always needs `tailbell register --approve`.

## Two things tailbell deliberately does not do

Both are common in comparable tools. Both were evaluated and declined, with the
reasoning written down rather than the verdict alone.

**Two-way remote control** — replying to a message to issue a new instruction.
It requires forwarding conversation context off the machine and injecting
commands into a live session. An attacker who captures a notification channel
learns your project names; an attacker who captures an instruction channel has a
shell on a shared HPC cluster with your identity. Full evaluation, and what would
change the answer: [docs/two-way-control.md](docs/two-way-control.md).

**Usage and quota warnings** — reading `~/.claude/.credentials.json` to warn at
20% and 10% remaining. tailbell does not open that file, and does not parse
session transcripts either. Reasoning:
[docs/usage-quota.md](docs/usage-quota.md). If you want this, `ccusage` and
Claude Code's own `/usage` already answer it well.

## Known limits

- **Permission prompts are invisible in the VS Code chat panel.** Not a bug in
  tailbell — there is no event to hook. Covered in the terminal CLI.
- **No SSH connection up means silence, not an error.** That is the cost of having
  no third party in the loop, and it is what the optional channels are for.
- **Voice and Focus detection are still untested on macOS.** The per-kind sounds
  are verified — all three play and are audibly distinct. The rest of this
  release was written on the cluster; see [docs/MIGRATION.md](docs/MIGRATION.md) for what
  that blindness has cost before.
- Tested against Claude Code `2.1.220` on macOS 15 + Rocky 8. Other combinations
  are unverified rather than known-broken.

## Configuration

`~/.tailbell/config`, sourced by every component. The installers write a copy
with all of this commented and explained.

| variable | default | meaning |
| --- | --- | --- |
| `TAILBELL_CHANNELS` | `file` (agent) · `desktop` (Mac) | comma-separated: `desktop`, `file`, `ntfy`, `slack`, `discord`, `feishu` |
| `TAILBELL_MIN_SECONDS` | `60` | turns shorter than this stay silent |
| `TAILBELL_NTFY_TOPIC` / `_SERVER` / `_TOKEN` | — | the ntfy channel |
| `TAILBELL_SLACK_WEBHOOK` | — | the Slack channel |
| `TAILBELL_DISCORD_WEBHOOK` | — | the Discord channel |
| `TAILBELL_FEISHU_WEBHOOK` / `_SECRET` | — | the Feishu channel; secret only for signed bots |
| `TAILBELL_HTTP_PROXY` / `_TIMEOUT` | — / `8` | only to override a preset proxy |
| `TAILBELL_APPROVE` / `_TOPIC` / `_TOKEN` / `_TTL` / `_TOOLS` | `0` / — / — / `90` / **required** | phone approval |
| `TAILBELL_MAX_AGE` | `300` | listener drops events older than this, so a replaced remote log cannot replay |
| `TAILBELL_SOUND` | `1` | `0` silences every sound |
| `TAILBELL_SOUND_DONE` / `_QUESTION` / `_PERMISSION` / `_ERROR` / `_IDLE` | `Glass` / `Ping` / `Sosumi` / `Basso` / `Tink` | per-kind sounds |
| `TAILBELL_VOICE` / `_NAME` | `0` / — | `1`, or a list of kinds, e.g. `question,permission` |
| `TAILBELL_RESPECT_FOCUS` | `1` | hold sound and speech back during Focus |
| `TAILBELL_RENDERER` | `auto` | `auto`, `hammerspoon`, `alerter`, `osascript` |
| `TAILBELL_HOST_PATTERN` | — | only tail SSH hosts matching this |

## Tests

```bash
bash tests/run-tests.sh
```

128 cases, no side effects, and **no network** — every channel is exercised
through a recorded fake `curl`, and the approval round trip through a fake phone
that presses the button on whatever was just pushed. Every case corresponds to
something that actually broke, so the suite doubles as the regression record.

## Roadmap

Eight releases, from this one to "any agent, any OS, local or remote" —
[docs/roadmap.md](docs/roadmap.md).

## Prior art

Worth knowing about before you adopt this. [**AgentBell**](https://agentbell.dev/)
is a Mac menu-bar app covering several agents and IDEs;
[ashmitb95/claude-notifier](https://github.com/ashmitb95/claude-notifier) has
native Remote-SSH support and far more installs;
[dimokol/claude-notifications](https://github.com/dimokol/claude-notifications)
focuses the correct terminal tab on click. A fuller survey, with what each one
has that this does not, is in [docs/competitors.md](docs/competitors.md).

If you want top-right banners with less maintenance, use one of those. tailbell
exists for the case they do not serve: a shared, headless HPC cluster reached
over Remote-SSH, with nothing third-party in the path.

## License

MIT — see [LICENSE](LICENSE).
