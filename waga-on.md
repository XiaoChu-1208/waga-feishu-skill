---
description: 挂上飞书 Waga 私聊的监听器（带 session 路由），让用户在外用飞书私聊机器人就能精准呼叫某个 Claude Code 会话
argument-hint: "[session-name]"
---

# Waga 监听 · session 路由版

## 作用

每个 Claude Code 会话挂一个独立的 Monitor 任务，只接收带自己 name 前缀的飞书消息（例如 `[csb] xxx`）。多个 session 同时挂载互不干扰。

## 决定 session name

按以下顺序：

1. 用户传了 args（例如 `/waga-on csb`） → 用这个
2. 没传 args → 取**当前 cwd 的 basename**当默认（例如 cwd 是 `Desktop\同步\capstoryboard\` → name = `capstoryboard`）
3. 第一次跑且 cwd 也不合适 → 起 name = `default`

挂载完后立刻给飞书发一条上线回执（cwd + 时间），让用户在飞书侧能看到 name 对应哪个目录的会话。

## 飞书侧消息路由约定（手机友好版）

冒号统一了"切粘性"和"一次性"两种语义——靠**冒号后有没有内容**区分。中英文冒号都认（手机中文键盘出全角冒号 `：` 比方括号方便）。

| 用法 | 例子 | 含义 |
|---|---|---|
| **无前缀（默认）** | `你看看 build.bat` | 路由到「当前粘性目标」session（默认 `main`） |
| **粘性切换** | `c:`（单独一条，或 `c：`） | 把粘性目标切到 `c`，之后无前缀消息都到 c |
| **冒号一次性** | `c: 帮我跑测试`（或 `c：帮我跑`） | 只这一条给 c，不改粘性目标 |
| **方括号一次性（老语法）** | `[c] 帮我跑` 或 `[c]帮我跑` | 同冒号，PC 上有人习惯 |
| **全员报数** | `/who` | 所有挂着的 session 各自回一条身份 |
| **悬空（无人接）** | `ghost: hi`、`[ghost] hi`、`ghost:`（无 ghost 在线） | 没人响应 |

粘性目标存在共享文件 `/tmp/waga_sticky.txt`，初始 `main`。多个 session 共读共写，最后写者赢——用户切换不会高频，竞态无害。

## 改名建议

用 1-2 字符短 name 在手机上最划算：`m` / `c` / `w` / `csb` / `wri`。`/waga-on c` 比 `/waga-on capstoryboard` 输入便宜。

## 挂载前：清理本 session 旧的 waga monitor（覆盖语义，不叠加）

**执行 `/waga-on` 时第一步必做**——保证同一 session 多次 `/waga-on` 是「改名」而非「叠加多个监听」：

⚠ **重要**：`TaskList` / `TaskGet` **看不到 Monitor 后台任务**（它们是 TaskCreate 那套任务清单的命名空间，跟 Monitor 的 local_bash 后台任务是两套东西）。所以**不能靠 TaskList 枚举 monitor**。

正确做法——靠对话历史里的 task-id：

1. 回看**本次会话的工具调用历史**，找之前调用 `Monitor` 挂 waga 监听时返回的 `task xxx`（description 以 `Waga 路由` 开头的那个）
2. 对找到的 task-id 调 **TaskStop**
3. 然后再挂新的 Monitor（下方命令）

这样第二次 `/waga-on site` 会先停掉之前的 `[main]` 监听，再挂 `[site]`，session 同一时刻只有一个 waga 身份。若不清理，两个 Monitor 会并存、同时收消息、共用 STICKY 文件互相打架。

**边界**：如果会话被 compact 丢了历史，找不到旧 task-id，则无法自动清理——此时新挂会与旧的并存。用户若看到重复上线回执即可察觉，让 Claude 手动处理或重开会话。

## 挂载命令

直接用 Monitor 工具（persistent: true，timeout 一小时），输出 `[WAGA-MSG]` 事件时会触发 task-notification 唤醒当前 session：

```bash
export LARK_CLI_NO_PROXY=1

# 决定 name：args > cwd basename > "default"
NAME="${1:-$(basename "$(pwd)")}"
NAME="${NAME:-default}"

# 前置：这三个环境变量必须先配好（见 README「前置条件」）
#   WAGA_CHAT_ID  你和 bot 的私聊 chat_id（oc_ 开头）
#   WAGA_USER_ID  你自己的 open_id（ou_ 开头，回信发给谁）
#   WAGA_DIR      本仓库脚本所在目录（waga-reply.sh / waga-react.sh）
# 元数据
CWD="$(pwd)"
CHAT="${WAGA_CHAT_ID:?need WAGA_CHAT_ID, see README}"
USER="${WAGA_USER_ID:?need WAGA_USER_ID, see README}"
SEEN="/tmp/waga_seen_${NAME}.txt"
STICKY="/tmp/waga_sticky.txt"
ALIVE="/tmp/waga_alive_${NAME}.txt"
touch "$SEEN"
[ -f "$STICKY" ] || echo "main" > "$STICKY"

# 路由到我时：瞬间贴中性「处理中」标记（OnIt+Typing），再 emit。
# ⚠ 情绪表情不在这里贴——情绪要呼应用户当下心情（怒→歉、喜→庆、悲→慰），
#   只有读完内容的我（大模型）能判断。所以 emit 只管中性标记，情绪层由我回信时按内容补。
# （带 mid，便于回完信用 waga-react.sh done 把 OnIt/Typing 换成 DONE 绿勾，情绪表情保留）
emit() {
  local m="$1" ct="$2" body="$3"
  for e in OnIt Typing; do
    lark-cli im reactions create --as bot --params "{\"message_id\":\"$m\"}" \
      --data "{\"reaction_type\":{\"emoji_type\":\"$e\"}}" >/dev/null 2>&1
    sleep 0.35
  done
  echo "[WAGA-MSG] $ct [mid=$m] :: $body"
}

# seed
lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
  --jq '.data.messages[].message_id' 2>/dev/null | tr -d '"' >> "$SEEN"

# 上线回执 1/2
ts=$(date +'%H:%M:%S')
reg1=$(lark-cli im +messages-send --as bot --user-id "$USER" \
  --text "[${NAME}] 上线 · cwd=${CWD} · 时间=${ts}" 2>&1)
if echo "$reg1" | grep -q '"ok": *true'; then
  echo "[WAGA] register-1 sent ok"
else
  echo "[WAGA-ERR-REGISTER] sendback-1: $(echo "$reg1" | tr '\n' ' ' | cut -c1-200)"
fi

# 上线回执 2/2 — 用法提示
sticky_now=$(cat "$STICKY" 2>/dev/null)
reg2=$(lark-cli im +messages-send --as bot --user-id "$USER" \
  --text "[${NAME}] 测通。触达我的方式：
  ${NAME}:         (冒号后空 = 切粘性到我)
  ${NAME}: 内容    (一次性给我)
  [${NAME}] 内容   (老语法兼容)
中英冒号都认（${NAME}： 也行）
当前粘性目标: ${sticky_now}" 2>&1)
if echo "$reg2" | grep -q '"ok": *true'; then
  echo "[WAGA] register-2 sent ok"
else
  echo "[WAGA-ERR-REGISTER] sendback-2: $(echo "$reg2" | tr '\n' ' ' | cut -c1-200)"
fi

echo "[WAGA] listener armed as [${NAME}]  cwd=${CWD}"

while true; do
  # 心跳：每轮写 epoch|name|cwd，/who 据此判断谁活着
  echo "$(date +%s)|${NAME}|${CWD}" > "$ALIVE"

  # 内容里的换行压成空格，避免多行消息被拆成多条幻影记录
  out=$(lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot \
    --jq '.data.messages[] | select(.sender.sender_type=="user") | .message_id + "\t" + .create_time + "\t" + ((.content // "")|tostring|gsub("\n";" "))' 2>&1)

  # 错误识别：token 失效 + API 报错(ok:false/5xx/api_error)。命中就跳过本轮，绝不把报错 JSON 当消息解析
  if echo "$out" | grep -qiE 'secret invalid|token.*expired|invalid_token|99991|10014|"ok" *: *false|api_error|HTTP [45][0-9][0-9]|internal error'; then
    echo "[WAGA-ERR] $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
    sleep 30; continue
  fi

  printf '%s\n' "$out" | while IFS=$'\t' read -r mid ctime content; do
    [ -z "$mid" ] && continue
    # 兜底：只有真正的消息 id(om_ 开头)才处理，挡住任何非消息行（错误 JSON 片段等）
    case "$mid" in om_*) ;; *) continue ;; esac
    grep -qF "$mid" "$SEEN" && continue

    # /who：读心跳文件给完整名单；文件锁保证一条 /who 只一个 monitor 应答（不刷屏）
    case "$content" in
      "/who"|"/who "*)
        echo "$mid" >> "$SEEN"
        lockf="/tmp/waga_who_${mid}.lock"
        if ( set -o noclobber; echo "$NAME" > "$lockf" ) 2>/dev/null; then
          now=$(date +%s)
          report=""
          for f in /tmp/waga_alive_*.txt; do
            [ -e "$f" ] || continue
            line=$(cat "$f" 2>/dev/null)
            hb_epoch="${line%%|*}"; rest="${line#*|}"
            hb_name="${rest%%|*}"; hb_cwd="${rest#*|}"
            [ -z "$hb_epoch" ] && continue
            age=$((now - hb_epoch))
            if [ "$age" -le 35 ]; then
              report="${report}
  [${hb_name}] 活 · ${age}s前心跳 · ${hb_cwd}"
            else
              report="${report}
  [${hb_name}] 疑似掉线 · ${age}s前心跳 · ${hb_cwd}"
            fi
          done
          [ -z "$report" ] && report="
  (无任何心跳文件)"
          lark-cli im +messages-send --as bot --user-id "$USER" \
            --text "[who] 当前 waga session（35s 内有心跳=活）:${report}" >/dev/null 2>&1
        fi
        continue
        ;;
    esac

    # name: 系列 (冒号后为空 = 切粘性；冒号后有内容 = 一次性)；中英冒号都认
    case "$content" in
      "${NAME}:"|"${NAME}: "|"${NAME}："|"${NAME}： ")
        # 冒号后只有空白 → 切粘性
        echo "$mid" >> "$SEEN"
        echo "$NAME" > "$STICKY"
        lark-cli im +messages-send --as bot --user-id "$USER" \
          --text "[${NAME}] 已切粘性到我 · 无前缀消息默认到 [${NAME}]" >/dev/null 2>&1
        continue
        ;;
      "${NAME}: "*)
        echo "$mid" >> "$SEEN"
        stripped="${content#${NAME}: }"
        emit "$mid" "$ctime" "$stripped"
        continue
        ;;
      "${NAME}:"*)
        echo "$mid" >> "$SEEN"
        stripped="${content#${NAME}:}"
        emit "$mid" "$ctime" "$stripped"
        continue
        ;;
      "${NAME}： "*)
        echo "$mid" >> "$SEEN"
        stripped="${content#${NAME}： }"
        emit "$mid" "$ctime" "$stripped"
        continue
        ;;
      "${NAME}："*)
        echo "$mid" >> "$SEEN"
        stripped="${content#${NAME}：}"
        emit "$mid" "$ctime" "$stripped"
        continue
        ;;
    esac

    # [name] 老语法
    case "$content" in
      "[${NAME}] "*)
        echo "$mid" >> "$SEEN"
        stripped="${content#\[${NAME}\] }"
        emit "$mid" "$ctime" "$stripped"
        continue
        ;;
      "[${NAME}]"*)
        echo "$mid" >> "$SEEN"
        stripped="${content#\[${NAME}\]}"
        emit "$mid" "$ctime" "$stripped"
        continue
        ;;
    esac

    # 看起来是给别的 session 的路由前缀 → 跳过
    case "$content" in
      "["*"]"*) continue ;;
    esac
    case "$content" in
      *":"*)
        first_token="${content%%:*}"
        if echo "$first_token" | grep -qE '^[a-zA-Z0-9_-]{1,16}$'; then
          # 看着像 other-name: 形式，留给别人
          continue
        fi
        ;;
      *"："*)
        first_token="${content%%：*}"
        if echo "$first_token" | grep -qE '^[a-zA-Z0-9_-]{1,16}$'; then
          continue
        fi
        ;;
    esac

    # 无前缀消息：粘性目标是不是我？
    sticky=$(cat "$STICKY" 2>/dev/null)
    if [ "$sticky" = "$NAME" ]; then
      echo "$mid" >> "$SEEN"
      emit "$mid" "$ctime" "$content"
    fi
    # 否则不响应，让粘性目标 session 处理
  done

  sleep 15
done
```

## 收到消息后的回信规范

**强制铁律**：从 task-notification 收到消息时，回答**必须用 lark-cli 发出去**——光在 Claude Code UI 里写字用户永远看不到，每次都会出现"为啥不回复"事故。

**推荐回信方式**——用 helper 脚本（最短）：

```bash
bash "${WAGA_DIR}/waga-reply.sh" <name> "<回复内容>"
```

例如：

```bash
bash "${WAGA_DIR}/waga-reply.sh" main "已修好"
```

脚本会自动：
- 设 `LARK_CLI_NO_PROXY=1`（避免 lark-cli 走系统代理被 reset）
- 加 `[name]` 前缀让用户在飞书侧能区分谁回的
- 调 lark-cli messages-send 发到 Waga 私聊
- 返回 `ok: <message_id>` 或 `ERR: ...`

**手写 lark-cli（备用，不推荐 — 容易漏 export）**：

```bash
export LARK_CLI_NO_PROXY=1
lark-cli im +messages-send --as bot \
  --user-id "$WAGA_USER_ID" \
  --text "[${NAME}] <你的回复内容>"
```

**Monitor 推送的每条消息后会跟一行 `[WAGA-REMINDER]`** 直接给出对应 session 的完整回信命令——照抄即可。

回信节奏建议：开工冒泡 → 中间进度冒泡 → 完成回报。

## 气泡 reaction（处理中 / 完成 / 生动）

仿 OpenClaw 的体验：给用户消息**气泡本身**打表情（不是回一条表情消息），让用户隔着飞书也知道"在转"。

- **自动中性标记**：Monitor 的 `emit()` 一路由到我就瞬间贴 `OnIt`(处理中)+`Typing`(打字)，纯状态、不带情绪。`[WAGA-MSG]` 行带 `[mid=...]`，回信时从这里取 message_id。
- **情绪层（核心，必做）**：我读完消息后**判断用户此刻的情绪并呼应它**——这才是"活"。不是随便贴几个，是共情：
  - 用户**开心/兴奋** → 跟着乐：`LAUGH JOYFUL PARTY Fire CLAP WOW`
  - 用户**赞同/夸我/感谢** → 谦逊收下：`THUMBSUP Salute HEART OK`
  - 用户**愤怒/不满/被我惹毛** → 认错示弱、别嬉皮：`Sigh Salute`（绝不贴庆祝类）
  - 用户**难过/沮丧** → 共情安慰：`Sigh HEART Salute`
  - 用户**惊叹/牛了** → 接梗：`WOW MUSCLE APPLAUSE Fire`
  - 用户**纯指令/中性** → 轻回应即可：`THUMBSUP OK`，或只留中性标记不加情绪
  ```bash
  bash "${WAGA_DIR}/waga-react.sh" vibe <mid> "LAUGH JOYFUL Fire CLAP"
  ```
  ⚠ 情绪要跟用户**对齐**：他怒你别乐，他丧你别嗨。可用负面/共情表情很少（飞书 API 就放行 `Sigh`/`Salute` 这类），但方向对了比数量重要。
- **完成收尾**：回完信后把临时标记（OnIt+Typing）换成 `DONE`(绿勾)，情绪表情保留当氛围：
  ```bash
  bash "${WAGA_DIR}/waga-react.sh" done <mid>
  ```
- ⚠ **emoji_type 大小写敏感、是 key 一部分**：`Fire`✓ `FIRE`✗（返 231001）。连发太快也会 231001 → 用 helper 自带限速。一条消息上限 ~10 个。**别信 WebFetch 文档小模型瞎编的清单**，靠 `reactions list` 回读验证。
- 已实证调色板：`OnIt DONE Typing` / `THUMBSUP CLAP APPLAUSE MUSCLE` / `LAUGH SMILE JOYFUL PARTY Fire WOW` / `HEART LOVE MeMeMe Get OK HUSKY`（详见 waga-react.sh 头注释）。

## 注意

- **Waga/lark-cli 自己开不了终端、启动不了 Claude Code**，只能驱动已开着的会话 → 用户出门前要先把当天要用的窗口都开好、各自 `/waga-on` 起名。关窗口=Monitor 自动失效，无残留；改名=同窗口重跑 `/waga-on <新名>`。
- **用户要远程「起个新 session」时**：跑 `bash "${WAGA_DIR}/waga-spawn.sh" <名字> "初始任务" "<工作目录>"`（后台），拉起一个 headless worker（`claude -p --resume` 保持上下文，自己收发飞书）。需用户预先在 settings.json 手动加 `Bash(bash "…/waga-spawn.sh"*)` 允许规则（带 `--dangerously-skip-permissions`，Claude 不能自我授权）。worker 用 `<名字>: /stop` 远程关闭。
- token 过期时（一般每 ~7 天）监听器会喷 `[WAGA-ERR]`，让用户跑 `lark-cli auth login --domain all` 重新扫码
- 一个 session 一个 NAME；如果用户在两个窗口跑了同 name 的 waga-on，他们都会响应同前缀消息（不致命但容易让用户糊涂），通过上线回执用户能立刻发现重名
