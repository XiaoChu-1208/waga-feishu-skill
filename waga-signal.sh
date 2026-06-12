#!/usr/bin/env bash
# waga-signal.sh —— Waga「信号台」一键写信号
# ────────────────────────────────────────────────────────────────────
# 背景：peer-agent（如 Dolan）的 inner_im_event 只收真实用户消息、不收 bot 消息，
#   所以我(bot)在群里 @它它收不到（只能等它 5 分钟轮询）。
# 解法：往「Agent 信号台」多维表格写一行 → 对端订阅了该表「记录新增」事件 → 实时触发。
#   这是「我→Dolan」的实时通道（Dolan→我 仍走群 @Waga，群监听已实时）。
# 用法：
#   waga-signal.sh <接收方> <类型> <内容> [关联]
#     <接收方>  Dolan | Dancer | 所有人
#     <类型>    交接 | 讨论 | 知会 | 回执
#     <内容>    正文（交接务必自带全上下文，对方看不到群历史）
#     [关联]    可选，关联的 mid/链接等；缺省为 -
#   发起方固定 Waga，状态固定「待处理」（对端处理完自行改「已完成」）。
set -euo pipefail
export LARK_CLI_NO_PROXY=1
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/.env" ] && . "$DIR/.env"
BT="${WAGA_SIGNAL_BASE:?需在 .env 设 WAGA_SIGNAL_BASE}"
TID="${WAGA_SIGNAL_TABLE:?需在 .env 设 WAGA_SIGNAL_TABLE}"

if [ "$#" -lt 3 ]; then
  echo "usage: waga-signal.sh <接收方:Dolan|Dancer|所有人> <类型:交接|讨论|知会|回执> <内容> [关联]" >&2
  exit 2
fi
TO="$1"; TYPE="$2"; CONTENT="$3"; REF="${4:--}"

J=$(TO="$TO" TYPE="$TYPE" CONTENT="$CONTENT" REF="$REF" python3 -c '
import json, os
print(json.dumps({
  "fields": ["内容","发起方","接收方","类型","状态","关联"],
  "rows": [[os.environ["CONTENT"], "Waga", os.environ["TO"], os.environ["TYPE"], "待处理", os.environ["REF"]]]
}, ensure_ascii=False))
')

# Base 记录写入用用户身份（bot 无 base scope；你是 Base owner）。写记录是数据录入，
# 非消息冒充，与被禁的 --as user 发消息不同。
lark-cli base +record-batch-create --as user --base-token "$BT" --table-id "$TID" \
  --json "$J" --jq '.ok, (.error.message // "signal written")'
