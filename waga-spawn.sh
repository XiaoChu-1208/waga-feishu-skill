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
LOGF="/tmp/waga_stream_${NAME}.log"
SENTFILE="/tmp/waga_sent.txt"   # 已发卡片登记（mid|name），引用回复(reply_to)路由用
# 流式卡片引擎（借鉴 feishu-claude-code-bridge 的单卡片实时刷新体验）
STREAM="$(dirname "$0")/waga-stream.py"
CARD="$(dirname "$0")/waga-card.py"
# ⚠ Git Bash 里 `python` 是 WindowsApps 坏桩（exit 49 吞输出），一律用 `py` 启动器
PY="py"
touch "$SEEN" "$SENTFILE"
[ -f "$STICKY" ] || echo "main" > "$STICKY"

# 固定 session-id（保持上下文；重启可续）
new_sid() {
  $PY -c 'import uuid;print(uuid.uuid4())' 2>/dev/null \
    || powershell.exe -NoProfile -Command '[guid]::NewGuid().ToString()' 2>/dev/null | tr -d '\r'
}
if [ -f "$SIDFILE" ]; then
  SID="$(cat "$SIDFILE")"
  STARTED=1
else
  SID="$(new_sid)"
  echo "$SID" > "$SIDFILE"
  STARTED=0
fi

react() { lark-cli im reactions create --as bot --params "{\"message_id\":\"$1\"}" \
  --data "{\"reaction_type\":{\"emoji_type\":\"$2\"}}" >/dev/null 2>&1; }
send() { lark-cli im +messages-send --as bot --user-id "$USER" --text "[${NAME}] $1" >/dev/null 2>&1; }
sendcard() { $PY "$CARD" say "$NAME" "$1" >/dev/null 2>&1 || send "$1"; }  # 内联卡片，失败降级纯文本
unreact() {  # 删掉触发消息上的某个表情（用完 OnIt 换 DONE）
  [ -z "$1" ] && return
  lark-cli im reactions list --as bot --params "{\"message_id\":\"$1\"}" \
    --jq ".data.items[]|select(.reaction_type.emoji_type==\"$2\").reaction_id" 2>/dev/null \
    | tr -d '"' | while read -r r; do [ -n "$r" ] && lark-cli im reactions delete --as bot \
    --params "{\"message_id\":\"$1\",\"reaction_id\":\"$r\"}" >/dev/null 2>&1; done
}

# 处理一条消息：贴 OnIt → （后台超时升级看门狗）→ 跑流式卡片 worker → 清表情换 DONE
# 超时升级看门狗：claude 跑得久就在用户消息上贴 衰→晕→骷髅→叉，让飞书侧更生动地看到"在转、转了多久"。
# 与窗口版 waga-on.md 的阶梯一致（2/3/5/8 分钟）。headless 不会"睡着"，所以没有 woke/灵光一现那步。
handle() {
  local mid="$1" body="$2"
  [ -n "$mid" ] && react "$mid" OnIt
  # esc 标志：看门狗一旦贴过任何超时表情就 touch 它，父进程据此判断"卡过一阵又回来了"
  local esc="/tmp/waga_esc_${NAME}.flag"; rm -f "$esc"
  # done 标志：任务收尾即 touch；看门狗每轮先检查，杜绝 done 后还刷晕/骷髅
  local donef="/tmp/waga_done_${NAME}.flag"; rm -f "$donef"
  local me=$$   # 父 worker PID，看门狗据此判断自己是否被孤儿化（worker 被重启/杀掉）

  local wd_pid=""
  if [ -n "$mid" ]; then
    ( start=$(date +%s); lv=0
      while :; do
        sleep 20
        # 两道保险：任务已收尾，或父 worker 没了 → 立刻收手（kill 没打中也不会 done 后乱刷）
        [ -f "$donef" ] && break
        kill -0 "$me" 2>/dev/null || break
        age=$(( $(date +%s) - start ))
        if   [ "$age" -ge 480 ] && [ "$lv" -lt 8 ]; then react "$mid" CrossMark; lv=8
        elif [ "$age" -ge 300 ] && [ "$lv" -lt 5 ]; then react "$mid" SKULL;     lv=5
        elif [ "$age" -ge 180 ] && [ "$lv" -lt 3 ]; then react "$mid" DIZZY;     lv=3
        elif [ "$age" -ge 120 ] && [ "$lv" -lt 2 ]; then react "$mid" TOASTED;   lv=2
        fi
        [ "$lv" -ge 2 ] && : > "$esc"   # 升过级=卡过，标记之
        [ "$lv" -ge 8 ] && break        # 已到彻底超时叉号，无更高级，停（也避免被孤儿化后空转）
      done ) &
    wd_pid=$!
  fi

  local firstflag=""
  if [ "$STARTED" = "0" ]; then firstflag="--first"; STARTED=1; fi
  # waga-stream.py 自己发卡片到飞书并随 claude 输出实时刷新；stdout 是最终文本（这里丢弃）
  # claude 若 529/报错：waga-stream 把卡片刷成红色 + 错误原文（已加 stderr drain + 800 字），不会静默
  $PY "$STREAM" --name "$NAME" --cwd "$WORKDIR" --sid "$SID" $firstflag \
     --user "$USER" "$body" >/dev/null 2>>"$LOGF" \
     || sendcard "stream worker 异常，详见 $LOGF"

  # 停掉看门狗，收尾：先立 done 标记再 kill —— kill 没打中时看门狗也会在 20s 内自杀
  : > "$donef"
  [ -n "$wd_pid" ] && kill "$wd_pid" 2>/dev/null
  if [ -n "$mid" ]; then
    unreact "$mid" OnIt
    if [ -f "$esc" ]; then
      # 卡过一阵（含 529 内部重试）才回来 → 撤超时表情，贴 灵光一现+举手 当"满血恢复"信号，再 DONE
      for x in TOASTED DIZZY SKULL CrossMark; do unreact "$mid" "$x"; done
      react "$mid" StatusFlashOfInspiration; react "$mid" STRIVE
    fi
    react "$mid" DONE
    rm -f "$esc" "$donef"
  fi
}

# 命令分发：/stop /status /cd 走特殊处理，其余交给 handle 跑流式卡片。
# 调用方负责先把 mid 标记 SEEN。
dispatch() {
  local mid="$1" body="$2"
  case "$body" in
    "/stop"|"/stop "*)
      sendcard "收到，headless worker 下线（/stop）"; rm -f "$ALIVE"; exit 0 ;;
    "/status"|"/status "*)
      sendcard "状态 · cwd=${WORKDIR} · session=${SID:0:8}… · 粘性目标=$(cat "$STICKY" 2>/dev/null)"
      [ -n "$mid" ] && react "$mid" DONE ;;
    "/cd "*)
      local np="${body#/cd }"; np="${np/#\~/$HOME}"
      if [ -d "$np" ]; then
        WORKDIR="$np"; SID="$(new_sid)"; echo "$SID" > "$SIDFILE"; STARTED=0
        sendcard "已切到 ${WORKDIR}（已新建 session）"
      else
        sendcard "目录不存在：${np}"
      fi
      [ -n "$mid" ] && react "$mid" DONE ;;
    *)
      handle "$mid" "$body" ;;
  esac
}

# seed：把现有消息标记已读，避免上线就处理历史
lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
  --jq '.data.messages[].message_id' 2>/dev/null | tr -d '"' >> "$SEEN"

# 上线回执走内联卡片（与窗口版一致）；卡片失败降级纯文本
$PY "$CARD" online "$NAME" "$WORKDIR" "$(cat "$STICKY" 2>/dev/null)" headless >/dev/null 2>&1 \
  || send "headless worker 上线 · cwd=${WORKDIR} · session=${SID:0:8}…
派活：${NAME}: 任务　切目录：${NAME}: /cd <路径>　状态：${NAME}: /status　关闭：${NAME}: /stop"

# 有初始任务就先干
[ -n "$INIT_TASK" ] && handle "" "$INIT_TASK"

STOPFILE="/tmp/waga_stop_${NAME}.txt"
rm -f "$STOPFILE"

while true; do
  # 本地关闭：touch 这个文件即可让 worker 优雅退出
  if [ -f "$STOPFILE" ]; then sendcard "headless worker 下线（stopfile）"; rm -f "$STOPFILE" "$ALIVE"; exit 0; fi
  # 心跳 epoch|name|cwd|type；type=headless：这是「无窗口的 worker」（spawn 的 headless 会话）
  echo "$(date +%s)|${NAME}|${WORKDIR}|headless" > "$ALIVE"
  out=$(lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
    --jq '.data.messages[] | select(.sender.sender_type=="user") | .message_id + "\t" + (.reply_to // "-") + "\t" + ((.content // "")|tostring|gsub("\n";" "))' 2>&1)

  # API 报错(token失效/ok:false/5xx)就跳过本轮，绝不把报错 JSON 当消息
  if echo "$out" | grep -qiE 'secret invalid|token.*expired|invalid_token|99991|10014|"ok" *: *false|api_error|HTTP [45][0-9][0-9]|internal error'; then
    sleep 30; continue
  fi

  # 用 here-string 跑主循环，避免 pipe 子shell 吃掉 exit
  while IFS=$'\t' read -r mid replyto content; do
    [ -z "$mid" ] && continue
    case "$mid" in om_*) ;; *) continue ;; esac   # 只处理真消息 id
    grep -qF "$mid" "$SEEN" && continue
    # 引用回复路由（最高优先级，与 waga-on.md 一致）：用户引用了某张已登记的卡片
    #   → 我发的卡：路由到我 + 切粘性；别人发的卡：跳过留给那个 worker。
    if [ "$replyto" != "-" ] && [ "$replyto" != "null" ] && grep -qF "${replyto}|" "$SENTFILE"; then
      if grep -qxF "${replyto}|${NAME}" "$SENTFILE"; then
        echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"; dispatch "$mid" "$content"
      fi
      continue
    fi
    # 路由规则（与 waga-on.md 一致）：
    #   冒号语法 name: / name:内容  → 切粘性到我 + 处理（新规则：带内容也切粘性）
    #   方括号 [name] 内容          → 纯一次性，不动粘性
    #   命令 /stop /status /cd 在 dispatch 里识别
    case "$content" in
      "${NAME}:"|"${NAME}："|"${NAME}: "|"${NAME}： ")
        # 冒号后只有空白 → 只切粘性，不跑
        echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"; sendcard "已切粘性到我 · 无前缀消息默认到我"; continue ;;
      "${NAME}:"*|"${NAME}："*)
        # 冒号带内容 → 切粘性 + 处理
        echo "$mid" >> "$SEEN"; echo "$NAME" > "$STICKY"
        # ⚠ 不能用字符类 [:：] 去剥全角冒号——多字节字符会被按字节切坏。分别剥。
        b="${content#${NAME}}"
        case "$b" in
          ":"*)  b="${b#:}"; b="${b# }" ;;
          "："*) b="${b#：}"; b="${b# }" ;;
        esac
        dispatch "$mid" "$b"; continue ;;
      "[${NAME}] "*)
        # 方括号一次性：不动粘性
        echo "$mid" >> "$SEEN"; dispatch "$mid" "${content#\[${NAME}\] }"; continue ;;
      "[${NAME}]"*)
        echo "$mid" >> "$SEEN"; dispatch "$mid" "${content#\[${NAME}\]}"; continue ;;
      "["*"]"*)
        continue ;;   # 给别的 session 的方括号前缀，跳过
    esac
    # 看起来是给别的 session 的「othername: 」前缀 → 跳过（别被粘性兜底误吞）
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
    # 无前缀：粘性目标是我才接
    if [ "$(cat "$STICKY" 2>/dev/null)" = "$NAME" ]; then
      echo "$mid" >> "$SEEN"; dispatch "$mid" "$content"
    fi
  done <<< "$out"
  sleep 15
done
