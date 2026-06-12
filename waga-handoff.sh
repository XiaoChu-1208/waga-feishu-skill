#!/usr/bin/env bash
# waga-handoff.sh —— 代表给【本机其它 Waga session】一键派活（同机内网总线）。
# ────────────────────────────────────────────────────────────────────
# 「代表架构」：群里只留一个代表 session(挂 /waga-on)。代表收到群任务后，若该派给本机
# 另一个正在干活的 session，用本脚本一键转单——同台机器共享 /tmp，所以走本地文件最快最稳
# （不碰信号表单选字段的限制、不走云端往返）。信号表只留给跨机器/Dolan。
#
# 两种用法：
#   发送（代表用）：  waga-handoff.sh <目标session> "任务内容" [类型]
#       会先查目标 session 是否活着(/tmp/waga_alive_<目标>.txt 心跳<=40s)，活才派、死则告警。
#   接收（目标session用，Monitor 挂）： waga-handoff.sh watch <我的名字>
#       盯 /tmp/waga_handoff_<我>.txt，有新任务行就 emit 唤醒本会话。
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

_hb_fresh() {  # $1=name；心跳文件存在且 <=40s 算活
  local f="/tmp/waga_alive_$1.txt" now ep
  [ -f "$f" ] || return 1
  now=$(date +%s); ep=$(cut -d'|' -f1 "$f" 2>/dev/null || echo 0)
  case "$ep" in ''|*[!0-9]*) return 1 ;; esac
  [ $((now - ep)) -le 40 ]
}

cmd="${1:?usage: waga-handoff.sh <目标session> \"任务\" [类型]  |  waga-handoff.sh watch <我的名字>}"

if [ "$cmd" = "watch" ]; then
  ME="${2:?usage: waga-handoff.sh watch <我的名字>}"
  F="/tmp/waga_handoff_${ME}.txt"
  touch "$F"
  # seed：从当前末尾开始，不回溯历史
  last=$(wc -l < "$F" 2>/dev/null | tr -d ' '); last=${last:-0}
  echo "[WAGA-HANDOFF] 派活接收监听已挂 [${ME}]（盯 $F）"
  while true; do
    cur=$(wc -l < "$F" 2>/dev/null | tr -d ' '); cur=${cur:-0}
    if [ "$cur" -gt "$last" ]; then
      sed -n "$((last+1)),${cur}p" "$F" 2>/dev/null | while IFS='|' read -r ep typ frm content; do
        [ -z "$content" ] && { content="$typ"; typ="交接"; }
        echo "[WAGA-HANDOFF-MSG] 来自代表 ${frm:-?} · ${typ} :: ${content}"
        echo "[WAGA-HANDOFF-REMINDER] 代表派给你的活，直接干。干完正常在群/私聊汇报，或回代表。"
      done
      last="$cur"
    fi
    sleep 5
  done
fi

# ── 发送模式 ──
TARGET="$cmd"
CONTENT="${2:?需要任务内容}"
TYPE="${3:-交接}"
FROM="${WAGA_NAME:-代表}"
F="/tmp/waga_handoff_${TARGET}.txt"

if _hb_fresh "$TARGET"; then
  alive="（活）"
else
  alive="（⚠ 没检测到心跳，目标可能没开或没挂 watch；活照写，但它不一定收得到）"
fi
printf '%s|%s|%s|%s\n' "$(date +%s)" "$TYPE" "$FROM" "$CONTENT" >> "$F"
echo "已派活给 [${TARGET}] ${alive}：${CONTENT}"
