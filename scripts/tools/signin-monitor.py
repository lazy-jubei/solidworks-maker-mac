#!/usr/bin/env python3
"""Display-only helper for the official login. Never handles credentials."""
import fcntl
import os
import pathlib
import subprocess
import sys
import time

def monitor(tools, stopping):
    prefix = pathlib.Path(os.environ['WINEPREFIX']).resolve()
    # The helpers are shared, but the windows each monitor can see belong to its prefix.
    lock = (prefix / '.solidworks-signin-monitor.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return
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
    while not stopping() and time.monotonic() < end:
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
                if stopping():
                    return
                subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=8)
        except subprocess.TimeoutExpired:
            pass
        time.sleep(2)


if __name__ == '__main__':
    session = os.environ.get('SW_SIGNIN_SESSION')
    lease = pathlib.Path(session) if session else None
    owner = int(os.environ.get('SW_SIGNIN_OWNER', '0'))

    def stopping():
        return (owner and os.getppid() != owner) or (lease and (lease / 'stop').is_file())

    try:
        monitor(pathlib.Path(sys.argv[1]), stopping)
    finally:
        if lease:
            (lease / 'stopped').touch()
