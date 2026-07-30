# tailbell

Desktop notifications when Claude Code finishes a turn or blocks waiting for you —
**including when Claude Code runs over SSH on a shared HPC cluster**, with no
third-party service, no account and no quota.

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

## Why this exists

Every notifier for Claude Code that we could find hangs off the `Notification`
hook. **In the VS Code extension's chat panel that hook never fires.** Measured on
extension `2.1.220`, in one session:

| hook | fires in the chat panel |
| --- | --- |
| `PreToolUse` / `PostToolUse` | 787 / 787 ✅ |
| `SubagentStop` | 10 ✅ |
| `UserPromptSubmit` | 2 ✅ |
| `Stop` | 1 ✅ |
| **`Notification`** | **0** ❌ |
| **`PermissionRequest`** | **0** ❌ |

The two dead ones are exactly the ones that would tell you *"Claude is waiting for
you"*. Upstream: [#80530](https://github.com/anthropics/claude-code/issues/80530),
[#26925](https://github.com/anthropics/claude-code/issues/26925),
[#11156](https://github.com/anthropics/claude-code/issues/11156),
[#59718](https://github.com/anthropics/claude-code/issues/59718) — root cause in
[#80110](https://github.com/anthropics/claude-code/issues/80110): the extension
passes `--permission-prompt-tool stdio`, which bypasses the event. They work fine
in the terminal CLI.

tailbell builds the signal from hooks that *do* fire, and adds the parts a
cluster needs. See [docs/architecture.md](docs/architecture.md) for the
measurements behind each design decision, including the routes that were tried and
rejected.

## What you get

| event | notification |
| --- | --- |
| turn finished, and it ran longer than 60 s | `✅ bradley · 完成` — `跑了 5m7s · gl-login4 (#b981)` |
| Claude asks a multiple-choice question | `❓ bradley · 在等你回答` (high priority) |
| Claude needs a permission decision *(terminal CLI only)* | `🔑 bradley · 需要你授权` |

- **Short turns stay silent.** Under 60 s you were still watching the screen.
- **Every notification names the project, the node and the session** — with a dozen
  editor windows across six round-robin login nodes, nothing else is identifiable.
- **One listener covers the whole cluster.** `/home` is a single NFS mount shared by
  every login node *and* the compute nodes, so `sbatch` jobs can ring the same bell.
- **Your reply text never leaves the machine.** The `Stop` payload contains
  `last_assistant_message` in full; tailbell never reads it.

## Requirements

Only system tooling — no Homebrew package, no app, no service.

| side | needs |
| --- | --- |
| agent host | `bash`, `jq`, `flock`, coreutils |
| workstation (macOS) | `bash`, `ssh`, `launchd`, `osascript`, `/usr/bin/python3` — all built in |

## Install

**On the machine running Claude Code** (the cluster login node):

```bash
git clone https://github.com/jackiectl/tailbell.git ~/tailbell
bash ~/tailbell/install.sh
```

Or install it as a Claude Code plugin, which registers the same hooks from
`hooks/hooks.json` — then you can skip `install.sh`.

**On your Mac:**

```bash
scp -r <cluster>:~/tailbell /tmp/tailbell
bash /tmp/tailbell/mac/install.sh
ssh <cluster> true          # establishes the shared SSH master (2FA once)
```

## Verify

```bash
~/.tailbell/bin/tailbell-doctor --test     # on either side
```

It checks every link in the chain and says which one is broken, then emits a real
notification. Run it on **both** sides to localise a problem.

If the first notification never appears, it is almost always this:
**System Settings › Notifications › Script Editor → allow notifications.**
`osascript` notifications are delivered as Script Editor, and without permission
macOS drops them silently while still returning success.

## Known limits

- **Permission prompts are invisible in the VS Code chat panel.** Not a bug in
  tailbell — there is no event to hook. Covered in the terminal CLI.
- **No SSH connection up means silence, not an error.** That is the cost of having
  no third party in the loop. Set `TAILBELL_TRANSPORT=ntfy` if you need to be
  reachable with every editor closed.
- Tested against Claude Code `2.1.220` on macOS 15 + Rocky 8. Other combinations
  are unverified rather than known-broken.

## Configuration

`~/.tailbell/config`, sourced by every component:

| variable | default | meaning |
| --- | --- | --- |
| `TAILBELL_TRANSPORT` | `file` | `file` or `ntfy` |
| `TAILBELL_MIN_SECONDS` | `60` | turns shorter than this stay silent |
| `TAILBELL_HOSTS` | `gl6,greatlakes` | hosts the listener tries, in order |
| `TAILBELL_RENDERER` | `auto` | `auto`, `hammerspoon`, `alerter`, `osascript` |
| `TAILBELL_NTFY_TOPIC` | — | only read when transport is `ntfy` |

## Tests

```bash
bash tests/run-tests.sh
```

Runs against a throwaway `TAILBELL_HOME`. Every case corresponds to something that
actually broke during development, so the suite doubles as the regression record.

## Roadmap

Eight releases, from this one to "any agent, any OS, local or remote" —
[docs/roadmap.md](docs/roadmap.md).

## Prior art

Worth knowing about before you adopt this. [**AgentBell**](https://agentbell.dev/)
is a Mac menu-bar app covering several agents and IDEs;
[ashmitb95/claude-notifier](https://github.com/ashmitb95/claude-notifier) has
native Remote-SSH support and far more installs;
[dimokol/claude-notifications](https://github.com/dimokol/claude-notifications)
focuses the correct terminal tab on click. If you want top-right banners with less
maintenance, use one of those. tailbell exists for the case they do not serve: a
shared, headless HPC cluster reached over Remote-SSH, with nothing third-party in
the path.

## License

MIT — see [LICENSE](LICENSE).
