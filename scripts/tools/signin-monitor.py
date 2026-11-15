#!/usr/bin/env python3
"""Display-only helper for the official login. Never handles credentials."""
import fcntl
import os
import pathlib
import subprocess
import sys
import time

tools = pathlib.Path(sys.argv[1])
prefix = pathlib.Path(os.environ['WINEPREFIX']).resolve()
# The helpers are shared, but the windows each monitor can see belong to its prefix.
lock = (prefix / '.solidworks-signin-monitor.lock').open('a')
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(0)
lock.seek(0)
lock.truncate()
lock.write(str(os.getpid()))
lock.flush()
commands = [
    ["wine", str(tools / 'ConfirmDialog.exe'), "Authentication Required",
     "eu1-makers.iam.3dexperience.3ds.com", "Cancel"],
]
if os.environ.get('SW_MAC_EMBEDDED_SIGNIN') != '1':
    commands.append(["wine", str(tools / 'WebViewWindow.exe'), "detach"])

end = time.monotonic() + 300
last_login = None
while time.monotonic() < end:
    try:
        windows = subprocess.run(['wine', str(tools / 'WinInput.exe'), '--list'],
                                 capture_output=True, timeout=8).stdout
        if b'3DEXPERIENCE ID' in windows or b'SolidWorks sign-in (Wine workaround)' in windows:
            last_login = time.monotonic()
        elif last_login is not None and time.monotonic() - last_login > 10:
            break
        elif last_login is None and time.monotonic() > end - 120:
            break
        for cmd in commands:
            subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=8)
    except subprocess.TimeoutExpired:
        pass
    time.sleep(2)
