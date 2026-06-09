#!/bin/bash
# waga-spawn-cursor.sh — waga-spawn.sh 的 Cursor CLI 版。
#
# 拉起一个 headless 的 waga worker，但底层用 `cursor-agent`（而非 `claude`），
# 因此可切换模型（Gemini / GPT / Grok / Sonnet / Opus ...）。
#
# 用法：
#   bash waga-spawn-cursor.sh <name> ["初始任务"] [工作目录] [模型]
#
# 例：
#   bash waga-spawn-cursor.sh api "看下 api 目录有没有 lint 错误" "$HOME/proj" gemini-3.1-pro
#   bash waga-spawn-cursor.sh web "" "$HOME/proj" gpt-5.5-high
#   bash waga-spawn-cursor.sh m ""                                # 模型用账号默认
#
# 模型来源优先级：第 4 参 > 环境变量 WAGA_CURSOR_MODEL > 账号默认（不传 --model）。
# 可用模型见 `cursor-agent models`：gemini-3.1-pro / gpt-5.5-high / grok-4.3 /
#   claude-4.6-sonnet-medium / composer-2.5 ...
#
# 与 claude 版的差异：
#   · 引擎走 waga-stream-cursor.py（cursor-agent -p --output-format stream-json --force）。
#   · session 续接：cursor-agent 自己生成 session_id，首条跑完写回 $SIDFILE，之后 --resume。
#   · headless 弹不出权限框 → --force（等价 claude 的 --dangerously-skip-permissions）。

set -u
export LARK_CLI_NO_PROXY=1
# 引擎标签：让本 worker 发的所有卡片在蓝名旁显示 · cursor（区分 Claude 拉起的卡）。
# waga-card.py / waga-stream-cursor.py 的 name_line 会读它。
export WAGA_ENGINE_LABEL=cursor
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"

NAME="${1:?usage: waga-spawn-cursor.sh <name> [初始任务] [cwd] [模型]}"
INIT_TASK="${2:-}"
WORKDIR="${3:-$(pwd)}"
MODEL="${4:-${WAGA_CURSOR_MODEL:-}}"

# 让上线卡/say卡（走 waga-card.py）也在 · cursor 右边显示当前模型
export WAGA_ENGINE_MODEL="$MODEL"

CHAT=${WAGA_CHAT_ID:?set WAGA_CHAT_ID}
USER=${WAGA_USER_ID:?set WAGA_USER_ID}
SEEN="/tmp/waga_seen_${NAME}.txt"
STICKY="/tmp/waga_sticky.txt"
ALIVE="/tmp/waga_alive_${NAME}.txt"
SIDFILE="/tmp/waga_session_${NAME}.txt"   # cursor-agent 的 session_id（由 stream 脚本写回）
LOGF="/tmp/waga_stream_${NAME}.log"
SENTFILE="/tmp/waga_sent.txt"
STREAM="$(dirname "$0")/waga-stream-cursor.py"
CARD="$(dirname "$0")/waga-card.py"
PY="$(command -v py 2>/dev/null || command -v python3 2>/dev/null || echo python3)"
touch "$SEEN" "$SENTFILE"
[ -f "$STICKY" ] || echo "main" > "$STICKY"

react() { lark-cli im reactions create --as bot --params "{\"message_id\":\"$1\"}" \
  --data "{\"reaction_type\":{\"emoji_type\":\"$2\"}}" >/dev/null 2>&1; }
send() { lark-cli im +messages-send --as bot --user-id "$USER" --text "[${NAME}] $1" >/dev/null 2>&1; }
sendcard() { $PY "$CARD" say "$NAME" "$1" >/dev/null 2>&1 || send "$1"; }
reseed() { lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
  --jq '.data.messages[].message_id' 2>/dev/null | tr -d '"' >> "$SEEN"; }
unreact() {
  [ -z "$1" ] && return
  lark-cli im reactions list --as bot --params "{\"message_id\":\"$1\"}" \
    --jq ".data.items[]|select(.reaction_type.emoji_type==\"$2\").reaction_id" 2>/dev/null \
    | tr -d '"' | while read -r r; do [ -n "$r" ] && lark-cli im reactions delete --as bot \
    --params "{\"message_id\":\"$1\",\"reaction_id\":\"$r\"}" >/dev/null 2>&1; done
}

# 处理一条消息：贴 OnIt → 超时升级看门狗 → 跑流式卡片 worker(cursor-agent) → 清表情换 DONE
handle() {
  local mid="$1" body="$2"
  [ -n "$mid" ] && react "$mid" OnIt
  local esc="/tmp/waga_esc_${NAME}.flag"; rm -f "$esc"
  local donef="/tmp/waga_done_${NAME}.flag"; rm -f "$donef"
  local me=$$

  local wd_pid=""
  if [ -n "$mid" ]; then
    ( start=$(date +%s); lv=0
      while :; do
        sleep 20
        [ -f "$donef" ] && break
        kill -0 "$me" 2>/dev/null || break
        age=$(( $(date +%s) - start ))
        if   [ "$age" -ge 480 ] && [ "$lv" -lt 8 ]; then react "$mid" CrossMark; lv=8
        elif [ "$age" -ge 300 ] && [ "$lv" -lt 5 ]; then react "$mid" SKULL;     lv=5
        elif [ "$age" -ge 180 ] && [ "$lv" -lt 3 ]; then react "$mid" DIZZY;     lv=3
        elif [ "$age" -ge 120 ] && [ "$lv" -lt 2 ]; then react "$mid" TOASTED;   lv=2
        fi
        [ "$lv" -ge 2 ] && : > "$esc"
        [ "$lv" -ge 8 ] && break
      done ) &
    wd_pid=$!
  fi

  # 续接 id：SIDFILE 里有就 --resume，没有则首条（stream 脚本跑完写回）
  local resume_id=""
  [ -f "$SIDFILE" ] && resume_id="$(cat "$SIDFILE" 2>/dev/null)"

  $PY "$STREAM" --name "$NAME" --cwd "$WORKDIR" --sidfile "$SIDFILE" \
     --resume-id "$resume_id" --model "$MODEL" --user "$USER" "$body" >/dev/null 2>>"$LOGF" \
     || sendcard "stream worker 异常，详见 $LOGF"

  : > "$donef"
  [ -n "$wd_pid" ] && kill "$wd_pid" 2>/dev/null
  if [ -n "$mid" ]; then
    unreact "$mid" OnIt
    if [ -f "$esc" ]; then
      for x in TOASTED DIZZY SKULL CrossMark; do unreact "$mid" "$x"; done
      react "$mid" StatusFlashOfInspiration; react "$mid" STRIVE
    fi
    react "$mid" DONE
    rm -f "$esc" "$donef"
  fi
}

dispatch() {
  local mid="$1" body="$2"
  case "$body" in
    "/stop"|"/stop "*)
      sendcard "收到，headless worker 下线（/stop）"; rm -f "$ALIVE"; exit 0 ;;
    "/status"|"/status "*)
      sendcard "状态 · cwd=${WORKDIR} · 模型=${MODEL:-账号默认} · session=$(cat "$SIDFILE" 2>/dev/null | cut -c1-8)… · 粘性目标=$(cat "$STICKY" 2>/dev/null)"
      [ -n "$mid" ] && react "$mid" DONE ;;
    "/model "*)
      # 远程切模型：name: /model gpt-5.5-high
      MODEL="${body#/model }"
      export WAGA_ENGINE_MODEL="$MODEL"   # 卡片标签同步显示新模型
      sendcard "已切模型 → ${MODEL}（下一条消息生效）"
      [ -n "$mid" ] && react "$mid" DONE ;;
    "/cd "*)
      local np="${body#/cd }"; np="${np/#\~/$HOME}"
      if [ -d "$np" ]; then
        WORKDIR="$np"; rm -f "$SIDFILE"   # 换目录=新 session（清掉旧 session_id）
        sendcard "已切到 ${WORKDIR}（已新建 session）"
      else
        sendcard "目录不存在：${np}"
      fi
      [ -n "$mid" ] && react "$mid" DONE ;;
    "/who"|"/who "*)
      [ -n "$mid" ] && react "$mid" Get ;;
    *)
      handle "$mid" "$body" ;;
  esac
}

# seed：把现有消息标记已读
lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
  --jq '.data.messages[].message_id' 2>/dev/null | tr -d '"' >> "$SEEN"

# 上线回执卡片；失败降级纯文本
$PY "$CARD" online "$NAME" "$WORKDIR" "$(cat "$STICKY" 2>/dev/null)" headless >/dev/null 2>&1 \
  || send "headless cursor worker 上线 · cwd=${WORKDIR} · 模型=${MODEL:-账号默认}
派活：${NAME}: 任务　切目录：${NAME}: /cd <路径>　切模型：${NAME}: /model <model>　状态：${NAME}: /status　关闭：${NAME}: /stop"

[ -n "$INIT_TASK" ] && handle "" "$INIT_TASK"

STOPFILE="/tmp/waga_stop_${NAME}.txt"
rm -f "$STOPFILE"

while true; do
  if [ -f "$STOPFILE" ]; then sendcard "headless worker 下线（stopfile）"; rm -f "$STOPFILE" "$ALIVE"; exit 0; fi
  # 心跳 type=headless-cursor：区分 Cursor 引擎的无窗口 worker
  echo "$(date +%s)|${NAME}|${WORKDIR}|headless-cursor" > "$ALIVE"
  out=$(lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
    --jq '.data.messages[] | select(.sender.sender_type=="user") | .message_id + "\t" + (.reply_to // "-") + "\t" + ((.content // "")|tostring|gsub("\n";" "))' 2>&1)

  if echo "$out" | grep -qiE 'secret invalid|token.*expired|invalid_token|99991|10014|"ok" *: *false|api_error|HTTP [45][0-9][0-9]|internal error'; then
    sleep 30; continue
  fi

  while IFS=$'\t' read -r mid replyto content; do
    [ -z "$mid" ] && continue
    case "$mid" in om_*) ;; *) continue ;; esac
    grep -qF "$mid" "$SEEN" && continue
    if [ "$replyto" != "-" ] && [ "$replyto" != "null" ] && grep -qF "${replyto}|" "$SENTFILE"; then
      if grep -qxF "${replyto}|${NAME}" "$SENTFILE"; then
        echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"; dispatch "$mid" "$content"
      fi
      continue
    fi
    case "$content" in
      "${NAME}:"|"${NAME}："|"${NAME}: "|"${NAME}： ")
        echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"; reseed; sendcard "已切粘性到我 · 此后无前缀消息默认到我（之前的不补读）"; continue ;;
      "${NAME}:"*|"${NAME}："*)
        echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"; reseed; echo "$mid" >> "$SEEN"
        b="${content#${NAME}}"
        case "$b" in
          ":"*)  b="${b#:}"; b="${b# }" ;;
          "："*) b="${b#：}"; b="${b# }" ;;
        esac
        dispatch "$mid" "$b"; continue ;;
      "[${NAME}] "*)
        echo "$mid" >> "$SEEN"; dispatch "$mid" "${content#\[${NAME}\] }"; continue ;;
      "[${NAME}]"*)
        echo "$mid" >> "$SEEN"; dispatch "$mid" "${content#\[${NAME}\]}"; continue ;;
      "["*"]"*)
        continue ;;
    esac
    case "$content" in
      *":"*)
        first_token="${content%%:*}"
        echo "$first_token" | grep -qE '^[a-zA-Z0-9_-]{1,16}$' && continue ;;
    esac
    case "$content" in
      *"："*)
        first_token="${content%%：*}"
        echo "$first_token" | grep -qE '^[a-zA-Z0-9_-]{1,16}$' && continue ;;
    esac
    if [ "$(cat "$STICKY" 2>/dev/null)" = "$NAME" ]; then
      echo "$mid" >> "$SEEN"; dispatch "$mid" "$content"
    fi
  done <<< "$out"
  sleep 15
done
