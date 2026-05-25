#!/bin/bash
# waga-reply.sh — 短命令包装 lark-cli 回信，自动加 [name] 前缀、设 LARK_CLI_NO_PROXY=1
#
# 用法：
#   bash waga-reply.sh <session-name> "<message>"
#
# 例：
#   bash waga-reply.sh main "已修好"
#   bash waga-reply.sh csb "检查完了，build 没问题"
#
# 把消息以 [<session-name>] 前缀发给 Waga 私聊用户。

set -eu

if [ $# -lt 2 ]; then
  echo "usage: $0 <session-name> <message...>" >&2
  exit 2
fi

NAME="$1"
shift
TEXT="$*"

export LARK_CLI_NO_PROXY=1
# 本地配置：真实 id 放同目录 .env（已 gitignore，不上传）；供 waga-card.py 读 WAGA_USER_ID
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"

# 2026-05-22 起：回复走内联蓝字卡片（waga-card.py say），不再发 [name] 纯文本。
# say 会自动登记卡片 mid 到 waga_sent.txt（供引用回复路由）。
# 启动器：Windows 用 py（python 是坏桩），Mac/Linux 用 python3——按序探测。
DIR="$(dirname "$0")"
PY="$(command -v py 2>/dev/null || command -v python3 2>/dev/null || echo python3)"
mid=$($PY "$DIR/waga-card.py" say "$NAME" "$TEXT" 2>/dev/null | tr -d '\r\n')

if [ -n "$mid" ]; then
  echo "ok: ${mid}"
else
  echo "ERR: waga-card say 失败（name=$NAME）" >&2
  exit 1
fi
