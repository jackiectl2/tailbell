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

# A turn that died on an API error is never a "quick success", so the elapsed-time
# gate must not apply to it.
s=$(sid jjjj); echo $(( $(date +%s) - 5 )) > "$TAILBELL_STATE_DIR/$s.start"
b=$(lines); fire StopFailure "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}"
check "StopFailure 无视时长门槛" "$(( $(lines) - b ))" "1"

b=$(lines); fire Elicitation "{\"session_id\":\"$(sid kkkk)\",\"cwd\":\"/x/p\"}"
check "Elicitation 会通知" "$(( $(lines) - b ))" "1"

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
for k in ("ts", "title", "message", "priority", "project", "node",
          "app", "entrypoint", "kind"):
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
echo "── 前端识别 (点击跳转要用) ──"

# entrypoint travels over SSH and is the only frontend hint a remote session has.
s=$(sid llll); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
CLAUDE_CODE_ENTRYPOINT=claude-vscode fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}"
check "entrypoint 写进事件" \
  "$(tail -1 "$TAILBELL_LOG" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["entrypoint"])')" \
  "claude-vscode"

# owning_app() must be a silent no-op off macOS, not an error.
s=$(sid mmmm); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}"
check "非 macOS 上 app 为空且不报错" \
  "$(tail -1 "$TAILBELL_LOG" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["app"])')" \
  ""

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
echo "── 送达通道 ──"
#
# Every case below runs through tests/fake-curl, which records the request
# instead of making it. The suite must work with the network unplugged: that is
# a release 8 guardrail, not a convenience.

FAKE="$REPO/tests/fake-curl"
REC="$TMP/curl.log"
export TAILBELL_CURL="$FAKE"
export FAKE_CURL_RECORD="$REC"
export TAILBELL_SYNC=1          # determinism: sinks are backgrounded by default

# grep -c prints 0 and *exits 1* when nothing matches, so `|| echo 0` appends a
# second line and every comparison against it fails. Capture, ignore the status.
calls() { local n; n="$(grep -c '^CALL$' "$REC" 2>/dev/null)"; echo "${n:-0}"; }
reset() { : > "$REC"; }
# The body of the Nth (default last) recorded call.
body_of() { grep '^BODY ' "$REC" | tail -n "${1:-1}" | head -1 | cut -c6-; }
url_of()  { grep '^URL ' "$REC" | tail -n "${1:-1}" | head -1 | cut -c5-; }
# One field out of a recorded JSON body, so a shape change fails loudly.
field()   { body_of | /usr/bin/python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    d = d[int(k)] if isinstance(d, list) else d[k]
print(d)" "$1" 2>/dev/null; }

# --- the guarantee: an unconfigured tailbell makes no network call at all -----
# This is release 0's path. If it ever reaches for the network, release 8 has
# failed regardless of what else works.
reset
s=$(sid n001); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
b=$(lines); fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/proj-v0\"}"
check "没配通道时仍写 events.log" "$(( $(lines) - b ))" "1"
check "没配通道时一个网络请求都不发" "$(calls)" "0"

# --- ntfy ---------------------------------------------------------------------
reset
export TAILBELL_CHANNELS="ntfy"
export TAILBELL_NTFY_TOPIC="tb-test-topic"
export TAILBELL_NTFY_SERVER="https://ntfy.example"
b=$(lines); fire AskUserQuestion "{\"session_id\":\"$(sid n002)\",\"cwd\":\"/x/proj-ntfy\"}"
check "ntfy 发出一次请求" "$(calls)" "1"
check "ntfy 走 JSON 发布接口 (根路径,不是 /topic)" "$(url_of)" "https://ntfy.example"
check "ntfy body 带 topic" "$(field topic)" "tb-test-topic"
check "ntfy 把 high 映射成数字 4" "$(field priority)" "4"
# A CJK title in an HTTP header is officially ISO-8859-1 and gets mangled; the
# JSON body is UTF-8 by definition. This asserts we send it in the body.
if body_of | grep -q '在等你回答'; then ok "ntfy 标题走 body,中文不进 header"
else no "ntfy 标题没进 body"; fi
check "只走 ntfy 时不写 events.log" "$(( $(lines) - b ))" "0"

# The topic is the only thing that makes the message deliverable, so no topic
# must be a logged skip, never a request to a URL that means nothing.
reset; unset TAILBELL_NTFY_TOPIC
fire AskUserQuestion "{\"session_id\":\"$(sid n003)\",\"cwd\":\"/x/p\"}"
check "没配 topic 时不发请求" "$(calls)" "0"
if grep -q 'SKIPPED ntfy' "$TAILBELL_DEBUG_LOG"; then ok "并记下 SKIPPED ntfy"
else no "没配 topic 却没记日志"; fi
export TAILBELL_NTFY_TOPIC="tb-test-topic"

# --- slack / discord / feishu -------------------------------------------------
reset
export TAILBELL_CHANNELS="slack"
export TAILBELL_SLACK_WEBHOOK="https://hooks.slack.com/services/T0/B0/xxx"
fire AskUserQuestion "{\"session_id\":\"$(sid n004)\",\"cwd\":\"/x/proj-slack\"}"
check "slack 打到配置的 webhook" "$(url_of)" "https://hooks.slack.com/services/T0/B0/xxx"
if [ -n "$(field text)" ]; then ok "slack body 是 {text:…}"; else no "slack body 形状不对"; fi

reset
export TAILBELL_CHANNELS="discord"
export TAILBELL_DISCORD_WEBHOOK="https://discord.com/api/webhooks/1/xxx"
fire AskUserQuestion "{\"session_id\":\"$(sid n005)\",\"cwd\":\"/x/proj-discord\"}"
if [ -n "$(field content)" ]; then ok "discord body 是 {content:…}"; else no "discord body 形状不对"; fi

reset
export TAILBELL_CHANNELS="feishu"
export TAILBELL_FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/abc"
fire AskUserQuestion "{\"session_id\":\"$(sid n006)\",\"cwd\":\"/x/proj-feishu\"}"
check "feishu body 是 text 消息" "$(field msg_type)" "text"
if [ -n "$(field content.text)" ]; then ok "feishu 文本在 content.text"; else no "feishu 文本位置不对"; fi

# Signed mode: the bot rejects an unsigned request, so the signature has to be
# there rather than silently omitted.
reset
export TAILBELL_FEISHU_SECRET="s3cr3t"
fire AskUserQuestion "{\"session_id\":\"$(sid n007)\",\"cwd\":\"/x/p\"}"
if [ -n "$(field sign)" ] && [ -n "$(field timestamp)" ]; then ok "配了 secret 就带签名和时间戳"
else no "签名模式没带 sign/timestamp"; fi
unset TAILBELL_FEISHU_SECRET

# --- several channels at once -------------------------------------------------
reset
export TAILBELL_CHANNELS="file,ntfy,slack"
b=$(lines); fire AskUserQuestion "{\"session_id\":\"$(sid n008)\",\"cwd\":\"/x/proj-fan\"}"
check "一个事件扇出到三条通道" "$(calls)" "2"
check "其中 file 那条照常落盘" "$(( $(lines) - b ))" "1"

# A channel that fails must not take the others down with it — the whole point
# of not chaining the sinks on success.
reset
FAKE_CURL_CODE=500 fire AskUserQuestion "{\"session_id\":\"$(sid n009)\",\"cwd\":\"/x/p\"}"
check "一条通道 500 了,其余照发" "$(calls)" "2"
if grep -q 'FAILED ntfy: HTTP 500' "$TAILBELL_DEBUG_LOG"; then ok "失败带状态码进日志"
else no "失败没记状态码"; fi

# curl itself dying (DNS, proxy, no route) is a different failure and must also
# be named rather than swallowed.
reset
FAKE_CURL_EXIT=7 FAKE_CURL_CODE=000 fire AskUserQuestion "{\"session_id\":\"$(sid n010)\",\"cwd\":\"/x/p\"}"
if grep -q 'FAILED slack: HTTP 000' "$TAILBELL_DEBUG_LOG"; then ok "curl 连不上也记进日志"
else no "curl 连接失败没记日志"; fi

# --- a name nobody implements --------------------------------------------------
reset
export TAILBELL_CHANNELS="file,typo-here,ntfy"
b=$(lines); fire AskUserQuestion "{\"session_id\":\"$(sid n011)\",\"cwd\":\"/x/p\"}"
check "拼错的通道不影响其它通道" "$(calls)" "1"
check "拼错的通道不影响落盘" "$(( $(lines) - b ))" "1"
if grep -q "unknown channel 'typo-here'" "$TAILBELL_DEBUG_LOG"; then ok "拼错的通道名进日志"
else no "拼错的通道名没进日志"; fi

# --- the proxy that makes compute nodes work -----------------------------------
reset
export TAILBELL_CHANNELS="ntfy"
TAILBELL_HTTP_PROXY="http://proxy.example:3128" \
  fire AskUserQuestion "{\"session_id\":\"$(sid n012)\",\"cwd\":\"/x/p\"}"
if grep -q '^PROXY http://proxy.example:3128$' "$REC"; then ok "配了代理就传给 curl"
else no "代理没传给 curl (sbatch 里会静默失败)"; fi

# --- privacy, on every channel -------------------------------------------------
# The file sink has been guarded since release 0. A webhook is a far shorter path
# to a stranger's screen, so the canary has to cover all of them.
reset
export TAILBELL_CHANNELS="file,ntfy,slack,discord,feishu"
export TAILBELL_DISCORD_WEBHOOK="https://discord.com/api/webhooks/1/xxx"
export TAILBELL_FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/abc"
s=$(sid n013); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/p\",\"last_assistant_message\":\"CANARY-STOP\"}"
if grep -q 'CANARY-STOP' "$REC"; then no "last_assistant_message 通过通道泄露了!"
else ok "四条通道都没带上 last_assistant_message"; fi

# PermissionRequest.tool_input is the second place a hook is handed conversation
# content — for AskUserQuestion it is the full text of every question.
fire AskUserQuestion "{\"session_id\":\"$(sid n014)\",\"cwd\":\"/x/p\",\"tool_input\":{\"questions\":[{\"question\":\"CANARY-QUESTION\"}]}}"
if grep -q 'CANARY-QUESTION' "$REC" || grep -q 'CANARY-QUESTION' "$TAILBELL_LOG"; then
  no "tool_input 泄露了!"
else ok "tool_input 从未被读取"; fi

# --- not blocking the session --------------------------------------------------
# A hook that waits on three webhooks is a hook that makes every turn feel slow.
reset
export TAILBELL_CHANNELS="ntfy"
unset TAILBELL_SYNC
t0=$(date +%s)
FAKE_CURL_SLEEP=3 fire AskUserQuestion "{\"session_id\":\"$(sid n015)\",\"cwd\":\"/x/p\"}"
t1=$(date +%s)
if [ "$(( t1 - t0 ))" -lt 3 ]; then ok "慢通道不阻塞 hook (用时 $(( t1 - t0 ))s)"
else no "hook 等了慢通道 $(( t1 - t0 ))s"; fi
export TAILBELL_SYNC=1
t0=$(date +%s)
FAKE_CURL_SLEEP=2 fire AskUserQuestion "{\"session_id\":\"$(sid n016)\",\"cwd\":\"/x/p\"}"
t1=$(date +%s)
if [ "$(( t1 - t0 ))" -ge 2 ]; then ok "TAILBELL_SYNC=1 时同步等待 (给 doctor 和测试用)"
else no "TAILBELL_SYNC=1 没有同步"; fi

# --- kind, which sound selection and routing key on ---------------------------
reset
export TAILBELL_CHANNELS="file"
kind_of() { tail -1 "$TAILBELL_LOG" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["kind"])'; }
s=$(sid n017); echo $(( $(date +%s) - 400 )) > "$TAILBELL_STATE_DIR/$s.start"
fire Stop "{\"session_id\":\"$s\",\"cwd\":\"/x/p\"}";                check "Stop 的 kind 是 done" "$(kind_of)" "done"
fire AskUserQuestion "{\"session_id\":\"$(sid n018)\",\"cwd\":\"/x/p\"}"; check "AskUserQuestion 的 kind 是 question" "$(kind_of)" "question"
fire StopFailure "{\"session_id\":\"$(sid n019)\",\"cwd\":\"/x/p\"}";     check "StopFailure 的 kind 是 error" "$(kind_of)" "error"
fire Notification "{\"session_id\":\"$(sid n020)\",\"cwd\":\"/x/p\",\"notification_type\":\"permission_prompt\"}"
check "权限提示的 kind 是 permission" "$(kind_of)" "permission"

# Leave the environment as the rest of the suite expects it.
unset TAILBELL_CHANNELS TAILBELL_NTFY_TOPIC TAILBELL_NTFY_SERVER \
      TAILBELL_SLACK_WEBHOOK TAILBELL_DISCORD_WEBHOOK TAILBELL_FEISHU_WEBHOOK \
      TAILBELL_CURL FAKE_CURL_RECORD TAILBELL_SYNC

########################################################################
echo
echo "── 声音与语音 ──"
#
# tailbell-show is macOS code, and this suite runs on the cluster. What IS
# testable here is every decision it makes before touching a Mac API: which
# sound each event kind picks, whether it plays one at all, and whether Focus
# suppresses it. Those are the parts that have logic in them. The Mac APIs
# themselves are stubbed through TAILBELL_OSASCRIPT / TAILBELL_AFPLAY /
# TAILBELL_SAY, the same seam idea as TAILBELL_CURL.
#
# ⚠️ What this does NOT prove: that the sounds are distinguishable, or that the
# Focus detection reads the right plist on any given macOS. Both are marked
# untested in the docs, and docs/MIGRATION.md records what that blindness cost
# last time.

SHOW="$REPO/bin/tailbell-show"
SH="$TMP/showhome"; mkdir -p "$SH"
STUB="$TMP/stubs"; mkdir -p "$STUB"
for prog in osascript afplay say; do
  cat > "$STUB/$prog" <<STUBEOF
#!/usr/bin/env bash
printf '$prog %s\n' "\$*" >> "$TMP/render.log"
exit 0
STUBEOF
  chmod +x "$STUB/$prog"
done

# draw <kind> [env assignments...] -> what the renderer would have run
draw() {
  local k="$1"; shift
  : > "$TMP/render.log"
  env TAILBELL_HOME="$SH" TAILBELL_RENDERER=osascript \
      TAILBELL_OSASCRIPT="$STUB/osascript" TAILBELL_AFPLAY="$STUB/afplay" \
      TAILBELL_SAY="$STUB/say" "$@" \
      bash "$SHOW" "标题" "正文" "" "proj" "" "" "$k" >/dev/null 2>&1
  # `say` is backgrounded so it never delays the alert; give it a moment to land.
  sleep 0.3
  cat "$TMP/render.log" 2>/dev/null
}

check "done 用 Glass"        "$(draw done       | grep -o 'sound name "[A-Za-z]*"')" 'sound name "Glass"'
check "question 用 Ping"     "$(draw question   | grep -o 'sound name "[A-Za-z]*"')" 'sound name "Ping"'
check "permission 用 Sosumi" "$(draw permission | grep -o 'sound name "[A-Za-z]*"')" 'sound name "Sosumi"'
check "error 用 Basso"       "$(draw error      | grep -o 'sound name "[A-Za-z]*"')" 'sound name "Basso"'
check "idle 用 Tink"         "$(draw idle       | grep -o 'sound name "[A-Za-z]*"')" 'sound name "Tink"'
# An event kind we have not invented yet must still make a noise, not fall silent.
check "没见过的 kind 退回默认音" "$(draw whatever | grep -o 'sound name "[A-Za-z]*"')" 'sound name "Glass"'

check "单个声音可以覆盖" \
  "$(draw done TAILBELL_SOUND_DONE=Submarine | grep -o 'sound name "[A-Za-z]*"')" \
  'sound name "Submarine"'

# One config line silences everything — the brief's requirement.
if draw done TAILBELL_SOUND=0 | grep -q 'sound name'; then no "TAILBELL_SOUND=0 没能静音"
else ok "TAILBELL_SOUND=0 一行静音"; fi
if draw done TAILBELL_SOUND=0 | grep -q 'osascript'; then ok "静音后通知照常弹出"
else no "静音把通知本身也弄没了"; fi

# Voice is off unless asked for: a machine that talks in a shared office is a
# different product.
if draw done | grep -q '^say '; then no "语音默认是开的"
else ok "语音默认关闭"; fi
if draw done TAILBELL_VOICE=1 | grep -q '^say '; then ok "TAILBELL_VOICE=1 会念出来"
else no "TAILBELL_VOICE=1 没念"; fi
check "只念被指定的 kind (question)" \
  "$(draw question TAILBELL_VOICE=question,permission | grep -c '^say ')" "1"
check "没被指定的 kind 不念 (done)" \
  "$(draw done TAILBELL_VOICE=question,permission | grep -c '^say ')" "0"

# Never the message text — same rule as the webhooks.
# Only the `say` line, not the whole render log — the notification itself
# carries the message, and that is fine; the spoken line must not.
if draw done TAILBELL_VOICE=1 | grep '^say ' | grep -q '正文'; then
  no "语音把正文念出去了"
else ok "语音只念项目和事件,不念正文"; fi

# Focus is a choice the user made. The notification respects it by way of macOS;
# `say` would not unless we check.
if draw done TAILBELL_VOICE=1 TAILBELL_FOCUS_CMD=true | grep -q '^say '; then
  no "专注模式开着还在念"
else ok "专注模式开着就不念 (不绕过 DND)"; fi
if draw done TAILBELL_VOICE=1 TAILBELL_FOCUS_CMD=false | grep -q '^say '; then
  ok "专注模式关着照常念"
else no "专注模式关着却不念"; fi
if draw done TAILBELL_VOICE=1 TAILBELL_FOCUS_CMD=true TAILBELL_RESPECT_FOCUS=0 | grep -q '^say '; then
  ok "TAILBELL_RESPECT_FOCUS=0 时明确地绕过 DND"
else no "关掉 RESPECT_FOCUS 也没生效"; fi

########################################################################
echo
echo "── 手机审批 ──"
#
# tests/fake-curl doubles as the phone here: when it sees a POST carrying ntfy
# action buttons it reads the request id and token out of the button and writes
# back the reply that pressing it would send. So the whole round trip — publish,
# tap, poll, verify — runs with no network and no server, which is the only way
# a path this security-sensitive gets regression-tested at all.

APPROVER="$REPO/bin/tailbell-approve"
AH="$TMP/approvehome"; mkdir -p "$AH/state"

approve_cfg() {
  : > "$AH/config"
  printf '%s\n' "$@" >> "$AH/config"
  printf '%s\n' "TAILBELL_CURL=\"$REPO/tests/fake-curl\"" \
                "TAILBELL_APPROVE_TTL=4" "TAILBELL_APPROVE_POLL=1" >> "$AH/config"
}
# ask <phone-behaviour> [tool] -> whatever the hook printed for Claude Code
ask() {
  : > "$AH/poll.json"
  printf '{"session_id":"abcd1234-0000-0000-0000-000000000000","cwd":"/x/demo","tool_name":"%s","tool_input":{"command":"CANARY-COMMAND"}}' \
    "${2:-Bash}" \
    | FAKE_CURL_RECORD="$AH/curl.log" FAKE_CURL_BODY_FILE="$AH/poll.json" \
      FAKE_PHONE="$1" TAILBELL_HOME="$AH" bash "$APPROVER" 2>/dev/null
}
verdict() { printf '%s' "$1" | /usr/bin/python3 -c '
import sys, json
t = sys.stdin.read().strip()
print(json.loads(t)["hookSpecificOutput"]["permissionDecision"] if t else "")' 2>/dev/null; }

approve_cfg 'TAILBELL_APPROVE=1' 'TAILBELL_APPROVE_TOPIC="tb-approve-secret"' \
            'TAILBELL_NTFY_TOPIC="tb-notify-public"'

check "手机点「允许」→ allow" "$(verdict "$(ask allow)")" "allow"
check "手机点「拒绝」→ deny"  "$(verdict "$(ask deny)")"  "deny"

# The three ways a reply must be refused. Each prints nothing at all, which is
# what makes Claude Code fall through to its own prompt — silence is never yes.
check "token 对不上 → 不做决定" "$(verdict "$(ask wrongtoken)")" ""
check "请求 id 对不上 → 不做决定" "$(verdict "$(ask wrongreq)")" ""
# "Late" is checked against the timestamp the message carries, so it is refused
# on the evidence rather than because we happened to stop looking.
check "回复晚于截止时间 → 不做决定" "$(verdict "$(ask late)")" ""
check "没人回 → 不做决定,交回本地弹窗" "$(verdict "$(ask none)")" ""

# tool_input is the command line. Approving without seeing it is the deliberate
# trade; leaking it to a third-party server is not.
if grep -q 'CANARY-COMMAND' "$AH/curl.log"; then no "tool_input 被推到了第三方服务器!"
else ok "推送里不含 tool_input (命令原文不出机器)"; fi
if grep -q 'Bash' "$AH/curl.log"; then ok "推送里有工具名,够你判断"
else no "推送里连工具名都没有,没法判断"; fi

# Sharing one topic would hand approval rights to everyone who can read your
# ordinary "turn finished" pings. That must be refused, not silently allowed.
approve_cfg 'TAILBELL_APPROVE=1' 'TAILBELL_APPROVE_TOPIC="same-topic"' \
            'TAILBELL_NTFY_TOPIC="same-topic"'
check "审批 topic 和通知 topic 相同 → 拒绝工作" "$(verdict "$(ask allow)")" ""
if grep -q 'same as the notification topic' "$TAILBELL_DEBUG_LOG"; then ok "并说明为什么拒绝"
else no "拒绝了但没说原因"; fi

# Off by default, and off means off even if a topic is sitting in the config.
approve_cfg 'TAILBELL_APPROVE_TOPIC="tb-approve-secret"'
check "没开 TAILBELL_APPROVE → 不介入" "$(verdict "$(ask allow)")" ""
: > "$AH/curl.log"; ask allow >/dev/null
if [ -s "$AH/curl.log" ]; then no "没开审批却还是发了请求"
else ok "没开审批时一个请求都不发"; fi

# Turned on but nowhere to send it: fall through, and say so.
approve_cfg 'TAILBELL_APPROVE=1'
check "开了但没配 topic → 不介入" "$(verdict "$(ask allow)")" ""

# In the chat panel this hook only ever fires for AskUserQuestion, which
# PreToolUse has already notified about — and two buttons cannot answer a
# multiple-choice question anyway.
approve_cfg 'TAILBELL_APPROVE=1' 'TAILBELL_APPROVE_TOPIC="tb-approve-secret"'
: > "$AH/curl.log"; ask allow AskUserQuestion >/dev/null
if [ -s "$AH/curl.log" ]; then no "AskUserQuestion 也去要审批了 (会重复通知)"
else ok "AskUserQuestion 不走审批,避免重复通知"; fi

# Narrowing to specific tools is how you avoid holding up every prompt.
approve_cfg 'TAILBELL_APPROVE=1' 'TAILBELL_APPROVE_TOPIC="tb-approve-secret"' \
            'TAILBELL_APPROVE_TOOLS="Write,Edit"'
check "不在 TAILBELL_APPROVE_TOOLS 里的工具不介入" "$(verdict "$(ask allow Bash)")" ""
check "在清单里的工具照常介入" "$(verdict "$(ask allow Write)")" "allow"

# A hook that writes anything else to stdout turns a decision into plain text —
# Claude Code parses this, and "does not start with {" means it is ignored.
out="$(ask allow Write)"
if [ "$(printf '%s' "$out" | wc -l)" -le 1 ] && printf '%s' "$out" | head -c1 | grep -q '{'; then
  ok "stdout 只有决定 JSON,没有别的输出"
else no "stdout 混进了别的东西,决定会被当成纯文本"; fi

########################################################################
echo
echo "── 安装 ──"

# install.sh used to carry its own copy of the settings.json merge. It drifted:
# five events registered here against seven in tailbell-register, so StopFailure
# and Elicitation did nothing at all for anyone who installed the documented
# way. Worse, it never wrote ~/.tailbell/cluster-id — and the listener skips any
# host that has none, so the README's install produced silence with every other
# check green. Both are regressions worth a test.
IH="$TMP/installhome"; mkdir -p "$IH"
HOME="$IH" bash "$REPO/install.sh" >/dev/null 2>&1
check "install.sh 成功退出" "$?" "0"

if [ -s "$IH/.tailbell/cluster-id" ]; then ok "install.sh 生成 cluster-id (没有它监听器会跳过这台机器)"
else no "install.sh 没生成 cluster-id —— 监听器会静默跳过这台机器"; fi

evs="$(/usr/bin/python3 -c "
import json
h = json.load(open('$IH/.claude/settings.json'))['hooks']
print(' '.join(sorted(h)))" 2>/dev/null)"
check "install.sh 注册全部 7 个事件" "$evs" \
  "Elicitation Notification PreToolUse SessionEnd Stop StopFailure UserPromptSubmit"

# Running it twice is the normal case — after a pull, after a redeploy.
printf 'TAILBELL_MIN_SECONDS=99\n' >> "$IH/.tailbell/config"
HOME="$IH" bash "$REPO/install.sh" >/dev/null 2>&1
if grep -q 'TAILBELL_MIN_SECONDS=99' "$IH/.tailbell/config"; then ok "重装不覆盖已有 config"
else no "重装把 config 覆盖了"; fi

########################################################################
echo
echo "── doctor 对通道的体检 ──"
#
# The doctor is what you run when a notification did not arrive, so it has to
# name the broken link rather than report a tally. These cases run it against a
# throwaway home with deliberately broken channels, through the fake curl, so
# they need no network either.

DH="$TMP/doctorhome"; mkdir -p "$DH/state"
doctor_out() {   # doctor_out <config lines...>  -> stdout of a doctor run
  : > "$DH/config"
  printf '%s\n' "$@" >> "$DH/config"
  printf '%s\n' "TAILBELL_CURL=\"$REPO/tests/fake-curl\"" >> "$DH/config"
  FAKE_CURL_RECORD="$DH/curl.log" TAILBELL_HOME="$DH" \
    bash "$REPO/bin/tailbell-doctor" ${DOCTOR_ARGS:-} 2>&1
}

out="$(doctor_out 'TAILBELL_CHANNELS="file,typo-here"')"
if printf '%s' "$out" | grep -q "不认识的通道名 'typo-here'"; then ok "doctor 点名不存在的通道"
else no "doctor 没点名不存在的通道"; fi

out="$(doctor_out 'TAILBELL_CHANNELS="slack"')"
if printf '%s' "$out" | grep -q 'slack: 没配 TAILBELL_SLACK_WEBHOOK'; then ok "doctor 点名没配置的通道"
else no "doctor 没点名没配置的通道"; fi

# The credential must not end up in a terminal that gets screenshotted, or in an
# issue. Host and first path segment identify it; the rest is the password.
out="$(doctor_out 'TAILBELL_CHANNELS="slack"' \
                  'TAILBELL_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/SUPERSECRET"')"
if printf '%s' "$out" | grep -q 'SUPERSECRET'; then no "doctor 把 webhook 密钥打出来了!"
else ok "doctor 打码 webhook,不泄露密钥"; fi

# The whole point: a channel the server rejects must be named, with the status.
out="$(FAKE_CURL_CODE=403 DOCTOR_ARGS=--test doctor_out \
        'TAILBELL_CHANNELS="file,slack"' \
        'TAILBELL_SLACK_WEBHOOK="https://hooks.slack.com/services/T00/B00/revoked"')"
if printf '%s' "$out" | grep -q 'FAILED slack: HTTP 403'; then ok "doctor --test 报出被拒的通道和状态码"
else no "doctor --test 没报出被拒的通道"; fi
if printf '%s' "$out" | grep -q 'EMITTED to .*events.log'; then ok "同一次实测里 file 通道照常成功"
else no "doctor --test 没验证 file 通道"; fi

# A diagnostic that exits non-zero gets wrapped in `|| true` and then nobody
# reads it. It reports, it does not fail.
FAKE_CURL_RECORD="$DH/curl.log" TAILBELL_HOME="$DH" \
  bash "$REPO/bin/tailbell-doctor" >/dev/null 2>&1
check "doctor 永远以 0 退出" "$?" "0"

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
