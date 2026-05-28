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

## Step 0 · 检测 lark-cli 是否已安装/已配置应用

```bash
export LARK_CLI_NO_PROXY=1
command -v lark-cli && lark-cli --version || echo "NOT_INSTALLED"
lark-cli config show 2>&1 | head -5    # 已装的话看有没有配过 app（appId/appSecret）
```

分支（注意：门槛是「有没有配过应用」，不是「有没有 auth login」——Waga 走 bot 身份不需要 login）：
- **已装且已配置应用**（`config show` 有 `appId`）→ 跳到 Step 3（抓 ID + 写配置）。
- **已装但未配置**（`config show` 报 `not configured`）→ 跳到 Step 2（已有 app 走 2a 零浏览器；否则 2b 新建）。
- **没装** → Step 1。

## Step 1 · 安装 lark-cli（没装才做）

按官方方式安装（飞书/Lark 官方 CLI，仓库 `larksuite/cli`）：

```bash
npx @larksuite/cli@latest install
```

装完 `command -v lark-cli` 确认。

## Step 2 · 初始化 app

**先问用户：是用现成的飞书自建应用，还是新建一个 bot？**（换电脑 / 重装的人通常已经有现成应用——这种一定走 2a，新建会让旧 `chat_id`/`open_id` 失配。）

### 2a. 已有应用（零浏览器，最省事）· 用户提供 App ID + App Secret

```bash
# Secret 走 stdin，不暴露在进程列表；国内飞书用 --brand feishu，国际 Lark 用 --brand lark
printf '%s' '<App Secret>' | lark-cli config init --app-id <App ID> --app-secret-stdin --brand feishu
```

配完即可——bot 身份立即可用（收发消息/读历史/打表情都走 `--as bot`）。**优先走这条**，配好直接跳 Step 3。

### 2b. 新建应用（没有现成应用时）

lark-cli 自带引导建应用，**用户不用去开放平台手动配权限/拿 App Secret**。

```bash
# 新建一个 app（会弹浏览器引导，用户在那给 bot 起名、换头像）
lark-cli config init --new
```

- 这条会阻塞等用户在浏览器完成。AI agent 场景：后台跑 + 从输出抓 verification URL，**用 `lark-cli auth qrcode "<URL>" --output qr.png` 生成二维码**连同链接一起发给用户（手机扫码最省事）→ 用户完成后继续。
- 若当前在 OpenClaw / Hermes 的 agent workspace（设了 `OPENCLAW_HOME` / `HERMES_HOME`），`config init` 会拒绝重复建 app，改用 `lark-cli config bind` 绑定 agent 现有的 app（这正是 Waga「把 Claude Code 当 OpenClaw/Hermes 用」的契合点）。

### 2c. 授权（可选 —— Waga 用不到，一般可跳过）

Waga 所有调用都走 **`--as bot`（应用身份）**，bot 身份**只需 App ID + Secret，无需 `auth login`**。
只有当你还想用同一个 lark-cli 访问**个人资源**（自己的日历/云盘/邮箱等，用户身份 `--as user`）时才需要：

```bash
lark-cli auth login --domain im      # 仅在需要用户身份时；Waga 本身不需要
```

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

## Step 4 · 写配置（两处）

**(1) 仓库目录下的 `.env`**（已 gitignore，脚本和 `/waga-on` 都自动 source 它）——写抓到的值：

```bash
cat > "<本仓库脚本所在目录>/.env" <<EOF
export WAGA_CHAT_ID="oc_..."     # Step 3 的 chat_id
export WAGA_USER_ID="ou_..."     # Step 3 的 open_id
export WAGA_DIR="<本仓库脚本所在目录>"
EOF
```

**(2) shell profile 里只加一个 `WAGA_DIR`**（macOS = `~/.zshrc`，Linux = `~/.bashrc`，Windows PowerShell = `$PROFILE`），`/waga-on` 靠它找到 `.env`：

```bash
echo 'export WAGA_DIR="<本仓库脚本所在目录>"' >> ~/.zshrc
echo 'export LARK_CLI_NO_PROXY=1' >> ~/.zshrc
```

> ⚠ **AI agent（Claude）注意**：Claude Code 在 auto / 默认权限模式下，会把「改 `~/.zshrc`」和 Step 5「拷命令到 `~/.claude/commands/`」判为**需用户显式授权**而拦掉。撞到拦截**别硬试**——把命令交给用户，让他在 Claude Code 输入框用 `!` 前缀自己跑（如 `! echo 'export WAGA_DIR=...' >> ~/.zshrc`），或在 `settings.json` 加对应 Bash 允许规则后再重试。写 `.env`（在项目目录内）一般不受此限。

## Step 5 · 装 skill 命令 + 自测

```bash
cp waga-on.md ~/.claude/commands/waga-on.md          # /waga-on 命令
cp waga-setup.md ~/.claude/commands/waga-setup.md    # /waga-setup 命令（可选）
chmod +x waga-reply.sh waga-react.sh waga-spawn.sh waga-doctor.sh
```

> ⚠ 同上：`cp` 到 `~/.claude/commands/` 在 auto 模式下可能被拦（视为改 agent 配置）。被拦就让用户用 `!` 前缀自己跑这两条 `cp`。`chmod`（改项目内脚本）一般不受限。

然后让用户在某个会话里跑 `/waga-on`，看飞书是否收到上线回执。收到即大功告成。

---

## 用户全程要做的（仅此而已）

- **已有应用**（含换电脑沿用旧 app）：把 App ID + App Secret 给 Claude（走 Step 2a，**零浏览器**）。
- **新建应用**：点 Claude 发的链接 / 扫二维码，完成 app 创建（给 bot 起名、换头像）。
- 两种都需要：在飞书给 bot 发一条消息（建立单聊），让 Claude 能抓到 `chat_id`/`open_id`。
- 若 Claude 报「改 `~/.zshrc` / 拷命令被拦」：用 `!` 前缀替它跑那两三条命令（Claude 会给出原文）。
- 之后 `/waga-on` 挂载，开始用。

其余检测、安装、抓 ID、写 `.env`、自测，全部 Claude Code 代劳。
