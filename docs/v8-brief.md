# Release 8 — `v8-parity`

Build what comparable tools offer and tailbell does not. The field this is
measured against, with sources, is [competitors.md](competitors.md); the gap table
there is the input to this brief.

Not in this release: **Windows and Linux desktops** (release 7) and **other agents**
(releases 5–6). Both are their own branches, and both come after this one — see
the execution order in [roadmap.md](roadmap.md).

## The guardrail that outranks every item below

**Release 0 owns the zero-dependency guarantee.** Today a cluster session reaches
a Mac with nothing but SSH — no account, no quota, no third party. Every item in
this release adds an *optional* path alongside that one.

Concretely, the release fails if any of these becomes true:

- the v0 path stops working when the new channels are unconfigured;
- an install step requires Homebrew, npm, or a service account to get a working
  notification;
- `tests/run-tests.sh` needs network access;
- conversation content leaves the machine on any path the user did not explicitly
  turn on.

That last one is not a style preference. The `Stop` payload carries
`last_assistant_message` — the entire reply text. `tailbell-notify` has never read
it and must not start. See §1 of [architecture.md](architecture.md).

## Workstreams, in order

### 1. Make optional delivery channels first-class

Today `TAILBELL_TRANSPORT=ntfy` exists, is documented in one line, is not covered
by the doctor, and has never been exercised by a test. Every rival treats phone
push as a headline feature. Close that.

- One emit layer with more than one sink, so a new channel is a table entry rather
  than a branch in `tailbell-notify`.
- Channels worth having, cheapest first: **ntfy** (already half-built), then
  **Slack**, **Discord**, **Feishu** — all of them are a single POST with a
  different body shape.
- `tailbell-doctor` must check each configured channel end to end and say which
  link is broken, the same way it already does for the SSH path.
- The installer offers channels but never requires one.

Known traps, already paid for once:

- **Never `ntfy subscribe TOPIC COMMAND`.** It splices message text into a shell
  command — unfixed RCE, [ntfy #1721](https://github.com/binwiederhier/ntfy/issues/1721).
  The listener parses JSON and dispatches through `argv`.
- **A free ntfy.sh account buys nothing.** Measured: `limits.basis` is `ip` for a
  free account exactly as for an anonymous one — same 250/day, same zero reserved
  topics, still metered on the shared login-node IP. Only a paid tier moves it.
- The topic string *is* the password. Anyone who knows it reads your
  notifications. Say so at the point of configuration, not in a footnote.
- Compute nodes reach the outside through ARC's preset `http_proxy`; login nodes
  reach it directly. A channel that ignores the proxy works in testing and fails
  under `sbatch`.

**Done when:** a notification raised on a compute node reaches a phone with every
editor closed, the doctor diagnoses a deliberately broken channel correctly, and
removing all channel config leaves the v0 path byte-for-byte unchanged.

### 2. Answer from the phone

`claude-remote-approver` lets you tap Allow or Deny on a push. tailbell only ever
says "it is waiting".

- **Terminal CLI only.** In the VS Code chat panel there is no event to hook —
  `PermissionRequest` fires 0 times, measured. Do not spend effort trying; the
  root cause is upstream ([#80110](https://github.com/anthropics/claude-code/issues/80110)).
  Say plainly in the docs which frontends this covers.
- The return path is the hard part, and it is the same problem `RemoteForward`
  already lost to: on a shared login node the loopback interface is shared across
  users, so an inbound port is not yours alone. Whatever is chosen, write down why
  it is safe on a machine other people are logged into.
- A decision arriving late must be inert, not applied to whatever prompt happens
  to be open. Tie every approval to the specific request id and expire it.

**Done when:** a permission prompt from a CLI session on the cluster is approved
from a phone, an expired approval is provably ignored, and a stranger holding the
topic cannot approve anything.

### 3. Sound, and being noticeable

Four of the surveyed tools have custom sounds; two speak the message aloud.
tailbell is silent, which on a busy screen is the difference between seeing an
alert and not.

- `afplay` and `say` both ship with macOS, so this costs no dependency.
- Different sound per event kind — finished, question, permission — is the point;
  one sound for everything is barely better than none.
- Must be off-switchable, and must respect Do Not Disturb / Focus rather than
  routing around it.

**Done when:** the three event kinds are distinguishable with the screen turned
away, and a single config line silences all of it.

### 4. Installing, and knowing your quota

- **One-line install.** Today: clone plus two scripts. A `brew tap` and/or an npm
  package would match the field. The constraint stands — the packaged install must
  still produce a working notification with no third-party service configured, so
  packaging is a convenience wrapper over the existing scripts, not a rewrite.
- **Usage and rate-limit warnings.** Rivals read the local credentials file to
  warn at 20% and 10% remaining. Before copying that: decide whether tailbell
  should read `~/.claude/.credentials.json` at all, and write the reasoning down.
  If the answer is no, say so in the README — an explicit "we do not do this, here
  is why" is worth more than a silent omission.

**Done when:** a fresh machine reaches a working notification in one command, and
the usage question has a written answer either way.

## Out of scope, and one open question

**Out:** Windows and Linux rendering (release 7). Codex, Gemini CLI and any other
agent (releases 5–6). Do not let a "small" adapter creep in here — the whole point
of holding releases 5–6 until last is that the event schema should be written once,
after this release has finished changing what it must carry.

**Open — decide before building, do not default into it:** two-way remote control,
the headline feature of Claude-Code-Remote (reply to an email or a Telegram message
to issue a new instruction). It requires forwarding conversation context off the
machine and injecting commands into a live session via tmux or a PTY. That is in
direct tension with the guarantee at the top of this file. Write a page evaluating
it — what would have to leave the machine, what an attacker who holds the channel
could do — and then decide. "We deliberately do not do this" is an acceptable
outcome and should be documented as a position, not a gap.

## Verify

```bash
bash tests/run-tests.sh          # add a case for every channel and every failure mode
bin/tailbell-doctor --test       # must now cover the new channels too, on BOTH sides
claude plugin validate .
bash -n <every shell file>       # two real syntax errors have shipped this way
```

Nothing merges to `main` without a test for it. `tests/run-tests.sh` is the
regression record, not a formality — the missing-start-marker bug that silently
dropped notifications is in there for exactly this reason.
