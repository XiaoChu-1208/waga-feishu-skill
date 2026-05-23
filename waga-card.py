#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
waga-card.py — 给【已开窗口的活会话】用的步进式进度卡片。

和 waga-stream.py 共用同一套卡片渲染（build_card / card_send / card_patch），
所以活会话刷的卡片跟 spawn worker 的长得一模一样、体验一致。区别只在驱动方式：
  · waga-stream.py：包着 claude -p 子进程，按 stream-json 自动逐步刷（worker 用）。
  · waga-card.py：由活会话的我手动驱动——接到任务先 start 发一张'处理中'卡，
    每做完一步 step 追加一行进度，完事 done 变绿定格。颗粒度是'每一步'而非逐字
    （用户 2026-05-22 明确：每一步也没关系，要的是一步步看进度的感觉）。

用法（同一个 name 跨多次调用共享一张卡，状态存 /tmp/waga_card_<name>.json）：
  py waga-card.py start <name> "收到，开始处理 X"
  py waga-card.py step  <name> "已读取配置" [--tool "Read:config.json"]
  py waga-card.py step  <name> "改完 3 处"
  py waga-card.py done  <name> "搞定，结果：…"
  py waga-card.py error <name> "失败原因"

start 会打印 message_id 到 stdout。done/error 跑完清状态文件。
"""
import argparse
import glob
import importlib.util
import json
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load_stream():
    spec = importlib.util.spec_from_file_location(
        "waga_stream", os.path.join(_HERE, "waga-stream.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


WS = _load_stream()
USER_OID = os.environ.get("WAGA_USER_ID", "")


def _state_path(name):
    return os.path.join(
        os.environ.get("TMP", os.environ.get("TEMP", "/tmp")),
        f"waga_card_{name}.json") if os.name == "nt" else f"/tmp/waga_card_{name}.json"


def _load(name):
    try:
        with open(_state_path(name), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _save(name, st):
    with open(_state_path(name), "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)


def _render(name, st, state, footer):
    elapsed = time.time() - st.get("started", time.time())
    return WS.build_card(name, state, st.get("body", ""),
                         st.get("tools", []), footer, elapsed)


def build_say_card(name, text):
    """一次性消息卡片：内联蓝色加粗 name（替代 [name] 方括号前缀）+ 空行 + 正文。
    用户 2026-05-22 拍板「A 内联蓝字」。<font> 的尖括号坑靠 waga-stream 的 lark_argv()
    node 直跑绕过（见那边注释）。与状态卡同一套 name_line，调性统一。"""
    summary = (text or name).replace("\n", " ")[:40]
    body_md = f"{WS.name_line(name)}\n\n{text}"
    return {
        "schema": "2.0",
        "config": {"summary": {"content": f"{name}: {summary}"}},
        "body": {"elements": [{"tag": "markdown", "content": body_md}]},
    }


def cmd_say(name, text):
    mid = WS.card_send(USER_OID, build_say_card(name, text))
    if not mid:
        sys.stderr.write("[waga-card] say: card_send 失败\n")
        return 1
    WS.record_sent(name, mid)
    print(mid)
    return 0


def build_online_card(name, cwd, sticky, kind="windowed"):
    """上线测通卡片（用户 2026-05-22 要求做个精致的）：内联蓝 name + 上线信息 + 用法。
    kind=windowed（/waga-on 开窗口）/ headless（spawn 无窗口）——用法区不同。"""
    head = (
        f"{WS.name_line(name)}　<font color='green'>已上线 · 测通</font>\n\n"
        f"**目录** `{cwd}`\n"
        f"**当前粘性目标** `{sticky}`\n\n"
    )
    if kind == "headless":
        cmds = (
            f"**派活/操作**（headless · 免值守）\n"
            f"`{name}: 任务`　处理 + 切粘性到我（结果走流式卡片）\n"
            f"`{name}:`　　　只切粘性\n"
            f"`[{name}] 任务`　纯一次性（不改粘性）\n"
            f"`{name}: /cd <路径>` 切目录　`{name}: /status` 状态　`{name}: /stop` 关闭"
        )
    else:
        cmds = (
            f"**触达我**\n"
            f"`{name}: 内容`　处理 + 切粘性到我\n"
            f"`{name}:`　　　只切粘性（无前缀消息默认到我）\n"
            f"`[{name}] 内容`　纯一次性（不改粘性）\n"
            f"`/who`　　　看谁在线"
        )
    return {
        "schema": "2.0",
        "config": {"summary": {"content": f"{name} 已上线"}},
        "body": {"elements": [{"tag": "markdown", "content": head + cmds}]},
    }


def cmd_online(name, cwd, sticky, kind="windowed"):
    mid = WS.card_send(USER_OID, build_online_card(name, cwd, sticky, kind))
    if not mid:
        sys.stderr.write("[waga-card] online: card_send 失败\n")
        return 1
    WS.record_sent(name, mid)
    print(mid)
    return 0


def build_who_card(entries):
    """/who 名册卡片。entries: [(name, type, cwd, age_sec)]，age<=35 视为 live。
    统一模型(用户 2026-05-23):都是 worker，只分 windowed(有窗口/waga-on) vs headless(无窗口/spawn)。"""
    body = [f"{WS.name_line('/who')}　waga 名册（35s 内有心跳 = live）"]
    if not entries:
        body.append("\n_（没有任何在线 worker）_")
    else:
        for nm, typ, cwd, age in entries:
            live = age <= 35
            status = "live" if live else "dead"
            color = "green" if live else "red"
            tcolor = "blue" if typ == "windowed" else ("grey" if typ == "headless" else "carmine")
            body.append(
                f"\n**{nm}** · <font color='{color}'>{status}</font>"
                f" · <font color='{tcolor}'>{typ}</font> · {age}s · `{cwd}`"
            )
    return {
        "schema": "2.0",
        "config": {"summary": {"content": "/who waga 名册"}},
        "body": {"elements": [{"tag": "markdown", "content": "".join(body)}]},
    }


def cmd_who():
    now = time.time()
    entries = []
    for f in glob.glob(os.path.join(WS._tmpdir(), "waga_alive_*.txt")):
        try:
            line = open(f, encoding="utf-8").read().strip()
        except OSError:
            continue
        parts = line.split("|")
        if len(parts) < 3:
            continue
        epoch = int(parts[0]) if parts[0].lstrip("-").isdigit() else 0
        nm, cwd = parts[1], parts[2]
        typ = parts[3] if len(parts) >= 4 and parts[3] else "?(旧)"
        entries.append((nm, typ, cwd, int(now - epoch)))
    entries.sort(key=lambda e: e[3])  # 最新心跳在前
    mid = WS.card_send(USER_OID, build_who_card(entries))
    if not mid:
        sys.stderr.write("[waga-card] who: card_send 失败\n")
        return 1
    WS.record_sent("who", mid)
    print(mid)
    return 0


def cmd_start(name, text):
    st = {"mid": None, "body": text or "处理中…", "tools": [], "started": time.time()}
    mid = WS.card_send(USER_OID, _render(name, st, "running", "处理中…"))
    if not mid:
        sys.stderr.write("[waga-card] start: card_send 失败\n")
        return 1
    st["mid"] = mid
    _save(name, st)
    WS.record_sent(name, mid)
    print(mid)
    return 0


def _append_line(st, text):
    if not text:
        return
    body = st.get("body", "")
    st["body"] = (body + "\n\n" + text) if body.strip() else text


def cmd_step(name, text, tool, tool_done):
    st = _load(name)
    if not st or not st.get("mid"):
        # 没 start 过就自动 start
        if cmd_start(name, text) != 0:
            return 1
        st = _load(name)
    else:
        _append_line(st, text)
    if tool_done:
        for t in reversed(st.get("tools", [])):
            if t.get("running"):
                t["running"] = False
                break
    if tool:
        tname, _, detail = tool.partition(":")
        st.setdefault("tools", []).append(
            {"name": tname.strip(), "detail": detail.strip(), "running": True})
    _save(name, st)
    WS.card_patch(st["mid"], _render(name, st, "running", "处理中…"))
    return 0


def cmd_done(name, text, state):
    st = _load(name)
    if not st or not st.get("mid"):
        # 没 start 过：直接发一张终态卡
        st = {"mid": None, "body": text or "", "tools": [], "started": time.time()}
        mid = WS.card_send(USER_OID, _render(name, st, state, ""))
        return 0 if mid else 1
    _append_line(st, text)
    for t in st.get("tools", []):
        t["running"] = False
    WS.card_patch(st["mid"], _render(name, st, state, ""))
    try:
        os.remove(_state_path(name))
    except OSError:
        pass
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("start"); p.add_argument("name"); p.add_argument("text", nargs="?", default="")
    p = sub.add_parser("step"); p.add_argument("name"); p.add_argument("text", nargs="?", default="")
    p.add_argument("--tool", default=""); p.add_argument("--tool-done", action="store_true")
    p = sub.add_parser("done"); p.add_argument("name"); p.add_argument("text", nargs="?", default="")
    p = sub.add_parser("error"); p.add_argument("name"); p.add_argument("text", nargs="?", default="")
    p = sub.add_parser("say"); p.add_argument("name"); p.add_argument("text", nargs="?", default="")
    p = sub.add_parser("online"); p.add_argument("name"); p.add_argument("cwd"); p.add_argument("sticky", nargs="?", default="main"); p.add_argument("kind", nargs="?", default="windowed")
    p = sub.add_parser("who")
    a = ap.parse_args()
    if a.cmd == "say":
        sys.exit(cmd_say(a.name, a.text))
    elif a.cmd == "online":
        sys.exit(cmd_online(a.name, a.cwd, a.sticky, a.kind))
    elif a.cmd == "who":
        sys.exit(cmd_who())
    elif a.cmd == "start":
        sys.exit(cmd_start(a.name, a.text))
    elif a.cmd == "step":
        sys.exit(cmd_step(a.name, a.text, a.tool, a.tool_done))
    elif a.cmd == "done":
        sys.exit(cmd_done(a.name, a.text, "done"))
    elif a.cmd == "error":
        sys.exit(cmd_done(a.name, a.text, "error"))


if __name__ == "__main__":
    main()
