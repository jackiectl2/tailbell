# The field — what comparable tools do, and what they do not

Surveyed 2026-08-19. Star counts and feature claims come from each project's own
GitHub repository and README; nothing here was measured by running them, so treat
a claim as "they say so", not as verified. Re-check before quoting any of it.

The gap table below was the input to release 8 and has been updated to record
what that release closed. The claims in the ✅ rows *are* verified — each one has
cases in `tests/run-tests.sh` — except where marked untested on macOS.

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

## What they have, and where tailbell now stands

Ordered by how often it appears in the field, which is roughly how much a new user
expects it. Release 8 was scoped from this list; see [v8-brief.md](v8-brief.md).

| gap | who has it | tailbell after release 8 |
| --- | --- | --- |
| phone push that works with every editor closed | CC-Remote, notif-go, approver, tap-to-tmux | ✅ `ntfy` channel, covered by the doctor and by tests |
| approve / deny a permission prompt from the phone | approver, CC-Remote | ✅ terminal CLI only — there is no event to hook in the chat panel |
| Slack / Discord / Feishu / Teams webhooks | notif-go, code-notify, CC-Remote | ✅ Slack, Discord, Feishu. Teams is one more row in the sink table |
| custom sounds, voice announcement | notif-go, code-notify, wyattjoh, CC-Remote | ✅ per event kind, voice off by default, Focus respected |
| one-line install (brew / npm / curl) | notif-go, code-notify, wyattjoh | ✅ all three, each a wrapper over `install.sh` |
| usage and quota warnings, rate-limit alerts | notif-go, code-notify | ❌ **declined** — [usage-quota.md](usage-quota.md) |
| two-way control (reply to issue a new instruction) | CC-Remote | ❌ **declined** — [two-way-control.md](two-way-control.md) |
| Windows / Linux desktop | notif-go, code-notify, wyattjoh | macOS only — release 7 |
| other agents (Codex, Gemini CLI) | code-notify, tap-to-tmux | Claude Code only — releases 5–6 |

The two ❌ rows are positions, not backlog. Each has a page saying what was
weighed and what would change the answer; an unexplained omission was the thing
worth avoiding, not the omission itself.

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
- A doctor that checks every link in the chain — now including each configured
  channel, end to end — and a 126-case regression suite that needs no network:
  channels run through a recorded fake `curl`, and the approval round trip
  through a fake phone that presses the button on whatever was just pushed.
- Optional channels that are genuinely optional. Configure none and the
  zero-dependency path is byte-for-byte what it was, which a test asserts.
