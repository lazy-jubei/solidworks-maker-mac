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
    shutil.copy2(root / 'scripts/install-windows-fonts.sh', scripts / 'install-local-fonts.sh')
    executable(scripts / 'install-windows-fonts.sh',
               'if (( $# )); then exec "${0:A:h}/install-local-fonts.sh" "$@"; fi\n'
               'print auto-fonts >> "$SW_SETUP_TEST_CALLS"\n'
               'exit "${SW_SETUP_TEST_FAIL_FONTS:-0}"\n')
    volume = base / 'wine volume'
    prefix = volume / 'prefix'
    app = volume / 'Wine Staging.app'
    calls = base / 'calls'
    env = dict(os.environ, SW_SETUP_TEST_CALLS=str(calls))
    env.pop('SW_WINDOWS_FONTS_DIR', None)
    env['SW_SETUP_TEST_SERVER'] = str(app / 'Contents/Resources/wine/bin/wineserver')
    bin_dir = base / 'bin'
    env['PATH'] = str(bin_dir) + os.pathsep + env['PATH']
    executable(bin_dir / 'ps', 'if [[ "${SW_SETUP_TEST_ACTIVE:-0}" == 1 ]]; then print -r -- "$SW_SETUP_TEST_SERVER"; fi\n')
    executable(bin_dir / 'wineserver', 'print -r -- "stop:$1" >> "$SW_SETUP_TEST_CALLS"\n')
    executable(bin_dir / 'wine', 'print -r -- "wine:$1" >> "$SW_SETUP_TEST_CALLS"\n')
    (scripts / 'env.sh').write_text('\n'.join(f'{key}={shlex.quote(str(value))}' for key, value in {
        'ROOT': project, 'WINEPREFIX': prefix, 'WINE_APP': app,
        'SW_CONFIG_FILE': project / 'config.local.zsh', 'VOL': volume,
        'W_CACHE': base / 'cache', 'XDG_CACHE_HOME': base / 'xdg',
        'WINE_VERSION': '11.16', 'WINE_FLAVOR': 'staging', 'WINETRICKS_VERSION': '20260125',
    }.items()) + '\nexport WINEPREFIX\n')
    tools = scripts / 'tools'
    tools.mkdir()
    shutil.copy2(root / 'scripts/tools/require-stopped.py', tools / 'require-stopped.py')
    executable(tools / 'check-setup-requirements.sh', 'print prerequisites >> "$SW_SETUP_TEST_CALLS"\n')
    names = ['01-storage.sh', '02-wine.sh', '03-prefix.sh', 'build-shell32.sh',
             'install-ntdll-shim.sh', 'build-mac-gdi.sh', 'build-button-capture.sh']
    for name in names:
        # The compile-only build runs in the background, so its record says so.
        executable(scripts / name, f'print -r -- {shlex.quote(name)}"${{SW_BUILD_ONLY:+ compile}}" >> "$SW_SETUP_TEST_CALLS"\n'
                   f'if [[ "${{SW_SETUP_TEST_FAIL_STAGE:-}}" == {shlex.quote(name)} ]]; then exit 37; fi\n')
    # Preparing the prefix creates it.
    with (scripts / '03-prefix.sh').open('a') as script:
        script.write('mkdir -p "$WINEPREFIX/drive_c/windows/Fonts"; touch "$WINEPREFIX/system.reg"\n')
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
    def recorded():
        # The background compile may land anywhere before build-shell32 installs it.
        lines = calls.read_text().splitlines()
        if 'build-shell32.sh compile' in lines:
            assert 'build-shell32.sh' not in lines or lines.index('build-shell32.sh compile') < lines.index('build-shell32.sh'), lines
        return [line for line in lines if line != 'build-shell32.sh compile'], 'build-shell32.sh compile' in lines
    success = run()
    assert success.returncode == 0, success.stderr
    expected = ['prerequisites', *names[:3], 'stop:-k', 'stop:-w', *names[3:], 'auto-fonts', 'stop:-k', 'stop:-w']
    assert recorded() == (expected, True)
    # The prepared prefix is kept, with a stamp of the scripts that made it.
    template = prefix.parent / 'prefix-template-11.16'
    assert (template / '.sw-template-stamp').exists() and (template / 'drive_c').is_dir()
    # A new install copies it instead of preparing a prefix again.
    calls.unlink()
    shutil.rmtree(prefix)
    copied = run()
    assert copied.returncode == 0 and 'Copying the prepared Wine prefix' in copied.stdout, copied.stderr
    assert calls.read_text().splitlines() == ['prerequisites', *names[:2], 'auto-fonts', 'stop:-k', 'stop:-w']
    assert (prefix / 'drive_c').is_dir() and not (prefix / '.sw-template-stamp').exists()
    # Supplied fonts install when reusing a prepared prefix and stay out of the template.
    calls.unlink()
    shutil.rmtree(prefix)
    font_source = base / 'source fonts'
    font_source.mkdir()
    (font_source / 'SegoeUI.TTF').write_bytes(b'regular')
    (font_source / 'Tahoma.ttf').write_bytes(b'tahoma')
    env['SW_WINDOWS_FONTS_DIR'] = str(font_source)
    fonts_installed = run()
    assert fonts_installed.returncode == 0, fonts_installed.stderr
    assert 'Copying the prepared Wine prefix' in fonts_installed.stdout
    assert calls.read_text().splitlines() == [
        'prerequisites', *names[:2], 'wine:reg', 'wine:reg', 'stop:-k', 'stop:-w'
    ]
    fonts_rel = Path('drive_c/windows/Fonts')
    assert (prefix / fonts_rel / 'segoeui.ttf').read_bytes() == b'regular'
    assert (prefix / fonts_rel / 'tahoma.ttf').read_bytes() == b'tahoma'
    assert not list((template / fonts_rel).iterdir())
    env.pop('SW_WINDOWS_FONTS_DIR')
    # Automatic font download/install failures must fail setup, including template reuse.
    calls.unlink()
    shutil.rmtree(prefix)
    env['SW_SETUP_TEST_FAIL_FONTS'] = '38'
    font_failure = run()
    assert font_failure.returncode == 38, font_failure.stderr
    assert calls.read_text().splitlines()[-3:] == ['auto-fonts', 'stop:-k', 'stop:-w']
    env.pop('SW_SETUP_TEST_FAIL_FONTS')
    # A changed setup script makes the kept prefix stale: prepare from scratch again.
    calls.unlink()
    shutil.rmtree(prefix)
    with (project / 'scripts/03-prefix.sh').open('a') as script:
        script.write('# changed\n')
    stale = run()
    assert stale.returncode == 0 and 'Copying' not in stale.stdout
    assert recorded()[0] == expected
    assert (project / 'config.local.zsh').read_bytes() == (project / 'config.example.zsh').read_bytes()
    calls.unlink()
    custom = 'export SW_TENANT=keep-this-setting\n'
    (project / 'config.local.zsh').write_text(custom)
    env['SW_SETUP_TEST_FAIL_STAGE'] = '03-prefix.sh'
    failed = run()
    assert failed.returncode == 37, (failed.returncode, failed.stdout, failed.stderr)
    assert recorded()[0] == ['prerequisites', *names[:3]]
    assert (project / 'config.local.zsh').read_text() == custom

    # Run the actual dependency script against fake winetricks and wineserver.
    calls.unlink()
    shutil.copy2(root / 'scripts/03-prefix.sh', project / 'scripts/03-prefix.sh')
    (project / 'logs').mkdir(exist_ok=True)
    executable(base / 'bin/winetricks', 'print -r -- "verb:$3" >> "$SW_SETUP_TEST_CALLS"\n'
               'if [[ "$3" == "${SW_SETUP_TEST_FAIL_VERB:-}" ]]; then exit 37; fi\n')
    env['SW_SETUP_TEST_FAIL_VERB'] = 'none'
    dependency = subprocess.run(['zsh', str(project / 'scripts/03-prefix.sh')],
                                env=env, capture_output=True, text=True)
    assert dependency.returncode == 0, dependency.stderr
    lines = calls.read_text().splitlines()
    # The prefix is created once, fonts run beside the installers, and win11 comes last.
    assert lines[:2] == ['wine:wineboot', 'stop:-w'], lines
    verbs = [line for line in lines if line.startswith('verb:')]
    installers = [verb for verb in verbs if verb != 'verb:corefonts']
    assert sorted(verbs) == sorted(['verb:corefonts', 'verb:vcrun2022', 'verb:dotnet48', 'verb:msxml6', 'verb:win11'])
    assert installers == ['verb:vcrun2022', 'verb:dotnet48', 'verb:msxml6', 'verb:win11'] and verbs[-1] == 'verb:win11', lines
    # A failing installer stops the run before the rest.
    calls.unlink()
    env['SW_SETUP_TEST_FAIL_VERB'] = 'vcrun2022'
    dependency = subprocess.run(['zsh', str(project / 'scripts/03-prefix.sh')],
                                env=env, capture_output=True, text=True)
    assert dependency.returncode == 37, dependency.stderr
    lines = calls.read_text().splitlines()
    assert 'verb:vcrun2022' in lines and 'verb:dotnet48' not in lines and 'verb:win11' not in lines, lines
    assert 'Dependency vcrun2022 failed' in dependency.stderr
    # A failing font install fails the run too, after the installers.
    calls.unlink()
    env['SW_SETUP_TEST_FAIL_VERB'] = 'corefonts'
    dependency = subprocess.run(['zsh', str(project / 'scripts/03-prefix.sh')],
                                env=env, capture_output=True, text=True)
    assert dependency.returncode == 37 and 'verb:win11' not in calls.read_text(), dependency.stderr

# Also refuse an existing Launcher first discovered after its image is attached.
with TemporaryDirectory(prefix='sw-mounted-setup-check-') as directory:
    base = Path(directory)
    project, prefix, calls, env, names = fixture(base)
    launcher = prefix / 'drive_c/Program Files/Dassault Systemes/3DEXPERIENCE Launcher/3DEXPERIENCELauncher.exe'
    executable(project / 'scripts/01-storage.sh',
               'print 01-storage.sh >> "$SW_SETUP_TEST_CALLS"\n'
               f'mkdir -p {shlex.quote(str(launcher.parent))}\n'
               f'touch {shlex.quote(str(launcher))}\n')
    mounted = subprocess.run(['zsh', str(project / 'setup.sh')], env=env, capture_output=True, text=True)
    assert mounted.returncode != 0 and 'already has the Launcher' in mounted.stderr
    assert calls.read_text().splitlines() == ['prerequisites', '01-storage.sh']

print('Passed: dry-run, active/installed refusal, ordering, parallel compile, kept prefix reuse/invalidation, failure propagation, config preservation and parallel dependencies.')
