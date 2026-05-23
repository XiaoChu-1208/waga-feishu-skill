#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
waga-stream.py — 跑一次 headless claude，把过程实时刷到一张飞书卡片上。

借鉴 zarazhangrui/feishu-claude-code-bridge 的「流式单卡片」体验，缝进 waga 的
spawn worker：用 `claude -p --output-format stream-json` 跑，逐行解析事件，
把【运行状态 / 正文 / 工具调用 / 最终结果】patch 到同一张飞书交互卡片上，
替代 waga 原来「发一串离散文本」的刷屏式输出。

用法：
  python waga-stream.py --name NAME --cwd DIR --sid SID [--first] \
      --user OU_XXX "用户消息文本"

行为：
  1. 先发一张「运行中」卡片（schema 2.0, streaming_mode），拿到 message_id。
  2. spawn claude，逐行读 stream-json，累积状态，节流 patch 卡片（~1.2s 一次）。
  3. 跑完 patch 成终态（绿=完成 / 红=错），打印最终结果文本到 stdout。

设计取舍：
  · headless 弹不出权限框 → --dangerously-skip-permissions 自动放行（按『正常 session』用）。
  · 卡片不放可点按钮：点击要事件回调服务器，waga 是轮询架构收不到回调。停止用
    文字 `name: /stop`，卡片只显示状态。
  · 按 no-emoji 规则：卡片不内联 emoji，靠头部颜色 + 文字标签表状态。
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time

# Windows 下 npm 全局命令是 .CMD，必须解析全路径——原生 python 的 subprocess
# 不会按 PATHEXT 查 .CMD，直接传名字会 WinError 2。Git Bash 里 `python` 还是
# WindowsApps 的坏桩，所以本脚本一律用 `py` 启动（见 waga-spawn.sh）。
LARK = shutil.which("lark-cli") or "lark-cli"
CLAUDE = shutil.which("claude") or "claude"
ENV = dict(os.environ, LARK_CLI_NO_PROXY="1")

# ⚠ 卡片正文用 <font color> 内联上色，但 `<` `>` 经 .CMD→cmd.exe 会被当重定向符
# 搞坏命令（bash 走 sh-shim 没事，python subprocess 走 .CMD 才坏）。绕法：直接用
# node 跑 lark-cli 的 run.js，argv 不过 cmd 就安全。lark_argv() 优先返回 node 直跑。
_NODE = shutil.which("node")
_LARK_RUNJS = os.path.expandvars(r"%APPDATA%\npm\node_modules\@larksuite\cli\scripts\run.js")


def lark_argv(*args):
    if _NODE and os.path.exists(_LARK_RUNJS):
        return [_NODE, _LARK_RUNJS, *args]
    return [LARK, *args]


def _tmpdir():
    # Git Bash 的 /tmp 实际就是 %TMP%（实测同一目录）；py 用 TMP 才能跟 bash 监听器共享文件。
    return os.environ.get("TMP") or os.environ.get("TEMP") or "/tmp"


# 已发卡片登记：每条卡片的 mid 追加到共享文件 waga_sent.txt（行格式 `mid|name`）。
# 监听器据此实现「引用回复某张卡 → 路由到发该卡的 session」（reply_to 路由）。
SENT_FILE = os.path.join(_tmpdir(), "waga_sent.txt")


def record_sent(name, mid):
    if not mid:
        return
    try:
        with open(SENT_FILE, "a", encoding="utf-8") as f:
            f.write(f"{mid}|{name}\n")
    except Exception:
        pass

# ---- 卡片渲染 -------------------------------------------------------------
# 统一风格（用户 2026-05-22 拍板「A 内联蓝字」）：不用彩色大头条，name 用内联蓝色
# 加粗写在正文最上面，状态用内联彩色小字（绿完成/红失败/灰处理中）标在末尾。轻、像聊天。

STATUS_LABEL = {"running": "运行中", "done": "完成", "error": "失败", "interrupted": "已中断"}
STATUS_COLOR = {"running": "grey", "done": "green", "error": "red", "interrupted": "grey"}
CARD_MD_CAP = 3500  # 卡片正文 markdown 上限，超长 head+tail 截断


def _clip(text, cap=CARD_MD_CAP):
    if len(text) <= cap:
        return text
    head = cap * 2 // 3
    tail = cap - head
    return text[:head] + "\n\n…（中间省略）…\n\n" + text[-tail:]


def name_line(name):
    """内联蓝色加粗 name —— 所有 waga 卡片的统一开头（替代 [name] 方括号/大头条）"""
    return f"<font color='blue'>**{name}**</font>"


def build_card(name, state, body_text, tools, footer, elapsed):
    """state: running|done|error|interrupted。内联蓝名 + 正文 + 工具 + 内联彩色状态小字。"""
    elements = [{"tag": "markdown", "content": name_line(name)}]

    if body_text.strip():
        elements.append({"tag": "markdown", "content": _clip(body_text.strip())})

    if tools:
        lines = []
        for t in tools[-12:]:
            mark = "·" if t.get("running") else "✓"  # ✓ 是文字勾，非 emoji
            detail = t.get("detail", "")
            detail = (" " + detail) if detail else ""
            lines.append(f"`{mark}` **{t['name']}**{detail}")
        if len(tools) > 12:
            lines.insert(0, f"_（前 {len(tools) - 12} 个工具调用已折叠）_")
        elements.append({"tag": "hr"})
        elements.append({"tag": "markdown", "content": "\n".join(lines)})

    # 状态：内联彩色小字（颜色即状态，不用大头条）
    if state == "running":
        label = footer or "处理中…"
    elif state == "done":
        label = "完成"
    elif state == "error":
        label = "失败" + (f"：{footer}" if footer else "")
    else:
        label = "已中断"
    # running 不写秒数：步进卡的秒数无法实时跳动，冻着显得假（用户 2026-05-22）。
    # 只在终态(done/error/中断)写总耗时，那是准确的最终值。
    if elapsed is not None and state != "running":
        label = f"{label} · {elapsed:.0f}s"
    elements.append({"tag": "hr"})
    elements.append({"tag": "markdown",
                     "content": f"<font color='{STATUS_COLOR[state]}'>{label}</font>"})

    summary = body_text.strip().replace("\n", " ")[:40] or STATUS_LABEL[state]
    return {
        "schema": "2.0",
        "config": {
            "streaming_mode": state == "running",
            "summary": {"content": f"{name}: {summary}"},
        },
        "body": {"elements": elements},
    }


# ---- 飞书 IO --------------------------------------------------------------

def card_send(user_oid, card):
    """发一张交互卡片，返回 message_id 或 None"""
    content = json.dumps(card, ensure_ascii=False)
    p = subprocess.run(
        lark_argv("im", "+messages-send", "--as", "bot", "--user-id", user_oid,
                  "--msg-type", "interactive", "--content", content),
        capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace",
    )
    out = (p.stdout or "") + (p.stderr or "")
    if '"ok": true' not in out and '"ok":true' not in out:
        sys.stderr.write(f"[waga-stream] card_send failed: {out[:300]}\n")
        return None
    try:
        # 抓 message_id
        for tok in ('"message_id": "', '"message_id":"'):
            i = out.find(tok)
            if i >= 0:
                j = out.find('"', i + len(tok))
                return out[i + len(tok):j]
    except Exception:
        pass
    return None


def card_patch(mid, card):
    """patch 已发出的卡片；失败时打到 stderr（不致命，下一帧会重试）"""
    content = json.dumps(card, ensure_ascii=False)
    body = json.dumps({"content": content}, ensure_ascii=False)
    p = subprocess.run(
        lark_argv("api", "PATCH", f"/open-apis/im/v1/messages/{mid}",
                  "--as", "bot", "--data", body),
        capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace",
    )
    out = (p.stdout or "") + (p.stderr or "")
    if '"code": 0' not in out and '"code":0' not in out:
        sys.stderr.write(f"[waga-stream] card_patch failed: {out[:200]}\n")


def reacted_no(mid):
    """用户是否在这张卡上贴了 No 表情（reaction 即动作：No → 终止任务）。"""
    if not mid:
        return False
    p = subprocess.run(
        lark_argv("im", "reactions", "list", "--as", "bot",
                  "--params", json.dumps({"message_id": mid})),
        capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace",
    )
    return '"No"' in (p.stdout or "")


# ---- stream-json 解析 -----------------------------------------------------

def run(name, cwd, sid, first, user_oid, message):
    started = time.time()
    body_text = ""
    tools = []          # [{name, detail, running}]
    footer = ""
    mid = card_send(user_oid, build_card(name, "running", "", [], "启动中…", 0))
    record_sent(name, mid)
    last_patch = 0.0

    def maybe_patch(force=False):
        nonlocal last_patch
        now = time.time()
        if not force and now - last_patch < 1.2:
            return
        last_patch = now
        if mid:
            card_patch(mid, build_card(name, "running", body_text, tools, footer,
                                       now - started))

    cmd = [CLAUDE, "-p", "--output-format", "stream-json", "--verbose",
           "--dangerously-skip-permissions"]
    cmd += (["--session-id", sid] if first else ["--resume", sid])
    cmd += [message]

    state = "done"
    err_msg = ""
    result_text = ""
    try:
        proc = subprocess.Popen(
            cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env=ENV, encoding="utf-8", errors="replace", bufsize=1,
        )
    except Exception as e:
        state, err_msg = "error", f"无法启动 claude: {e}"
        if mid:
            card_patch(mid, build_card(name, "error", f"**⚠ 失败原因**\n{err_msg}", [], err_msg, 0))
        print(err_msg)
        return 1

    # ⚠ stderr 必须在跑的同时排空：否则 claude 往 stderr 写满管道缓冲(~64KB)会阻塞，
    #   整个 headless worker 静默挂死（正是要消灭的"卡住不报错"）。后台线程持续 drain。
    stderr_lines = []

    def drain_err():
        try:
            for ln in proc.stderr:
                stderr_lines.append(ln)
        except Exception:
            pass

    threading.Thread(target=drain_err, daemon=True).start()

    # reaction 即动作：后台线程轮询这张卡，用户贴 No → 杀 claude（终止任务）
    watch = {"interrupted": False, "done": False}

    def watcher():
        while not watch["done"]:
            if reacted_no(mid):
                watch["interrupted"] = True
                try:
                    proc.kill()
                except Exception:
                    pass
                return
            time.sleep(3)

    threading.Thread(target=watcher, daemon=True).start()

    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except Exception:
            continue
        et = ev.get("type")

        if et == "assistant":
            for blk in ev.get("message", {}).get("content", []):
                bt = blk.get("type")
                if bt == "text":
                    body_text += blk.get("text", "")
                elif bt == "tool_use":
                    tname = blk.get("name", "tool")
                    inp = blk.get("input", {})
                    detail = ""
                    for k in ("command", "file_path", "path", "pattern", "query", "url"):
                        if k in inp and isinstance(inp[k], str):
                            detail = inp[k][:80]
                            break
                    tools.append({"name": tname, "detail": detail, "running": True})
                    footer = f"调用 {tname}"
            maybe_patch()

        elif et == "user":
            # tool_result 回来：把对应工具标记完成
            for t in reversed(tools):
                if t.get("running"):
                    t["running"] = False
                    break
            footer = "处理结果…"
            maybe_patch()

        elif et == "result":
            result_text = ev.get("result", "") or ""
            if ev.get("is_error"):
                state = "error"
                err_msg = result_text[:800] or "未知错误"
            else:
                state = "done"
            if not body_text.strip() and result_text.strip():
                body_text = result_text

    proc.wait()
    watch["done"] = True
    for t in tools:
        t["running"] = False
    time.sleep(0.1)  # 让 drain 线程收尾
    stderr_tail = "".join(stderr_lines)[-800:].strip()
    if watch["interrupted"]:
        state = "interrupted"
    elif proc.returncode not in (0, None) and state != "error":
        state = "error"
        err_msg = stderr_tail or f"claude 退出码 {proc.returncode}"
    elif state == "error" and stderr_tail and stderr_tail not in err_msg:
        # 已是 error 但 stderr 有更具体内容 → 补上，让"什么原因"看得全
        err_msg = (err_msg + "\n" + stderr_tail)[:800]

    # 失败时把原因塞进卡片正文（大字可读），而不是只压在末尾小字状态行——
    # 用户明确要求"得知道到底什么原因"。
    final_body = body_text
    if state == "error" and err_msg:
        final_body = (body_text + "\n\n**⚠ 失败原因**\n" + err_msg).strip()

    if mid:
        card_patch(mid, build_card(name, state, final_body,
                                   tools, err_msg if state == "error" else "",
                                   time.time() - started))
    # 给 spawn 循环回最终文本
    print(result_text or body_text or "(claude 无输出)")
    return 0 if state == "done" else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--sid", required=True)
    ap.add_argument("--first", action="store_true")
    ap.add_argument("--user", required=True)
    ap.add_argument("message")
    a = ap.parse_args()
    sys.exit(run(a.name, a.cwd, a.sid, a.first, a.user, a.message))


if __name__ == "__main__":
    main()
