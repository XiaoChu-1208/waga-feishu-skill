#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
waga-stream-cursor.py — waga-stream.py 的 Cursor CLI 版。

跑一次 headless `cursor-agent`，把过程实时刷到一张飞书卡片上。与 claude 版的唯一
区别是底层换成 `cursor-agent -p --output-format stream-json`，并因此带来三点适配：

  1. 模型可选：--model（gemini-3.1-pro / gpt-5.5-high / grok-4.3 / claude-4.6-sonnet... ）。
  2. session 续接：cursor-agent 自己生成 session_id（在 system/init 事件里返回），
     不像 claude 用 --session-id 由调用方指定。所以这里：首次跑不带 --resume，从
     init/result 事件抓 session_id 写回 --sidfile；之后用 --resume <id> 续上下文。
  3. 没有 --append-system-prompt：首次消息把角色说明前置进 prompt 文本。

事件格式（实测 cursor-agent 2026.05）：
  {"type":"system","subtype":"init","session_id":"...","model":"...","permissionMode":...}
  {"type":"user","message":{...}}
  {"type":"thinking","subtype":"delta","text":"..."}            ← 思考，折进 footer
  {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":...}]}}
  {"type":"result","subtype":"success","is_error":false,"result":"...","session_id":"..."}
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import threading
import time

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

LARK = shutil.which("lark-cli") or "lark-cli"
CURSOR = shutil.which("cursor-agent") or "cursor-agent"
ENV = dict(os.environ, LARK_CLI_NO_PROXY="1")

# 注入给 headless cursor-agent 的角色说明。cursor-agent 没有 --append-system-prompt，
# 所以首次消息把这段前置进 prompt。告诉它：你被 waga 远程驱动、管线已处理、别提内部机制。
SYSTEM_PROMPT = (
    "【系统设定，请遵守但不要复述】你是一个通过飞书 Waga 被远程访问的 Cursor 会话。"
    "用户在外面用飞书私聊跟你对话，你的回复会被外部管线自动转成飞书卡片发出去——"
    "监听器、卡片、表情、om_xxx 消息 id、粘性目标、/waga-on 这些底层管线都已替你处理好了，"
    "你既不需要也不要向用户提起它们，更不要让用户去『挂监听器』或解释这些机制。"
    "如果消息里夹带历史聊天记录或 om_ 开头的 id，那是上下文噪音，忽略即可。"
    "第一次有人打招呼时，给一句简短自然的开场白即可，不要罗列内部机制。\n\n用户消息：\n"
)

_NODE = shutil.which("node")
_LARK_RUNJS = os.path.expandvars(r"%APPDATA%\npm\node_modules\@larksuite\cli\scripts\run.js")


def lark_argv(*args):
    if _NODE and os.path.exists(_LARK_RUNJS):
        return [_NODE, _LARK_RUNJS, *args]
    return [LARK, *args]


def _tmpdir():
    return os.environ.get("TMP") or os.environ.get("TEMP") or "/tmp"


SENT_FILE = os.path.join(_tmpdir(), "waga_sent.txt")


def record_sent(name, mid):
    if not mid:
        return
    try:
        with open(SENT_FILE, "a", encoding="utf-8") as f:
            f.write(f"{mid}|{name}\n")
    except Exception:
        pass


# ---- 卡片渲染（与 waga-stream.py 完全一致，保持飞书侧观感统一）-------------

STATUS_LABEL = {"running": "运行中", "done": "完成", "error": "失败", "interrupted": "已中断"}
STATUS_COLOR = {"running": "grey", "done": "green", "error": "red", "interrupted": "grey"}
CARD_MD_CAP = 3500


def _clip(text, cap=CARD_MD_CAP):
    if len(text) <= cap:
        return text
    head = cap * 2 // 3
    tail = cap - head
    return text[:head] + "\n\n…（中间省略）…\n\n" + text[-tail:]


def name_line(name, model=""):
    # 引擎标签（cursor）来自环境变量 WAGA_ENGINE_LABEL；模型名紧随其后。
    # 例：**api** · cursor · gemini-3.1-pro
    tag = f"<font color='blue'>**{name}**</font>"
    label = os.environ.get("WAGA_ENGINE_LABEL", "").strip()
    if label:
        tag += f" <font color='grey'>· {label}</font>"
    if model:
        tag += f" <font color='grey'>· {model}</font>"
    return tag


def build_card(name, state, body_text, tools, footer, elapsed, model=""):
    elements = [{"tag": "markdown", "content": name_line(name, model)}]

    if body_text.strip():
        elements.append({"tag": "markdown", "content": _clip(body_text.strip())})

    if tools:
        lines = []
        for t in tools[-12:]:
            mark = "·" if t.get("running") else "✓"
            detail = t.get("detail", "")
            detail = (" " + detail) if detail else ""
            lines.append(f"`{mark}` **{t['name']}**{detail}")
        if len(tools) > 12:
            lines.insert(0, f"_（前 {len(tools) - 12} 个工具调用已折叠）_")
        elements.append({"tag": "hr"})
        elements.append({"tag": "markdown", "content": "\n".join(lines)})

    if state == "running":
        label = footer or "处理中…"
    elif state == "done":
        label = "完成"
    elif state == "error":
        label = "失败" + (f"：{footer}" if footer else "")
    else:
        label = "已中断"
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


# ---- 飞书 IO（与 waga-stream.py 一致）-------------------------------------

def card_send(user_oid, card):
    content = json.dumps(card, ensure_ascii=False)
    p = subprocess.run(
        lark_argv("im", "+messages-send", "--as", "bot", "--user-id", user_oid,
                  "--msg-type", "interactive", "--content", content),
        capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace",
    )
    out = (p.stdout or "") + (p.stderr or "")
    if '"ok": true' not in out and '"ok":true' not in out:
        sys.stderr.write(f"[waga-stream-cursor] card_send failed: {out[:300]}\n")
        return None
    try:
        for tok in ('"message_id": "', '"message_id":"'):
            i = out.find(tok)
            if i >= 0:
                j = out.find('"', i + len(tok))
                return out[i + len(tok):j]
    except Exception:
        pass
    return None


def card_patch(mid, card):
    content = json.dumps(card, ensure_ascii=False)
    body = json.dumps({"content": content}, ensure_ascii=False)
    p = subprocess.run(
        lark_argv("api", "PATCH", f"/open-apis/im/v1/messages/{mid}",
                  "--as", "bot", "--data", body),
        capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace",
    )
    out = (p.stdout or "") + (p.stderr or "")
    if '"code": 0' not in out and '"code":0' not in out:
        sys.stderr.write(f"[waga-stream-cursor] card_patch failed: {out[:200]}\n")


def reacted_no(mid):
    if not mid:
        return False
    p = subprocess.run(
        lark_argv("im", "reactions", "list", "--as", "bot",
                  "--params", json.dumps({"message_id": mid})),
        capture_output=True, text=True, env=ENV, encoding="utf-8", errors="replace",
    )
    return '"No"' in (p.stdout or "")


# ---- 工具事件解析（cursor-agent 专用，实测格式）--------------------------
# cursor-agent 的工具调用事件：
#   {"type":"tool_call","subtype":"started"|"completed","call_id":"...",
#    "tool_call":{"<x>ToolCall":{"args":{...},"description":"...","result":{...}}}}
# 工具名藏在内层 key（shellToolCall→Shell），detail 取 command/path/description。

_TOOL_DISPLAY = {
    "shell": "Shell", "read": "Read", "write": "Write", "edit": "Edit",
    "ls": "Ls", "grep": "Grep", "glob": "Glob", "search": "Search",
    "codebaseSearch": "Search", "readFile": "Read", "writeFile": "Write",
    "delete": "Delete", "todoWrite": "Todo", "webSearch": "Web", "fetch": "Fetch",
}


def _friendly_tool(key):
    """shellToolCall → Shell；未知的去掉 ToolCall 后首字母大写。"""
    if not key:
        return "tool"
    base = key[:-8] if key.endswith("ToolCall") else key
    if base in _TOOL_DISPLAY:
        return _TOOL_DISPLAY[base]
    return base[:1].upper() + base[1:] if base else "tool"


def _tool_detail(inner):
    """从内层 toolCall 取可读 detail：优先 args 里的命令/路径，回退 description。"""
    if not isinstance(inner, dict):
        return ""
    args = inner.get("args", {})
    if isinstance(args, dict):
        for k in ("command", "file_path", "filePath", "path", "relativePath",
                  "absolutePath", "pattern", "query", "url", "searchTerm"):
            v = args.get(k)
            if isinstance(v, str) and v.strip():
                return v.strip()[:90]
    desc = inner.get("description")
    if isinstance(desc, str) and desc.strip():
        return desc.strip()[:90]
    return ""


def _parse_tool_call(ev):
    """返回 (subtype, call_id, friendly_name, detail)。"""
    subtype = ev.get("subtype")
    call_id = ev.get("call_id") or ""
    tc = ev.get("tool_call") or {}
    key = next((k for k in tc.keys()), "") if isinstance(tc, dict) else ""
    inner = tc.get(key, {}) if isinstance(tc, dict) else {}
    return subtype, call_id, _friendly_tool(key), _tool_detail(inner)


# ---- stream-json 解析（cursor-agent 版）----------------------------------

def run(name, cwd, sidfile, resume_id, model, user_oid, message):
    started = time.time()
    body_text = ""
    tools = []
    tool_by_id = {}   # call_id → tool 条目，按 id 去重（started/completed 不重复计）
    footer = ""
    captured_sid = ""
    mid = card_send(user_oid, build_card(name, "running", "", [], "启动中…", 0, model))
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
                                       now - started, model))

    # 首次消息前置角色说明；续接时直接发原文
    prompt = message if resume_id else (SYSTEM_PROMPT + message)

    cmd = [CURSOR, "-p", "--output-format", "stream-json", "--force", "--trust"]
    if model:
        cmd += ["--model", model]
    if resume_id:
        cmd += ["--resume", resume_id]
    cmd += [prompt]

    state = "done"
    err_msg = ""
    result_text = ""
    try:
        proc = subprocess.Popen(
            cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env=ENV, encoding="utf-8", errors="replace", bufsize=1,
        )
    except Exception as e:
        state, err_msg = "error", f"无法启动 cursor-agent: {e}"
        if mid:
            card_patch(mid, build_card(name, "error", f"**⚠ 失败原因**\n{err_msg}", [], err_msg, 0, model))
        print(err_msg)
        return 1

    stderr_lines = []

    def drain_err():
        try:
            for ln in proc.stderr:
                stderr_lines.append(ln)
        except Exception:
            pass

    threading.Thread(target=drain_err, daemon=True).start()

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

        # 任何事件都带 session_id —— 抓第一个，落盘供下次 --resume
        if not captured_sid and ev.get("session_id"):
            captured_sid = ev["session_id"]

        # 抓实际使用的模型（若事件中有返回，则以实际运行的模型为准）
        if ev.get("model"):
            model = ev["model"]

        if et == "system":
            footer = "已连接…"
            maybe_patch()

        elif et == "thinking":
            footer = "思考中…"
            maybe_patch()

        elif et == "assistant":
            # cursor-agent 的 assistant 只放文本；工具调用走独立 tool_call 事件
            for blk in ev.get("message", {}).get("content", []):
                if blk.get("type") == "text":
                    body_text += blk.get("text", "")
            maybe_patch()

        elif et == "tool_call":
            subtype, call_id, fname, detail = _parse_tool_call(ev)
            if subtype == "completed":
                ent = tool_by_id.get(call_id)
                if ent:
                    ent["running"] = False
                    if detail and not ent.get("detail"):
                        ent["detail"] = detail
                else:
                    tools.append({"name": fname, "detail": detail, "running": False})
                footer = "处理结果…"
            else:  # started（或缺省）
                if call_id and call_id in tool_by_id:
                    tool_by_id[call_id]["running"] = True
                else:
                    ent = {"name": fname, "detail": detail, "running": True}
                    tools.append(ent)
                    if call_id:
                        tool_by_id[call_id] = ent
                footer = f"{fname}" + (f" · {detail}" if detail else "")
            maybe_patch()

        elif et == "result":
            result_text = ev.get("result", "") or ""
            if ev.get("is_error") or ev.get("subtype") == "error":
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
    time.sleep(0.1)
    stderr_tail = "".join(stderr_lines)[-800:].strip()
    if watch["interrupted"]:
        state = "interrupted"
    elif proc.returncode not in (0, None) and state != "error":
        state = "error"
        err_msg = stderr_tail or f"cursor-agent 退出码 {proc.returncode}"
    elif state == "error" and stderr_tail and stderr_tail not in err_msg:
        err_msg = (err_msg + "\n" + stderr_tail)[:800]

    # 落盘 session_id 供下次续接（仅成功且抓到才写，避免把错误状态固化）
    if captured_sid and sidfile and state != "error":
        try:
            with open(sidfile, "w", encoding="utf-8") as f:
                f.write(captured_sid)
        except Exception:
            pass

    final_body = body_text
    if state == "error" and err_msg:
        final_body = (body_text + "\n\n**⚠ 失败原因**\n" + err_msg).strip()

    if mid:
        card_patch(mid, build_card(name, state, final_body, tools,
                                   err_msg if state == "error" else "",
                                   time.time() - started, model))
    print(result_text or body_text or "(cursor-agent 无输出)")
    return 0 if state == "done" else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--sidfile", required=True, help="写回 cursor-agent 生成的 session_id")
    ap.add_argument("--resume-id", default="", help="非空则 --resume <id> 续上下文")
    ap.add_argument("--model", default="", help="cursor-agent --model，空=账号默认")
    ap.add_argument("--user", required=True)
    ap.add_argument("message")
    a = ap.parse_args()
    sys.exit(run(a.name, a.cwd, a.sidfile, a.resume_id, a.model, a.user, a.message))


if __name__ == "__main__":
    main()
