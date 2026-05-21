#!/bin/bash
# rebrand.sh — 一键把整套 "Waga" 换成你自己的品牌名（如 Ali / Bilu）
#
# 用法（在仓库根目录跑）：
#   bash rebrand.sh <新名字>
#
# 例：
#   bash rebrand.sh ali      # /waga-on → /ali-on，脚本/标记/临时文件/环境变量全改
#   bash rebrand.sh Bilu
#
# 它会改三种大小写形态，保持各处风格一致：
#   waga → <新名小写>     命令名 waga-on、脚本名 waga-*.sh、临时文件 /tmp/waga_*
#   WAGA → <新名大写>     事件标记 [WAGA-MSG]、环境变量 WAGA_CHAT_ID 等
#   Waga → <新名首字母大写>  文档里的品牌字样
# 同时把 waga-*.md / waga-*.sh 文件重命名为 <新名>-*。
#
# ⚠ 改完后，如果你已经把命令装进 ~/.claude/commands/，记得把那边的
#    waga-on.md 也改名成 <新名>-on.md（命令名 = 文件名，CLI 不认仓库内变量）。

set -eu

NEW="${1:-}"
if [ -z "$NEW" ]; then
  echo "usage: $0 <newbrand>   e.g. $0 ali" >&2
  exit 2
fi

# 三种形态
to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
to_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
to_title() {
  local s; s="$(to_lower "$1")"
  printf '%s' "$(to_upper "${s:0:1}")${s:1}"
}
L="$(to_lower "$NEW")"
U="$(to_upper "$NEW")"
T="$(to_title "$NEW")"

echo "rebrand: waga→$L  WAGA→$U  Waga→$T"

# 处理哪些文件（排除 .git、本脚本自身、LICENSE）
FILES=$(find . -type f \( -name '*.md' -o -name '*.sh' \) \
  -not -path './.git/*' -not -name 'rebrand.sh')

# 1) 文本内容替换（顺序：先大写、再首字母大写、最后小写，避免互相吃字）
for f in $FILES; do
  sed -i \
    -e "s/WAGA/$U/g" \
    -e "s/Waga/$T/g" \
    -e "s/waga/$L/g" \
    "$f"
  echo "  patched $f"
done

# 2) 文件重命名 waga-* → <新名>-*
for f in $(find . -type f -name 'waga-*' -not -path './.git/*' -not -name 'rebrand.sh'); do
  dir="$(dirname "$f")"; base="$(basename "$f")"
  newbase="${base/waga-/${L}-}"
  mv "$f" "$dir/$newbase"
  echo "  renamed $base → $newbase"
done

echo "done. 别忘了:"
echo "  · 重新设环境变量 ${U}_CHAT_ID / ${U}_USER_ID / ${U}_DIR"
echo "  · 装进 ~/.claude/commands/ 的那份也改名成 ${L}-on.md"
