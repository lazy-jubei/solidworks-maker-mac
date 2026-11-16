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
    auth_title = 'Authentication Required'
    update_title = b'3DEXPERIENCE Update'
    detach_browser = os.environ.get('SW_MAC_EMBEDDED_SIGNIN') != '1'

    end = time.monotonic() + 300
    last_login = None
    while not stopping() and time.monotonic() < end:
        try:
            windows = subprocess.run(['wine', str(tools / 'WinInput.exe'), '--list'],
                                     capture_output=True, timeout=8).stdout
            rows = (line.split(maxsplit=3) for line in windows.splitlines())
            titles = [row[3] for row in rows if len(row) == 4]
            if any(update_title in title for title in titles):
                # The vendor's update prompt holds startup until the user answers it,
                # so the sign-in wait starts again once it closes.
                end = time.monotonic() + 300
            embedded_login = any(b'3DEXPERIENCE ID' in title for title in titles)
            if embedded_login or b'SolidWorks sign-in (Wine workaround)' in titles:
                last_login = time.monotonic()
            elif last_login is not None and time.monotonic() - last_login > 10:
                break
            elif last_login is None and time.monotonic() > end - 120:
                break
            if auth_title.encode() in titles and not stopping():
                subprocess.run(['wine', str(tools / 'ConfirmDialog.exe'), auth_title,
                                'eu1-makers.iam.3dexperience.3ds.com', 'Cancel'],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=8)
            if embedded_login and detach_browser and not stopping():
                subprocess.run(['wine', str(tools / 'WebViewWindow.exe'), 'detach'],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
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
