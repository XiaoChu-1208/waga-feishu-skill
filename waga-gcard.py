#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
waga-gcard.py —— 协作群【卡片显示层 + 信号表机读层】二合一发卡器。

2026-06-12 定稿方案（老板要卡片、又要 agent 能互读）：
  · 卡片正文 API 读不出来（连自己发的卡读回都是「请升级客户端」占位符，summary 等字段也不留）
    → 卡片只能给【人】看。
  · 所以每条群发言【双写】：
      (1) 发一张漂亮的 interactive 卡片到群（人看，按 agent 上色）
      (2) 把同一句话写进【信号表】当机读镜像（agent 之间靠轮询读表互读，关联=卡片 mid）
  · 对端 agent 不读卡片，读信号表。Waga 侧有「信号表轮询监听」(waga-table-watch)每 ~20s 拉表→秒收。

用法：
  waga-gcard.py post --agent Waga --action 交接 --content "正文" [--to Dolan|Dancer|所有人] [--at ou_xxx]
  --to / --at 决定表镜像的「接收方」；--at 还会在卡片里 @人。二者可同时给。

agent 预设（色 + 角色）：Waga=blue/本地手·个人Mac，Dolan=purple/云端手·高权限，Dancer=teal/本地手·另一台Mac。

————— 给 Dolan 的协议（照此做，群里才统一且能互读）—————
你每条群发言也【双写】：
  1) 发 interactive 卡片到群（schema 2.0，header 用你的紫色 + 角色 + 【动作】，正文 markdown，hr，状态行）
  2) 往信号表写一行：发起方=Dolan，接收方=Waga/Dancer/所有人，类型=交接|讨论|知会|回执，内容=正文，关联=卡片mid，状态=待处理
你读对方消息：轮询信号表，取 接收方∈{你,所有人} 且 发起方≠你 且 状态=待处理 的行，读「内容」字段；处理完把状态改「已完成」。
信号表：base=WAGA_SIGNAL_BASE，table=WAGA_SIGNAL_TABLE（见 .env）。写用 `lark-cli base +record-batch-create --as user`。
————————————————————————————————————————————————
"""
import argparse
import json
import os
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))


def _env(key, default=""):
    v = os.environ.get(key)
    if v:
        return v
    try:
        with open(os.path.join(_HERE, ".env"), encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("export "):
                    line = line[7:]
                k, _, val = line.partition("=")
                if k.strip() == key:
                    return val.strip().strip("'\"")
    except OSError:
        pass
    return default


# 资源 ID 全走 .env（gitignore，本机私有）；公开仓库不带任何具体 ID。
GCHAT = _env("WAGA_GROUP_CHAT_ID", "")
SIG_BASE = _env("WAGA_SIGNAL_BASE", "")
SIG_TABLE = _env("WAGA_SIGNAL_TABLE", "")
LARK = os.environ.get("LARK_CLI_BIN", "lark-cli")

# agent -> (卡片色, 角色)
AGENTS = {
    "Waga":   ("blue",   "本地手·个人Mac"),
    "Dolan":  ("purple", "云端手·高权限"),
    "Dancer": ("teal",   "本地手·另一台Mac"),
}
# open_id -> agent 名（用于 --at 反查接收方）。从 .env 的 WAGA_PEER_OIDS 读，
# 格式 "ou_xxx:Dolan,ou_yyy:Dancer"；不配也行（那就显式传 --to）。
OID2AGENT = {}
for _pair in _env("WAGA_PEER_OIDS", "").split(","):
    if ":" in _pair:
        _oid, _nm = _pair.split(":", 1)
        OID2AGENT[_oid.strip()] = _nm.strip()
# 动作 -> (卡片状态色, 信号表「类型」选项)
ACTION_COLOR = {
    "收到": "blue", "进度": "blue", "讨论": "blue", "知会": "grey",
    "完成": "green", "交接": "orange", "失败": "red", "中断": "red",
}
ACTION_TYPE = {  # 信号表 类型 字段只有 交接/讨论/知会/回执
    "交接": "交接", "讨论": "讨论", "收到": "回执", "回执": "回执",
}


def _env_run():
    return {**os.environ, "LARK_CLI_NO_PROXY": "1"}


def build_card(agent, action, content, at=None):
    color, role = AGENTS.get(agent, ("grey", ""))
    scolor = ACTION_COLOR.get(action, "blue")
    header = (f"<font color='{color}'>**{agent}**</font> "
              f"<font color='grey'>· {role}</font>　"
              f"<font color='{scolor}'>【{action}】</font>")
    at_prefix = f'<at id="{at}"></at> ' if at else ""
    summary = content.replace("\n", " ")[:40]
    return {
        "schema": "2.0",
        "config": {"summary": {"content": f"{agent}: {summary}"}},
        "body": {"elements": [
            {"tag": "markdown", "content": header},
            {"tag": "markdown", "content": at_prefix + content},
            {"tag": "hr"},
            {"tag": "markdown", "content": f"<font color='{scolor}'>{action}</font>"},
        ]},
    }


def send_card(card, chat_id):
    content = json.dumps(card, ensure_ascii=False)
    p = subprocess.run(
        [LARK, "im", "+messages-send", "--as", "bot", "--chat-id", chat_id,
         "--msg-type", "interactive", "--content", content],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=_env_run())
    out = (p.stdout or "") + (p.stderr or "")
    if '"ok": true' not in out and '"ok":true' not in out:
        sys.stderr.write(f"[waga-gcard] card send failed: {out[:300]}\n")
        return None
    for tok in ('"message_id": "', '"message_id":"'):
        i = out.find(tok)
        if i >= 0:
            return out[i + len(tok):out.find('"', i + len(tok))]
    return None


def write_mirror(agent, action, content, to, ref):
    """把同一句话写进信号表当机读镜像。失败只告警（卡片已发出，不致命）。"""
    typ = ACTION_TYPE.get(action, "知会")
    row = {"fields": ["内容", "发起方", "接收方", "类型", "状态", "关联"],
           "rows": [[content, agent, to, typ, "待处理", ref or "-"]]}
    p = subprocess.run(
        [LARK, "base", "+record-batch-create", "--as", "user",
         "--base-token", SIG_BASE, "--table-id", SIG_TABLE,
         "--json", json.dumps(row, ensure_ascii=False)],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=_env_run())
    out = (p.stdout or "") + (p.stderr or "")
    if '"ok": true' not in out and '"ok":true' not in out:
        sys.stderr.write(f"[waga-gcard] mirror write failed: {out[:200]}\n")
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("post")
    p.add_argument("--agent", required=True)
    p.add_argument("--action", required=True)
    p.add_argument("--content", required=True)
    p.add_argument("--at", default="")
    p.add_argument("--to", default="")
    p.add_argument("--chat", default=GCHAT)
    p.add_argument("--no-mirror", action="store_true", help="只发卡片不写表（纯给人看的状态卡用）")
    a = ap.parse_args()
    if a.cmd == "post":
        at = a.at or None
        # 接收方：--to 优先；否则 --at 反查；否则 所有人
        to = a.to or (OID2AGENT.get(a.at, "") if a.at else "") or "所有人"
        mid = send_card(build_card(a.agent, a.action, a.content, at=at), a.chat)
        if not mid:
            sys.exit(1)
        if not a.no_mirror:
            write_mirror(a.agent, a.action, a.content, to, mid)
        print(mid)


if __name__ == "__main__":
    main()
