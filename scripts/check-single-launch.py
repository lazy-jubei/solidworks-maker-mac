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
    for name in ['launch-once.py', 'signin-monitor.py', 'permission-notice.sh']:
        shutil.copy2(root / 'scripts/tools' / name, tools / name)
    probe_path = tools / 'ExistingCad.exe'
    probe_path.write_bytes(b'MZ')
    fakebin = base / 'bin'
    fakebin.mkdir()
    probe = fakebin / 'wine'
    probe.write_text('''#!/bin/zsh
if [[ "$1" == *WinInput.exe ]]; then
    touch "$SINGLE_TEST_MONITOR"
    exit 0
fi
[[ "$1" == *ConfirmDialog.exe || "$1" == *WebViewWindow.exe ]] && exit 0
print probe >> "$SINGLE_TEST_CALLS"
if [[ "$SINGLE_TEST_STATUS" == stall ]]; then
    # A pending macOS privacy prompt holds Wine's first file access until someone answers it.
    for _ in {1..200}; do
        [[ -f "$SINGLE_TEST_NOTICE" ]] && exit 0
        if [[ -n "${SW_LAUNCHER_NOTICE:-}" && -s "$SW_LAUNCHER_NOTICE" ]]; then
            head -1 "$SW_LAUNCHER_NOTICE" > "$SINGLE_TEST_NOTICE.title"
            exit 0
        fi
        sleep .05
    done
    exit 1
fi
[[ "$SINGLE_TEST_STATUS" == hang ]] && exec sleep 30
exit "$SINGLE_TEST_STATUS"
''')
    probe.chmod(0o755)
    notice = fakebin / 'osascript'
    notice.write_text('''#!/bin/zsh
trap 'touch "$SINGLE_TEST_NOTICE.dismissed"; exit 0' TERM
touch "$SINGLE_TEST_NOTICE"
for _ in {1..300}; do sleep .1; done
''')
    notice.chmod(0o755)
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
               WINEPREFIX=str(prefix), SINGLE_TEST_CALLS=str(calls), SINGLE_TEST_STATUS='0',
               SINGLE_TEST_MONITOR=str(base / 'monitor-started'), SINGLE_TEST_NOTICE=str(base / 'notice'),
               SW_PERMISSION_NOTICE_DELAY='0.5')
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
    # A stalled probe shows the permission notice, keeps waiting, and dismisses it once Wine
    # carries on. One that never finishes is still refused, without leaving the notice up.
    for status, code in (('stall', 0), ('hang', None)):
        stalled = subprocess.run(command, env=dict(env, SINGLE_TEST_STATUS=status, SW_PERMISSION_WAIT='2'),
                                 capture_output=True, text=True, timeout=20)
        assert (base / 'notice').exists() and (base / 'notice.dismissed').exists(), status
        if code is None:
            assert stalled.returncode != 0 and 'refusing a duplicate' in stalled.stderr
        else:
            assert stalled.returncode == code, stalled.stderr
        assert calls.read_text().splitlines() == ['probe']
        for leftover in ('notice', 'notice.dismissed', 'calls'):
            (base / leftover).unlink()
    assert not (base / 'notice').exists()
    # Launched from Finder, the app shows the notice itself while its notice file exists.
    app_notice = base / 'app-notice'
    stalled = subprocess.run(command, env=dict(env, SINGLE_TEST_STATUS='stall', SW_LAUNCHER_NOTICE=str(app_notice)),
                             capture_output=True, text=True, timeout=20)
    assert stalled.returncode == 0, stalled.stderr
    assert (base / 'notice.title').read_text().strip() == 'SolidWorks is still starting'
    assert not (base / 'notice').exists(), 'The Finder launch fell back to osascript'
    for _ in range(40):
        if not app_notice.exists():
            break
        time.sleep(.05)
    assert not app_notice.exists(), 'The notice stayed up after Wine carried on'
    for leftover in ('notice.title', 'calls'):
        (base / leftover).unlink()
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
        deadline = time.monotonic() + 5
        while not (base / 'monitor-started').exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert (base / 'monitor-started').exists()
        session, = (p for p in prefix.glob('.solidworks-signin-*') if p.is_dir())
        monitor_pid = int((prefix / '.solidworks-signin-monitor.lock').read_text())
        first.communicate('x', timeout=10)
        assert first.returncode == 37
        assert not session.exists()
        try:
            os.kill(monitor_pid, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError('The launch left its sign-in monitor running')
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
    (base / 'monitor-started').unlink()
    with (prefix / '.solidworks-signin-monitor.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        duplicate = subprocess.run(monitor, env=dict(env, WINEPREFIX=str(alias)), timeout=10)
        assert duplicate.returncode == 0 and not (base / 'monitor-started').exists()
        separate = subprocess.Popen(monitor, env=dict(env, WINEPREFIX=str(other_prefix)))
        try:
            deadline = time.monotonic() + 5
            while not (base / 'monitor-started').exists() and separate.poll() is None and time.monotonic() < deadline:
                time.sleep(0.05)
            assert (base / 'monitor-started').exists(), 'A different prefix should run its sign-in monitor'
        finally:
            if separate.poll() is None:
                separate.terminate()
                separate.wait(timeout=10)


    # Only start the helper for the window that actually needs it.
    auth = b'10052 #32770 660x456 Authentication Required\r\n'
    login = b'20130 #32770 1200x1000 Login - 3DEXPERIENCE ID\r\n'
    for mode, windows, expected in (
        ('0', b'10458 Afx:fixture 1200x804 splash\r\n', ['--list']),
        ('0', auth, ['--list', 'Cancel']),
        ('0', login, ['--list', 'detach']),
        ('0', auth + login, ['--list', 'Cancel', 'detach']),
        ('1', auth + login, ['--list', 'Cancel']),
        ('0', b'10034 Chrome_WidgetWin_1 1200x1000 SolidWorks sign-in (Wine workaround)\r\n',
         ['--list']),
    ):
        report = subprocess.CompletedProcess([], 0, stdout=windows)
        with (patch.dict(os.environ, WINEPREFIX=str(prefix), SW_MAC_EMBEDDED_SIGNIN=mode),
              patch.object(sys, 'argv', [monitor[1], str(tools)]),
              patch('time.monotonic', side_effect=[0, 1, 1, 301]),
              patch('time.sleep'),
              patch('subprocess.run', return_value=report) as helpers):
            runpy.run_path(monitor[1], run_name='__main__')
        assert [call.args[0][-1] for call in helpers.call_args_list] == expected


    # The vendor's update prompt can hold startup past the no-login cutoff. The
    # monitor must still be waiting when the authentication box appears after it.
    update = b'10088 #32770 520x300 3DEXPERIENCE Update\r\n'
    for prompt_until, expected_cancel in ((240, True), (0, False)):
        clock = [0]
        def windows_at(command, **kwargs):
            if command[-1] != '--list':
                return subprocess.CompletedProcess([], 0, stdout=b'')
            if clock[0] < prompt_until:
                return subprocess.CompletedProcess([], 0, stdout=update)
            return subprocess.CompletedProcess([], 0, stdout=auth if clock[0] >= 300 else b'')
        with (patch.dict(os.environ, WINEPREFIX=str(prefix), SW_MAC_EMBEDDED_SIGNIN='0'),
              patch.object(sys, 'argv', [monitor[1], str(tools)]),
              patch('time.monotonic', side_effect=lambda: clock[0]),
              patch('time.sleep', side_effect=lambda seconds: clock.__setitem__(0, clock[0] + 60)),
              patch('subprocess.run', side_effect=windows_at) as helpers):
            runpy.run_path(monitor[1], run_name='__main__')
        cancelled = any(call.args[0][-1] == 'Cancel' for call in helpers.call_args_list)
        assert cancelled == expected_cancel, (prompt_until, cancelled)
        assert clock[0] < 1000, 'The monitor did not stop after the update prompt closed'

print('Passed: existing session reuse, probe failure refusal, stalled-probe permission notice (script and app), prefix isolation, launch lock recovery, sign-in monitor shutdown, update-prompt wait and embedded browser handling.')
