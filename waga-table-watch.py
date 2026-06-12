#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
waga-table-watch.py —— 信号表轮询监听（卡片方案的「机读层」接收端）。

为什么要它：群里 agent 之间发的是 interactive 卡片（人看好看），但卡片正文 API 读不出来。
所以每条群发言都把同一句话写进信号表当机读镜像（waga-gcard.py 自动双写）。本脚本每 ~20s
轮询信号表，发现【发给我(Waga)的新行】就 emit 一行唤醒会话——带上正文 + 关联的卡片 mid，
我据此①给对方那张卡贴 reaction（情绪层，逻辑同 waga 技能）②读懂正文做回应。

被 Monitor 持久运行（输出 [WAGA-SIG] 行触发 task-notification）。
唤醒条件：发起方≠ME 且 接收方∈{ME,所有人} 且 状态=待处理 且 record_id 未见过。
"""
import json
import os
import subprocess
import sys
import time

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


ME = _env("WAGA_NAME", "Waga")   # 本 agent 名（别的机器改 .env 的 WAGA_NAME，如 Dancer）
BASE = _env("WAGA_SIGNAL_BASE", "")   # 资源 ID 走 .env，公开仓库不带具体 ID
TABLE = _env("WAGA_SIGNAL_TABLE", "")
WAGA_DIR = _env("WAGA_DIR", _HERE)
LARK = os.environ.get("LARK_CLI_BIN", "lark-cli")
SEEN = "/tmp/waga_sig_seen.txt"
ENV = {**os.environ, "LARK_CLI_NO_PROXY": "1"}


def _seen_load():
    try:
        return set(open(SEEN, encoding="utf-8").read().split())
    except OSError:
        return set()


def _seen_add(rid):
    with open(SEEN, "a", encoding="utf-8") as f:
        f.write(rid + "\n")


def _cell(row, fields, name):
    try:
        v = row[fields.index(name)]
    except ValueError:
        return ""
    if isinstance(v, list):
        return (v[0] if v else "")
    return v if v is not None else ""


def poll():
    p = subprocess.run(
        [LARK, "base", "+record-list", "--as", "user", "--base-token", BASE,
         "--table-id", TABLE, "--format", "json", "--limit", "50"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=ENV)
    out = p.stdout or ""
    try:
        d = json.loads(out)["data"]
    except Exception:
        if "token" in (out.lower()) and ("expired" in out.lower() or "invalid" in out.lower()):
            print(f"[WAGA-SIG-ERR] 信号表读取 token 失效：{out[:120]}", flush=True)
        return
    fields = d.get("fields") or []
    rows = d.get("data") or []
    rids = d.get("record_id_list") or []
    seen = _seen_load()
    for i, row in enumerate(rows):
        rid = rids[i] if i < len(rids) else None
        if not rid or rid in seen:
            continue
        frm = _cell(row, fields, "发起方")
        to = _cell(row, fields, "接收方")
        status = _cell(row, fields, "状态")
        if frm == ME or to not in (ME, "所有人") or status != "待处理":
            # 不是发给我的新待办 → 也登记为已见（避免反复扫）。但只登记别人发的；
            # 我自己发的镜像直接跳过登记会一直重扫，所以也登记。
            if rid:
                _seen_add(rid)
            continue
        _seen_add(rid)
        content = _cell(row, fields, "内容")
        card = _cell(row, fields, "关联")
        typ = _cell(row, fields, "类型")
        print(f"[WAGA-SIG] 来自 {frm} · {typ} · card={card} · rid={rid}\n　内容：{content}", flush=True)
        print(f"[WAGA-SIG-REMINDER] 处理：①给对方卡片贴情绪 reaction(同 waga 技能,读懂内容贴2-4个真实表情): "
              f"bash \"{WAGA_DIR}/waga-react.sh\" vibe {card} \"E1 E2 E3\"  "
              f"②回应就发卡+镜像: python3 \"{WAGA_DIR}/waga-gcard.py\" post --agent Waga --action <动作> --to {frm} --content \"...\"  "
              f"③处理完把该行状态改已完成: python3 \"{WAGA_DIR}/waga-table-watch.py\" done {rid}", flush=True)


def cmd_done(rid):
    """把某行状态改「已完成」（处理完调）。"""
    body = {"record_id_list": [rid], "patch": {"状态": "已完成"}}
    subprocess.run(
        [LARK, "base", "+record-batch-update", "--as", "user", "--base-token", BASE,
         "--table-id", TABLE, "--json", json.dumps(body, ensure_ascii=False)],
        env=ENV)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "done":
        cmd_done(sys.argv[2])
        return
    # seed：首轮把现有行全标已见，避免回溯
    p = subprocess.run(
        [LARK, "base", "+record-list", "--as", "user", "--base-token", BASE,
         "--table-id", TABLE, "--format", "json", "--limit", "50"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", env=ENV)
    try:
        for rid in json.loads(p.stdout)["data"].get("record_id_list", []):
            if rid not in _seen_load():
                _seen_add(rid)
    except Exception:
        pass
    print(f"[WAGA-SIG] 信号表轮询监听已挂（每 20s 拉表，发给 {ME} 的新行唤醒我）", flush=True)
    while True:
        try:
            poll()
        except Exception as e:
            print(f"[WAGA-SIG-ERR] {e}", flush=True)
        time.sleep(20)


if __name__ == "__main__":
    main()
