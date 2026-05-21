<div align="center">

# Waga · 用飞书远程指挥 Claude Code

**把跑在你电脑上的 [Claude Code](https://claude.com/claude-code) 变成一个能用飞书私聊远程操控的 AI 智能体** —— 人在外面，手机一条消息就能精准呼叫某个会话干活、看进度、收报告。

*Drive Claude Code remotely from Feishu / Lark IM — like [OpenClaw](https://github.com/) or Hermes, but for Claude Code, powered by `lark-cli`.*

`Claude Code` · `Feishu` · `Lark` · `飞书` · `remote agent` · `mobile control` · `lark-cli` · `IM bot` · `slash command` · `multi-session routing` · `message reactions`

</div>

---

## 这是什么 / What it is

一句话：**Waga 让你用飞书私聊，从手机精准指挥电脑上的某一个 Claude Code 会话。**

挂上 `/waga-on` 后，你的每个 Claude Code 会话都盯着同一个飞书机器人，**只响应带自己名字前缀的消息**。于是人在外面也能：

- 用手机飞书发一句「`build 跑一下`」，电脑上对应的 Claude Code 就开工；
- 同时开几个会话（前端、后端、文档…），用 `c:` / `web:` 精准点名其中一个，其余不抢答；
- 隔着飞书看到进度：消息一被接走，气泡上自动冒出「处理中」表情，干完变绿勾。

## 既然 lark-cli 已经能驱动 Claude Code，为什么还要 Waga？

这是最该说清的一点。

**单个会话**：其实你光用 `lark-cli` 让一个 Claude Code 会话收发飞书消息就够了，不需要 Waga。

**问题出在多窗口**：当你同时开了三四个 Claude Code 窗口，飞书那头**没法分辨该把消息交给哪一个**——它们要么全抢答，要么你根本点不到指定的那个。

**Waga 就是补这一层**：用 `/waga-on <名字>` 给每个会话起个名，一个 bot 就能同时跟多个会话协作、各干各的，互不打架。外加状态/情绪气泡反馈，让远程操控顺手。

> 类比：把 Claude Code 当 [OpenClaw](https://github.com/) / Hermes 那样的远程 IM 智能体来用——Waga 给 `lark-cli` 套了一层**多会话路由 + 状态反馈**。

## ⚠ 一个重要前提：先开好窗口

Waga（和 lark-cli）**自己没法开终端、启动 Claude Code**。它只能驱动**已经开着**的会话。所以：

- **出门前，先把当天要用的 Claude Code 窗口都开好**，各自 `/waga-on` 起好名。
- 多开就起 `/waga-on 1`、`/waga-on 2`，或 `/waga-on web`、`/waga-on api` 这种有意义的名。
- **不用了**：像关任何窗口一样直接关掉，对应的后台 Monitor 自动失效，无残留。
- **想改名**：在同一个窗口重跑 `/waga-on <新名>` 即可（覆盖式，不会叠加）。

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

## 快速开始 / Quick start — 让 Claude Code 帮你配

**最省事的方式：clone 本仓库后，直接跟 Claude Code 说一句「帮我配 Waga」**（或把 [`waga-setup.md`](./waga-setup.md) 装成 `/waga-setup` 命令运行）。Claude 会按 `waga-setup.md` 的剧本：

1. 检测 / 安装 `lark-cli`（飞书官方 CLI [`larksuite/cli`](https://github.com/larksuite/cli)）
2. 跑 `lark-cli config init --new` —— **自带浏览器引导建应用**，你只需在那一步给 bot **起个名、换个头像**；不用去开放平台手动配权限或拿 App Secret
3. 跑 `lark-cli auth login --domain im` —— 把授权链接发给你，你点一下完成
4. 自动抓你和 bot 的 `chat_id` / 你的 `open_id`，写好环境变量
5. 装好 `/waga-on` 命令

**你全程只需要：** 点一次浏览器链接（建 app + 授权）→ 给 bot 起名换头像 → 在飞书给 bot 发条消息建立单聊。其余 Claude 全包。

> 💡 lark-cli 原生支持 OpenClaw / Hermes 的 agent workspace（检测到会用 `config bind` 绑定现有 app）。Waga 把这套能力对准了 Claude Code。

## 前置条件 / Prerequisites（手动配的话）

如果你想手动配、或了解底层依赖：

- **lark-cli**：飞书官方 CLI。装 + `lark-cli config init` + `lark-cli auth login --domain im` 即可，无需自建应用配 scope。
- **三个环境变量**（`waga-setup.md` 会帮你写好）：

| 变量 | 含义 |
|---|---|
| `WAGA_CHAT_ID` | 你和 bot 私聊的 `chat_id`（`oc_` 开头） |
| `WAGA_USER_ID` | 你自己的 `open_id`（`ou_` 开头，回信发给谁） |
| `WAGA_DIR` | 本仓库脚本所在目录 |

```bash
export WAGA_CHAT_ID="oc_xxxxxxxxxxxx"
export WAGA_USER_ID="ou_xxxxxxxxxxxx"
export WAGA_DIR="$HOME/path/to/waga-feishu-skill"
export LARK_CLI_NO_PROXY=1     # lark-cli 走系统代理易被 reset，强制直连
```

手动拿 ID：先在飞书给 bot 发条消息建立单聊，再 `lark-cli im +chat-list --as bot` 取 `chat_id`、`lark-cli im +chat-messages-list` 取你的 `open_id`。

## 安装命令 / Install the command

```bash
cp waga-on.md ~/.claude/commands/waga-on.md          # /waga-on
cp waga-setup.md ~/.claude/commands/waga-setup.md     # /waga-setup（可选）
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
| `waga-setup.md` | 一键 onboarding 剧本：让 Claude Code 帮你检测/装 lark-cli、引导授权、抓 ID、写配置（`/waga-setup`） |
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
