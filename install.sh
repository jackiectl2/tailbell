#!/usr/bin/env bash
# Install the tailbell agent side — run this on the machine where Claude Code
# itself runs (the cluster login node, in the Remote-SSH case).
#
# If you installed tailbell as a Claude Code plugin, you do NOT need this: the
# plugin's hooks/hooks.json registers the same hooks automatically. Use this when
# you want the hooks in your own ~/.claude/settings.json instead, pointing at this
# checkout.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TB="$HOME/.tailbell"

echo "==> 1/3 检查依赖"
missing=""
for t in jq flock hostname stat tee date; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
  echo "    ❌ 缺少:$missing"
  echo "       tailbell 会静默失效。装上再来。"
  exit 1
fi
echo "    jq / flock / coreutils 都在"

echo "==> 2/3 建立 $TB"
mkdir -p "$TB/state"
if [ ! -f "$TB/config" ]; then
  cat > "$TB/config" <<'EOF'
# tailbell agent config.
#
# ---------------------------------------------------------------------------
# Channels: where a notification is sent. A comma-separated list; every name in
# it is tried, and a failure in one never stops another.
#
#   file    — append to events.log; the workstation tails it over the SSH
#             connection your editor already holds. No third party, no account,
#             no quota, and it works from compute nodes because $HOME is one
#             shared NFS mount. This is the guaranteed path: leave it in.
#   ntfy    — push to a phone, reaches you with every editor closed.
#   slack / discord / feishu — post to an incoming webhook.
#
# Everything after `file` puts a third party in the path, which is why none of
# it is on by default. Leave TAILBELL_CHANNELS commented out and tailbell
# behaves exactly as it did before channels existed.
#TAILBELL_CHANNELS="file,ntfy"
TAILBELL_TRANSPORT="file"          # legacy name for a single channel; still honoured

# Turns shorter than this are not worth interrupting you for — you were watching.
TAILBELL_MIN_SECONDS=60

# ---------------------------------------------------------------------------
# ntfy. THE TOPIC IS THE PASSWORD: anyone who knows it reads every notification
# you send, so make it long and random —
#     head -c 18 /dev/urandom | base64 | tr -d '/+='
# and note that a *free* ntfy.sh account cannot reserve or privatise a topic.
# Measured: limits.basis is "ip" for a free account exactly as for an anonymous
# one — same 250/day, still metered on this login node's shared address.
#TAILBELL_NTFY_TOPIC=""
#TAILBELL_NTFY_SERVER="https://ntfy.sh"
#TAILBELL_NTFY_TOKEN=""

# ---------------------------------------------------------------------------
# Webhooks. Each of these URLs *is* a credential — whoever holds it can post as
# you. This file is chmod 600 for that reason; keep it that way, and remember a
# shared login node has other people's root on it.
#TAILBELL_SLACK_WEBHOOK=""
#TAILBELL_DISCORD_WEBHOOK=""
#TAILBELL_FEISHU_WEBHOOK=""
#TAILBELL_FEISHU_SECRET=""        # only if the bot is in "signed request" mode

# ---------------------------------------------------------------------------
# Compute nodes reach the outside through ARC's preset http_proxy and curl picks
# that up on its own. Set this only to override a preset one that is wrong.
#TAILBELL_HTTP_PROXY=""
#TAILBELL_HTTP_TIMEOUT=8
EOF
  chmod 600 "$TB/config"
  echo "    写入 $TB/config"
else
  echo "    $TB/config 已存在,保留"
fi

echo "==> 3/3 注册 hooks 到 ~/.claude/settings.json"
# Delegated to tailbell-register rather than repeated here. Keeping a second
# copy of the merge meant this script registered five events while the register
# script registered seven — so StopFailure and Elicitation silently did nothing
# for anyone who installed the documented way. It also creates
# ~/.tailbell/cluster-id, which the workstation listener uses to open exactly one
# stream per cluster; without that file the listener skips the host entirely and
# you get silence with every other check green.
bash "$REPO/bin/tailbell-register" "$REPO/bin/tailbell-notify" | sed 's/^/    /'

cat <<DONE

────────────────────────────────────────────────
agent 侧装好了。设置是热加载的,不需要重启 Claude Code。

自查:
    $REPO/bin/tailbell-doctor --test

接下来在你的工作站上装接收端:
    macOS →  scp -r <this-host>:$REPO /tmp/tailbell && bash /tmp/tailbell/mac/install.sh
────────────────────────────────────────────────
DONE
