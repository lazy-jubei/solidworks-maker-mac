#!/usr/bin/env python3
"""Exercise the CATSTART-exit and watchdog teardown paths without Wine."""
from pathlib import Path
import os
import shutil
import subprocess
from tempfile import TemporaryDirectory

runner = Path(__file__).resolve().with_name("run-solidworks.sh")
with TemporaryDirectory(prefix='sw-teardown-') as tmp:
    root = Path(tmp).resolve()
    shutil.copy2(runner, root / runner.name)
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
[[ ! -f "$TEST_ROOT/release-foreign" ]] || exit 1
print 777
''')
    (root / 'lsof').write_text('''#!/bin/zsh
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
    wineserver:-w)
        print wait >> "$TEST_ROOT/calls"
        touch "$TEST_ROOT/waiter"
        for _ in {1..160}; do
            [[ -f "$TEST_ROOT/stopped" ]] && exit 0
            sleep .05
        done
        exit 97
        ;;
    wineserver:-k)
        print stop >> "$TEST_ROOT/calls"
        touch "$TEST_ROOT/stopped"
        ;;
esac
''')
    for name in ['pgrep', 'curl', 'lsof', 'wine']:
        (root / name).chmod(0o755)
    env = dict(os.environ, TEST_ROOT=str(root), SW_TENANT='fixture',
               SW_SHUTDOWN_GRACE='3')
    for test_case in ['watchdog', 'launcher']:
        result = subprocess.run(['/bin/zsh', str(root / runner.name)],
                                env=dict(env, TEST_CASE=test_case), timeout=16)
        assert result.returncode == 37, result.returncode
        assert not list((root / 'logs').glob('.container-teardown.*'))
        assert (root / 'calls').read_text().splitlines() == ['wait', 'stop'], (
            test_case, (root / 'calls').read_text())
        for name in ['calls', 'waiter', 'stopped', 'checked-foreign', 'release-foreign']:
            (root / name).unlink(missing_ok=True)
    print('Watchdog-owned and launcher-owned teardown each completed once with a separate prefix active.')
