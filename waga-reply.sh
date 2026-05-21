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
USER_OID="${WAGA_USER_ID:?set WAGA_USER_ID}"

response=$(lark-cli im +messages-send --as bot --user-id "$USER_OID" --text "[${NAME}] ${TEXT}" 2>&1)

if echo "$response" | grep -q '"ok": *true'; then
  msg_id=$(echo "$response" | grep -oE '"message_id": *"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  echo "ok: ${msg_id}"
else
  echo "ERR: $response" >&2
  exit 1
fi
