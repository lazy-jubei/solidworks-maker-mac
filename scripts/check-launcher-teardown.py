#!/usr/bin/env python3
"""Exercise the CATSTART-exit and watchdog teardown paths without Wine."""
from pathlib import Path
import os
import shutil
import subprocess
import sys
import time
from tempfile import TemporaryDirectory

runner = Path(__file__).resolve().with_name("run-solidworks.sh")
with TemporaryDirectory(prefix='sw-teardown-') as tmp:
    root = Path(tmp).resolve()
    shutil.copy2(runner, root / runner.name)
    (root / 'tools').mkdir()
    scanner = root / 'tools/container-processes.py'
    shutil.copy2(runner.parent / 'tools' / scanner.name, scanner)
    (root / 'drive_c').mkdir()
    (root / 'env.sh').write_text("""
ROOT=$TEST_ROOT
WINE_APP=$ROOT
WINEPREFIX=$ROOT
export PATH="$ROOT:$PATH"
""")
    (root / 'pgrep').write_text('''#!/bin/zsh
if [[ "$TEST_CASE" == watchdog ]] && mkdir "$TEST_ROOT/seen" 2>/dev/null; then
    print 778
fi
if [[ "$TEST_CASE" == detached && ! -f "$TEST_ROOT/release-cad" ]]; then
    print 778
fi
[[ ! -f "$TEST_ROOT/release-foreign" ]] || exit 1
print 777
''')
    (root / 'lsof').write_text(r'''#!/bin/zsh
if [[ "$1" == -nP && "$TEST_CASE" == identity ]]; then
    printf 'p771\x00\nn%s\x00\nn%s\x00\n' "$TEST_ROOT/identity prefix/drive_c/data" "$TEST_ROOT/runtime with spaces/lib/wine.so"
    printf 'p772\x00\nn%s\x00\nn%s\x00\n' "$TEST_ROOT/identity prefix-other/drive_c/data" "$TEST_ROOT/runtime with spaces/lib/wine.so"
    printf 'p773\x00\nn%s\x00\nn%s\x00\n' "$TEST_ROOT/identity prefix/drive_c/data" "$TEST_ROOT/runtime with spaces-other/lib/wine.so"
    printf 'p774\x00\nn%s\x00\n' "$TEST_ROOT/identity prefix/drive_c/data"
    printf 'p775\x00\nn%s\x00\nn%s\x00\n' "$TEST_ROOT/identity prefix" "$TEST_ROOT/runtime with spaces/lib/wine.so"
    exit
fi
if [[ "$1" == -nP ]]; then
    touch "$TEST_ROOT/scanned"
    exit
fi
[[ "$1" == -a ]] || exit 1
if [[ "$3" == 778 ]]; then
    print -r -- "n$TEST_ROOT/drive_c/Program Files/SLDWORKS.exe"
else
    print -r -- "n$TEST_ROOT/another prefix/drive_c/Program Files/SLDWORKS.exe"
    touch "$TEST_ROOT/checked-foreign"
fi
''')
    (root / 'curl').write_text('#!/bin/zsh\nexit 0\n')
    (root / 'wine').write_text('''#!/bin/zsh
case "$1:$2" in
    *CATSTART.exe:*)
        if [[ "$TEST_CASE" == detached ]]; then
            touch "$TEST_ROOT/catstart-returned"
            exit 0
        fi
        if [[ "$TEST_CASE" == watchdog ]]; then
            for _ in {1..200}; do
                [[ -f "$TEST_ROOT/waiter" ]] && exit 37
                sleep .05
            done
            exit 96
        fi
        for _ in {1..100}; do
            [[ -f "$TEST_ROOT/checked-foreign" ]] && break
            sleep .05
        done
        [[ -f "$TEST_ROOT/checked-foreign" ]] || exit 98
        touch "$TEST_ROOT/release-foreign"
        sleep 2.5
        [[ ! -f "$TEST_ROOT/waiter" ]] || exit 99
        exit 37
        ;;
    wineserver:*)
        print erroneous-wine-wrapper >> "$TEST_ROOT/calls"
        exit 1
        ;;
esac
''')
    (root / 'wineserver').write_text('''#!/bin/zsh
case "$1" in
    -w)
        if [[ -n "$SW_SIGNIN_SESSION" && ! -f "$SW_SIGNIN_SESSION/stopped" ]]; then
            print monitor-still-running >> "$TEST_ROOT/calls"
        fi
        print wait >> "$TEST_ROOT/calls"
        touch "$TEST_ROOT/waiter"
        for _ in {1..160}; do
            [[ -f "$TEST_ROOT/stopped" ]] && exit 0
            sleep .05
        done
        exit 97
        ;;
    -k)
        print stop >> "$TEST_ROOT/calls"
        touch "$TEST_ROOT/stopped"
        ;;
esac
''')
    for name in ['pgrep', 'curl', 'lsof', 'wine', 'wineserver']:
        (root / name).chmod(0o755)
    env = dict(os.environ, TEST_ROOT=str(root), SW_TENANT='fixture',
               SW_SHUTDOWN_GRACE='3')
    runtime = root / 'runtime with spaces'
    result = subprocess.run([sys.executable, str(scanner), str(root / 'identity prefix'), str(runtime)],
                            env=dict(env, TEST_CASE='identity', PATH=f"{root}{os.pathsep}{env['PATH']}"),
                            capture_output=True, text=True, check=True)
    assert result.stdout.splitlines() == ['771', '775'], result.stdout
    for test_case in ['watchdog', 'launcher', 'detached']:
        session = root / test_case
        session.mkdir()
        case_env = dict(env, TEST_CASE=test_case, SW_SIGNIN_SESSION=str(session))
        with subprocess.Popen(['/bin/zsh', '-c', '''
for _ in {1..200}; do
    if [[ -f "$SW_SIGNIN_SESSION/stop" ]]; then
        sleep .3
        touch "$SW_SIGNIN_SESSION/stopped"
        exit
    fi
    sleep .05
done
exit 1
'''], env=case_env) as monitor:
            with subprocess.Popen(['/bin/zsh', str(root / runner.name)], env=case_env) as result:
                try:
                    if test_case == 'detached':
                        deadline = time.monotonic() + 5
                        while not (root / 'catstart-returned').exists() and time.monotonic() < deadline:
                            time.sleep(.05)
                        assert (root / 'catstart-returned').exists()
                        time.sleep(1)
                        assert result.poll() is None and not (session / 'stop').exists()
                        assert not (root / 'waiter').exists()
                        (root / 'release-cad').touch()
                    assert result.wait(timeout=16) == (0 if test_case == 'detached' else 37)
                finally:
                    if result.poll() is None:
                        result.kill()
            assert monitor.wait(timeout=2) == 0
        assert not list((root / 'logs').glob('.container-teardown.*'))
        assert (root / 'scanned').exists()
        assert (root / 'calls').read_text().splitlines() == ['wait', 'stop'], (
            test_case, (root / 'calls').read_text())
        for name in ['calls', 'waiter', 'stopped', 'checked-foreign', 'release-foreign', 'scanned']:
            (root / name).unlink(missing_ok=True)
    print('The watchdog, launcher failure and detached CAD exit paths each stopped the monitor before draining the correct prefix through native wineserver.')
