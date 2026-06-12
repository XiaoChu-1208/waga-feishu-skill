# Waga 复制指南 —— 给「Waga ByteDancer」一次性配齐

> 目的：让另一台 Mac 上的 Claude Code（代号 **Waga ByteDancer / Dancer**）一次性配置到
> 个人 Mac 上 Waga 的同等程度——能被飞书私聊远程指挥、能进多智能体协作群、能出统一制式卡片。
> 本文是「照着做就行」的落地清单，不是原理科普。整理于 2026-06-12 凌晨。

---

## 0. Waga 是什么（一句话）
用**飞书私聊/群** 远程指挥某台机器上**已开着的 Claude Code 会话**：你在外面用手机飞书发消息，
机器上的 Claude 收到、干活、回你。多台机器 + 云端 agent 组成协作群。

**核心约束**：Claude/lark-cli **开不了终端、起不了 Claude Code**，只能驱动**已开着的窗口**。
→ 出门前要先把窗口开好、各自 `/waga-on` 起名。关窗口=监听自动失效。

---

## 1. 前置条件（Dancer 这台机器要先有）

1. **lark-cli** 已装并授权：`lark-cli auth login --domain all`（扫码）。
2. **独立的飞书自建应用/bot**（⚠ 关键）：**一台机器一个 bot**。多机共用一个 bot 会
   跨机器抢答（`/who`、无前缀消息都会被多台抢），状态锁只在本机 `/tmp`。所以 Dancer
   要用**它自己的** app（cli_xxx），不要复用别台机器的 app。
3. **waga-daemon 目录**：脚本在 `~/Desktop/同步/waga-daemon/`（同步盘，Dancer 这台应已有同样文件）。
4. **profile 里 export 一个变量即可**：`export WAGA_DIR=~/Desktop/同步/waga-daemon`
   —— chat_id/open_id 全部由 `$WAGA_DIR/.env` 自动 source，.env 是 ID 的唯一真相源。

### 1.1 .env 模板（每台机器本地私有，gitignore，**不要**共享）
```sh
# Dancer 自己 bot 的私聊 chat_id 和你的 user open_id
export WAGA_CHAT_ID=oc_xxx          # Dancer bot 与你的私聊 chat_id
export WAGA_USER_ID=<你的-user-open_id>   # 你许宸扬的 open_id（同一个）
# 协作群（三方共用同一个群，全机器一致）
export WAGA_GROUP_CHAT_ID=<协作群-chat_id>
# 信号台（共用，全机器一致）
export WAGA_SIGNAL_BASE=<信号表-app_token>
export WAGA_SIGNAL_TABLE=<信号表-table_id>
```
> chat_id/open_id 怎么拿：用 `waga-setup` skill 自动抓，或 `lark-cli api GET /open-apis/bot/v3/info --as bot`
> 拿 bot open_id；私聊 chat_id 在你给 bot 发一条消息后用 `lark-cli im +chat-list --as bot` 找。

---

## 2. 核心文件清单（`$WAGA_DIR/`）

| 文件 | 作用 |
|---|---|
| `waga-on.md` | slash command / skill：挂监听器（私聊+群） |
| `waga-reply.sh` | 私聊回信（自动加 `[name]` 前缀 + NO_PROXY） |
| `waga-react.sh` | 给消息气泡贴表情：`vibe <mid> "E1 E2 E3"` / `done <mid>` / `woke <mid>` |
| `waga-card.py` + `waga-stream.py` | **私聊**卡片引擎（online/who/say/start-step-done 进度卡） |
| `waga-gcard.py` | **群**卡片（统一制式，按 agent 上色，可 @人）← 2026-06-12 新增 |
| `waga-signal.sh` | 往「信号台」多维表格写一行（agent 间异步信号）← 新增 |
| `waga-ureply.sh` | 用户身份代发（⚠ 已废，见 §8，留作记录别用） |
| `waga-spawn.sh` | 拉起 headless worker（`claude -p --resume`，自收发飞书） |
| `waga-doctor.sh` | 自检（lark-cli 连通/粘性目标/各 worker 心跳/日志） |

---

## 3. 挂监听器：`/waga-on <短名>`

进 Claude Code 窗口，跑 `/waga-on dancer`（或更短 `d`）。它会挂**两个独立 Monitor**：

### 3.1 私聊监听（盯 `$WAGA_CHAT_ID`）
- 前缀路由：`name: 内容`=切粘性+处理｜`name:`=只切粘性｜`[name] 内容`=一次性｜无前缀=走粘性目标｜`/who`=报数
- 错误处理（踩过的坑，必带）：
  - stderr 的 `warning:` 行先 `grep -v '^warning:'` 滤掉（lark-cli 的 `reactions_batch_query_failed: HTTP 500` 是**非致命**警告，会误触发错误分支刷屏）
  - 只把 **auth/token 失效**当致命（立即报，让用户 `lark-cli auth login`）；**网络抖动**静默重试、连失 4 次才报一次（别每 30s 刷屏）

### 3.2 群监听 v5（盯 `$WAGA_GROUP_CHAT_ID`）
- **用原始列表 API 轮询**（`lark-cli api GET /open-apis/im/v1/messages --as bot --params '{container_id_type:chat,container_id:群,sort_type:ByCreateTimeDesc,page_size:20}'`），
  因为它**返回的 items 自带 `mentions` 字段**；而 `+chat-messages-list` 快捷命令会**抹掉 mentions**，
  逼你逐条 raw GET 解析 @——那个 raw GET 在 `printf|while` 管道子 shell 里会被本机沙箱杀掉，导致静默漏判。
- 收 **text + post**（Dolan 发的常是 post 富文本，只收 text 会整条漏掉）。
- 检测：`mentions[].id` 含我的 bot open_id → @我；正文含 `@_all` → @所有人。
- 路由：**人@我→处理**｜**人@所有人→自判相关性再发言**｜**peer-agent(app)@我→当交接处理**｜
  排除自己发的（按自己 app id）+ 非@一律沉默（**防机器人互撕铁律**）。

> 两个监听是独立 Monitor，互不干扰。改名=同窗口重跑 `/waga-on <新名>`（覆盖语义，先停旧再挂新）。

---

## 4. 回信/发卡规约

- **私聊回信**：`bash $WAGA_DIR/waga-reply.sh <name> "内容"`（铁律：收到消息**必须** lark-cli 发出去，
  光在 Claude UI 写字用户看不到）。富报告用 `python3 $WAGA_DIR/waga-card.py say <name> "markdown"`。
- **群发言**：一律走**群卡片** `python3 $WAGA_DIR/waga-gcard.py post --agent Dancer --action <动作> --content "markdown" [--at ou_xxx]`
  —— 统一制式见 §6。
- **表情两层**（用户反复拍板）：
  1. **状态层**：emit 自动贴 `Typing`(处理中) → 回完 `waga-react.sh done <mid>` 换 `DONE`。
  2. **反应层（最常漏！）**：读懂消息后**亲贴一组 2-4 个真实贴合用户当下情绪的表情**，
     每次不同、绝不随机、绝不只一个。怒别乐、丧别嗨。`waga-react.sh vibe <mid> "E1 E2 E3"`。
     调色板实证：`OnIt DONE Typing` / `THUMBSUP CLAP MUSCLE` / `LAUGH JOYFUL PARTY Fire WOW` / `Sigh Salute HEART`。
     ⚠ emoji_type **大小写敏感**：`Fire`✓ `FIRE`✗。

---

## 5. 多智能体协作群

- **成员/分工**：你许宸扬（总指挥）｜Waga（个人 Mac 本地手）｜Dolan（云端高权限手）｜Dancer（另一台 Mac 本地手）。
- **寻址**（用户拍板）：@谁谁说话；@所有人→agent 自判相关性再发言；peer@我→交接。
- **防互撕铁律**：默认不回应别的 agent，只在被显式 @我 时醒；回复别反手 @ 对方（除非真有具体活交回去，人在环里）。
- **上下文同步 = 群聊当唯一日志**：发言带结构化头/卡片动作（收到/进度/完成/交接/讨论）；
  **交接必须自带全上下文**（被唤醒的 agent 看不到群历史，只看到触发它的那一条）。

### 5.1 信号台（多维表格，agent 间异步信号）
- Base `<信号表-app_token>`，表「信号」`<信号表-table_id>`，字段 ID/内容/发起方/接收方/类型/状态/关联/创建时间。
- 写：`bash $WAGA_DIR/waga-signal.sh <接收方> <类型> <内容> [关联]`（`--as user` 写记录；bot 无 base scope）。
- ⚠ 注意：它**不能实时触发对端**（见 §8），只能当**共享异步看板**，对端轮询时一眼看全待办。

---

## 6. 群发言制式：**卡片(给人看) + 信号表镜像(给 agent 读) 双写**

> 老板要卡片好看，但 agent 又得能互读、能互贴 reaction。卡片正文 API 读不出来（连自己的卡读回都是
> 「请升级客户端」占位符，summary 等字段也不留）。所以定方案：**每条群发言双写**——
> ①发 interactive 卡片到群（人看）②同一句话写进信号表当机读镜像（agent 读表、据镜像的「关联=卡片mid」
> 互相贴 reaction）。**这是 2026-06-12 定稿，别再走纯卡片或纯 post 的弯路。**

**发言（双写，一条命令搞定）**：
```
python3 waga-gcard.py post --agent Dancer --action <动作> --content "正文" [--to Waga|Dolan|所有人] [--at ou_xxx]
```
- 卡片：schema 2.0，header=`<font color='<agent色>'>**<agent>**</font> <font color='grey'>· <角色></font>　<font color='<状态色>'>【<动作>】</font>`，正文 markdown，hr，状态行。
- agent 色：Waga=blue / Dolan=purple / Dancer=teal。动作→状态色：收到/进度/讨论=blue｜完成=green｜交接=orange｜失败=red｜知会=grey。
- 镜像行（脚本自动写）：发起方=本agent，接收方=`--to`或`--at`反查或所有人，类型=交接/讨论/知会/回执，内容=正文，**关联=刚发卡片的 message_id**，状态=待处理。

**收发对端消息（轮询信号表，不读卡片）**：
- 接收端跑轮询监听 `waga-table-watch.py`（每 20s 拉表，取 接收方∈{我,所有人}、发起方≠我、状态待处理 的新行，读「内容」）。
  Waga 这套用 `python3 waga-table-watch.py`（已带 Waga 过滤）；Dancer 把脚本里 `ME="Waga"` 改成 `ME="Dancer"`。
- 表 envelope（坑）：`--format json`（默认 markdown 读不了）；记录在 `data`(行数组) 与 `record_id_list`(并列对齐)，
  列序 `[ID,状态,关联,内容,发起方,类型,创建时间,接收方]`，select 字段是单元素数组如 `["Waga"]`。
- 处理完把该行状态改「已完成」：`python3 waga-table-watch.py done <record_id>`。

**互贴 reaction（老板要，逻辑同 §4.2 两层）**：读懂对端「内容」后，给对端那张**卡片**(镜像「关联」里的 mid)
贴 2-4 个贴合情绪的表情：`bash waga-react.sh vibe <关联mid> "E1 E2 E3"`。reaction 只认 mid、不需要读卡片正文，
所以卡片不透明也能贴。

**信号表**：app_token=`<信号表-app_token>`，table_id=`<信号表-table_id>`（.env 里 WAGA_SIGNAL_BASE/TABLE）。
写记录 `lark-cli base +record-batch-create --as user`（bot 无 base scope，用 user）。

> ⚠ 昨晚整夜没对上话的根因：Dolan 把 @ 写在卡片里，而卡片 @ 不进消息级 mentions、卡片内容 API 也读不到，
> Waga 既没被唤醒也读不到它说啥。本方案（表镜像 + 轮询）绕开了这个：唤醒靠轮询表、读内容靠表、贴表情靠关联 mid。

---

## 7. 能力边界（互相交代清楚，方便老板掌握分工）

| | **Waga / Dancer**（Claude Code on Mac） | **Dolan**（飞书云端 agent） |
|---|---|---|
| 本地文件/代码/跑脚本 | ✅ 本机 Mac（各管各的机器） | ❌ 碰不到 |
| lark-cli 飞书全家桶 | ✅ 消息/表情/卡片/建群/多维表格/文档/表格/幻灯片/云盘/日历/邮件/通讯录/妙记/会议（多 bot 身份） | 部分（云文档/妙记/跨群消息/邮件/表格） |
| 云端高权限/定时任务&心跳 | 一般权限 | ✅ 高权限 + 定时巡检 |
| 联网搜索/抓取、深度推理/调试/造工具、前端设计 | ✅ | 视其平台 |
| 实时收消息 | ✅ 轮询，bot 消息也收得到 | ⚠ 事件只收**真实用户消息**，5 分钟轮询兜底 |

分工：难/解析性 → Waga/Dancer；权限重但简单/云端 → Dolan；本地文件按机器分给对应的 Waga/Dancer。

---

## 8. ★四堵墙：实时「我(bot)→对端 agent」做不到，别再撞（血泪，2026-06-12 一整晚验的）

**根因一条**：飞书 notice/receive 类事件**只为「真实用户动作」触发，bot 一律被系统排除**；
加上租户/应用没开通相关事件。撞过的死路：
1. **以用户身份发消息**：`im:message.send_as_user`「以用户身份发送消息」**这个权限根本不存在**于飞书权限目录，
   硬用用户 token 发群消息报 **230027**。
2. **Base 记录变更事件** `drive.file.bitable_record_changed_v1`：**当前租户不支持**（aily 平台层没放开，不在可订阅列表）。
3. **文档评论事件** `drive.notice.comment_add_v1`：**应用不可订阅**（不在 event list）。
4. **表情事件** `im.message.reaction.created_v1`：能订阅，但 lark-cli 事件长连接在本机连不上（`context canceled`），
   且按规律 bot 加的表情大概率也不触发。

**稳定可用形态**（认这个，别浪费时间找绕法）：
- 我↔用户：实时（私聊）
- 对端 agent → 我：实时（它在群 @我，我群监听秒收）
- **我 → 对端 agent：紧急时戳用户 → 用户在群 @它（真实用户瞬间触发）；不急走信号表/对端 5 分钟轮询**

附：`lark-cli event consume <key>` 必须 `--as bot`（默认 auto 会判成 user 直接报错）。

---

## 9. 隐私红线
**不要把用户的本地文件内容传给其它 agent**（Dolan/别的机器）。agent 之间只交代**能力边界**
（谁能碰哪台机器的本地文件、谁有云端高权限），不传文件内容。

---

## 10. 落地顺序（Dancer 照此跑一遍）
1. 装/授权 lark-cli（用 Dancer 自己的 bot）。
2. 写好 `$WAGA_DIR/.env`（§1.1，注意 WAGA_GROUP_CHAT_ID / 信号台用共享值，私聊 ID 用自己 bot 的）。
3. 让你许宸扬把 Dancer 的 bot 拉进协作群。
4. 开一个 Claude Code 窗口，跑 `/waga-on d`。
5. 群里用 `waga-gcard.py post --agent Dancer ...` 出张卡报到。
6. 读本文件 §8，认清实时的墙，别重撞。
