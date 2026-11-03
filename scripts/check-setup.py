#!/usr/bin/env python3
"""Check setup ordering/failure guards with fake stages; never install or run Wine."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/bin/zsh\nset -eu\n' + text)
    path.chmod(0o755)


def fixture(base):
    project = base / 'checkout with spaces'
    scripts = project / 'scripts'
    scripts.mkdir(parents=True)
    shutil.copy2(root / 'setup.sh', project / 'setup.sh')
    shutil.copy2(root / 'config.example.zsh', project / 'config.example.zsh')
    volume = base / 'wine volume'
    prefix = volume / 'prefix'
    app = volume / 'Wine Staging.app'
    calls = base / 'calls'
    env = dict(os.environ, SW_SETUP_TEST_CALLS=str(calls))
    env['SW_SETUP_TEST_SERVER'] = str(app / 'Contents/Resources/wine/bin/wineserver')
    bin_dir = base / 'bin'
    env['PATH'] = str(bin_dir) + os.pathsep + env['PATH']
    executable(bin_dir / 'ps', 'if [[ "${SW_SETUP_TEST_ACTIVE:-0}" == 1 ]]; then print -r -- "$SW_SETUP_TEST_SERVER"; fi\n')
    executable(bin_dir / 'wineserver', 'print -r -- "stop:$1" >> "$SW_SETUP_TEST_CALLS"\n')
    (scripts / 'env.sh').write_text('\n'.join(f'{key}={shlex.quote(str(value))}' for key, value in {
        'ROOT': project, 'WINEPREFIX': prefix, 'WINE_APP': app,
        'SW_CONFIG_FILE': project / 'config.local.zsh', 'VOL': volume,
        'W_CACHE': base / 'cache', 'XDG_CACHE_HOME': base / 'xdg',
    }.items()) + '\nexport WINEPREFIX\n')
    tools = scripts / 'tools'
    tools.mkdir()
    shutil.copy2(root / 'scripts/tools/require-stopped.py', tools / 'require-stopped.py')
    executable(tools / 'check-setup-requirements.sh', 'print prerequisites >> "$SW_SETUP_TEST_CALLS"\n')
    names = ['01-storage.sh', '02-wine.sh', '03-prefix.sh', 'build-shell32.sh',
             'install-ntdll-shim.sh', 'build-mac-gdi.sh', 'build-button-capture.sh']
    for name in names:
        executable(scripts / name, f'print {shlex.quote(name)} >> "$SW_SETUP_TEST_CALLS"\n'
                   f'if [[ "${{SW_SETUP_TEST_FAIL_STAGE:-}}" == {shlex.quote(name)} ]]; then exit 37; fi\n')
    return project, prefix, calls, env, names


with TemporaryDirectory(prefix='sw-setup-check-') as directory:
    base = Path(directory)
    project, prefix, calls, env, names = fixture(base)

    def run(*args):
        return subprocess.run([str(project / 'setup.sh'), *args], cwd=base,
                              env=env, capture_output=True, text=True)

    dry = run('--dry-run')
    assert dry.returncode == 0 and not calls.exists()
    assert not prefix.exists() and not (project / 'config.local.zsh').exists()
    env['SW_SETUP_TEST_ACTIVE'] = '1'
    active = run()
    assert active.returncode != 0 and 'stop this Wine prefix' in active.stderr
    assert not calls.exists() and not (project / 'config.local.zsh').exists()
    env.pop('SW_SETUP_TEST_ACTIVE')
    launcher = prefix / 'drive_c/Program Files/Dassault Systemes/3DEXPERIENCE Launcher/3DEXPERIENCELauncher.exe'
    launcher.parent.mkdir(parents=True)
    launcher.touch()
    installed = run()
    assert installed.returncode != 0 and 'already has the Launcher' in installed.stderr
    assert not calls.exists()
    launcher.unlink()
    success = run()
    assert success.returncode == 0, success.stderr
    expected = ['prerequisites', *names[:3], 'stop:-k', 'stop:-w', *names[3:]]
    assert calls.read_text().splitlines() == expected
    assert (project / 'config.local.zsh').read_bytes() == (project / 'config.example.zsh').read_bytes()
    calls.unlink()
    custom = 'export SW_TENANT=keep-this-setting\n'
    (project / 'config.local.zsh').write_text(custom)
    env['SW_SETUP_TEST_FAIL_STAGE'] = '03-prefix.sh'
    failed = run()
    assert failed.returncode == 37
    assert calls.read_text().splitlines() == ['prerequisites', *names[:3]]
    assert (project / 'config.local.zsh').read_text() == custom

    # Run the actual dependency script against fake winetricks and wineserver.
    calls.unlink()
    shutil.copy2(root / 'scripts/03-prefix.sh', project / 'scripts/03-prefix.sh')
    executable(base / 'bin/winetricks', 'print -r -- "verb:$3" >> "$SW_SETUP_TEST_CALLS"\n'
               'if [[ "$3" == vcrun2022 ]]; then exit 37; fi\n')
    dependency = subprocess.run(['zsh', str(project / 'scripts/03-prefix.sh')],
                                env=env, capture_output=True, text=True)
    assert dependency.returncode == 37, dependency.stderr
    assert calls.read_text().splitlines() == ['verb:corefonts', 'stop:-w', 'verb:vcrun2022']
    assert 'Dependency vcrun2022 failed' in dependency.stderr

print('Passed: dry-run, active/installed refusal, ordering, failure propagation, config preservation and dependency failure.')
