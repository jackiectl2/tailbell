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

Not fixable in the VS Code chat panel. `Notification` fires **zero** times there.
`PermissionRequest` does fire — but measured over two weeks, every single one was
`AskUserQuestion`, never a tool permission prompt, because the extension handles
those itself. There is no event to hook. Both work in the terminal CLI, where
tailbell reports them as `🔑 需要你授权`.

## Two windows on different login nodes, and I cannot tell which rang

Every message ends with `· <node> (#<session>)`, e.g. `· gl-login4 (#b981)`. If the
node is missing, the agent side is running an older build.

## I need notifications with every editor closed

The default path has no third party, and therefore no way to reach you with no SSH
session up. Add a channel in `~/.tailbell/config` — it sits alongside the default
rather than replacing it:

```sh
TAILBELL_CHANNELS="file,ntfy"
TAILBELL_NTFY_TOPIC="<long random string>"
```

Two things to know before you do: the topic **is** the password and a free ntfy.sh
account cannot make it private, and the free quota is metered per source IP — which
on a shared login node means shared with everyone on that node.

`TAILBELL_TRANSPORT="ntfy"` from before release 8 still works and means the same
thing as `TAILBELL_CHANNELS="ntfy"`.

## A channel is configured but nothing arrives on it

`tailbell-doctor` checks each one and names the broken link; `--test` sends a real
message through every channel and quotes back what the server said.

| what the doctor says | meaning |
| --- | --- |
| `SKIPPED ntfy: no TAILBELL_NTFY_TOPIC` | the channel is listed but not configured |
| `连不上主机` | no route out. On a **compute node** that means `http_proxy`; ARC presets it, so check it survived into the job's environment |
| `FAILED slack: HTTP 403 — invalid_token` | the webhook was revoked or is for another workspace |
| `FAILED feishu: … sign match fail` | the bot is in signed mode; set `TAILBELL_FEISHU_SECRET` |
| `FAILED …: HTTP 000, curl exit 6` | DNS. Usually a proxy that is set but wrong |
| `不认识的通道名 'ntfy '` | a stray space or a typo in `TAILBELL_CHANNELS` |
| nothing at all in `debug.log` | the hook never ran — see the first section |

Delivery is verified from a Great Lakes **compute node** through ARC's proxy, so
`sbatch` jobs can reach a phone. Login nodes reach ntfy.sh directly.

## The phone never gets the Allow / Deny buttons

Check, in this order:

1. **Is it registered?** `tailbell register --approve`. Registering is separate
   from enabling on purpose.
2. **Is it on?** `TAILBELL_APPROVE=1` *and* `TAILBELL_APPROVE_TOPIC` in the config.
   Both are required.
3. **Is it the terminal CLI?** In the chat panel there is no permission event, so
   nothing will ever fire. This is the same limitation as the section above.
4. **Are the two topics different?** tailbell refuses to run when the approval
   topic equals the notification topic, and says so in `debug.log`. Anyone who can
   read a topic can answer the prompt, and your notification topic is the one that
   ends up in screenshots.
5. **Is the tool in the list?** An empty `TAILBELL_APPROVE_TOOLS` means every
   prompt; a non-empty one means only those, and `debug.log` names the tool it
   skipped.

`debug.log` records every request and every rejected reply, including *why* it was
rejected — wrong token, wrong request, or timestamped past the deadline.

## I tapped Allow and nothing happened

If more than `TAILBELL_APPROVE_TTL` seconds (90 by default) passed, the request had
already expired and Claude Code fell back to its own prompt. That is deliberate: a
decision that arrives late must be inert rather than applied to whatever prompt
happens to be open by then.

If it was well inside the window, look for `rejected a reply` in `debug.log`. The
usual cause is a clock skew between the phone and the cluster large enough that the
reply's own timestamp lands past the deadline.

## The alerts are too loud, or all sound the same

```sh
TAILBELL_SOUND=0                  # silence everything
TAILBELL_SOUND_DONE=Submarine     # or change just one
TAILBELL_VOICE=question,permission   # speak only when something waits on you
```

If every event sounds identical, the agent side is older than the workstation
side — `kind` is what selects the sound and an old build does not emit it. Redeploy
the agent side.

Sound and speech are held back while a Focus mode is on. If that detection is wrong
on your macOS version, replace it rather than disabling it:

```sh
TAILBELL_FOCUS_CMD="/path/to/a/command that exits 0 when Focus is on"
```

## Uninstall

Agent side — re-run `tailbell register` **without** `--approve` to remove the
permission hook, then drop the remaining tailbell entries from
`~/.claude/settings.json` (every install backs the file up first), or uninstall
the plugin. Then:

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
