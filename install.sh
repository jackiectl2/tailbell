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
# transport:
#   file  — append events to events.log; the workstation tails it over the SSH
#           connection your editor already holds. No third party, no quota.
#   ntfy  — POST to an ntfy server; reaches you with no SSH session up, at the
#           cost of a third party seeing project names.
TAILBELL_TRANSPORT="file"

# Turns shorter than this are not worth interrupting you for — you were watching.
TAILBELL_MIN_SECONDS=60

# Only read when transport=ntfy. The topic IS the password: make it long and
# random, and note that a free ntfy.sh account cannot reserve (privatise) it.
#TAILBELL_NTFY_TOPIC=""
#TAILBELL_NTFY_SERVER="https://ntfy.sh"
#TAILBELL_NTFY_TOKEN=""
EOF
  chmod 600 "$TB/config"
  echo "    写入 $TB/config"
else
  echo "    $TB/config 已存在,保留"
fi

echo "==> 3/3 注册 hooks 到 ~/.claude/settings.json"
# Resolve the interpreter first. A bare `python3` would pick up whatever
# virtualenv is active, which on this cluster is a per-project .venv.
PY=/usr/bin/python3
[ -x "$PY" ] || PY="$(command -v python3 || echo python3)"
"$PY" - "$REPO" <<'PYEOF'
import json, pathlib, shutil, sys, time
repo = sys.argv[1]
p = pathlib.Path.home()/".claude"/"settings.json"
cfg = {}
if p.exists():
    shutil.copy(p, str(p) + ".bak." + time.strftime("%Y%m%d-%H%M%S"))
    cfg = json.loads(p.read_text())
N = "%s/bin/tailbell-notify" % repo
h = cfg.setdefault("hooks", {})

def merge(ev, arg, matcher=None):
    """Replace any existing tailbell entry for this event, keep everyone else's."""
    entry = {"hooks": [{"type": "command", "command": "%s %s" % (N, arg)}]}
    if matcher:
        entry["matcher"] = matcher
    kept = [e for e in (h.get(ev) or [])
            if "tailbell-notify" not in " ".join(
                x.get("command", "") for x in e.get("hooks", []))]
    h[ev] = kept + [entry]

merge("Stop", "Stop")
merge("UserPromptSubmit", "UserPromptSubmit")
merge("SessionEnd", "SessionEnd")
merge("Notification", "Notification")
merge("PreToolUse", "AskUserQuestion", matcher="AskUserQuestion")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(cfg, indent=2) + "\n")
print("    已合并 (旧文件已备份,其他 hook 保留)")
PYEOF

cat <<DONE

────────────────────────────────────────────────
agent 侧装好了。设置是热加载的,不需要重启 Claude Code。

自查:
    $REPO/bin/tailbell-doctor --test

接下来在你的工作站上装接收端:
    macOS →  scp -r <this-host>:$REPO /tmp/tailbell && bash /tmp/tailbell/mac/install.sh
────────────────────────────────────────────────
DONE
