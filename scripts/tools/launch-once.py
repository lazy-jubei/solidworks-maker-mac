#!/usr/bin/env python3
"""Serialize startup per prefix and reuse a running CAD or vendor sign-in session."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys


def launch(tools, runner):
    # flock owns the lock; a leftover file after a crash never blocks a later launch.
    prefix = Path(os.environ['WINEPREFIX']).resolve()
    with (prefix / '.solidworks-launch.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('SOLIDWORKS launch is already in progress.', flush=True)
            return 0
        try:
            probe = subprocess.run(['wine', str(tools / 'ExistingCad.exe'), '--activate'], timeout=30)
        except subprocess.TimeoutExpired:
            sys.exit('Could not check the existing CAD session; refusing a duplicate launch.')
        if probe.returncode == 0:
            return 0
        if probe.returncode != 2:
            sys.exit('Could not check the existing CAD session; refusing a duplicate launch.')
        subprocess.Popen([sys.executable, str(Path(__file__).with_name('signin-monitor.py')), str(tools)],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return subprocess.call([str(runner)])


if __name__ == '__main__':
    sys.exit(launch(Path(sys.argv[1]), Path(sys.argv[2])))
