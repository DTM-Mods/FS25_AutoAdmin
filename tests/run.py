"""Runs the Auto Admin scripts offline with stand-ins for the game (Lua 5.1 via lupa).

Usage: python tests/run.py        (needs `pip install lupa`)
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"

lua = lua51.LuaRuntime()
runner = lua.execute("return function(s, n) local f, e = loadstring(s, n) if not f then error(e) end return f() end")


def run(path):
    return runner(path.read_text(encoding="utf-8"), "@" + path.name)


texts = {e.get("name"): e.findtext("en") for e in ET.parse(ROOT / "modDesc.xml").iter("text")}
lua.globals().AA_TEXTS = lua.table_from(texts)

run(TESTS / "stubs.lua")
for name in ["AutoAdmin", "AutoAdminEvents", "gui/AutoAdminGui", "gui/AutoAdminDialog"]:
    run(ROOT / "scripts" / (name + ".lua"))
failed = run(TESTS / "scenarios.lua")
log = lua.globals().LOG
for i in range(1, len(log) + 1):
    line = log[i]
    if line.startswith("FAIL") or "checks passed" in line:
        print(line)
sys.exit(1 if failed else 0)
