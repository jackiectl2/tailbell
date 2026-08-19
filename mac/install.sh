#!/usr/bin/env bash
# Install the tailbell workstation side on macOS.
#
# Run this ON YOUR MAC, from a Mac-local Terminal — not the editor's integrated
# terminal, which in a Remote-SSH window is on the cluster.
#
# What it sets up:
#   1. SSH connection reuse (ControlMaster). The listener attaches to connections
#      your editor already holds, so it never triggers a 2FA prompt of its own —
#      and, because every such connection leaves a socket behind, it is also how
#      hosts get discovered rather than configured.
#   2. The Hammerspoon renderer, if Hammerspoon is installed. Optional: without it
#      alerts fall back to a top-right banner.
#   3. tailbell-listen as a LaunchAgent: starts at login, restarts if it dies.
#   4. Local hooks, so Claude Code running on this Mac notifies directly.
#
# It also retires the cc-notify.sh prototype this grew out of, if present, so the
# two do not both fire.
#
# Installs nothing from Homebrew and requires no third-party service: rendering
# falls back to osascript, which ships with macOS.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TB="$HOME/.tailbell"
PLIST="$HOME/Library/LaunchAgents/dev.tailbell.listen.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/sh.claude-code.gl-notify.plist"
SSHCFG="$HOME/.ssh/config"
CM_PATH="$HOME/.ssh/cm-%r@%h-%p"
HSDIR="$HOME/.hammerspoon"

[ "$(uname)" = "Darwin" ] || { echo "这个脚本只在 macOS 上跑。当前: $(uname)"; exit 1; }

echo "==> 1/6 前置检查"
[ -x /usr/bin/python3 ] || { echo "需要 /usr/bin/python3: xcode-select --install"; exit 1; }
echo "    /usr/bin/python3 $(/usr/bin/python3 -V 2>&1 | awk '{print $2}')"

echo "==> 2/6 SSH 连接复用"
mkdir -p "$HOME/.ssh"; touch "$SSHCFG"; chmod 600 "$SSHCFG"
if grep -qE '^[[:space:]]*ControlPath' "$SSHCFG"; then
  echo "    已有 ControlPath 设置,保留不动"
else
  cp "$SSHCFG" "$SSHCFG.bak.$(date +%Y%m%d-%H%M%S)"
  # Appended, not prepended: ssh takes the first value it sees for each option, so
  # anything already configured wins and only the unset multiplexing options are
  # added. %h keeps one master per node, which matters when a cluster alias
  # round-robins across login nodes.
  {
    echo ""
    echo "Host *.arc-ts.umich.edu gl* lighthouse* armis*"
    echo "    ControlMaster auto"
    echo "    ControlPath $CM_PATH"
    echo "    ControlPersist 12h"
  } >> "$SSHCFG"
  echo "    已追加 (原文件已备份)"
fi

echo "==> 3/6 安装到 $TB"
mkdir -p "$TB/bin" "$TB/state"
for f in tailbell-notify tailbell-show tailbell-listen tailbell-doctor \
         tailbell-register tailbell-approve; do
  install -m 755 "$REPO/bin/$f" "$TB/bin/$f"
done
if [ ! -f "$TB/config" ]; then
  printf '%s\n' \
    '# tailbell workstation config. Rendering happens locally, so no transport.' \
    'TAILBELL_MIN_SECONDS=60' \
    '# Uncomment if you keep SSH masters to machines unrelated to Claude Code:' \
    '#TAILBELL_HOST_PATTERN="arc-ts"' \
    '' \
    '# Sound. Each event kind gets its own, so you can tell "it finished" from' \
    '# "it needs you" without looking. All five ship with macOS.' \
    '#TAILBELL_SOUND=1                  # 0 silences every one of them' \
    '#TAILBELL_SOUND_DONE=Glass' \
    '#TAILBELL_SOUND_QUESTION=Ping' \
    '#TAILBELL_SOUND_PERMISSION=Sosumi' \
    '#TAILBELL_SOUND_ERROR=Basso' \
    '#TAILBELL_SOUND_IDLE=Tink' \
    '' \
    '# Spoken announcement. Off by default — a machine that talks out loud in a' \
    '# shared office is a different product. 1 speaks every kind; a list speaks' \
    '# only those, and "question,permission" is the useful setting: speak when' \
    '# something is waiting on you, stay quiet when something merely finished.' \
    '# Only the project name and what happened are ever spoken, never the text.' \
    '#TAILBELL_VOICE=0' \
    '#TAILBELL_VOICE_NAME=Tingting      # the prompts are Chinese; pick a voice that reads it' \
    '' \
    '# Do Not Disturb / Focus is a choice you made, so sound and speech are held' \
    '# back while one is on. Set to 0 only if you mean to override it.' \
    '#TAILBELL_RESPECT_FOCUS=1' > "$TB/config"
  chmod 600 "$TB/config"
  echo "    写入 $TB/config"
else
  echo "    $TB/config 已存在,保留"
fi

echo "==> 4/6 Hammerspoon 渲染器 (可选)"
if [ -d "/Applications/Hammerspoon.app" ]; then
  mkdir -p "$HSDIR"
  install -m 644 "$REPO/mac/tailbell.lua" "$HSDIR/tailbell.lua"
  touch "$HSDIR/init.lua"
  cp "$HSDIR/init.lua" "$HSDIR/init.lua.bak.$(date +%Y%m%d-%H%M%S)"
  # Drop the prototype's require so its ⌥Esc binding does not fight ours.
  /usr/bin/sed -i '' '/require("cc-notify")/d' "$HSDIR/init.lua" 2>/dev/null || true
  grep -q 'require("tailbell")' "$HSDIR/init.lua" || \
    printf '\nrequire("tailbell")\n' >> "$HSDIR/init.lua"
  # Restart rather than just launch: a running Hammerspoon would not pick up the
  # edited init.lua.
  killall Hammerspoon 2>/dev/null || true
  sleep 1
  open -a Hammerspoon 2>/dev/null || true
  sleep 5
  if [ -f "$TB/receipt" ]; then
    echo "    ✅ 配置已加载 (回执: $(cat "$TB/receipt"))"
  else
    echo "    ⚠️  没写出回执 —— Lua 可能有错,看 Hammerspoon 菜单 → Console"
    echo "       不影响使用:没有回执时会自动退回右上角横幅"
  fi
else
  echo "    没装 Hammerspoon —— 用右上角横幅,这是保底路径,正常"
fi

echo "==> 5/6 LaunchAgent"
if [ -f "$OLD_PLIST" ]; then
  launchctl unload "$OLD_PLIST" 2>/dev/null || true
  mv "$OLD_PLIST" "$OLD_PLIST.retired"
  echo "    已停用旧的 sh.claude-code.gl-notify"
fi
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.tailbell.listen</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$TB/bin/tailbell-listen</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>TAILBELL_SHOW</key><string>$TB/bin/tailbell-show</string>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/tmp/tailbell.err</string>
</dict>
</plist>
PLIST_EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "    已加载 dev.tailbell.listen"

echo "==> 6/6 本地 hooks"
bash "$TB/bin/tailbell-register" "$TB/bin/tailbell-notify" | sed 's/^/    /'

cat <<DONE

────────────────────────────────────────────────
工作站侧装好了。

接下来把 agent 侧推到各个集群 —— 每台集群都要一份,因为
Claude Code 读的是它自己所在机器的文件系统:

    bash $REPO/mac/deploy.sh <你的集群别名> ...

集群没有连接的话先建一条 (2FA 在这里认证一次,之后 12 小时复用):

    ssh <别名> true

自检:

    $TB/bin/tailbell-doctor --test

第一次没看到通知,九成是这个:
系统设置 › 通知 › Script Editor → 允许通知。osascript 的通知
以 Script Editor 身份出现,没授权会静默丢弃。
────────────────────────────────────────────────
DONE
