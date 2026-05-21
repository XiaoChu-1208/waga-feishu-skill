#!/bin/bash
# waga-react.sh — 给飞书消息气泡打/换 reaction（不是回复表情，是对气泡本身贴表情）
#
# 用法：
#   bash waga-react.sh add  <message_id> <emoji_type>      # 加一个表情（默认 OnIt）
#   bash waga-react.sh done <message_id>                   # 把本 bot 的 OnIt 换成 DONE(绿勾)
#   bash waga-react.sh clear <message_id> <emoji_type>     # 删掉本 bot 该 emoji 的 reaction
#   bash waga-react.sh vibe <message_id> "E1 E2 E3 ..."    # 一次贴一串表情（生动模式，≤10个，自动限速）
#
# ⚠ emoji_type 大小写敏感，是 key 的一部分。FIRE 无效、Fire 才对。
#    不在下表的别乱试——错的会返回 231001。WebFetch 文档那个小模型会瞎编，别信。
#
# 已实证可用调色板（canonical 形式）+ 情绪映射（要呼应用户当下心情）：
#   状态：      OnIt(处理中) Typing(打字) DONE(绿勾)
#   开心/兴奋：  LAUGH JOYFUL PARTY Fire CLAP WOW
#   赞同/感谢：  THUMBSUP OK Get Salute(敬礼/收到)
#   暖心/喜欢：  HEART LOVE SMILE
#   佩服/牛了：  WOW MUSCLE APPLAUSE
#   认错/无奈/共情：Sigh(叹气) Salute   ← 用户怒/丧时用这类，别贴庆祝
#   卖萌/调皮：  MeMeMe HUSKY
# ⚠ 飞书 API 放行的 key 有限，负面情绪基本只有 Sigh/Salute；方向对齐比数量重要。
#
# 例：
#   bash waga-react.sh add  om_xxx OnIt                          # 收到消息先贴“处理中”
#   bash waga-react.sh done om_xxx                               # 回完信换成绿勾
#   bash waga-react.sh vibe om_xxx "THUMBSUP Fire PARTY LAUGH"   # 应景贴一串

set -eu
export LARK_CLI_NO_PROXY=1

MODE="${1:-}"
MID="${2:-}"
EMOJI="${3:-OnIt}"

if [ -z "$MODE" ] || [ -z "$MID" ]; then
  echo "usage: $0 add|done|clear <message_id> [emoji_type]" >&2
  exit 2
fi

react_add() {
  # 成功返回 reaction_id；出错（含 231001 无效表情）返回空字符串
  lark-cli im reactions create --as bot \
    --params "{\"message_id\":\"$1\"}" \
    --data "{\"reaction_type\":{\"emoji_type\":\"$2\"}}" \
    --jq '.data.reaction_id // empty' 2>/dev/null | tr -d '"\n'
}

# 删掉本 bot 在该消息上、指定 emoji 的 reaction（按 emoji 过滤；bot 只能删自己加的）
react_clear() {
  local mid="$1" emoji="$2"
  lark-cli im reactions list --as bot --params "{\"message_id\":\"$mid\"}" \
    --jq ".data.items[] | select(.reaction_type.emoji_type==\"$emoji\") | .reaction_id" 2>/dev/null \
    | tr -d '"' | while read -r rid; do
      [ -z "$rid" ] && continue
      lark-cli im reactions delete --as bot \
        --params "{\"message_id\":\"$mid\",\"reaction_id\":\"$rid\"}" >/dev/null 2>&1
    done
}

case "$MODE" in
  add)
    rid=$(react_add "$MID" "$EMOJI")
    echo "added $EMOJI -> ${rid:-ERR}"
    ;;
  vibe)
    # $3 = 空格分隔的 emoji 列表；逐个加，限速避免 231001，最多 10 个
    n=0
    for e in $EMOJI; do
      [ "$n" -ge 10 ] && break
      rid=$(react_add "$MID" "$e")
      [ ${#rid} -gt 20 ] && { echo "+ $e"; n=$((n+1)); } || echo "x $e (invalid?)"
      sleep 0.6
    done
    echo "vibe done: $n reactions"
    ;;
  clear)
    react_clear "$MID" "$EMOJI"
    echo "cleared $EMOJI on $MID"
    ;;
  done)
    # 清掉临时「处理中」标记（OnIt + Typing），换成 DONE 绿勾；情绪表情保留当氛围
    react_clear "$MID" "OnIt"
    react_clear "$MID" "Typing"
    rid=$(react_add "$MID" "DONE")
    echo "done(DONE) -> ${rid:-ERR}"
    ;;
  *)
    echo "unknown mode: $MODE" >&2
    exit 2
    ;;
esac
