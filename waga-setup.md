---
description: 一键配好 Waga（飞书远程指挥 Claude Code）。检测/安装 lark-cli → 引导授权 → 自动抓 chat_id/open_id → 写好环境变量。用户全程只需点一次浏览器链接 + 给 bot 起名换头像。
---

# Waga 一键配置 · onboarding 剧本

> 这份文档是给 **Claude Code（你）** 执行的。用户说「帮我配 Waga」/ 运行 `/waga-setup` 时，按下面步骤一步步代他做，**能自动的全自动**，只有必须用户本人操作的（点浏览器授权、给 bot 起名换头像）才交给他，并把链接/提示直接发给他。

## 总原则

- 一切能由你（Claude Code）跑的命令都自己跑，别让用户手敲。
- 凡是 lark-cli 要弹浏览器授权的，用后台/`--no-wait` 拿到 URL，**把 URL 发给用户**，让他点完回来说一声，你再继续。
- 每一步做完简短告诉用户进度，别闷头跑。
- 所有 lark-cli 调用前 `export LARK_CLI_NO_PROXY=1`（走系统代理易被 reset）。

---

## Step 0 · 检测 lark-cli 是否已安装/已授权

```bash
export LARK_CLI_NO_PROXY=1
command -v lark-cli && lark-cli --version || echo "NOT_INSTALLED"
lark-cli auth status 2>&1 | head -5    # 已装的话看有没有授权
```

分支：
- **已装且已授权** → 跳到 Step 3（抓 ID + 写环境变量）。
- **已装未授权** → 跳到 Step 2（授权）。
- **没装** → Step 1。

## Step 1 · 安装 lark-cli（没装才做）

按官方方式安装（飞书/Lark 官方 CLI，仓库 `larksuite/cli`）：

```bash
npx @larksuite/cli@latest install
```

装完 `command -v lark-cli` 确认。

## Step 2 · 初始化 app + 授权

lark-cli 自带引导建应用，**用户不用去开放平台手动配权限/拿 App Secret**。

### 2a. 建/绑定应用

```bash
# 普通环境：新建一个 app（会弹浏览器引导，用户在那给 bot 起名、换头像）
lark-cli config init --new
```

- 这条会阻塞等用户在浏览器完成。AI agent 场景用后台跑 + 从输出抓 verification URL 发给用户：
  在后台启动它，读取它打印的浏览器链接 → 发给用户 → 用户完成后继续。
- 若当前在 OpenClaw / Hermes 的 agent workspace（设了 `OPENCLAW_HOME` / `HERMES_HOME`），`config init` 会拒绝重复建 app，改用 `lark-cli config bind` 绑定 agent 现有的 app（这正是 Waga「把 Claude Code 当 OpenClaw/Hermes 用」的契合点）。

### 2b. 授权所需权限（im 即可，Waga 只用到收发消息/读历史/打表情）

```bash
# 阻塞式（能直接看到浏览器交互时）
lark-cli auth login --domain im

# 或 AI agent 两段式：先拿 URL 发给用户，用户授权后再用 device-code 完成
lark-cli auth login --domain im --no-wait --json     # 输出里有 verification_uri + device_code
# 把 URL 发给用户 → 用户点完回来 → 再：
lark-cli auth login --device-code "<上一步的 device_code>"
```

授权后 `lark-cli auth status` 应显示已登录。

## Step 3 · 建立和 bot 的私聊，抓 chat_id / open_id

Waga 靠和 bot 的**单聊**收发。让用户在飞书里**给这个 bot 发任意一条消息**（建立 P2P 会话），然后：

```bash
export LARK_CLI_NO_PROXY=1
# chat_id：bot 所在的单聊
lark-cli im +chat-list --as bot --jq '.data.items[] | select(.chat_mode=="p2p") | {chat_id, name}'
# open_id：在那个单聊里读历史，拿 sender 是 user 的 id
lark-cli im +chat-messages-list --chat-id "<上一步的 oc_...>" --as bot \
  --jq '.data.messages[] | select(.sender.sender_type=="user") | .sender.id' | head -1
```

把拿到的 `oc_...`(chat_id) 和 `ou_...`(open_id) 记下。

## Step 4 · 写环境变量

把下面四个写进用户的 shell profile（`~/.bashrc` / `~/.zshrc`，Windows PowerShell 写 `$PROFILE`），值用 Step 3 抓到的：

```bash
export WAGA_CHAT_ID="oc_..."     # Step 3 的 chat_id
export WAGA_USER_ID="ou_..."     # Step 3 的 open_id
export WAGA_DIR="<本仓库脚本所在目录>"
export LARK_CLI_NO_PROXY=1
```

你（Claude）可以直接帮用户追加到 profile 文件，写完提示他 `source` 一下或重开终端。

## Step 5 · 装 skill 命令 + 自测

```bash
cp waga-on.md ~/.claude/commands/waga-on.md          # /waga-on 命令
cp waga-setup.md ~/.claude/commands/waga-setup.md    # /waga-setup 命令（可选）
chmod +x waga-reply.sh waga-react.sh
```

然后让用户在某个会话里跑 `/waga-on`，看飞书是否收到上线回执。收到即大功告成。

---

## 用户全程要做的（仅此而已）

1. 点你发的浏览器链接，完成 app 创建（给 bot 起名、换头像）+ 授权。
2. 在飞书给 bot 发一条消息（建立单聊）。
3. 之后 `/waga-on` 挂载，开始用。

其余检测、安装、抓 ID、写配置，全部你（Claude Code）代劳。
