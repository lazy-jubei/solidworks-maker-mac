#!/usr/bin/env python3
"""Make HDM_LAYOUT with a NULL layout fail instead of crashing in Wine 11.16's header control.

SOLIDWORKS sends this while loading its task panes (sldimporttabu.dll), and sldworks.exe crashed at
"Loading task panes...". Returning FALSE for NULL is inferred from SOLIDWORKS sending it on Windows,
not from Windows documentation.

Usage: comctl32-header-layout.py <wine source dir>
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1]) / "dlls"
old = """HEADER_Layout (HEADER_INFO *infoPtr, LPHDLAYOUT lpLayout)
{
"""
new = old + """    if (!lpLayout) return FALSE;

"""
hits = 0
for path in src.glob("comctl32*/header.c"):
    code = path.read_text()
    if code.count(old) == 1:
        path.write_text(code.replace(old, new))
        print("patched", path)
        hits += 1
if not hits:
    sys.exit("expected code not found")
