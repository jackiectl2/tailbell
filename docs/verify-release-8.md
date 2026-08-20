# Verifying release 8 — the parts a cluster session cannot check itself

Everything in this release is covered by `tests/run-tests.sh`, which runs offline.
What a test suite on a Linux login node **cannot** do is look at a screen, listen
to a sound, or hold a phone. This file is the checklist for those, written to be
worked through in one sitting.

Tick them off in `docs/STATUS.md` as you go. Nothing merges to `main` until §1–§3
are done.

---

## 1. The workstation — macOS

Run this **on the Mac, from a Mac-local terminal** — not the editor's integrated
terminal, which in a Remote-SSH window is on the cluster.

```bash
scp -r <cluster>:~/tailbell /tmp/tailbell
bash /tmp/tailbell/mac/install.sh
~/.tailbell/bin/tailbell-doctor --test
```

### What to look for

`--test` now does three things beyond what it used to:

1. **Draws a real notification.** If nothing appears, it is almost always
   System Settings › Notifications › **Script Editor** → allow. `osascript`
   notifications are delivered as Script Editor and macOS drops them silently
   while still reporting success.
2. **Plays the three event sounds in sequence**, naming each one first. **Turn
   away from the screen for this.** The claim being tested is that you can tell
   「完成」 from 「在等你回答」 from 「需要授权」 without looking. If two of them
   sound alike, change one:
   ```sh
   # ~/.tailbell/config
   TAILBELL_SOUND_QUESTION=Submarine
   ```
   `ls /System/Library/Sounds` lists what you have.
3. **Reports the channel table**, which on the Mac should be just `desktop`.

### Two rendering problems to look at while you are there

Both were seen on 2026-08-19 and neither has been diagnosed:

- The message line appeared **truncated** — `跑了 5m7s · gl-` with the node name
  cut off. Probably a width calculation in `mac/tailbell.lua`.
- Stacked alerts **overlapped each other** and the window behind them, rather
  than tiling. Related to the stack-compression path that has never been
  exercised.

Reproduce by raising several alerts quickly:

```bash
ssh <cluster> 'for i in 1 2 3 4 5; do
  printf "{\"session_id\":\"test%s-0000-0000-0000-000000000000\",\"cwd\":\"/x/proj-$i\"}" "$i" \
    | ~/.tailbell/bin/tailbell-notify AskUserQuestion; sleep 1; done'
```

**⌥Esc clears the stack.**

### Sound off, and Focus

```sh
TAILBELL_SOUND=0            # silences every sound in one line — check it does
TAILBELL_VOICE=question,permission
TAILBELL_VOICE_NAME=Tingting   # the prompts are Chinese; the default voice is not
```

Then turn on a Focus mode and raise an alert. **Nothing should be spoken and no
sound should play** — the banner is held back by macOS, and tailbell holds back
`afplay`/`say` itself. If speech still happens, the Focus detection is reading the
wrong file on your macOS version; do not disable the feature, replace the check:

```sh
TAILBELL_FOCUS_CMD="/path/to/a/command that exits 0 while Focus is on"
```

---

## 2. A channel to your phone

The server half is already verified: a Slurm job on a compute node published to
ntfy through ARC's preset proxy and the message came back off the topic intact
(architecture.md §7). What is untested is the last hop — your phone.

1. Install the **ntfy** app. Generate a topic; do not choose one:
   ```bash
   head -c 18 /dev/urandom | base64 | tr -d '/+='
   ```
   Subscribe the app to it. **That string is the password** — anyone who knows it
   reads every notification you send.
2. On the cluster:
   ```sh
   # ~/.tailbell/config
   TAILBELL_CHANNELS="file,ntfy"
   TAILBELL_NTFY_TOPIC="<the string you just generated>"
   ```
3. `~/.tailbell/bin/tailbell-doctor --test` — it reports what each channel
   answered, quoting the server.
4. **Close every editor**, then have a cluster session run for more than 60 s.
   The phone should buzz with nothing else connected. That is the point of the
   whole channel.

### Then, from a compute node

```bash
sbatch --account=<acct> --time=00:03:00 --wrap \
  'printf "{\"session_id\":\"sb000000-0000-0000-0000-000000000000\",\"cwd\":\"$PWD\"}" \
   | TAILBELL_SYNC=1 ~/.tailbell/bin/tailbell-notify AskUserQuestion'
```

If that one does not arrive but the login-node one does, the job's environment
lost `http_proxy`. `TAILBELL_HTTP_PROXY` in the config overrides it.

### Slack / Discord / Feishu

Each needs one webhook URL from the service, then one config line. The doctor
checks the URL shape, whether the host is reachable, and — with `--test` — what
the server actually replied.

```sh
TAILBELL_CHANNELS="file,slack"
TAILBELL_SLACK_WEBHOOK="https://hooks.slack.com/services/…"
```

A Feishu bot set to **signed request** also needs `TAILBELL_FEISHU_SECRET`; one
set to **keyword** mode needs that keyword to appear in the message text, which
tailbell's titles will not contain unless you pick a keyword like `Claude`.

---

## 3. Approving from the phone

The mechanism is verified against a real terminal CLI session: request pushed,
button pressed, decision applied, the tool ran and no prompt was drawn. What is
untested is whether a real ntfy app renders the action buttons and posts back.

1. Generate a **second** topic, different from the notification one. tailbell
   refuses to run if they are equal — whoever can read a topic can answer the
   prompt, and the notification topic is the one that ends up in screenshots.
2. ```sh
   # ~/.tailbell/config
   TAILBELL_APPROVE=1
   TAILBELL_APPROVE_TOPIC="<the second string>"
   TAILBELL_APPROVE_TOOLS="Write,Edit"
   TAILBELL_APPROVE_TTL=90
   ```
   `TAILBELL_APPROVE_TOOLS` is required and is also the hook's matcher. Name the
   few tools you actually get asked about: this hook runs before *every* matching
   tool call, not only the ones that would have prompted.
3. ```bash
   ~/.tailbell/bin/tailbell-register --approve
   ```
4. Open a **terminal** `claude` session on the cluster — not the VS Code chat
   panel, where there is no permission event to hook — and ask it to edit a file.

### What should happen

The phone gets 「🔑 … 需要你授权」 with **允许** and **拒绝** buttons. Tap 允许
and the edit proceeds **without a prompt ever appearing in the terminal**.

### What to check deliberately

- **Wait it out.** Do nothing for longer than the TTL. The terminal must fall
  back to its own prompt. Silence must never become approval.
- **Tap after it expired.** Nothing should happen, and `~/.tailbell/debug.log`
  should say `rejected a reply … timestamped after the … deadline`.
- **Check what the push says.** It names the tool (`Write`), the project and the
  host. It must **not** contain the file contents or the command line — that is
  the deliberate trade, and a test enforces it, but look with your own eyes.

If the buttons never arrive, `debug.log` names the reason: not registered, not
enabled, no topic, the two topics equal, the tool not in the list, the session
already auto-approving, or the poll failing outright.

---

## 4. After all three

- Update `docs/STATUS.md`: move what passed out of *Open*, and record anything
  that failed with what you saw.
- Then release 8 can merge to `main`.

Still deliberately not done at that point, and each needs its own decision:
publishing to GitHub, cutting a tag, the Homebrew tap, and the npm package.
