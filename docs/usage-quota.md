# Usage and quota warnings — why tailbell does not read your credentials

**Position: tailbell does not read `~/.claude/.credentials.json`, and does not
parse session transcripts to estimate quota.**

Two tools in [the field](competitors.md) — `claude-notifications-go` and
`code-notify` — warn you at 20% and 10% of your rate limit remaining, by reading
the local credentials file. The [v8 brief](v8-brief.md) required a decision with
reasoning attached before copying that, so here it is.

## Why not the credentials file

**A credential should be touched by as few programs as possible.** That file holds
an OAuth access token and refresh token for the user's Anthropic account.
`tailbell-notify` is a script that, when channels are configured, makes outbound
HTTPS requests to third-party servers. Putting "reads an OAuth refresh token" and
"POSTs to a webhook URL from a config file" inside the same process is one
mistake away from exfiltrating the credential — and the mistakes that do this are
ordinary ones, like widening a debug line or adding a field to a payload. The
separation is worth more than the feature.

**It is not reliably a file.** On macOS, Claude Code stores these in the Keychain,
not on disk. A feature that silently does nothing on half the platforms tailbell
supports is worse than an absent feature, because the absence of a warning reads
as "you have quota left".

**It is undocumented private state.** The path, the shape and the field names are
implementation detail of another program, on a fast release cadence. This repo's
rule is that every claim in `docs/` is a measurement; a quota reading built on an
unversioned private file cannot honour that.

## Why not transcripts either

Token counts are recoverable without any credential, by summing the `usage` fields
in `~/.claude/projects/*/*.jsonl` — that is how `ccusage` and similar tools do it.
It is rejected for a different reason: **those files are the conversation.** The
one invariant this project has kept since release 0 is that tailbell does not read
conversation content — not `Stop.last_assistant_message`, not
`PermissionRequest.tool_input`, both of which are guarded by canary tests. Opening
the transcript to read a number beside the text would leave nothing but discipline
between the text and the next webhook body. The invariant is worth more than the
percentage.

## What tailbell reports instead

What it can see honestly, which is less:

- a turn that **ended in an error** rather than finishing (`StopFailure`), which
  is what a rate limit actually looks like from a hook's position;
- how long the turn ran, which is the signal the notification already carries.

If Claude Code ever exposes remaining quota in a hook payload, this is a five-line
change and the reasoning above stops applying — the objection is to the *source*,
not the feature.

## If you want it anyway

`ccusage` and the `/usage` command inside Claude Code both answer this question
today and are built for it. Running one of those is a better answer than tailbell
growing a credential reader, and it costs you nothing that this repo can protect.
