# Two-way remote control — evaluated, and declined

**Position: tailbell does not accept instructions from a notification channel, and
this is a design decision rather than an unbuilt feature.**

This page exists because the omission would otherwise look like a gap. The
[v8 brief](v8-brief.md) required the question be answered before anything was
built, not defaulted into either way.

## What was evaluated

[Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote)'s headline
feature: you reply to the email or the Telegram message the tool sent you, and
your reply becomes the next instruction in the live Claude Code session. It is the
most-starred tool in [the field we surveyed](competitors.md), and this is the
capability that earns it those stars.

Mechanically it needs three things tailbell does not currently do:

1. **Send enough context out** that the reply can be meaningful. "Claude is asking
   something" is not answerable; you have to be shown the question, which means
   the question text leaves the machine.
2. **Hold a channel open inbound** — polled or pushed — that carries instructions
   rather than acknowledgements.
3. **Inject into a live session**, in practice `tmux send-keys` into the pane
   Claude Code is running in, or a PTY the tool owns.

## Why the answer is no

### It inverts the guarantee release 0 was built for

Today the strongest sentence in the README is that nothing but SSH is in the path,
and that the reply text never leaves the machine — the `Stop` payload carries
`last_assistant_message` in full and tailbell has never read it. Two-way control
requires the opposite: the conversation must be forwarded to a third party for the
feature to have any use at all. There is no version of this that keeps the
guarantee; it is not a matter of implementing it carefully.

### The blast radius is the whole account, not the notification

A notification channel that leaks gives away project names and host names. That is
a real cost and it is why the ntfy path is opt-in and documented as such. An
*instruction* channel that leaks gives an attacker a shell on a university HPC
cluster, with the user's Kerberos identity, their `/scratch`, their Turbo mounts,
and their Slurm allocation. The two are not the same kind of risk and should not
share a threat model.

Concretely, an attacker holding the channel could: issue any instruction the user
could issue; ask Claude Code to read `~/.ssh`, `~/.claude/.credentials.json`, or
any dataset the account can reach; and do it while the user is asleep, since the
whole point of the feature is that the human is not at the keyboard.

### The channels available here cannot carry it

On free ntfy.sh a topic cannot be read-protected — measured, and recorded in
[architecture.md](architecture.md): `limits.basis` is `ip` for a free account
exactly as for an anonymous one, so an account buys neither a reserved topic nor a
private one. Email is worse: reply-address spoofing is trivial and the tools in
this space authenticate on the `From:` header. Telegram is the only one of the
three with real authentication, and it puts a chat service in the trust path for
running commands on a HIPAA-aligned cluster.

### It is the wrong shape for the machine this runs on

The clusters are shared. `Armis2` is HIPAA-aligned. `~/.tailbell/config` on a
login node is one `chmod` mistake away from being another user's read. A feature
whose failure mode is "somebody else runs commands as you" does not belong on a
box whose security model you do not control.

## What is offered instead

The narrow, useful half of the feature — **answer a yes/no from your phone** — is
in this release as workstream 2, and it is deliberately not the same thing:

- the decision space is `allow` / `deny`, not arbitrary text;
- it is tied to one request id, single-use, and expires;
- a timeout is never an approval, so silence can only ever be safe;
- and the push says which *tool* is being requested, never the command itself.

An attacker who captures that channel can approve or deny one pending prompt
inside a two-minute window. An attacker who captures a two-way control channel
owns the account. That difference is the entire reason one is built and the other
is not.

## What would change this

Stated so the decision can be revisited on evidence rather than mood:

- an end-to-end-encrypted channel where the agent host holds a key the service
  never sees, so the transport is not in the trust path;
- a Claude Code API for *queueing* an instruction into a session, so that
  injection does not mean synthesising keystrokes into somebody's terminal;
- and a per-instruction confirmation on the machine itself, so that the remote
  channel proposes and the local session still consents.

Until those exist, tailbell rings the bell. It does not answer the door.
