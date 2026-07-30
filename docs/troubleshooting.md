# Troubleshooting

Start here, always:

```bash
~/.tailbell/bin/tailbell-doctor --test
```

Run it on **both** sides. The chain has two halves and the doctor only sees the one
it is running on; "all green here" plus "all green there" is what tells you the
problem is between them.

Then read `~/.tailbell/debug.log` on the agent side. Every invocation records what
it decided, so a missing notification has a written reason rather than needing a
reproduction.

## Nothing at all appears

**Check the log is being written.** On the agent host:

```bash
tail -5 ~/.tailbell/events.log
```

- **Lines are there** → the agent side is fine, the problem is on the workstation.
  Skip to the next section.
- **No lines** → look at `~/.tailbell/debug.log`:

| log line | meaning |
| --- | --- |
| `skipped: turn was 12s < 60s` | working as designed; lower `TAILBELL_MIN_SECONDS` if you want shorter turns to ring |
| `ABORT: jq not on PATH` | install `jq`; without it the hook can do nothing |
| `ABORT: payload has no session_id` | the hook is being called with something other than a hook payload |
| `FAILED writing …` | permissions or a full quota on `$HOME` |
| *(file does not exist)* | the hook was never called — the events are not registered; run `install.sh` or install the plugin |

## The log has lines but no notification appears

Almost always one of three things, in this order:

1. **No SSH master is alive.** The listener attaches to the connection your editor
   already holds; with nothing connected there is nothing to attach to.
   ```bash
   ssh -O check gl6        # want: "Master running"
   ssh gl6 true            # establishes one (2FA once, then 12h)
   ```
2. **macOS notification permission.** `osascript` notifications are delivered as
   **Script Editor**, and without permission macOS drops them *silently while still
   reporting success*.
   → System Settings › Notifications › Script Editor → allow.
3. **The listener died.**
   ```bash
   pgrep -f tailbell-listen
   cat /tmp/tailbell.err
   launchctl kickstart -k gui/$(id -u)/dev.tailbell.listen
   ```

## Notifications arrive late, or only after I reconnect

Expected. `tail -n0 -F` starts at end of file, so anything appended while the
listener was disconnected is skipped rather than replayed — a "task done" from an
hour ago is noise. On reconnect you get new events only.

The listener backs off up to 120 s between attempts while no SSH master exists, so
after reconnecting the editor there can be up to two minutes of lag before the
first event. To force it:

```bash
launchctl kickstart -k gui/$(id -u)/dev.tailbell.listen
```

## I get notified for turns I was watching

Raise the gate in `~/.tailbell/config`:

```sh
TAILBELL_MIN_SECONDS=180
```

Note that `AskUserQuestion` deliberately ignores this — being blocked is worth
knowing about immediately, however short the turn.

## I am never told about permission prompts

Not fixable in the VS Code chat panel: `Notification` and `PermissionRequest` both
fire **zero** times there. There is no event to hook. They work in the terminal CLI,
where tailbell reports them as `🔑 需要你授权`.

## Two windows on different login nodes, and I cannot tell which rang

Every message ends with `· <node> (#<session>)`, e.g. `· gl-login4 (#b981)`. If the
node is missing, the agent side is running an older build.

## I need notifications with every editor closed

The default transport has no third party, and therefore no way to reach you with no
SSH session up. Switch transports in `~/.tailbell/config`:

```sh
TAILBELL_TRANSPORT="ntfy"
TAILBELL_NTFY_TOPIC="<long random string>"
```

Two things to know before you do: the topic **is** the password and a free ntfy.sh
account cannot make it private, and the free quota is metered per source IP — which
on a shared login node means shared with everyone on that node.

## Uninstall

Agent side — drop the tailbell entries from `~/.claude/settings.json` (every
install backs the file up first), or uninstall the plugin. Then:

```bash
rm -rf ~/.tailbell
```

Workstation:

```bash
launchctl unload ~/Library/LaunchAgents/dev.tailbell.listen.plist
rm ~/Library/LaunchAgents/dev.tailbell.listen.plist
rm -rf ~/.tailbell
```

The `Host … ControlMaster` block appended to `~/.ssh/config` is harmless to leave —
connection reuse is a good default on a 2FA cluster regardless.
