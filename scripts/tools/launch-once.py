#!/usr/bin/env python3
"""Serialize startup per prefix and reuse a running CAD or vendor sign-in session."""
import fcntl
import os
import signal
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory


def run_probe(probe_path):
    """Run the CAD session probe. Return its exit status, or None if it never finished.

    This is the launch's first Wine command, so a pending macOS privacy prompt can hold it (see
    permission-notice.sh). If it stalls, say where to look and keep waiting for an answer.
    """
    probe = subprocess.Popen(['wine', str(probe_path), '--activate'])
    try:
        return probe.wait(timeout=float(os.environ.get('SW_PERMISSION_NOTICE_DELAY', '20')))
    except subprocess.TimeoutExpired:
        pass
    notice = subprocess.Popen([str(Path(__file__).with_name('permission-notice.sh'))],
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)
    try:
        return probe.wait(timeout=float(os.environ.get('SW_PERMISSION_WAIT', '900')))
    except subprocess.TimeoutExpired:
        probe.kill()
        probe.wait()
        return None
    finally:
        if notice.poll() is None:
            notice.terminate()
        notice.wait()


def launch(tools, runner):
    # flock owns the lock; a leftover file after a crash never blocks a later launch.
    prefix = Path(os.environ['WINEPREFIX']).resolve()
    with (prefix / '.solidworks-launch.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('SOLIDWORKS launch is already in progress.', flush=True)
            return 0
        probe_path = tools / 'ExistingCad.exe'
        # macOS may ask for disk-image access on the first read. Keep that
        # prompt outside the Wine probe's timeout so a first launch can finish.
        try:
            with probe_path.open('rb') as executable:
                if not executable.read(1):
                    sys.exit(f'Empty CAD session probe: {probe_path}')
        except OSError as exc:
            sys.exit(f'Could not read the CAD session probe: {exc}')
        status = run_probe(probe_path)
        if status == 0:
            return 0
        if status != 2:
            sys.exit('Could not check the existing CAD session; refusing a duplicate launch.')
        with TemporaryDirectory(prefix='.solidworks-signin-', dir=prefix) as session:
            env = dict(os.environ, SW_SIGNIN_SESSION=session, SW_SIGNIN_OWNER=str(os.getpid()))
            monitor = subprocess.Popen(
                [sys.executable, str(Path(__file__).with_name('signin-monitor.py')), str(tools)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True, env=env)
            try:
                return subprocess.call([str(runner)], env=env)
            finally:
                (Path(session) / 'stop').touch()
                try:
                    monitor.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(monitor.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    monitor.wait()


if __name__ == '__main__':
    sys.exit(launch(Path(sys.argv[1]), Path(sys.argv[2])))
