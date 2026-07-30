# Roadmap

Eight releases, each a top-level branch. Smaller test branches hang off whichever
release they belong to.

The effort is deliberately **not** evenly spread. Releases 0–3 are mostly the same
machinery with wider testing, because Claude Code hooks are registered per *process*
and do not care which editor or terminal started it. Releases 5–7 are where real
architecture appears, because every other agent has a different hook mechanism, and
Windows has a different notification stack. Planning them as equal-sized steps
would be wrong.

| # | branch | scope | est. |
| --- | --- | --- | --- |
| 0 | `v0-ssh-vscode-chatbox` | Claude Code over SSH in the VS Code chat panel → notification on macOS. Zero third-party software or service. | ✅ done |
| 1 | `v1-rich-presentation` | Centered, clickable overlay: close button, fade in/out, click to focus the originating editor window. Hammerspoon as an **optional** dependency; release 0's zero-dependency path stays the guarantee. | small |
| 2 | `v2-ssh-terminal-cli` | Claude Code CLI in an SSH terminal. Mostly already working — the addition is `Notification`, which fires in the CLI and covers permission prompts that the chat panel cannot report. | small |
| 3 | `v3-ssh-any-frontend` | Any editor, terminal or MCP frontend over SSH. Largely documentation and a test matrix rather than new code, for the same reason: hooks are process-level. | small |
| 4 | `v4-local-and-remote` | Same behaviour whether Claude Code runs on the cluster or on the Mac. The local path already exists; this release is about making one install cover both without branching config. | medium |
| 5 | `v5-claude-and-codex` | Codex as well as Claude Code. **First real architectural step:** an adapter layer, because each agent's event model differs. Needs a stable internal event schema first. | large |
| 6 | `v6-any-agent` | Arbitrary agents. Generalises release 5's adapter into a documented contract so a new agent is a plugin, not a patch. | large |
| 7 | `v7-any-os` | Windows as well as macOS: a third renderer (BurntToast or SnoreToast, both of which need an AppId registered first) and a listener that does not assume `launchd`. | large |

## Boundaries worth keeping

**Release 0 owns the guarantee, release 1 owns the polish.** Release 0 must keep
working with nothing installed beyond system tooling. If a later release makes a
third-party component load-bearing, that is a regression, not a feature.

**Release 5 is the point of no return for the event schema.** Up to release 4
everything can keep speaking Claude Code's payload shape. From release 5 onward the
schema must be the agent-neutral thing, with per-agent adapters translating into it.
Getting that boundary right before writing the Codex adapter costs far less than
retrofitting it after.

**"Any" is a claim that needs a test matrix, not a wish.** Releases 3, 6 and 7 use
the word "any". Each needs an explicit, written list of what was actually verified,
with everything else labelled unverified rather than implied to work.
