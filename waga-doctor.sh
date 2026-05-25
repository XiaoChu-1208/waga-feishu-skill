#!/bin/bash
# waga-doctor.sh — waga 自检：收集诊断信息，给 Claude 读了判断哪儿出毛病。
#
# 借鉴 feishu-claude-code-bridge 的 /doctor。用法：用户发 `/doctor`（或 name: /doctor），
# 监听器把它当普通消息路由给我（有窗口的 worker），我跑 `bash waga-doctor.sh`、读输出、
# 判断问题、回一张诊断卡。脚本只【收集】，判断由我（大模型）做。
#
# 收集：lark-cli 连通/token、粘性目标、各 worker 心跳(live/dead/类型)、
#       粘性是否指向死 worker(今天踩过的坑)、worker 日志末尾、在跑 monitor 进程数。

export LARK_CLI_NO_PROXY=1
# 本地配置：真实 id 放同目录 .env（已 gitignore，不上传）
[ -f "$(dirname "$0")/.env" ] && . "$(dirname "$0")/.env"
CHAT=${WAGA_CHAT_ID:?set WAGA_CHAT_ID}
STICKY="/tmp/waga_sticky.txt"
now=$(date +%s)

echo "===== WAGA DOCTOR @ $(date +'%Y-%m-%d %H:%M:%S') ====="

echo ""
echo "--- 1. lark-cli 连通性 / token ---"
out=$(lark-cli im +chat-messages-list --chat-id "$CHAT" --as bot --page-size 1 \
  --jq '.data.messages[0].message_id' 2>&1)
if echo "$out" | grep -qiE 'secret invalid|token.*expired|invalid_token|99991|10014|"ok" *: *false|api_error|HTTP [45][0-9][0-9]'; then
  echo "X 异常（疑似 token 过期，跑 lark-cli auth login --domain all 重扫码）: $(echo "$out" | tr '\n' ' ' | cut -c1-160)"
else
  echo "OK lark-cli 通（拿到 message_id: $(echo "$out" | tr -d '\n' | cut -c1-24)…）"
fi

echo ""
sticky=$(cat "$STICKY" 2>/dev/null)
echo "--- 2. 粘性目标: ${sticky:-(空)} ---"

echo ""
echo "--- 3. worker 心跳（live=35s 内有心跳）---"
sticky_alive="no"; sticky_seen="no"
for f in /tmp/waga_alive_*.txt; do
  [ -e "$f" ] || continue
  line=$(cat "$f" 2>/dev/null)
  ep="${line%%|*}"; rest="${line#*|}"
  nm="${rest%%|*}"; rest2="${rest#*|}"
  cwd="${rest2%|*}"; typ="${rest2##*|}"
  [ "$cwd" = "$typ" ] && typ="?(旧)"
  [ -z "$ep" ] && continue
  age=$((now - ep))
  [ "$age" -le 35 ] && state="live" || state="dead"
  printf '  %-10s %-9s %-9s %ss前  %s\n' "$nm" "$state" "$typ" "$age" "$cwd"
  if [ "$nm" = "$sticky" ]; then
    sticky_seen="yes"
    [ "$state" = "live" ] && sticky_alive="yes"
  fi
done

echo ""
echo "--- 4. 粘性目标健康度 ---"
if [ -z "$sticky" ]; then
  echo "X 粘性文件为空"
elif [ "$sticky_seen" = "no" ]; then
  echo "X 粘性目标 [$sticky] 没有任何心跳文件（这个 worker 根本没在跑）→ 无前缀消息会丢"
elif [ "$sticky_alive" = "no" ]; then
  echo "X 粘性目标 [$sticky] 已 dead（心跳过期）→ 无前缀消息会路由到死 worker、被静默丢弃"
else
  echo "OK 粘性目标 [$sticky] live，无前缀消息能正常落到它"
fi

echo ""
echo "--- 5. worker stream 日志末尾（headless worker 报错看这里）---"
shopt -s nullglob
logs=(/tmp/waga_stream_*.log)
if [ ${#logs[@]} -eq 0 ]; then
  echo "  (无 worker 日志)"
else
  for l in "${logs[@]}"; do
    echo "  [$(basename "$l")]:"
    tail -n 4 "$l" 2>/dev/null | sed 's/^/    /'
  done
fi

echo ""
echo "--- 6. 在跑的 monitor/worker bash 进程数 ---"
# ps -W 是 Git Bash/MSYS 专属（列 Windows 进程）；Mac/Linux 用 ps ax 兜底
n=$( { ps -W 2>/dev/null || ps ax 2>/dev/null; } | grep -c -iE 'bash')
echo "  bash 进程总数 ≈ $n（含非 waga 的；同名重复挂会导致双重处理/抢答）"

echo ""
echo "===== END DOCTOR — 请据此判断问题并回报用户 ====="
