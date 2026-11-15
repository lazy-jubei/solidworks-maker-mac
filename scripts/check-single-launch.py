#!/usr/bin/env python3
"""Check duplicate/startup guards and lock lifetime using fake probe/runner commands."""
import fcntl
import os
from pathlib import Path
import runpy
import select
import shutil
import subprocess
import sys
import time
from tempfile import TemporaryDirectory
from unittest.mock import patch

root = Path(__file__).resolve().parent.parent
with TemporaryDirectory(prefix='sw-single-launch-') as directory:
    base = Path(directory)
    tools = base / 'tools'
    tools.mkdir()
    for name in ['launch-once.py']:
        shutil.copy2(root / 'scripts/tools' / name, tools / name)
    (tools / 'signin-monitor.py').write_text('# No live monitor in this fixture.\n')
    probe_path = tools / 'ExistingCad.exe'
    probe_path.write_bytes(b'MZ')
    fakebin = base / 'bin'
    fakebin.mkdir()
    probe = fakebin / 'wine'
    probe.write_text('#!/bin/zsh\nprint probe >> "$SINGLE_TEST_CALLS"\nexit "$SINGLE_TEST_STATUS"\n')
    probe.chmod(0o755)
    runner = base / 'runner'
    runner.write_text('#!' + sys.executable + '\nimport os,sys\n'
                      'from pathlib import Path\n'
                      'with Path(os.environ["SINGLE_TEST_CALLS"]).open("a") as out: out.write("runner\\n")\n'
                      'print("RUNNER_STARTED",flush=True)\n'
                      'sys.stdin.read(1)\n'
                      'sys.exit(37)\n')
    runner.chmod(0o755)
    prefix = base / 'prefix with spaces'
    prefix.mkdir()
    calls = base / 'calls'
    env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ['PATH'],
               WINEPREFIX=str(prefix), SINGLE_TEST_CALLS=str(calls), SINGLE_TEST_STATUS='0')
    command = [sys.executable, str(tools / 'launch-once.py'), str(tools), str(runner)]
    probe_path.unlink()
    unreadable = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
    assert unreadable.returncode != 0 and 'Could not read the CAD session probe' in unreadable.stderr
    assert not calls.exists()
    probe_path.write_bytes(b'MZ')
    existing = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
    assert existing.returncode == 0 and calls.read_text().splitlines() == ['probe']
    calls.unlink()
    env['SINGLE_TEST_STATUS'] = '1'
    failed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
    assert failed.returncode != 0 and 'refusing a duplicate' in failed.stderr
    assert calls.read_text().splitlines() == ['probe']
    calls.unlink()
    env['SINGLE_TEST_STATUS'] = '2'
    first = subprocess.Popen(command, env=env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert select.select([first.stdout], [], [], 10)[0], 'Runner did not start'
        assert first.stdout.readline().strip() == 'RUNNER_STARTED'
        # Resolve aliases to the same prefix, retaining a kernel-owned lock.
        alias = base / 'prefix alias'
        alias.symlink_to(prefix, target_is_directory=True)
        duplicate = subprocess.run(command, env=dict(env, WINEPREFIX=str(alias)),
                                   capture_output=True, text=True, timeout=10)
        assert duplicate.returncode == 0 and 'already in progress' in duplicate.stdout
        assert calls.read_text().splitlines() == ['probe', 'runner']
        # A different prefix must not share this lock.
        other_prefix = base / 'separate prefix'
        other_prefix.mkdir()
        other = subprocess.run(command, env=dict(env, WINEPREFIX=str(other_prefix), SINGLE_TEST_STATUS='0'),
                               capture_output=True, text=True, timeout=10)
        assert other.returncode == 0 and calls.read_text().splitlines() == ['probe', 'runner', 'probe']
        first.communicate('x', timeout=10)
        assert first.returncode == 37
    finally:
        if first.poll() is None:
            first.kill()
            first.communicate()
    # The leftover lock file must not block later launches after normal exit.
    later = subprocess.run(command, env=dict(env, SINGLE_TEST_STATUS='0'),
                           capture_output=True, text=True, timeout=10)
    assert later.returncode == 0 and calls.read_text().splitlines()[-1] == 'probe'


    # Both prefixes trust the same helper directory. Hold the main prefix's
    # lock under its canonical path while starting the real monitor.
    monitor = [sys.executable, str(root / 'scripts/tools/signin-monitor.py'), str(tools)]
    calls.unlink()
    with (prefix / '.solidworks-signin-monitor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        duplicate = subprocess.run(monitor, env=dict(env, WINEPREFIX=str(alias)), timeout=10)
        assert duplicate.returncode == 0 and not calls.exists()
        separate = subprocess.Popen(monitor, env=dict(env, WINEPREFIX=str(other_prefix)))
        try:
            deadline = time.monotonic() + 5
            while not calls.exists() and separate.poll() is None and time.monotonic() < deadline:
                time.sleep(0.05)
            assert calls.exists(), 'A different prefix should run its sign-in monitor'
        finally:
            if separate.poll() is None:
                separate.terminate()
                separate.wait(timeout=10)


    # Run one monitor cycle with a visible login. Only the fallback should
    # move the browser out of the vendor window.
    for mode, expected in (
        ('0', ['--list', 'Cancel', 'detach']),
        ('1', ['--list', 'Cancel']),
    ):
        report = subprocess.CompletedProcess([], 0, stdout=b'Login - 3DEXPERIENCE ID')
        with (patch.dict(os.environ, WINEPREFIX=str(prefix), SW_MAC_EMBEDDED_SIGNIN=mode),
              patch.object(sys, 'argv', [monitor[1], str(tools)]),
              patch('time.monotonic', side_effect=[0, 1, 1, 301]),
              patch('time.sleep'),
              patch('subprocess.run', return_value=report) as helpers):
            runpy.run_path(monitor[1], run_name='__main__')
        assert [call.args[0][-1] for call in helpers.call_args_list] == expected

print('Passed: existing session reuse, probe failure refusal, simultaneous/aliased-prefix launches, distinct-prefix isolation, runner failure, stale lock-file recovery and per-prefix sign-in monitor isolation and embedded browser handling. No Wine or CAD executed.')
