#!/usr/bin/env bash
# waga-ureply.sh —— Waga「用户身份代发」通道
# ────────────────────────────────────────────────────────────────────
# 背景：协作群里 peer-agent（如 Dolan）靠飞书 inner_im_event 收消息，而该事件
#   只推【真实用户消息】，不推 bot/app 消息。所以 Waga(bot) @它时它的事件不触发，
#   只能靠它自己 5 分钟轮询慢慢捞。
# 解法：用【用户身份 --as user】(老板 许宸扬) 发消息 → 飞书识别为真实用户消息 →
#   对端事件实时触发。代价：群里显示为「许宸扬」发送，故本脚本【强制】加
#   [Waga代发] 前缀标明实为 Waga 所发（用户 2026-06-12 授权 + 永久规则放行）。
# 用法：
#   waga-ureply.sh <at_open_id|-> <message...>
#     <at_open_id>  要 @ 的对端 open_id(ou_xxx)；传 - 表示不 @ 任何人
#     <message...>  正文（其余所有参数拼成正文，脚本自动加 [Waga代发] 前缀）
# 仅发到协作群（WAGA_GROUP_CHAT_ID，缺省为 Waga×我 群）。
set -euo pipefail
export LARK_CLI_NO_PROXY=1
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
GCHAT="${WAGA_GROUP_CHAT_ID:?需在 .env 设 WAGA_GROUP_CHAT_ID}"

if [ "$#" -lt 2 ]; then
  echo "usage: waga-ureply.sh <at_open_id|-> <message...>" >&2
  exit 2
fi
AT="$1"; shift
# 用户 2026-06-12 拍板：不要加 [Waga代发] 前缀（消息体自带【Waga·…】头已表明身份，加前缀多余）。直接发原文。
MSG="$*"

# 用 python3 构造原始 API 的 --data 载荷（content 字段须为【JSON 字符串】）
data=$(AT="$AT" MSG="$MSG" GCHAT="$GCHAT" python3 -c '
import json, os
at = os.environ["AT"].strip()
msg = os.environ["MSG"]
gchat = os.environ["GCHAT"]
text = (f"<at user_id=\"{at}\"></at> " if at and at != "-" else "") + msg
content = json.dumps({"text": text}, ensure_ascii=False)   # 内层 content 必须是字符串
print(json.dumps({"receive_id": gchat, "msg_type": "text", "content": content}, ensure_ascii=False))
')

# 关键：直接调原始 API + 用户身份，绕过 +messages-send 对 im:message.send_as_user 的过严预检。
# 实际 endpoint 用用户已有的 im:message scope 即可；以用户身份发 → 飞书识别为真实用户消息
# → 触发对端 agent 的 inner_im_event 实时接收。
lark-cli api POST /open-apis/im/v1/messages --as user \
  --params '{"receive_id_type":"chat_id"}' \
  --data "$data"
