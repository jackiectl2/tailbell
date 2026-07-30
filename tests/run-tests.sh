#!/usr/bin/env bash
# tailbell test suite. Runs against a throwaway TAILBELL_HOME so it never touches
# your real config, log or state.
#
# Every case here corresponds to something that actually went wrong during
# development, so this file is the regression record as much as a test suite.
#
# Usage: bash tests/run-tests.sh
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
NOTIFY="$REPO/bin/tailbell-notify"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export TAILBELL_HOME="$TMP"
export TAILBELL_TRANSPORT="file"
export TAILBELL_LOG="$TMP/events.log"
export TAILBELL_DEBUG_LOG="$TMP/debug.log"
export TAILBELL_STATE_DIR="$TMP/state"
export TAILBELL_MIN_SECONDS=60
mkdir -p "$TAILBELL_STATE_DIR"
: > "$TAILBELL_LOG"

pass=0; fail=0
ok()   { printf '  ✅ %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  ❌ %s\n' "$1"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (期望 '$3',实得 '$2')"; fi; }

lines() { wc -l < "$TAILBELL_LOG" | tr -d ' '; }
fire()  { printf '%s' "$2" | "$NOTIFY" "$1"; }
sid()   { printf '%s-0000-0000-0000-000000000000' "$1"; }

echo "tailbell tests   (TAILBELL_HOME=$TMP)"

########################################################################
echo
echo "── Stop 的时长闸门 ──"

# A turn the user was plainly watching must not interrupt them.
s=$(sid aaaa); echo $(( $(date +%s) - 5 )) > "$TAILBELL_STATE_DIR/$s.start"
b=$(lines); fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/proj-short\"}"
check "5 秒的回合被抑制" "$(( $(lines) - b ))" "0"

s=$(sid bbbb); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
b=$(lines); fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/proj-long\"}"
check "400 秒的回合会通知" "$(( $(lines) - b ))" "1"

# Regression: a missing start marker used to be read as elapsed=0, which is
# below the threshold, so the notification was dropped without a trace. Unknown
# duration must notify, not stay silent.
s=$(sid cccc); rm -f "$TAILBELL_STATE_DIR/$s.start"
b=$(lines); fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/proj-nomarker\"}"
check "没有计时标记时照样通知 (回归)" "$(( $(lines) - b ))" "1"
if tail -1 "$TAILBELL_LOG" | grep -q '时长未知'; then ok "并标注「时长未知」"
else no "应标注「时长未知」"; fi

########################################################################
echo
echo "── 阻塞类事件 ──"

# Being blocked is always worth a ping, however short the turn.
s=$(sid dddd)
b=$(lines); fire AskUserQuestion "{\"session_id\":\"$s\",\"cwd\":\"/x/proj-ask\"}"
check "AskUserQuestion 无条件通知" "$(( $(lines) - b ))" "1"
check "并标为 high 优先级" \
  "$(tail -1 "$TAILBELL_LOG" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["priority"])')" \
  "high"

b=$(lines); fire Notification \
  "{\"session_id\":\"$s\",\"cwd\":\"/x/p\",\"notification_type\":\"permission_prompt\"}"
check "Notification:permission_prompt 会通知" "$(( $(lines) - b ))" "1"

b=$(lines); fire Notification \
  "{\"session_id\":\"$s\",\"cwd\":\"/x/p\",\"notification_type\":\"auth_success\"}"
check "无关的 notification_type 被忽略" "$(( $(lines) - b ))" "0"

########################################################################
echo
echo "── 隐私 ──"

# The Stop payload carries the whole reply text. It must never be emitted.
s=$(sid eeee); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/p\",\"last_assistant_message\":\"TOPSECRET-CANARY\"}"
if grep -q 'TOPSECRET-CANARY' "$TAILBELL_LOG"; then no "last_assistant_message 泄露了!"
else ok "last_assistant_message 从未被读取"; fi

########################################################################
echo
echo "── 输出格式 ──"

bad=0
while IFS= read -r l; do
  [ -n "$l" ] || continue
  printf '%s' "$l" | /usr/bin/python3 -c '
import sys, json
d = json.load(sys.stdin)
for k in ("ts", "title", "message", "priority", "project", "node"):
    assert k in d, k
' 2>/dev/null || bad=$((bad+1))
done < "$TAILBELL_LOG"
check "每一行都是含全部字段的合法 JSON" "$bad" "0"

# A project name with a quote in it must not be able to break the line.
s=$(sid ffff); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/we\\\"ird\"}"
if tail -1 "$TAILBELL_LOG" | /usr/bin/python3 -c 'import sys,json;json.load(sys.stdin)' 2>/dev/null
then ok "含引号的项目名仍产出合法 JSON"; else no "含引号的项目名破坏了 JSON"; fi

########################################################################
echo
echo "── 健壮性 ──"

b=$(lines); fire Stop '{"cwd":"/x/p"}'
check "缺 session_id 时安全退出" "$(( $(lines) - b ))" "0"

b=$(lines); fire Stop 'this is not json'
check "非 JSON 输入不会崩" "$(( $(lines) - b ))" "0"

b=$(lines); fire NoSuchEvent "{\"session_id\":\"$(sid gggg)\",\"cwd\":\"/x/p\"}"
check "未知事件被忽略" "$(( $(lines) - b ))" "0"

# UserPromptSubmit must leave a marker for Stop to measure against.
s=$(sid hhhh); rm -f "$TAILBELL_STATE_DIR/$s.start"
fire UserPromptSubmit "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}"
if [ -f "$TAILBELL_STATE_DIR/$s.start" ]; then ok "UserPromptSubmit 写下计时标记"
else no "UserPromptSubmit 没写计时标记"; fi

fire SessionEnd "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}"
if [ -f "$TAILBELL_STATE_DIR/$s.start" ]; then no "SessionEnd 没清理标记"
else ok "SessionEnd 清理了标记"; fi

########################################################################
echo
echo "── 日志轮转 (NFS home 有配额,不能无限增长) ──"

/usr/bin/python3 -c "
open('$TAILBELL_LOG','a').write('{\"ts\":0,\"title\":\"f\",\"message\":\"%s\"}\n' % ('x'*100) * 12000)
" 2>/dev/null || /usr/bin/python3 -c "
with open('$TAILBELL_LOG','a') as f:
    for _ in range(12000): f.write('{\"ts\":0,\"title\":\"f\",\"message\":\"%s\"}\n' % ('x'*100))
"
big=$(stat -c %s "$TAILBELL_LOG")
s=$(sid iiii); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}"
now=$(stat -c %s "$TAILBELL_LOG")
if [ "$now" -lt "$big" ] && [ "$(lines)" -le 201 ]; then
  ok "超过 1 MB 后自动截断到最近 200 行 ($((big/1024)) KB → $((now/1024)) KB)"
else no "轮转没生效 ($big → $now bytes, $(lines) 行)"; fi

########################################################################
echo
echo "── 决策日志 (「为什么没通知」靠它排查) ──"
if [ -s "$TAILBELL_DEBUG_LOG" ]; then ok "debug.log 有内容"; else no "debug.log 是空的"; fi
if grep -q 'skipped:' "$TAILBELL_DEBUG_LOG"; then ok "抑制决策有记录"
else no "抑制决策没记录"; fi
if grep -q 'no start marker' "$TAILBELL_DEBUG_LOG"; then ok "缺计时标记有记录"
else no "缺计时标记没记录"; fi

########################################################################
echo
printf '结果: %d 通过, %d 失败\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
