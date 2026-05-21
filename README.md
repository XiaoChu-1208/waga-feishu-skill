# Waga · 飞书 ↔ Claude Code 远程路由 skill

用**飞书私聊**远程指挥跑在电脑上的 [Claude Code](https://claude.com/claude-code) 会话——人在外面，手机一条消息就能精准呼叫某一个 session，让它干活、收报告。多个 session 同时挂载互不打架。

还附带 **OpenClaw 同款气泡 reaction**：消息一被接走，对应气泡上自动冒出「处理中」表情，干完换成绿勾，远程也能直观看到进度。

> 这是一个 Claude Code 的 **slash-command skill**（`/waga-on`）。核心是一段挂在 Claude Code 后台的 Monitor 脚本，长轮询飞书私聊、按前缀把消息路由到对应会话。

---

## 它解决什么问题

Claude Code 跑在你的电脑上，但你出门了。你想用手机让它：
- 「去把那个 build 跑一下」
- 「capstoryboard 那个会话，帮我看下报错」
- 同时开着三四个 session，想精准点名其中一个，而不是让所有会话一起抢答。

挂上 `/waga-on` 后，每个会话各自盯着同一个飞书 bot 私聊，只认带自己 name 前缀的消息。你在飞书发 `csb: 跑下测试`，就只有名叫 `csb` 的会话响应。

---

## 前置条件

### 1. 一个飞书自建机器人（bot）

去 [飞书开放平台](https://open.feishu.cn/) 建一个企业自建应用，开通机器人能力，拿到 `App ID` / `App Secret`。需要的权限（scope）：

- `im:message`（收发消息）
- `im:message.group_at_msg` / `im:message:readonly`（读会话历史）
- `im:message.reaction`（给消息打表情，reaction 功能需要）

把机器人加进**你和它的单聊**（P2P 会话）。

### 2. lark-cli（飞书命令行工具）

本 skill 所有飞书交互都通过 `lark-cli`。需要先安装并以 **bot 身份**登录授权：

```bash
lark-cli auth login --domain all     # 扫码授权；token 一般 ~7 天过期，过期重跑即可
```

> lark-cli 是飞书官方/社区的 CLI（提供 `lark-cli im +messages-send`、`im reactions` 等子命令）。请按你获取到的渠道安装。

### 3. 三个环境变量

挂载脚本和 helper 都从环境变量读配置，**不硬编码**任何账号信息：

| 变量 | 含义 | 怎么拿 |
|---|---|---|
| `WAGA_CHAT_ID` | 你和 bot 私聊的 `chat_id`（`oc_` 开头） | 见下方「拿 ID」 |
| `WAGA_USER_ID` | 你自己的 `open_id`（`ou_` 开头，回信发给谁） | 见下方「拿 ID」 |
| `WAGA_DIR` | 本仓库脚本所在目录（含 `waga-reply.sh` / `waga-react.sh`） | 你 clone 的路径 |

建议写进 shell profile（`.bashrc` / `.zshrc` / PowerShell `$PROFILE`）：

```bash
export WAGA_CHAT_ID="oc_xxxxxxxxxxxxxxxx"
export WAGA_USER_ID="ou_xxxxxxxxxxxxxxxx"
export WAGA_DIR="$HOME/path/to/waga-feishu-skill"
export LARK_CLI_NO_PROXY=1     # 见下方「注意 · 代理」
```

#### 拿 ID

和 bot 互发一条消息后，列一下会话历史，里面就有 `chat_id` 和你的 `open_id`：

```bash
# 找 chat_id：列出 bot 所在的单聊
lark-cli im +chat-list --as bot --jq '.data.items[] | {chat_id, name, chat_mode}'

# 找你自己的 open_id：在那个 chat 里发条消息，然后看历史里 sender 的 id
lark-cli im +chat-messages-list --chat-id "<上一步的 oc_...>" --as bot \
  --jq '.data.messages[] | {sender: .sender.id, type: .sender.sender_type}'
```

---

## 安装为 Claude Code skill

把 `waga-on.md` 放进 Claude Code 的命令目录，它就会作为 `/waga-on` 出现：

```bash
# 用户级（所有项目可用）
cp waga-on.md ~/.claude/commands/waga-on.md
# 脚本留在仓库里即可，靠 $WAGA_DIR 引用；确保可执行
chmod +x waga-reply.sh waga-react.sh
```

> 不用 Claude Code 也能用：`waga-on.md` 里那段挂载脚本是普通 bash，可单独跑；只是没有「事件唤醒会话」那层，需要自己读 `[WAGA-MSG]` 输出。

---

## 用法

### 挂载

在某个 Claude Code 会话里：

```
/waga-on            # name = 当前目录 basename
/waga-on csb        # 自定义 name（手机上 1-2 字符最省事：m / c / w / csb）
```

挂上后会立刻往飞书发两条上线回执（name + cwd + 时间 + 用法提示），你在飞书侧就能看到「这个 name 对应哪个目录的会话」。

同一会话再次 `/waga-on <新名>` 是**改名**（先停旧监听再挂新的），不会叠加。

### 飞书侧路由语法（手机友好）

冒号一统天下，靠**冒号后有没有内容**区分「切粘性」和「一次性」。中英文冒号都认（手机中文键盘默认出全角 `：`）。

| 用法 | 例子 | 含义 |
|---|---|---|
| **无前缀** | `你看看 build.bat` | 发给「当前粘性目标」会话（默认 `main`） |
| **粘性切换** | `c:` 或 `c：`（单独一条） | 把粘性目标切到 `c`，之后无前缀消息都到 c |
| **冒号一次性** | `c: 帮我跑测试` | 只这一条给 c，不改粘性目标 |
| **方括号一次性** | `[c] 帮我跑`（PC 习惯） | 同冒号一次性 |
| **全员报数** | `/who` | 列出所有在线会话（含 cwd、心跳新鲜度） |

最常用：手机想找 `c` 长聊 → 发 `c：` → 之后随便说啥都自动到 c → 想切回去发 `main：`。

### 气泡 reaction（处理中 / 完成 / 生动）

- **自动开工标记**：消息一被路由到某会话，监听器立刻给那条**气泡本身**贴 `OnIt`（处理中），无需手动。
- **完成收尾**：会话回完信后把 `OnIt` 换成 `DONE`（绿勾）：
  ```bash
  bash "$WAGA_DIR/waga-react.sh" done <message_id>
  ```
- **生动模式**：根据消息情绪贴一串表情（≤10，自动限速）：
  ```bash
  bash "$WAGA_DIR/waga-react.sh" vibe <message_id> "THUMBSUP Fire PARTY LAUGH"
  ```

`message_id` 从监听器推送的 `[WAGA-MSG] <时间> [mid=om_xxx] :: <内容>` 那行取。

> ⚠ **emoji_type 大小写敏感、是 key 的一部分**：`Fire` 有效、`FIRE` 报 `231001 invalid`。连发太快也会触发 231001，所以 helper 自带 0.6s 限速。一条消息 reaction 上限约 10 个。**别信网页文档里 LLM 总结的表情清单**（容易瞎编对不上），以真机 `lark-cli im reactions list` 回读为准。
>
> 实证可用调色板：`OnIt DONE Typing` · `THUMBSUP CLAP APPLAUSE MUSCLE` · `LAUGH SMILE JOYFUL PARTY Fire WOW` · `HEART LOVE MeMeMe Get OK HUSKY`（详见 `waga-react.sh` 头注释）。

### 回信

会话给飞书回话用 helper（自动加 `[name]` 前缀、自动设 `LARK_CLI_NO_PROXY=1`）：

```bash
bash "$WAGA_DIR/waga-reply.sh" <name> "<回复内容>"
```

---

## 工作原理

- 每个会话跑一个独立的后台 **Monitor**，长轮询飞书私聊历史（`lark-cli im +chat-messages-list`，~15s 一轮）。
- 用 `/tmp/waga_seen_<name>.txt` 记已处理消息去重；`/tmp/waga_sticky.txt` 存共享的粘性目标（初始 `main`）。
- 每轮写心跳 `/tmp/waga_alive_<name>.txt`（`epoch|name|cwd`），`/who` 据此判断谁活着（35s 内有心跳=活）；文件锁保证一条 `/who` 只一个会话应答、不刷屏。
- 命中给本会话的消息时，先贴 `OnIt` reaction，再 emit `[WAGA-MSG]` 事件唤醒会话。
- 会话关闭 = Monitor 死 = 自动注销，无残留。

详细脚本见 [`waga-on.md`](./waga-on.md)。

---

## 注意

- **代理**：`lark-cli` 走系统代理时容易被 reset，所有调用前设 `LARK_CLI_NO_PROXY=1`（helper 已内置）。
- **token 过期**：一般每 ~7 天，监听器会喷 `[WAGA-ERR]`，重跑 `lark-cli auth login --domain all` 扫码即可。
- **一个会话一个 name**：两个窗口挂了同名 `waga-on` 会都响应同前缀消息（不致命，但通过上线回执能立刻发现重名）。
- **隐私**：`WAGA_CHAT_ID` / `WAGA_USER_ID` 是你私人的飞书标识，只放进环境变量、别提交进仓库或贴公开处。

---

## 文件清单

| 文件 | 作用 |
|---|---|
| `waga-on.md` | skill 本体：`/waga-on` 说明 + 挂载用的 Monitor 脚本 |
| `waga-reply.sh` | 回信 helper：加 `[name]` 前缀、设 NO_PROXY、发到飞书私聊 |
| `waga-react.sh` | 气泡表情 helper：`add` / `done` / `clear` / `vibe` |

## License

MIT
