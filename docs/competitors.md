# The field — what comparable tools do, and what they do not

Surveyed 2026-08-19. Star counts and feature claims come from each project's own
GitHub repository and README; nothing here was measured by running them, so treat
a claim as "they say so", not as verified. Re-check before quoting any of it.

## The tools

| project | ★ | shape | delivery | platforms |
| --- | --- | --- | --- | --- |
| [Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote) | 1285 | remote control + notify | email · Telegram · LINE · local sound | local + phone |
| [claude-notifications-go](https://github.com/777genius/claude-notifications-go) | 790 | desktop, most complete | system notification + ~12 webhooks | mac · Win · Linux |
| [code-notify](https://github.com/mylee04/code-notify) | 287 | desktop, multi-agent | notification · sound · voice · Slack | mac · Win · Linux · WSL |
| [CCNotify](https://github.com/dazuiba/CCNotify) | 216 | desktop + duration | terminal-notifier | macOS |
| [claude-code-notification](https://github.com/wyattjoh/claude-code-notification) | 96 | lightweight + sounds | system notification | macOS mainly |
| [claude-remote-approver](https://github.com/yuuichieguchi/claude-remote-approver) | 72 | approve from phone | ntfy | phone |
| [tap-to-tmux](https://github.com/flavio87/tap-to-tmux) | 35 | any agent in tmux | ntfy | phone |
| [Claude Notifications (VS Code ext)](https://marketplace.visualstudio.com/items?itemName=dimokol.claude-notifications) | 2.3k installs | editor-side | OS banner + focus | mac · Win · Linux |

## The one claim to state carefully

`README.md` says every notifier we could find hangs off the `Notification` hook.
**That is too strong.** `claude-notifications-go` and the VS Code extension above
also use `Stop` and `PreToolUse` with an `AskUserQuestion` matcher — the same
workaround tailbell uses. So in the chat panel they *can* report "the turn
finished"; what none of them can report is "Claude is waiting for permission",
because no event for it exists there.

The accurate claim is narrower and still uncontested: **no surveyed tool delivers
from a headless remote host to a workstation without a third party in the path.**
The three that handle remote hosts at all (Claude-Code-Remote, claude-remote-approver,
tap-to-tmux) all require email, Telegram or ntfy.

## What they have that tailbell does not

Ordered by how often it appears in the field, which is roughly how much a new user
expects it. Release 8 is scoped from this list; see [v8-brief.md](v8-brief.md).

| gap | who has it | tailbell today |
| --- | --- | --- |
| phone push that works with every editor closed | CC-Remote, notif-go, approver, tap-to-tmux | `TAILBELL_TRANSPORT=ntfy` exists but is an untested fallback, not a supported path |
| approve / deny a permission prompt from the phone | approver, CC-Remote | nothing |
| Slack / Discord / Feishu / Teams webhooks | notif-go, code-notify, CC-Remote | nothing |
| custom sounds, voice announcement | notif-go, code-notify, wyattjoh, CC-Remote | nothing — silent notification only |
| one-line install (brew / npm / curl) | notif-go, code-notify, wyattjoh | clone plus two scripts |
| usage and quota warnings, rate-limit alerts | notif-go, code-notify | nothing |
| Windows / Linux desktop | notif-go, code-notify, wyattjoh | macOS only — release 7 |
| other agents (Codex, Gemini CLI) | code-notify, tap-to-tmux | Claude Code only — releases 5–6 |
| two-way control (reply to issue a new instruction) | CC-Remote | nothing, and possibly should stay that way |

## What tailbell has that none of them do

- Remote host → workstation with **no third party anywhere** in the path.
- One listener covers a whole cluster, **including Slurm compute nodes**, because
  `$HOME` is one shared NFS mount.
- Several clusters watched at once, each stream reconnecting on its own.
- **Hosts are discovered, not configured** — login nodes are not stable, so a
  hardcoded list is wrong the moment you land on a different node.
- Notifications name the **project, the node and the session**.
- **Short turns stay silent** (60 s gate, configurable). No surveyed tool has a
  duration threshold at all.
- A doctor that checks every link in the chain, and a 24-case regression suite.
