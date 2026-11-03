#!/usr/bin/env python3
"""Add HttpWebSocket* exports to Wine 11.16's dlls/wininet.

The SolidWorks installer decides "IE 10 or later" by looking up HttpWebSocketReceive in
wininet.dll. These fail with ERROR_CALL_NOT_IMPLEMENTED and log a FIXME if ever called.

Usage: wininet-websocket-stubs.py <wine source dir>
"""
import pathlib
import sys

src = pathlib.Path(sys.argv[1]) / "dlls" / "wininet"

spec = (src / "wininet.spec").read_text()
if "HttpWebSocket" in spec:
    sys.exit("already patched")
spec += """@ stdcall HttpWebSocketClose(ptr long ptr long)
@ stdcall HttpWebSocketCompleteUpgrade(ptr long)
@ stdcall HttpWebSocketQueryCloseStatus(ptr ptr ptr long ptr)
@ stdcall HttpWebSocketReceive(ptr ptr long ptr ptr)
@ stdcall HttpWebSocketSend(ptr long ptr long)
@ stdcall HttpWebSocketShutdown(ptr long ptr long)
"""
(src / "wininet.spec").write_text(spec)

code = (src / "http.c").read_text()
code += """
BOOL WINAPI HttpWebSocketClose(HINTERNET handle, USHORT status, void *reason, DWORD len)
{
    FIXME("(%p %u %p %lu): stub\\n", handle, status, reason, len);
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}

HINTERNET WINAPI HttpWebSocketCompleteUpgrade(HINTERNET request, DWORD_PTR context)
{
    FIXME("(%p %Ix): stub\\n", request, context);
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return NULL;
}

BOOL WINAPI HttpWebSocketQueryCloseStatus(HINTERNET handle, USHORT *status, void *reason, DWORD len, DWORD *ret_len)
{
    FIXME("(%p %p %p %lu %p): stub\\n", handle, status, reason, len, ret_len);
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}

BOOL WINAPI HttpWebSocketReceive(HINTERNET handle, void *buffer, DWORD len, DWORD *read, DWORD *type)
{
    FIXME("(%p %p %lu %p %p): stub\\n", handle, buffer, len, read, type);
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}

BOOL WINAPI HttpWebSocketSend(HINTERNET handle, DWORD type, void *buffer, DWORD len)
{
    FIXME("(%p %lu %p %lu): stub\\n", handle, type, buffer, len);
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}

BOOL WINAPI HttpWebSocketShutdown(HINTERNET handle, USHORT status, void *reason, DWORD len)
{
    FIXME("(%p %u %p %lu): stub\\n", handle, status, reason, len);
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    return FALSE;
}
"""
(src / "http.c").write_text(code)
print("patched", src)
