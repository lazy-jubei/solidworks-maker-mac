#!/usr/bin/env python3
"""Check duplicate/startup guards and lock lifetime using fake probe/runner commands."""
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent
with TemporaryDirectory(prefix='sw-single-launch-') as directory:
    base = Path(directory)
    tools = base / 'tools'
    tools.mkdir()
    for name in ['launch-once.py']:
        shutil.copy2(root / 'scripts/tools' / name, tools / name)
    (tools / 'signin-monitor.py').write_text('# No live monitor in this fixture.\n')
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

print('Passed: existing session reuse, probe failure refusal, simultaneous/aliased-prefix launches, distinct-prefix isolation, runner failure and stale lock-file recovery. No Wine or CAD executed.')
