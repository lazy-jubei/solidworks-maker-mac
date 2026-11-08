#!/usr/bin/env python3
"""Exercise download/bootstrap and dependency failure paths without installing software."""
import importlib.util
import os
import shlex
from pathlib import Path
import shutil
import struct
import subprocess
import time
import tarfile
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('shortcut', root / 'scripts/tools/configure-shortcut.py')
shortcut = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shortcut)


def executable(path, body):
    path.write_text('#!/bin/zsh\nset -eu\n' + body)
    path.chmod(0o755)


with TemporaryDirectory(prefix='sw-install-check-') as temporary:
    base = Path(temporary)
    fakebin = base / 'bin'
    fakebin.mkdir()
    env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ['PATH'])
    calls = base / 'calls'
    env['INSTALL_TEST_CALLS'] = str(calls)
    executable(fakebin / 'uname', 'print Darwin\n')
    payload = base / 'payload/solidworks-maker-mac-main/scripts'
    payload.mkdir(parents=True)
    executable(payload / 'install-guided.sh', 'print guided >> "$INSTALL_TEST_CALLS"\nexit "${INSTALL_TEST_FAIL:-0}"\n')
    archive = base / 'payload.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(payload.parent, arcname='solidworks-maker-mac-main')
    env['INSTALL_TEST_ARCHIVE'] = str(archive)
    executable(fakebin / 'curl', '''print download >> "$INSTALL_TEST_CALLS"
if [[ "${INSTALL_TEST_DOWNLOAD_FAIL:-0}" == 1 ]]; then exit 22; fi
while (( $# )); do
  if [[ "$1" == -o ]]; then cp "$INSTALL_TEST_ARCHIVE" "$2"; exit; fi
  shift
done
exit 2
''')
    target = base / 'install with spaces'
    env['SW_INSTALL_DIR'] = str(target)

    def run():
        return subprocess.run(['zsh', str(root / 'install.sh')], env=env, capture_output=True, text=True)

    env['INSTALL_TEST_DOWNLOAD_FAIL'] = '1'
    assert run().returncode == 22 and not target.exists()
    env.pop('INSTALL_TEST_DOWNLOAD_FAIL')
    calls.unlink()
    assert run().returncode == 0
    assert calls.read_text().splitlines() == ['download', 'guided']
    sentinel = target / 'keep'
    sentinel.write_text('preserve')
    calls.unlink()
    assert run().returncode != 0 and sentinel.read_text() == 'preserve' and not calls.exists()
    env['SW_INSTALL_DIR'] = str(base / 'failed guided')
    env['INSTALL_TEST_FAIL'] = '37'
    assert run().returncode == 37

    # Use a sandbox Homebrew prefix; intercept every command that can install anything.
    requirements = base / 'requirements.sh'
    requirements.write_text((root / 'scripts/tools/check-setup-requirements.sh').read_text()
                            .replace('/opt/homebrew/bin:/usr/local/bin:', '')
                            .replace('/usr/sbin/sysctl', 'sysctl'))
    brew_prefix = base / 'brew'
    (brew_prefix / 'opt/bison/bin').mkdir(parents=True)
    executable(brew_prefix / 'opt/bison/bin/bison', 'exit 0\n')
    env['INSTALL_TEST_BREW'] = str(brew_prefix)
    env.pop('INSTALL_TEST_FAIL')
    executable(fakebin / 'xcrun', 'exit 0\n')
    executable(fakebin / 'arch', 'exit 0\n')
    executable(fakebin / 'sysctl', 'print 0\n')
    executable(fakebin / 'cabextract', 'exit 0\n')
    executable(fakebin / 'brew', '''if [[ "$1" == --prefix ]]; then print -r -- "$INSTALL_TEST_BREW"; exit; fi
print -r -- "$*" >> "$INSTALL_TEST_CALLS"
exit "${INSTALL_TEST_FAIL:-0}"
''')
    calls.unlink()
    result = subprocess.run(['zsh', str(requirements)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert calls.read_text().splitlines() == ['install python cabextract']
    env['INSTALL_TEST_FAIL'] = '37'
    assert subprocess.run(['zsh', str(requirements)], env=env, capture_output=True).returncode == 37

    # Intel without Homebrew: never run Homebrew's installer (it refuses Intel); use tools/.
    tools = base / 'tools'
    (tools / 'bin').mkdir(parents=True)
    executable(tools / 'bin/bison', 'print "bison (GNU Bison) 3.8.2"\n')
    executable(tools / 'bin/cabextract', 'print "cabextract version 1.11"\n')
    (fakebin / 'cabextract').unlink()
    intel = dict(env, SW_TOOLS=str(tools), PATH=str(fakebin) + ':/usr/bin:/bin')
    intel.pop('INSTALL_TEST_FAIL')
    (fakebin / 'brew').rename(base / 'brew-hidden')
    calls.unlink()
    result = subprocess.run(['zsh', str(requirements)], env=intel, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert not calls.exists()
    (tools / 'bin/bison').unlink()
    intel['INSTALL_TEST_DOWNLOAD_FAIL'] = '1'
    result = subprocess.run(['zsh', str(requirements)], env=intel, capture_output=True, text=True)
    assert result.returncode != 0 and calls.read_text().splitlines() == ['download']
    (base / 'brew-hidden').rename(fakebin / 'brew')
    executable(fakebin / 'cabextract', 'exit 0\n')

    # Run the full guided orchestrator against fake stages and vendor artifacts.
    project = base / 'guided checkout'
    scripts = project / 'scripts'
    tools = scripts / 'tools'
    tools.mkdir(parents=True)
    prefix = base / 'guided prefix'
    desktop = prefix / 'drive_c/users/Public/Desktop'
    desktop.mkdir(parents=True)
    envfile = {
        'ROOT': project, 'CACHE': project / 'cache', 'WINEPREFIX': prefix,
        'WINE_APP': base / 'fake wine app', 'SW_CONFIG_FILE': project / 'config.local.zsh',
    }
    (scripts / 'env.sh').write_text(''.join(f'{key}={shlex.quote(str(value))}\n'
                                         for key, value in envfile.items()))
    guided = (root / 'scripts/install-guided.sh').read_text().replace('exec </dev/tty', ': # Test input is supplied through stdin')
    (scripts / 'install-guided.sh').write_text(guided)
    shutil.copy(root / 'scripts/tools/installer-ui.zsh', tools / 'installer-ui.zsh')
    env['SW_INSTALLER_UI'] = 'terminal'
    names = ['04-launcher.sh', '05-webview2.sh', '06-settings.sh', 'install-dxmt.sh',
             'build-signin-tools.sh', '09-mac-launcher.sh', '10-fresh-signin.sh', '01-storage.sh']
    executable(project / 'setup.sh', 'print setup >> "$INSTALL_TEST_CALLS"\n')
    executable(scripts / 'open-dashboard.sh', 'exit 0\n')
    for name in names:
        executable(scripts / name, f'print {name} >> "$INSTALL_TEST_CALLS"\n'
                   f'if [[ "${{INSTALL_TEST_FAIL_STAGE:-}}" == {name} ]]; then exit 37; fi\n')
    executable(fakebin / 'wineserver', 'print -r -- "stop:$1" >> "$INSTALL_TEST_CALLS"\n')
    (tools / 'configure-shortcut.py').write_text('import os\nfrom pathlib import Path\nPath(os.environ["INSTALL_TEST_CALLS"]).open("a").write("configure\\n")\n')
    # A completed vendor installation provides the shortcut when preparation finishes.
    with (scripts / 'build-signin-tools.sh').open('a') as output:
        output.write(f'touch {shlex.quote(str(desktop / "SOLIDWORKS Design.lnk"))}\n')
    (tools / 'require-stopped.py').write_text('import sys\nsys.exit(37)\n')
    msi = base / 'launcher.msi'
    msi.touch()
    calls.unlink()
    env.pop('INSTALL_TEST_FAIL')
    wizard = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                            input=f'\nhttps://example.com/\n{msi}\n\n', capture_output=True, text=True)
    assert wizard.returncode == 0, wizard.stderr
    assert calls.read_text().splitlines() == ['setup', '04-launcher.sh', '05-webview2.sh',
            '06-settings.sh', 'stop:-k', 'stop:-w', 'install-dxmt.sh',
            'build-signin-tools.sh', 'configure', '09-mac-launcher.sh', '10-fresh-signin.sh']
    calls.unlink()
    refused = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                             input='', capture_output=True)
    assert refused.returncode == 37 and not calls.exists()
    shutil.rmtree(project / 'cache/install-state')
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    env['INSTALL_TEST_FAIL_STAGE'] = '05-webview2.sh'
    failed = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                            input=f'\nhttps://example.com/\n{msi}\n', capture_output=True, text=True)
    assert failed.returncode == 37
    assert calls.read_text().splitlines() == ['setup', '04-launcher.sh', '05-webview2.sh']
    assert not (project / 'cache/install-state/runtime').exists()
    assert 'Setup stopped during: installing WebView2' in failed.stderr

    # Dialog mode: answers come from macOS dialogs (a fake osascript), defaulting to Maker Cloud.
    shutil.rmtree(project / 'cache/install-state')
    (desktop / 'SOLIDWORKS Design.lnk').unlink(missing_ok=True)
    env.pop('INSTALL_TEST_FAIL_STAGE')
    executable(scripts / 'open-dashboard.sh', 'print -r -- "browser:$1" >> "$INSTALL_TEST_CALLS"\n')
    executable(fakebin / 'osascript', '''script="$2"
if [[ "$script" == *"choose file"* ]]; then print -r -- "dialog:launcher:$5" >> "$INSTALL_TEST_CALLS"; print -r -- "$INSTALL_TEST_MSI"
elif [[ "$script" == *"default answer"* ]]; then print -r -- "$5"
elif [[ "$script" == *"display dialog"* ]]; then print -r -- "dialog:$5" >> "$INSTALL_TEST_CALLS"; print "button returned:$5"
fi
''')
    dialogs = dict(env, SW_INSTALLER_UI='dialogs', INSTALL_TEST_MSI=str(msi), HOME=str(base / 'home'))
    calls.unlink()
    wizard = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=dialogs,
                            input='', capture_output=True, text=True)
    assert wizard.returncode == 0, wizard.stderr
    steps = calls.read_text().splitlines()
    assert steps[0] == 'dialog:Start' and 'browser:https://www.solidworks.com/maker-cloud' in steps
    assert f'dialog:launcher:{base}/home/Downloads/3DEXPERIENCELauncher.msi' in steps and steps[-2:] == ['dialog:Open SOLIDWORKS', '10-fresh-signin.sh']
    # Quit (AppleScript "User canceled") stops quietly with status 130 and records nothing new.
    shutil.rmtree(project / 'cache/install-state')
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    executable(fakebin / 'osascript', 'print -u2 "execution error: User canceled. (-128)"\nexit 1\n')
    calls.unlink()
    quit = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=dialogs,
                          input='', capture_output=True, text=True)
    assert quit.returncode == 130 and not calls.exists() and 'Setup stopped' not in quit.stderr

    # Window mode: the installer window talks to the script over stdin/stderr. A fake window
    # answers each prompt; the dashboard browser is closed once SOLIDWORKS is installed.
    executable(scripts / 'open-dashboard.sh', 'print -r -- "browser:$1" >> "$INSTALL_TEST_CALLS"\n'
               'trap \'print browser-closed >> "$INSTALL_TEST_CALLS"; exit 0\' TERM\n'
               'while true; do sleep 0.1; done\n')

    def run_window(answer):
        calls.unlink(missing_ok=True)
        window = dict(env, SW_INSTALLER_UI='app', HOME=str(base / 'home'))
        window.pop('INSTALL_TEST_FAIL_STAGE', None)
        process = subprocess.Popen(['zsh', str(scripts / 'install-guided.sh')], env=window, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        events = []
        for line in process.stdout:
            if line.startswith('@@sw\t'):
                fields = line.rstrip('\n').split('\t')[1:]
                events.append(fields)
                reply = answer(fields)
                if reply is not None:
                    process.stdin.write(reply + '\n')
                    process.stdin.flush()
        return process.wait(timeout=30), events

    shutil.rmtree(project / 'cache/install-state', ignore_errors=True)
    (desktop / 'SOLIDWORKS Design.lnk').unlink(missing_ok=True)
    answers = {'message': 'ok', 'url': 'https://www.solidworks.com/maker-cloud', 'msi': str(msi)}
    code, events = run_window(lambda fields: answers.get(fields[0]))
    assert code == 0, events
    kinds = [fields[0] for fields in events]
    assert events[0][:3] == ['message', 'Start', 'Welcome'] and kinds[-1] == 'finished', events
    assert events[kinds.index('url')][:2] == ['url', 'https://www.solidworks.com/maker-cloud']
    assert events[kinds.index('msi')][1] == f'{base}/home/Downloads/3DEXPERIENCELauncher.msi'
    assert '\\n' in events[0][3], 'multi-line text is escaped onto one line'
    order = ['wine', 'launcher', 'components', 'solidworks', 'finish']
    steps = [fields[1] for fields in events if fields[0] == 'stage']
    assert steps == sorted(steps, key=order.index) and steps[-1] == 'finish', steps
    # The final launch is detached from the window, so it may land just after the exit.
    for _ in range(50):
        if '10-fresh-signin.sh' in calls.read_text():
            break
        time.sleep(0.1)
    lines = calls.read_text().splitlines()
    assert lines.index('browser-closed') < lines.index('configure') and lines[-1] == '10-fresh-signin.sh', lines
    # Quitting from the window stops quietly, without a failure, and closes the browser.
    shutil.rmtree(project / 'cache/install-state')
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    def quit_at_msi(fields):
        if fields[0] == 'msi':
            # Quit once the browser is up, as a person would.
            for _ in range(50):
                if calls.exists() and 'browser:' in calls.read_text():
                    break
                time.sleep(0.1)
            return '@@quit'
        return {'message': 'ok', 'url': 'https://example.com/'}.get(fields[0])
    code, events = run_window(quit_at_msi)
    assert code == 130 and 'failed' not in [fields[0] for fields in events], events
    assert calls.read_text().splitlines()[-1] == 'browser-closed', calls.read_text()
    # Install SOLIDWORKS: the window waits for the shortcut; continuing early asks again.
    (tools / 'require-stopped.py').write_text('')
    (project / 'cache/install-state').mkdir(parents=True, exist_ok=True)
    for name in ('wine', 'launcher', 'runtime'):
        (project / 'cache/install-state' / name).touch()
    (desktop / 'SOLIDWORKS Design.lnk').unlink(missing_ok=True)
    asked = []
    def install_late(fields):
        if fields[0] == 'message' and fields[2] == 'Install SOLIDWORKS':
            assert fields[4] == str(desktop / 'SOLIDWORKS Design.lnk'), fields
            asked.append(fields[3])
            if len(asked) == 2:
                (desktop / 'SOLIDWORKS Design.lnk').touch()
            return 'ok'
        return {'url': 'https://example.com/'}.get(fields[0])
    code, events = run_window(install_late)
    assert code == 0 and len(asked) == 2 and asked[1].startswith('SOLIDWORKS is not installed yet'), events
    for _ in range(50):
        if '10-fresh-signin.sh' in calls.read_text():
            break
        time.sleep(0.1)
    assert calls.read_text().splitlines()[-1] == '10-fresh-signin.sh'
    (tools / 'require-stopped.py').write_text('import sys\nsys.exit(37)\n')
    env['INSTALL_TEST_FAIL_STAGE'] = '05-webview2.sh'

    # Structured Unicode .lnk with optional preceding fields and account arguments.
    header = bytearray(76)
    struct.pack_into('<I', header, 0, 76)
    header[4:20] = bytes.fromhex('0114020000000000c000000000000046')
    struct.pack_into('<I', header, 20, 128 | 4 | 32)
    args = '-object "--AppName=SWXCSWK_AP -tenant=TEST_TENANT -monoapp -3DRegistryURL=https://eu1-makers-registry.3dexperience.3ds.com"'
    data = bytes(header)
    for value in ['Example description', args]:
        encoded = value.encode('utf-16-le')
        data += struct.pack('<H', len(encoded) // 2) + encoded
    assert shortcut.settings(data)[0] == 'TEST_TENANT'
    link = base / 'design.lnk'
    link.write_bytes(data)
    config = base / 'config.local.zsh'
    config.write_text("export SW_VOL='/custom volume'\nexport SW_TENANT='old'\n")
    shortcut.configure(link, config)
    assert "export SW_VOL='/custom volume'" in config.read_text()
    assert config.read_text().count('SW_TENANT=') == 1
    assert config.stat().st_mode & 0o777 == 0o600
    for malformed in [b'', data[:-10], data.replace(b'h\x00t\x00t\x00p\x00s\x00', b'h\x00t\x00t\x00p\x00x\x00')]:
        try:
            shortcut.settings(malformed)
        except (ValueError, struct.error):
            pass
        else:
            raise AssertionError('Malformed shortcut accepted')

print('Passed: bootstrap download/failure, existing-folder protection, prerequisite selection/failure, guided ordering/failure/resume guard, shortcut configuration and malformed-input refusal.')
