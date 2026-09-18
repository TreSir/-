#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《黑页》项目审计 —— 架构规约的执行器。

用法（在 TreSir/ 目录，或任意位置传路径）：

    python tools/audit.py                # 审计当前目录所在的 Godot 项目
    python tools/audit.py --strict       # 把启发式警告也算失败
    python tools/audit.py --path <项目根>

退出码：0 = 干净（或只有已知白名单项），1 = 有真问题。可直接挂进提交前钩子。

────────────────────────────────────────────────────────────────
⚠️ 先读这段再改这个脚本

自动审计只能**提出候选**，每一条都必须人工甄别过再动手。实测踩过的假阳性：

  1. 立绘「没人引用」—— 路径是**动态拼**的：
     "res://assets/portraits/black_page_portrait_%s%s.png" % [id, suffix]
  2. 旗标「从没被提及」—— 名字是**动态拼**的：
     "person." + id + ".identity" / "action." + id + ".done" / "ui." + key
  3. 服务公开方法「没人调」—— 模块**内部**互相调用的辅助函数
  4. project.godot「指向已删文件」—— res:// 不是文件系统路径，要先剥前缀
  5. 英文注释「残留」—— 数学公式（scale = max(view / tex)）语言中立，不该报

所以本脚本把这些已知模式做了**显式白名单**（见 DYNAMIC_PATTERNS / KNOWN_OK）。
看到白名单命中，先想清楚「它是不是动态拼的」再决定要不要动它。
────────────────────────────────────────────────────────────────
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

GAME_SUFFIXES = {".gd", ".tscn", ".tres", ".json", ".godot", ".cfg"}

# ---------------------------------------------------------------- 白名单

## 路径动态拼出来的素材（静态扫描看不到引用，但运行时用得上）。
DYNAMIC_ASSET_PATTERNS = [
    re.compile(r"black_page_portrait_\w+\.png$"),   # main.gd 拼 person id + 清晰度后缀
]

## 名字动态拼出来的旗标前缀（声明了也不会被文本扫到，属于正常）。
DYNAMIC_FLAG_PREFIXES = (
    "person.", "clue.", "action.", "case.", "event.", "ui.", "minigame.",
)

## 已知的「故意保留」项，不算问题。
KNOWN_OK = {
    # 没人调用的能力，但那是缺功能不是多代码 —— 保留，等接线。
    "unused_funcs": {"fade_out"},
}

## 文件头注释里的公式/专有名词允许是英文。
FORMULA_LINE = re.compile(r"[=<>]|max\(|min\(|UV|JSON|OGL|API|Gui|ID")

# ---------------------------------------------------------------- 工具


def is_game_file(p: Path) -> bool:
    return "addons" not in p.parts and ".godot" not in p.parts


def strip_comments(txt: str, suffix: str) -> str:
    """GDScript 的行注释去掉再参与匹配。

    **注释不是引用。** 反例：main.gd 关于「表现层不读数据文件」的注释里写着
    `data_loader`，那只是在说规矩，不是在读文件；不剥注释的话这条会被当成违规，
    而且「某个名字只在注释里出现过」也会把死代码藏起来。
    """
    if suffix != ".gd":
        return txt
    return "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith("#"))


def load_texts(root: Path) -> tuple[dict[Path, str], str]:
    blobs: dict[Path, str] = {}
    for p in root.rglob("*"):
        if not p.is_file() or p.suffix not in GAME_SUFFIXES or not is_game_file(p):
            continue
        try:
            blobs[p] = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
    return blobs, "\n".join(blobs.values())


def code_only(blobs: dict[Path, str]) -> str:
    return "\n".join(strip_comments(t, p.suffix) for p, t in blobs.items())


class Audit:
    def __init__(self, root: Path, strict: bool) -> None:
        self.root = root
        self.strict = strict
        self.blobs, _ = load_texts(root)
        # 参与「有没有人引用」判断的一律是**去掉注释的代码**。
        self.alltext = code_only(self.blobs)
        self.problems: list[str] = []
        self.warnings: list[str] = []

    # --- 报告 -------------------------------------------------------------

    def ok(self, label: str) -> None:
        print(f"  {label:<34} OK")

    def bad(self, label: str, items: list[str]) -> None:
        if not items:
            self.ok(label)
            return
        print(f"  {label:<34} {len(items)} 处")
        for it in items:
            print(f"       ✗ {it}")
        self.problems.extend(items)

    def warn(self, label: str, items: list[str]) -> None:
        if not items:
            self.ok(label)
            return
        print(f"  {label:<34} {len(items)} 处（启发式，需人工判断）")
        for it in items:
            print(f"       ? {it}")
        self.warnings.extend(items)

    # --- 各项检查 ---------------------------------------------------------

    def orphan_uid(self) -> list[str]:
        return [
            p.relative_to(self.root).as_posix()
            for p in self.root.rglob("*.gd.uid")
            if not p.with_suffix("").exists()
        ]

    def orphan_import(self) -> list[str]:
        return [
            p.relative_to(self.root).as_posix()
            for p in self.root.rglob("*.import")
            if not Path(str(p)[:-7]).exists()
        ]

    def unused_assets(self) -> list[str]:
        out = []
        for p in (self.root / "assets").rglob("*"):
            if not p.is_file() or p.suffix not in (".png", ".ogg", ".wav", ".jpg"):
                continue
            if any(rx.search(p.as_posix()) for rx in DYNAMIC_ASSET_PATTERNS):
                continue  # 动态拼路径，跳过
            rel = "res://" + p.relative_to(self.root).as_posix()
            if rel not in self.alltext and p.name not in self.alltext:
                out.append(rel)
        return out

    def unused_funcs(self) -> list[str]:
        funcs: dict[str, list[str]] = {}
        for p, txt in self.blobs.items():
            if p.suffix != ".gd":
                continue
            for m in re.finditer(r"^(?:static )?func ([A-Za-z_][A-Za-z0-9_]*)\(?", txt, re.M):
                funcs.setdefault(m.group(1), []).append(p.relative_to(self.root).as_posix())
        return [
            f"{n}  @ {w[0]}"
            for n, w in sorted(funcs.items())
            if self.alltext.count(n) <= 1 and n not in KNOWN_OK["unused_funcs"]
        ]

    def unused_consts(self) -> list[str]:
        ui = self.blobs.get(self.root / "scripts/black_page/ui_style.gd", "")
        if not ui:
            return []
        return [
            m.group(1)
            for m in re.finditer(r"^const ([A-Z][A-Z0-9_]*)", ui, re.M)
            if self.alltext.count(m.group(1)) <= 1
        ]

    def dead_signals(self) -> list[str]:
        bus = self.root / "scripts/services/event_bus.gd"
        txt = self.blobs.get(bus, "")
        rest = self.alltext.replace(txt, "")
        return [
            s
            for s in re.findall(r"^signal ([a-z_][a-z0-9_]*)", txt, re.M)
            if len(re.findall(r"\b" + s + r"\b", rest)) == 0
        ]

    def layering_violations(self) -> list[str]:
        """铁律 1：只有 investigation.gd 能写 GameState。"""
        out = []
        for p in (self.root / "scripts").rglob("*.gd"):
            if p.name == "investigation.gd":
                continue
            if "GameState." in self.blobs.get(p, ""):
                out.append(p.relative_to(self.root).as_posix())
        return out

    def ui_reads_data(self) -> list[str]:
        """铁律 2：表现层不读数据文件。"""
        out = []
        for p in (self.root / "scripts/black_page").rglob("*.gd"):
            txt = strip_comments(self.blobs.get(p, ""), ".gd")
            if "FileAccess" in txt or "JSON.parse_string" in txt:
                out.append(p.relative_to(self.root).as_posix())
        return out

    def project_refs(self) -> list[str]:
        txt = self.blobs.get(self.root / "project.godot", "")
        out = []
        for m in re.finditer(r'="(\*?)(res://[^"]+)"', txt):
            if not (self.root / m.group(2).replace("res://", "")).exists():
                out.append(m.group(2))
        return out

    def english_comments(self) -> list[str]:
        out = []
        for p, txt in self.blobs.items():
            if p.suffix != ".gd":
                continue
            for i, line in enumerate(txt.splitlines(), 1):
                s = line.strip()
                if not s.startswith("##"):
                    continue
                # 文档注释里  之后缩进 >= 4 空格的是**代码示例**，不是英文残留。
                if s[2:].startswith("    "):
                    continue
                if re.search(r"[\u4e00-\u9fff]", s):
                    continue
                # 文档注释里缩进 >= 4 空格的行是**代码示例**，不是英文残留。
                if line.startswith("    "):
                    continue
                if re.search(r"[a-zA-Z]{5,}", s) and not FORMULA_LINE.search(s):
                    out.append(f"{p.relative_to(self.root).as_posix()}:{i}")
        return out

    def loader_vs_data(self) -> list[str]:
        """data/black_page/*.json 与 data_loader 的加载列表必须一一对应。"""
        loader = self.blobs.get(self.root / "scripts/black_page/data_loader.gd", "")
        m = re.search(r"for name in \[([^\]]+)\]", loader)
        if not m:
            return ["data_loader.gd 里找不到加载列表"]
        listed = set(re.findall(r'"(\w+)"', m.group(1)))
        on_disk = {p.stem for p in (self.root / "data/black_page").glob("*.json")}
        out = [f"声明了但文件不存在: {n}.json" for n in sorted(listed - on_disk)]
        out += [f"文件存在但没被加载: {n}.json" for n in sorted(on_disk - listed)]
        return out

    def flags_declared_unused(self) -> list[str]:
        """声明了但全项目从没被提到的旗标（动态拼名的前缀自动跳过）。"""
        p = self.root / "data/black_page/flags.json"
        if p not in self.blobs:
            return []
        try:
            flags = json.loads(self.blobs[p])
        except json.JSONDecodeError:
            return ["flags.json 解析失败"]
        out = []
        for name in flags:
            if name.startswith(DYNAMIC_FLAG_PREFIXES):
                continue  # 动态拼名，扫不到是正常的
            if self.alltext.count(name) <= 2:
                out.append(name)
        return out

    # --- 主流程 -----------------------------------------------------------

    def run(self) -> int:
        print(f"\n《黑页》项目审计 —— {self.root}\n")

        print("【铁律】")
        self.bad("只有 investigation 能写 GameState", self.layering_violations())
        self.bad("表现层不读数据文件", self.ui_reads_data())

        print("\n【一致性】")
        self.bad("data 文件与 loader 列表对账", self.loader_vs_data())
        self.bad("孤儿 .uid（无对应 .gd）", self.orphan_uid())
        self.bad("孤儿 .import（无对应素材）", self.orphan_import())

        print("\n【死代码】")
        self.bad("没人调用的函数", self.unused_funcs())
        self.bad("没人引用的常量", self.unused_consts())
        self.bad("没人用的信号", self.dead_signals())

        print("\n【配置】")
        self.bad("project.godot 指向已删文件", self.project_refs())

        print("\n【启发式（需人工判断）】")
        self.warn("没被引用的素材", self.unused_assets())
        self.warn("声明了但没被提到的旗标", self.flags_declared_unused())
        self.warn("英文残留注释", self.english_comments())

        print("\n" + "─" * 60)
        if self.problems:
            print(f"结论：发现 {len(self.problems)} 个问题（必须修）")
            return 1
        if self.warnings:
            note = "（--strict 下算失败）" if self.strict else "（人工确认可忽略）"
            print(f"结论：铁律与死代码全过；{len(self.warnings)} 处启发式提示 {note}")
            return 1 if self.strict else 0
        print("结论：干净。")
        return 0


def find_project_root(start: Path) -> Path | None:
    for cand in [start, *start.parents]:
        if (cand / "project.godot").exists():
            return cand
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="《黑页》项目审计")
    ap.add_argument("--path", default=".", help="项目根（含 project.godot）")
    ap.add_argument("--strict", action="store_true", help="启发式提示也算失败")
    args = ap.parse_args()

    root = find_project_root(Path(args.path).resolve())
    if root is None:
        print("找不到 project.godot —— 请在 Godot 项目里运行，或用 --path 指定。")
        return 2
    return Audit(root, args.strict).run()


if __name__ == "__main__":
    sys.exit(main())
