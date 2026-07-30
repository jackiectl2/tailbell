#!/usr/bin/env bash
# Install the tailbell workstation side on macOS.
#
# Run this ON YOUR MAC, from a Mac-local Terminal — not the editor's integrated
# terminal, which in a Remote-SSH window is on the cluster.
#
# What it sets up:
#   1. SSH connection reuse (ControlMaster) for the cluster hosts, so the listener
#      can attach to the connection the editor already holds and never triggers a
#      2FA prompt of its own.
#   2. tailbell-listen as a LaunchAgent: starts at login, restarts if it dies.
#   3. Local hooks, so Claude Code running on this Mac notifies directly instead
#      of going through the log.
#
# Installs nothing from Homebrew and requires no third-party service: rendering
# falls back to osascript, which ships with macOS.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOSTS="${TAILBELL_HOSTS:-gl6,greatlakes,greatlakes.arc-ts.umich.edu}"
SCP_HOST="${TAILBELL_SCP_HOST:-${HOSTS%%,*}}"
TB="$HOME/.tailbell"
PLIST="$HOME/Library/LaunchAgents/dev.tailbell.listen.plist"
SSHCFG="$HOME/.ssh/config"
CM_PATH="$HOME/.ssh/cm-%r@%h-%p"

[ "$(uname)" = "Darwin" ] || { echo "这个脚本只在 macOS 上跑。当前: $(uname)"; exit 1; }

echo "==> 1/5 检查前置条件"
[ -x /usr/bin/python3 ] || { echo "需要 /usr/bin/python3: xcode-select --install"; exit 1; }
echo "    /usr/bin/python3 $(/usr/bin/python3 -V 2>&1 | awk '{print $2}')"

echo "==> 2/5 开启 SSH 连接复用"
mkdir -p "$HOME/.ssh"; touch "$SSHCFG"; chmod 600 "$SSHCFG"
if grep -qE '^[[:space:]]*ControlPath' "$SSHCFG"; then
  echo "    已有 ControlPath 设置,跳过 (不覆盖你的配置)"
else
  cp "$SSHCFG" "$SSHCFG.bak.$(date +%Y%m%d-%H%M%S)"
  # Appended, not prepended: ssh takes the first value it sees for each option, so
  # anything already configured for these hosts wins and only the multiplexing
  # options you had not set get added. %h keeps one master per node, which matters
  # when the cluster alias round-robins across several login nodes.
  {
    echo ""
    echo "Host $(printf '%s' "$HOSTS" | tr ',' ' ')"
    echo "    ControlMaster auto"
    echo "    ControlPath $CM_PATH"
    echo "    ControlPersist 12h"
  } >> "$SSHCFG"
  echo "    已追加 (原文件已备份)"
fi

echo "==> 3/5 安装到 $TB"
mkdir -p "$TB/bin" "$TB/state"
install -m 755 "$REPO/bin/tailbell-show"   "$TB/bin/tailbell-show"
install -m 755 "$REPO/bin/tailbell-listen" "$TB/bin/tailbell-listen"
install -m 755 "$REPO/bin/tailbell-notify" "$TB/bin/tailbell-notify"
install -m 755 "$REPO/bin/tailbell-doctor" "$TB/bin/tailbell-doctor"
if [ ! -f "$TB/config" ]; then
  cat > "$TB/config" <<EOF
# tailbell workstation config.
# Rendering happens locally here, so no transport is needed.
TAILBELL_MIN_SECONDS=60
TAILBELL_HOSTS="$HOSTS"
EOF
  chmod 600 "$TB/config"
  echo "    写入 $TB/config"
else
  echo "    $TB/config 已存在,保留"
fi

echo "==> 4/5 装 LaunchAgent"
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
    <key>TAILBELL_HOSTS</key><string>$HOSTS</string>
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

echo "==> 5/5 本地 hooks (Claude Code 直接跑在这台 Mac 上时用)"
/usr/bin/python3 - "$TB" <<'PY'
import json, pathlib, shutil, sys, time
tb = sys.argv[1]
p = pathlib.Path.home()/".claude"/"settings.json"
cfg = {}
if p.exists():
    shutil.copy(p, str(p) + ".bak." + time.strftime("%Y%m%d-%H%M%S"))
    cfg = json.loads(p.read_text())
N = "%s/bin/tailbell-notify" % tb
h = cfg.setdefault("hooks", {})
def one(ev, arg, matcher=None):
    e = {"hooks": [{"type": "command", "command": "%s %s" % (N, arg)}]}
    if matcher:
        e["matcher"] = matcher
    h[ev] = [e]
one("Stop", "Stop")
one("UserPromptSubmit", "UserPromptSubmit")
one("SessionEnd", "SessionEnd")
one("Notification", "Notification")
one("PreToolUse", "AskUserQuestion", matcher="AskUserQuestion")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(cfg, indent=2) + "\n")
print("    已合并 ~/.claude/settings.json (旧文件已备份)")
PY

cat <<DONE

────────────────────────────────────────────────
装好了。还剩一步要你手动做 —— 建立共享 SSH 连接
(需要 2FA 的话就在这里认证一次,之后 12 小时复用):

    ssh ${SCP_HOST} true

然后验证:

    $TB/bin/tailbell-doctor --test

它会逐项检查并真发一条通知。

第一次没看到弹窗,九成是这个:
    系统设置 › 通知 › Script Editor → 允许通知
osascript 的通知以 Script Editor 的身份出现,没授权时会静默丢弃。
────────────────────────────────────────────────
DONE
