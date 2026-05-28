<div align="center">

# Waga · 用飞书远程指挥 Claude Code

**把跑在你电脑上的 [Claude Code](https://claude.com/claude-code) 变成一个能用飞书私聊远程操控的 AI 智能体** —— 人在外面，手机一条消息就能精准呼叫某个会话干活、看进度、收报告。

*Drive Claude Code remotely from Feishu / Lark IM — like [OpenClaw](https://github.com/) or Hermes, but for Claude Code, powered by `lark-cli`.*

`Claude Code` · `Feishu` · `Lark` · `飞书` · `remote agent` · `mobile control` · `lark-cli` · `IM bot` · `slash command` · `multi-session routing` · `message reactions`

</div>

---

## 这是什么 / What it is

一句话：**Waga 让你用飞书私聊，从手机精准指挥电脑上的某一个 Claude Code 会话。**

挂上 `/waga-on` 后，你的每个 Claude Code 会话都盯着同一个飞书机器人，**只响应开头带自己名字的消息**（这个开头的名字就叫「前缀」，比如 `web:` 里的 `web`）。于是人在外面也能：

- 用手机飞书发一句「`build 跑一下`」，电脑上对应的 Claude Code 就开工；
- 同时开几个会话（前端、后端、文档…），用 `c:` / `web:` 精准点名其中一个，其余不抢答；
- 隔着飞书看到进度：消息一被接走，气泡上自动冒出「处理中」表情，干完变绿勾；
- **甚至人在外面、电脑前没人，也能让 Claude 远程新起一个会话来干活**（见下方「如何拉起新 session · 方式 B」，需提前做一次性设置）。

## 既然 lark-cli 已经能驱动 Claude Code，为什么还要 Waga？

这是最该说清的一点。

**单个会话**：其实你光用 `lark-cli` 让一个 Claude Code 会话收发飞书消息就够了，不需要 Waga。

**问题出在多窗口**：当你同时开了三四个 Claude Code 窗口，飞书那头**没法分辨该把消息交给哪一个**——它们要么全抢答，要么你根本点不到指定的那个。

**Waga 就是补这一层**：用 `/waga-on <名字>` 给每个会话起个名，一个 bot 就能同时跟多个会话协作、各干各的，互不打架。外加状态/情绪气泡反馈，让远程操控顺手。

> 类比：把 Claude Code 当 [OpenClaw](https://github.com/) / Hermes 那样的远程 IM 智能体来用——Waga 给 `lark-cli` 套了一层**多会话路由 + 状态反馈**。

## Waga 在原生 lark-cli 之上补了什么 / What Waga adds over raw lark-cli

根本区别：**`lark-cli` 是一次性命令**（跑一次 = 一次 API 调用），**Waga 把它变成常驻事件流 + 多会话编排**。

| 能力 | 原生 lark-cli | Waga |
|---|---|---|
| **常驻消息泵** | ❌ 一次性命令，不持续监听 | ✅ Monitor 长轮询 + 去重(SEEN) + 命中就**唤醒对应会话**——把被动 CLI 变主动事件流 |
| **多会话路由** | ❌ 无会话概念 | ✅ 一个 bot 管多个 Claude Code 窗口，前缀精准点名互不抢答 |
| **粘性目标** | ❌ | ✅ 无前缀消息自动归当前会话，手机长聊不用每条加前缀 |
| **手机友好语法** | ❌ | ✅ 冒号统一切换/一次性，中英文全角冒号都认 |
| **在线探活** | ❌ | ✅ 心跳文件 + `/who` 报谁在线/哪个目录/多久没动静（文件锁防刷屏） |
| **状态气泡** | ⚠ 只有原始 reactions API | ✅ 自动 `OnIt`(处理中)→`DONE`(绿勾) 状态机 |
| **情绪呼应** | ❌ | ✅ 按你当下情绪贴表情（怒→致歉、喜→庆祝），实证调色板+情绪映射 |
| **会话生命周期** | ❌ | ✅ 关窗=Monitor 自动注销、同窗重跑=覆盖改名 |
| **回信纪律** | ❌ | ✅ helper 强制 `[name]` 前缀 + `NO_PROXY` + 「必须发飞书别只在 UI 写」 |

一句话：**lark-cli 给的是『能力原料』，Waga 给的是『把多个 Claude Code 会话变成可远程精准调度的助手群』这套成品编排。**

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
| 🪧 **流式 / 进度卡片** | 回复与干活进度刷在一张飞书交互卡片上实时更新（蓝运行/绿完成/红失败 + 工具调用），不再发一串刷屏文本（`waga-card.py` / `waga-stream.py`，借鉴 [feishu-claude-code-bridge](https://github.com/zarazhangrui/feishu-claude-code-bridge)） |
| ↩️ **引用回复路由** | 在飞书里「引用」某个会话发的卡片回复，自动路由到那个会话并切粘性，连前缀都不用打 |
| 🤖 **两层 reaction** | 状态层 `Typing→DONE`（处理中/完成，远程可见）+ 情绪层（读完按你心情亲贴一组真实表情） |
| ❤️ **情绪呼应** | 情绪层每次按内容现挑、像人一样贴 2-4 个、绝不随机/复读：开心→庆祝、愤怒→致歉、沮丧→安慰 |
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

- **lark-cli**：飞书官方 CLI。装 + `lark-cli config init`（配好 App ID/Secret）即可。Waga 全程走 **bot 身份**（`--as bot`），**不需要 `lark-cli auth login`**（那是用户身份、访问个人资源才用）。
- **Claude Code CLI**：`claude`，spawn worker / 流式卡片靠它的 `-p --output-format stream-json`。
- **Python 3**（仅卡片功能 `waga-card.py` / `waga-stream.py` 用）：脚本一律用 `py` 启动器跑（Windows 上 `python` 常被 WindowsApps 桩占用）。卡片正文用 `<font color>` 上色，Windows 下 Python 调 `lark-cli.CMD` 时 `<>` 会被 cmd 当重定向符——脚本已自动改用 `node` 直跑 lark-cli 的 JS 绕过，无需你操心。
- **配置放在仓库目录下的 `.env`**（已 gitignore，绝不上传）。所有脚本（`reply`/`react`/`card`/`spawn`/`doctor`）**以及 `/waga-on`** 都会自动 `source` 它，所以 **shell profile 里只需 export 一个 `WAGA_DIR`**：

| 变量 | 放哪 | 含义（大白话） |
|---|---|---|
| `WAGA_CHAT_ID` | `.env` | 你和机器人那个**对话框的编号**（`oc_` 开头）——消息从哪读 |
| `WAGA_USER_ID` | `.env` | 你这个人在飞书里的**身份编号**（`open_id`，`ou_` 开头）——回信发给谁 |
| `WAGA_DIR` | `.env` ＋ **shell profile** | 本仓库脚本所在目录；`/waga-on` 靠它找到 `.env` |

仓库目录下的 `.env`（`waga-setup.md` 会帮你写好）：
```bash
export WAGA_CHAT_ID="oc_xxxxxxxxxxxx"
export WAGA_USER_ID="ou_xxxxxxxxxxxx"
export WAGA_DIR="$HOME/path/to/waga-feishu-skill"
export LARK_CLI_NO_PROXY=1     # lark-cli 走系统代理易被 reset，强制直连
```

然后**只把 `WAGA_DIR` 放进 shell profile**（macOS = `~/.zshrc`，Linux = `~/.bashrc`，Windows PowerShell = `$PROFILE`），`/waga-on` 就能自动 `source $WAGA_DIR/.env` 拿到其余变量，不必把 ID 在两处重复维护：
```bash
echo 'export WAGA_DIR="$HOME/path/to/waga-feishu-skill"' >> ~/.zshrc
echo 'export LARK_CLI_NO_PROXY=1' >> ~/.zshrc
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

先解释「粘性目标」：它就是**当前默认接活的那个会话**。你发的消息如果开头没带名字，就自动归给这个「粘性目标」处理——省得每条都打前缀。

冒号一统天下，靠**冒号后有没有内容**区分「切粘性」（换默认接活的人）和「一次性」（只这一条临时给某人）。中英文冒号都认。

| 用法 | 例子 | 含义 |
|---|---|---|
| **无前缀** | `你看看 build.bat` | 发给当前粘性目标会话（默认 `main`） |
| **粘性切换** | `c:` / `c：`（单独一条） | 把粘性目标切到 `c` |
| **冒号一次性** | `c: 跑下测试` | 只这一条给 c |
| **方括号一次性** | `[c] 跑下测试` | 同上，PC 习惯 |
| **全员报数** | `/who` | 列出所有在线会话（含 cwd、心跳新鲜度） |

最常用：想找 `c` 长聊 → 发 `c：` → 之后随便说啥都到 c → 发 `main：` 切回去。

### 气泡 reaction：两层设计

- **状态层**：`Typing`(处理中) → 回完换 `DONE`(绿勾)。固定的，纯状态显示，远程可见「在处理/已处理」。
- **情绪层（核心）**：会话**读完消息、判断你当下情绪后亲贴一组（常 2-4 个）真实表情**——你开心它庆祝、你愤怒它致歉、你沮丧它安慰。**绝不随机、绝不只贴一个、每次都不同**（随机/复读=糊弄，不是「活」）。

```bash
bash "$WAGA_DIR/waga-react.sh" vibe <mid> "JOYFUL Fire CLAP"   # 情绪层：按内容现挑一组
bash "$WAGA_DIR/waga-react.sh" done <mid>                      # 状态层：Typing 换 DONE
```

> ⚠ 飞书 `emoji_type` **大小写敏感、是 key 的一部分**：`Fire` 有效、`FIRE` 报 `231001`。连发太快也会 231001（helper 自带限速）。一条消息上限约 10 个。可用调色板见 `waga-react.sh` 头注释；负面/共情表情飞书放行得少（基本 `Sigh`/`Salute`），方向对齐比数量重要。

### 回信

```bash
bash "$WAGA_DIR/waga-reply.sh" <name> "<回复内容>"   # 自动加 [name] 前缀、设 NO_PROXY
```

---

## 如何拉起一个新 session（多种方式）

先分清两种「session」：

- **交互式会话**：一个你能看到、能在窗口里继续打字操作的 Claude Code（就是你平时用的那种）。
- **headless worker**：没有界面、在后台默默跑的 Claude。（headless = 无头 = 没有界面）。它自己收发飞书消息、自己干活，你看不到窗口，全靠飞书跟它沟通。

下面 4 种方式，**方式 B 最重要**——它是你人在外面、电脑前没人时，唯一能新起一个会话的办法。

| 方式 | 类型 | 在哪触发 | 适用 |
|---|---|---|---|
| A. 开窗口 + `/waga-on` | 交互式 | 电脑前 | 最常规；出门前把当天要用的都开好 |
| **B. 飞书一句话让 Claude 远程起** ⭐ | headless | **飞书（远程）** | **人在外面、电脑前没人——唯一可行的远程起法** |
| C. 命令行起 worker | headless | 任意终端 | 在电脑前、不想占一个窗口 |
| D. `!` 前缀起 worker | headless | Claude Code 输入框 | 已经在一个会话里，顺手起一个 |

---

### 方式 A · 开窗口 + `/waga-on`（交互式，最常规）

在电脑上**新开一个 Claude Code 窗口/标签**（终端里再跑一个 `claude`，或 IDE 里开一个），然后：

```
/waga-on api          # 起名 api
```

- 这是完整交互会话，你能看到界面、随时接管。
- ⚠ Waga 自己开不了窗口，所以这种方式**必须你人在电脑前**。出门前把当天要用的窗口都开好、各自 `/waga-on` 起名。

---

### 方式 B · 飞书一句话，让 Claude 远程起 ⭐（人在外面用这个，最重要）

人在外面、电脑前没人，也能新起一个会话干活。对任意一个**已经挂着的** Waga 会话，在飞书说一句大白话，Claude 就会去跑 `waga-spawn.sh` 帮你起一个新的 headless worker：

```
waga: 起个新 session 叫 api，去 /path/to/proj 干「把测试跑一遍」
```

它起好后，这个叫 `api` 的 worker 就常驻后台，你再用 `[api] xxx` 给它派活（见下方「给 worker 派活」）。

#### ⚠ 方式 B 的一次性前置：加一条权限规则（必须你本人在电脑前做一次，做完永久生效）

**为什么要加**：headless worker 没有界面，弹不出「是否允许执行这条命令」的确认框，所以它得带一个开关 `--dangerously-skip-permissions`（大白话：**让它干活时不用每次都问你同意**，因为后台没界面没法问你）。而 Claude Code 出于安全，**不允许 AI 自己给自己开这个开关**，也不允许 AI 偷偷改配置来绕过——所以这条规则**只能你本人手动加**。

**第 1 步：找到配置文件 `settings.json`**。它在你家目录下的 `.claude` 文件夹里（`~` 就是「你的家目录」的简写）。完整路径按系统：

| 系统 | `settings.json` 完整路径 |
|---|---|
| **Windows** | `C:\Users\你的用户名\.claude\settings.json` |
| **macOS** | `/Users/你的用户名/.claude/settings.json` |
| **Linux** | `/home/你的用户名/.claude/settings.json` |

> 把「你的用户名」换成你电脑的登录名。`.claude` 前面有个点，是隐藏文件夹。文件不存在就新建一个。

**第 2 步：在里面的 `permissions.allow` 列表加一条规则**。改完大概长这样（把路径换成你 clone 本仓库的真实位置）：

```jsonc
{
  "permissions": {
    "allow": [
      "Edit",
      "Bash",
      "Bash(bash \"/你clone的路径/waga-feishu-skill/waga-spawn.sh\"*)"
    ]
  }
}
```

> ⚠ 光写宽泛的 `"Bash"` **不够**——Claude Code 有一层「意图审查」会拦下「自动跳过权限的后台 agent」，必须是上面这条**精确指向 waga-spawn.sh 的规则**才放行。
>
> 因为加规则得在电脑前，所以方式 B 是「**桌前花一分钟设置好，之后随时在外面远程用**」。

---

### 方式 C · 命令行直接起 headless worker（在电脑前时）

任意终端（Git Bash）里：

```bash
bash "$WAGA_DIR/waga-spawn.sh" <名字> "初始任务(可留空)" "/工作目录"
# 例：
bash "$WAGA_DIR/waga-spawn.sh" api "看下 api 目录有没有 lint 错误" "$HOME/proj"
```

worker 后台常驻，监听 `[名字]` 的飞书消息，每条用 `claude -p --resume <固定session-id>` 处理（`claude -p` = 不开界面、跑一次就出结果的模式；`--resume <号>` = 接着同一个对话存档号聊，所以**记得上下文，跟正常会话一样**），结果发回飞书。

### 方式 D · `!` 前缀（已在一个 Claude Code 会话里时）

在 Claude Code 的输入框里直接敲（`!` 是输入框的本地执行前缀，敲了它会直接在本机跑这条命令）：

```
! bash "$WAGA_DIR/waga-spawn.sh" api "初始任务" "/工作目录"
```

> 注意：`!` 只在你**亲手在输入框敲**时有效；把 `! ...` 通过飞书发给 Claude 只是一段文字，不会执行。

---

### 给 worker 派活

不管哪种方式起的 worker，都用同一套飞书语法派活：

```
[api] 把测试跑一遍          # 一次性给 api
api: 看下 lint              # 同上
api:                        # 单独发一条，把粘性目标切到 api，之后无前缀都给它
```

### 关闭 worker

```
api: /stop                  # 远程：worker 收到后优雅下线退出
```

本地关闭：`touch /tmp/waga_stop_<名字>.txt`，或杀进程 `pkill -f "waga-spawn.sh <名字>"`。关掉即注销，无残留。

> 交互式会话（方式 A）的关闭就是关掉那个窗口，对应 Monitor 自动失效。

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

- 每个会话跑一个独立后台 **Monitor**（常驻后台小程序，负责盯飞书有没有新消息），每 ~15s 拉一次飞书私聊历史（`lark-cli im +chat-messages-list`）。
- `/tmp/waga_seen_<name>.txt` 记已处理的消息（防重复）；`/tmp/waga_sticky.txt` 存当前粘性目标；`/tmp/waga_alive_<name>.txt` 每轮写个时间戳当「心跳」，`/who` 靠它判断谁还活着。
- 命中给本会话的消息 → 先贴状态 reaction → emit `[WAGA-MSG]` 事件唤醒会话。
- 会话关闭 = Monitor 死 = 自动注销，无残留。

详见 [`waga-on.md`](./waga-on.md)。

## 换到新电脑 / 多台机器 / Moving to a new machine

⚠ **最容易误解的一点**：飞书 **App ID / App Secret 和登录 token 不在本仓库里**，也不会随同步盘（iCloud / Syncthing / Dropbox）走——它们存在 **lark-cli 自己的、每台机器独立的配置目录**（macOS: `~/.lark-cli/`）。仓库里的 `.env` 只有 `chat_id` / `open_id` / `WAGA_DIR` 三样。

所以换一台新电脑（哪怕仓库已经同步过去了），lark-cli 这一层要重做：

1. 装 lark-cli：`npx @larksuite/cli@latest install`
2. **接回同一个已有应用**（强烈推荐——旧的 `chat_id`/`open_id` 继续有效，无需重抓）：
   ```bash
   # 零浏览器：用已有应用的 App ID + Secret 直接配（Secret 走 stdin，不进进程列表）
   printf '%s' '<你的 App Secret>' | lark-cli config init --app-id <你的 App ID> --app-secret-stdin --brand feishu
   ```
   只有想**新建** app 时才用 `lark-cli config init --new`（浏览器流程）；但新 app 会让旧 `chat_id`/`open_id` 失配，得按 [`waga-setup.md`](./waga-setup.md) Step 3 重抓。
3. 验证 bot 通了：`lark-cli im +chat-messages-list --chat-id "$WAGA_CHAT_ID" --as bot --page-size 1`（返回 `"ok": true` 即可）。
4. 把 `.env` 里的 `WAGA_DIR` 改成新机器上仓库的真实路径，并在 profile 里 `export WAGA_DIR=...`。
5. 装命令 + 加执行权限（见上方「安装命令」），跑 `/waga-on` 测通。

> 💡 用 bot 身份收发消息**只需要 App ID + Secret**（`config init` 配好即可），**不需要 `auth login`**。`auth login`（用户身份）只有访问你个人日历/云盘/邮箱才用到，Waga 用不上。

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

**Q: 人在外面，能让 Claude 自己新起一个会话干活吗？**
A: 能，就是上面的「方式 B」。需要你**提前在电脑前加一条权限规则**（一次性，做完永久有效）。之后在飞书说一句「起个新 session 叫 X 干 Y」即可。

**Q: 让后台 worker 自动跳过权限确认，安全吗？**
A: 它带 `--dangerously-skip-permissions`（自动放行工具），等于给这个无人值守的会话放了权——能力强但也意味着它会自动执行你飞书发去的指令。Claude Code 特意要求这一步**由真人手动开**就是这个原因。只在你自己的机器、给自己用的场景下用，别把 bot 暴露给别人。

**Q: 会泄露我的聊天/账号吗？**
A: 不会。所有账号标识走环境变量，仓库零硬编码。

---

## 文件清单 / Files

| 文件 | 作用 |
|---|---|
| `waga-setup.md` | 一键 onboarding 剧本：让 Claude Code 帮你检测/装 lark-cli、引导授权、抓 ID、写配置（`/waga-setup`） |
| `waga-on.md` | skill 本体：`/waga-on` 说明 + 挂载用的 Monitor 脚本 |
| `waga-reply.sh` | 回信 helper（走内联蓝字卡片，自动登记卡片 mid 供引用回复路由） |
| `waga-react.sh` | 气泡表情 helper：`add` / `done` / `clear` / `vibe` |
| `waga-card.py` | 卡片 helper：`say`(蓝字消息卡) / `start`+`step`+`done`(步进进度卡) / `online`(上线卡)。需 Python 3，用 `py` 启动 |
| `waga-stream.py` | 流式卡片引擎：包 `claude -p --output-format stream-json` 跑，把过程实时刷到一张卡（spawn worker 用）。被 `waga-card.py` 复用渲染 |
| `waga-spawn.sh` | 远程 spawn 一个 headless waga worker（无需开窗口的新 Claude 会话），输出走流式卡片 |
| `rebrand.sh` | 一键换皮改名 |

## License

[MIT](./LICENSE)

---

<div align="center">
<sub>Keywords: Claude Code Feishu integration · control Claude Code from Lark · 飞书远程操控 Claude Code · Claude Code mobile remote · lark-cli automation · Claude Code IM bot · OpenClaw / Hermes alternative for Claude Code · 用手机指挥 AI coding agent</sub>
</div>
