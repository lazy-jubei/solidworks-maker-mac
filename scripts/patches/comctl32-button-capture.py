#!/usr/bin/env python3
"""Opt-in SolidWorks PropertyManager button capture guard for Wine 11.16.

CAD's button tracking already captures the OK/Cancel button before dispatching
WM_LBUTTONDOWN. The v6 control reacquires it, provoking a self capture-change,
then a release that clears its pressed state before mouse-up. This guard skips
that redundant capture only for sldworks.exe's observed confirmation control IDs,
with SW_BUTTON_CAPTURE_GUARD=1. It does not change SetCapture globally.
"""
from pathlib import Path
import sys
path=Path(sys.argv[1])/'dlls/comctl32_v6/button.c'
code=path.read_text()
if 'SW_BUTTON_CAPTURE_GUARD' in code:
    legacy='(id != 4900 && id != 4901)'
    current='(id != 4900 && id != 4903)'
    if code.count(legacy)==1:
        path.write_text(code.replace(legacy,current))
        print('Updated Cancel capture guard to observed control ID 4903');sys.exit(0)
    if code.count(current)==1:
        print('Button capture guard already applied');sys.exit(0)
    sys.exit('Unrecognized existing capture guard; inspect before replacing it')
anchor='WINE_DEFAULT_DEBUG_CHANNEL(button);\n'
helper='''
/* Scoped compatibility experiment: avoid a redundant capture notification in
 * SOLIDWORKS PropertyManager's already-captured confirmation buttons. */
static BOOL sw_keep_button_capture(HWND hwnd)
{
    WCHAR enabled[2], path[MAX_PATH], *base;
    int id = GetDlgCtrlID(hwnd);
    if ((id != 4900 && id != 4903) || GetCapture() != hwnd) return FALSE;
    if (GetEnvironmentVariableW(L"SW_BUTTON_CAPTURE_GUARD", enabled, 2) != 1 || enabled[0] != '1')
        return FALSE;
    if (!GetModuleFileNameW(NULL, path, MAX_PATH)) return FALSE;
    base = wcsrchr(path, '\\\\');
    return !wcsicmp(base ? base + 1 : path, L"sldworks.exe");
}
'''
old='''        SetCapture( hWnd );
        SendMessageW( hWnd, BM_SETSTATE, TRUE, 0 );
        break;

    case WM_KEYUP:'''
new=old.replace('        SetCapture( hWnd );','        if (!sw_keep_button_capture(hWnd)) SetCapture( hWnd );')
if code.count(anchor)!=1 or code.count(old)!=1:sys.exit('Expected Wine 11.16 button code not found')
backup=path.with_name(path.name+'.before-button-capture')
if not backup.exists():backup.write_text(code)
path.write_text(code.replace(anchor,anchor+helper).replace(old,new))
print('Patched',path)
