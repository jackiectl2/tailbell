#!/usr/bin/env bash
# Push the tailbell agent side to a cluster and register its hooks there.
#
#   bash mac/deploy.sh gl4
#   bash mac/deploy.sh lighthouse armis2
#
# Claude Code reads the filesystem of the machine it runs on, so every cluster
# needs its own copy of bin/. This is that copy step, plus the settings.json merge,
# plus a remote self-check. Run it again after any change — it is idempotent.
#
# Login nodes are deliberately NOT baked in. Pass whichever host alias you use;
# within one cluster it does not matter which login node you pick, because that
# cluster's login nodes share one NFS $HOME. Across clusters they do not, which is
# why each cluster must be deployed separately.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] || { echo "用法: bash mac/deploy.sh <host> [host...]"; exit 1; }

for HOST in "$@"; do
  echo "════════════════════════════════════════ $HOST"

  echo "==> 1/4 检查依赖"
  missing="$(ssh -o BatchMode=yes "$HOST" '
    m=""
    for t in jq flock hostname stat tee date; do
      command -v "$t" >/dev/null 2>&1 || m="$m $t"
    done
    printf "%s" "$m"' 2>/dev/null || echo "__UNREACHABLE__")"
  if [ "$missing" = "__UNREACHABLE__" ]; then
    echo "    ❌ 连不上 (需要先建立连接: ssh $HOST true)"; continue
  fi
  if [ -n "$missing" ]; then
    echo "    ❌ 缺少:$missing —— tailbell 会静默失效,先装上"; continue
  fi
  echo "    依赖齐全"

  echo "==> 2/3 复制 bin/"
  ssh -o BatchMode=yes "$HOST" 'mkdir -p ~/.tailbell/bin ~/.tailbell/state'
  scp -q "$REPO/bin/tailbell-notify" "$REPO/bin/tailbell-doctor" \
         "$REPO/bin/tailbell-register" "$REPO/bin/tailbell-approve" \
         "$HOST:.tailbell/bin/"
  ssh -o BatchMode=yes "$HOST" 'chmod +x ~/.tailbell/bin/*'

  # The settings.json merge lives in tailbell-register rather than inline here.
  # Inline meant nesting a Python program inside single quotes inside a remote
  # command; it broke on the first parenthesis and was unreadable besides.
  echo "==> 3/3 写 config 并注册 hooks"
  ssh -o BatchMode=yes "$HOST" '
    if [ ! -f ~/.tailbell/config ]; then
      printf "%s\n" \
        "# tailbell agent config. See docs/architecture.md for why file is default." \
        "TAILBELL_TRANSPORT=\"file\"" \
        "TAILBELL_MIN_SECONDS=60" > ~/.tailbell/config
      chmod 600 ~/.tailbell/config
    fi
    bash ~/.tailbell/bin/tailbell-register' | sed 's/^/    /'

  echo "==> 自检"
  ssh -o BatchMode=yes "$HOST" 'bash ~/.tailbell/bin/tailbell-doctor' 2>&1 \
    | sed -n '/hooks 是否注册/,/结论/p' | sed 's/^/    /'
done

cat <<'DONE'

────────────────────────────────────────────────
部署完成。设置是热加载的,不用重启 Claude Code。

接收端不需要为新集群做任何配置 —— tailbell-listen 通过扫描
~/.ssh/cm-* 这些 ControlMaster socket 自动发现你连着哪些机器,
所以你开哪个登录节点、系统把你分到哪个节点,它都能跟上。

验证:在那台集群上让 Claude Code 跑一个超过 60 秒的任务。
DONE
