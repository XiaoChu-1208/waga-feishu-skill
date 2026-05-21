#!/bin/bash
# waga-spawn.sh — 拉起一个 headless 的 waga worker（无需开窗口的新 Claude 会话）
#
# 用法：
#   bash waga-spawn.sh <name> ["初始任务"] [工作目录]
#
# 例：
#   bash waga-spawn.sh api "看下 api 目录有没有 lint 错误"
#   bash waga-spawn.sh web "" "$HOME/proj"
#
# 它干什么：
#   后台常驻，监听飞书里发给 [<name>] 的消息，每来一条就用
#   `claude -p --resume <固定session-id>` 跑一个 headless Claude 处理，
#   保持上下文（跟正常会话一样），把结果发回飞书。自己挂名、自己收发、自己干活。
#
# 设计取舍：
#   · headless 弹不出权限框，所以带 --dangerously-skip-permissions 自动放行工具，
#     否则会卡在权限上干不了活。等于给这个 worker 放权——按『当正常 session 用』处理。
#   · 不设预算上限（用户要求当正常 session 用）。
#   · claude -p 会阻塞到任务完成，期间不收新消息（顺序处理），简单可靠。
#
# 用 run_in_background 方式启动（detached），关进程即注销。

set -u
export LARK_CLI_NO_PROXY=1

NAME="${1:?usage: waga-spawn.sh <name> [初始任务] [cwd]}"
INIT_TASK="${2:-}"
WORKDIR="${3:-$(pwd)}"

CHAT=${WAGA_CHAT_ID:?set WAGA_CHAT_ID}
USER=${WAGA_USER_ID:?set WAGA_USER_ID}
SEEN="/tmp/waga_seen_${NAME}.txt"
STICKY="/tmp/waga_sticky.txt"
ALIVE="/tmp/waga_alive_${NAME}.txt"
SIDFILE="/tmp/waga_session_${NAME}.txt"
touch "$SEEN"
[ -f "$STICKY" ] || echo "main" > "$STICKY"

# 固定 session-id（保持上下文；重启可续）
if [ -f "$SIDFILE" ]; then
  SID="$(cat "$SIDFILE")"
  STARTED=1
else
  SID="$(python -c 'import uuid;print(uuid.uuid4())' 2>/dev/null \
        || powershell.exe -NoProfile -Command '[guid]::NewGuid().ToString()' 2>/dev/null | tr -d '\r')"
  echo "$SID" > "$SIDFILE"
  STARTED=0
fi

react() { lark-cli im reactions create --as bot --params "{\"message_id\":\"$1\"}" \
  --data "{\"reaction_type\":{\"emoji_type\":\"$2\"}}" >/dev/null 2>&1; }
send() { lark-cli im +messages-send --as bot --user-id "$USER" --text "[${NAME}] $1" >/dev/null 2>&1; }

# 跑一次 headless claude，保持上下文；返回结果文本
run_claude() {
  local msg="$1" out
  if [ "$STARTED" = "0" ]; then
    out=$(cd "$WORKDIR" && claude -p --session-id "$SID" --dangerously-skip-permissions "$msg" 2>&1)
    STARTED=1
  else
    out=$(cd "$WORKDIR" && claude -p --resume "$SID" --dangerously-skip-permissions "$msg" 2>&1)
  fi
  printf '%s' "$out"
}

# 处理一条消息：贴 OnIt → 跑 claude → 回飞书 → 贴 DONE
handle() {
  local mid="$1" body="$2"
  [ -n "$mid" ] && react "$mid" OnIt
  local reply; reply="$(run_claude "$body")"
  # 飞书消息别太长，超长截断
  if [ "${#reply}" -gt 1800 ]; then reply="${reply:0:1800}
…（输出过长已截断）"; fi
  [ -z "$reply" ] && reply="(claude 无输出)"
  send "$reply"
  [ -n "$mid" ] && { lark-cli im reactions list --as bot --params "{\"message_id\":\"$mid\"}" \
      --jq '.data.items[]|select(.reaction_type.emoji_type=="OnIt").reaction_id' 2>/dev/null \
      | tr -d '"' | while read -r r; do [ -n "$r" ] && lark-cli im reactions delete --as bot \
      --params "{\"message_id\":\"$mid\",\"reaction_id\":\"$r\"}" >/dev/null 2>&1; done; react "$mid" DONE; }
}

# seed：把现有消息标记已读，避免上线就处理历史
lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
  --jq '.data.messages[].message_id' 2>/dev/null | tr -d '"' >> "$SEEN"

send "headless worker 上线 · cwd=${WORKDIR} · session=${SID:0:8}…
派活：[${NAME}] 任务  或  ${NAME}: 任务
关闭：${NAME}: /stop"

# 有初始任务就先干
[ -n "$INIT_TASK" ] && handle "" "$INIT_TASK"

STOPFILE="/tmp/waga_stop_${NAME}.txt"
rm -f "$STOPFILE"

while true; do
  # 本地关闭：touch 这个文件即可让 worker 优雅退出
  if [ -f "$STOPFILE" ]; then send "headless worker 下线（stopfile）"; rm -f "$STOPFILE" "$ALIVE"; exit 0; fi
  echo "$(date +%s)|${NAME}|${WORKDIR}" > "$ALIVE"
  out=$(lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
    --jq '.data.messages[] | select(.sender.sender_type=="user") | .message_id + "\t" + ((.content // "")|tostring|gsub("\n";" "))' 2>&1)

  # API 报错(token失效/ok:false/5xx)就跳过本轮，绝不把报错 JSON 当消息
  if echo "$out" | grep -qiE 'secret invalid|token.*expired|invalid_token|99991|10014|"ok" *: *false|api_error|HTTP [45][0-9][0-9]|internal error'; then
    sleep 30; continue
  fi

  # 用 here-string 跑主循环，避免 pipe 子shell 吃掉 exit
  while IFS=$'\t' read -r mid content; do
    [ -z "$mid" ] && continue
    case "$mid" in om_*) ;; *) continue ;; esac   # 只处理真消息 id
    grep -qF "$mid" "$SEEN" && continue
    # 远程关闭：api: /stop  或  [api] /stop
    case "$content" in
      "${NAME}: /stop"|"${NAME}：/stop"|"${NAME}：/stop "*|"${NAME}: /stop "*|"[${NAME}] /stop"*)
        echo "$mid" >> "$SEEN"; send "收到，headless worker 下线"; rm -f "$ALIVE"; exit 0 ;;
      "${NAME}:"|"${NAME}：")          echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"; send "已切粘性到我"; continue ;;
      "${NAME}: "*|"${NAME}："*)       echo "$mid" >> "$SEEN"; handle "$mid" "${content#*[:：] }"; continue ;;
      "[${NAME}] "*)                   echo "$mid" >> "$SEEN"; handle "$mid" "${content#\[${NAME}\] }"; continue ;;
      "["*"]"*)                        continue ;;
    esac
    # 无前缀：粘性目标是我才接
    if [ "$(cat "$STICKY" 2>/dev/null)" = "$NAME" ]; then
      echo "$mid" >> "$SEEN"; handle "$mid" "$content"
    fi
  done <<< "$out"
  sleep 15
done
