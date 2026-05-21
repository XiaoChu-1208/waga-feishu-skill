<div align="center">

# Waga · 用飞书远程指挥 Claude Code

**把跑在你电脑上的 [Claude Code](https://claude.com/claude-code) 变成一个能用飞书私聊远程操控的 AI 智能体** —— 人在外面，手机一条消息就能精准呼叫某个会话干活、看进度、收报告。

*Drive Claude Code remotely from Feishu / Lark IM — like [OpenClaw](https://github.com/) or Hermes, but for Claude Code, powered by `lark-cli`.*

`Claude Code` · `Feishu` · `Lark` · `飞书` · `remote agent` · `mobile control` · `lark-cli` · `IM bot` · `slash command` · `multi-session routing` · `message reactions`

</div>

---

## 这是什么 / What it is

Waga 是一个 **Claude Code slash-command skill**（`/waga-on`）。挂上之后，你的每个 Claude Code 会话都会盯着同一个飞书机器人私聊，**只响应带自己名字前缀的消息**。于是你可以：

- 人在地铁上，用手机飞书发一句「`build 跑一下`」，电脑上的 Claude Code 就开工；
- 同时开三四个会话（前端、后端、文档…），用 `c:` / `web:` 精准点名其中一个，其余不抢答；
- 隔着飞书也能看到进度：消息一被接走，气泡上自动冒出「处理中」表情，干完变绿勾。

> 一句话定位：**Waga = 把 Claude Code 当 OpenClaw / Hermes 那样的远程 IM 智能体来用**。核心是给 `lark-cli`（飞书命令行）套一层会话路由 + 状态反馈，让「远程操控本地 AI coding agent」这件事在飞书里变顺。

## 为什么需要它 / Why

Claude Code 很强，但它跑在你的电脑上、绑在终端里。你一旦离开座位，它就停摆了。市面上 OpenClaw、Hermes 这类工具把 AI agent 接进 IM 实现远程操控——Waga 做的是同一件事，但**专门面向 Claude Code + 飞书**，而且：

- **零额外服务**：不用部署 server、不用 webhook 公网回调，就是一段挂在 Claude Code 后台的 Monitor 脚本 + `lark-cli` 长轮询。
- **多会话精准路由**：手机友好的冒号语法，一个 bot 管多个会话互不打架。
- **情绪化的气泡反馈**：仿 OpenClaw 的消息 reaction，且情绪会**呼应你当下的心情**（你急它致歉、你乐它跟着乐）。

---

## 功能亮点 / Features

| | |
|---|---|
| 🎯 **多会话精准路由** | 一个飞书 bot，多个 Claude Code 会话各认各的前缀，`c:` / `web:` 点名互不干扰 |
| 📱 **手机友好语法** | 冒号一统「切换/一次性」，中英文冒号都认，全角 `：` 也行，单手可打 |
| 📌 **粘性目标** | `c:` 单独发一条就把后续无前缀消息都粘到 c，长聊不用每条加前缀 |
| 💓 **心跳 + /who** | 每个会话写心跳文件，`/who` 一键报数（谁在线、哪个目录、多久没动静） |
| 🤖 **气泡 reaction** | 消息被接走自动贴「处理中」，干完换绿勾，远程可见状态 |
| ❤️ **情绪呼应** | 读完消息按你心情贴表情：开心→庆祝、愤怒→致歉、沮丧→安慰，不是乱贴 |
| 🏷️ **可换皮** | 一条命令把 `Waga` 整套改名成你自己的品牌（`/ali-on` / `/bilu-on`） |
| 🔒 **零硬编码** | 所有账号信息走环境变量，仓库里不含任何私密标识 |

---

## 前置条件 / Prerequisites

### 1. 一个飞书自建机器人

去 [飞书开放平台](https://open.feishu.cn/) 建企业自建应用，开通机器人能力，拿到 `App ID` / `App Secret`。需要的权限：

- `im:message`（收发消息）
- `im:message:readonly`（读会话历史）
- `im:message.reaction`（给消息打表情，reaction 功能需要）

把机器人加进**你和它的单聊**（P2P 会话）。

### 2. lark-cli（飞书命令行）

Waga 所有飞书交互都通过 [`lark-cli`](https://github.com/) 完成。先安装并以 **bot 身份**登录：

```bash
lark-cli auth login --domain all     # 扫码授权；token 约 7 天过期，过期重跑
```

### 3. 三个环境变量

脚本全部从环境变量读配置，**不硬编码**：

| 变量 | 含义 |
|---|---|
| `WAGA_CHAT_ID` | 你和 bot 私聊的 `chat_id`（`oc_` 开头） |
| `WAGA_USER_ID` | 你自己的 `open_id`（`ou_` 开头，回信发给谁） |
| `WAGA_DIR` | 本仓库脚本所在目录 |

写进 shell profile：

```bash
export WAGA_CHAT_ID="oc_xxxxxxxxxxxx"
export WAGA_USER_ID="ou_xxxxxxxxxxxx"
export WAGA_DIR="$HOME/path/to/waga-feishu-skill"
export LARK_CLI_NO_PROXY=1     # lark-cli 走系统代理易被 reset，强制直连
```

**怎么拿 ID**：和 bot 互发一条消息后列会话历史，里面就有 `chat_id` 和你的 `open_id`：

```bash
lark-cli im +chat-list --as bot --jq '.data.items[] | {chat_id, name}'
lark-cli im +chat-messages-list --chat-id "<oc_...>" --as bot \
  --jq '.data.messages[] | {sender: .sender.id, type: .sender.sender_type}'
```

---

## 安装 / Install

把 `waga-on.md` 放进 Claude Code 命令目录，它就成了 `/waga-on`：

```bash
cp waga-on.md ~/.claude/commands/waga-on.md
chmod +x waga-reply.sh waga-react.sh
```

---

## 用法 / Usage

### 挂载

在某个 Claude Code 会话里：

```
/waga-on            # name = 当前目录名
/waga-on c          # 自定义 name（手机上 1-2 字符最省事）
```

挂上后立刻往飞书发上线回执（name + cwd + 时间）。同一会话再 `/waga-on <新名>` 是**改名**（先停旧的再挂新的），不叠加。

### 飞书侧路由语法（手机友好）

冒号一统天下，靠**冒号后有没有内容**区分「切粘性」和「一次性」。中英文冒号都认。

| 用法 | 例子 | 含义 |
|---|---|---|
| **无前缀** | `你看看 build.bat` | 发给当前粘性目标会话（默认 `main`） |
| **粘性切换** | `c:` / `c：`（单独一条） | 把粘性目标切到 `c` |
| **冒号一次性** | `c: 跑下测试` | 只这一条给 c |
| **方括号一次性** | `[c] 跑下测试` | 同上，PC 习惯 |
| **全员报数** | `/who` | 列出所有在线会话（含 cwd、心跳新鲜度） |

最常用：想找 `c` 长聊 → 发 `c：` → 之后随便说啥都到 c → 发 `main：` 切回去。

### 气泡 reaction 与情绪呼应

- **自动状态标记**：消息被路由到某会话，瞬间贴 `OnIt`(处理中) + `Typing`(打字)，纯状态。
- **情绪呼应**：会话读完消息后**判断你的情绪并呼应**——你开心它庆祝、你愤怒它致歉、你沮丧它安慰，不是随便贴。
- **完成收尾**：回完信把状态标记换成 `DONE`(绿勾)，情绪表情保留当氛围。

```bash
bash "$WAGA_DIR/waga-react.sh" vibe <mid> "LAUGH JOYFUL Fire CLAP"   # 按情绪贴一串
bash "$WAGA_DIR/waga-react.sh" done <mid>                            # 收尾换绿勾
```

> ⚠ 飞书 `emoji_type` **大小写敏感、是 key 的一部分**：`Fire` 有效、`FIRE` 报 `231001`。连发太快也会 231001（helper 自带限速）。一条消息上限约 10 个。可用调色板见 `waga-react.sh` 头注释；负面/共情表情飞书放行得少（基本 `Sigh`/`Salute`），方向对齐比数量重要。

### 回信

```bash
bash "$WAGA_DIR/waga-reply.sh" <name> "<回复内容>"   # 自动加 [name] 前缀、设 NO_PROXY
```

---

## 换皮改名 / Rebrand

不喜欢叫 Waga？一条命令全套改名（命令名、脚本名、事件标记、临时文件、环境变量）：

```bash
bash rebrand.sh ali        # /waga-on → /ali-on，WAGA_CHAT_ID → ALI_CHAT_ID …
bash rebrand.sh Bilu
```

改完记得：① 重设 `<新名大写>_CHAT_ID` 等环境变量；② 装进 `~/.claude/commands/` 的那份也改名成 `<新名>-on.md`（命令名 = 文件名）。

---

## 工作原理 / How it works

- 每个会话跑一个独立后台 **Monitor**，长轮询飞书私聊历史（`lark-cli im +chat-messages-list`，~15s 一轮）。
- `/tmp/waga_seen_<name>.txt` 去重；`/tmp/waga_sticky.txt` 存共享粘性目标；`/tmp/waga_alive_<name>.txt` 写心跳供 `/who` 判活。
- 命中给本会话的消息 → 先贴状态 reaction → emit `[WAGA-MSG]` 事件唤醒会话。
- 会话关闭 = Monitor 死 = 自动注销，无残留。

详见 [`waga-on.md`](./waga-on.md)。

## 注意 / Caveats

- **代理**：`lark-cli` 走系统代理易被 reset，所有调用前设 `LARK_CLI_NO_PROXY=1`（helper 已内置）。
- **token 过期**：约每 7 天，监听器喷 `[WAGA-ERR]`，重跑 `lark-cli auth login --domain all`。
- **一会话一 name**：两个窗口挂同名会都响应（通过上线回执能立刻发现）。
- **隐私**：`WAGA_CHAT_ID` / `WAGA_USER_ID` 是你私人的飞书标识，只进环境变量，别提交进仓库。

---

## FAQ

**Q: 跟 OpenClaw / Hermes 有什么关系？**
A: 思路一样——把 AI agent 接进 IM 远程操控。Waga 专做 **Claude Code + 飞书**，更轻（无需部署服务），并加了多会话路由和情绪化反馈。

**Q: 必须用 Claude Code 吗？**
A: skill 形态是给 Claude Code 的。但 `waga-on.md` 里那段挂载脚本是普通 bash，可单独跑，只是少了「事件唤醒会话」那层。

**Q: 支持飞书国际版 Lark 吗？**
A: 支持，`lark-cli` 同时覆盖飞书与 Lark；建机器人和拿 ID 的流程一致。

**Q: 会泄露我的聊天/账号吗？**
A: 不会。所有账号标识走环境变量，仓库零硬编码。

---

## 文件清单 / Files

| 文件 | 作用 |
|---|---|
| `waga-on.md` | skill 本体：`/waga-on` 说明 + 挂载用的 Monitor 脚本 |
| `waga-reply.sh` | 回信 helper |
| `waga-react.sh` | 气泡表情 helper：`add` / `done` / `clear` / `vibe` |
| `rebrand.sh` | 一键换皮改名 |

## License

[MIT](./LICENSE)

---

<div align="center">
<sub>Keywords: Claude Code Feishu integration · control Claude Code from Lark · 飞书远程操控 Claude Code · Claude Code mobile remote · lark-cli automation · Claude Code IM bot · OpenClaw / Hermes alternative for Claude Code · 用手机指挥 AI coding agent</sub>
</div>
