#!/usr/bin/env python3
"""Exercise download/bootstrap and dependency failure paths without installing software."""
import importlib.util
import hashlib
import os
import shlex
from pathlib import Path
import shutil
import signal
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
    checksum = base / 'SHA256SUMS'
    checksum.write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  solidworks-maker-mac.tar.gz\n')
    env['INSTALL_TEST_CHECKSUM'] = str(checksum)
    executable(fakebin / 'curl', '''print download >> "$INSTALL_TEST_CALLS"
if [[ "${INSTALL_TEST_DOWNLOAD_FAIL:-0}" == 1 ]]; then exit 22; fi
while (( $# )); do
  if [[ "$1" == -o ]]; then
    if [[ "$2" == */SHA256SUMS ]]; then cp "$INSTALL_TEST_CHECKSUM" "$2"; else cp "$INSTALL_TEST_ARCHIVE" "$2"; fi
    exit
  fi
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
    assert calls.read_text().splitlines() == ['download', 'download', 'guided']
    sentinel = target / 'keep'
    sentinel.write_text('preserve')
    calls.unlink()
    assert run().returncode != 0 and sentinel.read_text() == 'preserve' and not calls.exists()
    env['SW_INSTALL_DIR'] = str(base / 'failed guided')
    env['INSTALL_TEST_FAIL'] = '37'
    assert run().returncode == 37

    # Prerequisites come from MacPorts: a sandbox MacPorts prefix with a fake port command;
    # every command that could install anything is intercepted.
    requirements = base / 'requirements.sh'
    requirements.write_text((root / 'scripts/tools/check-setup-requirements.sh').read_text()
                            .replace('/usr/sbin/sysctl', 'sysctl'))
    shutil.copy(root / 'scripts/tools/macports.sh', base / 'macports.sh')
    ports = base / 'macports-bin'
    ports.mkdir()
    executable(ports / 'port', '''if [[ "$1" == -q && "$2" == installed ]]; then
  [[ -x "${0:h}/$3" ]] && print -r -- "  $3 @1.0_0 (active)"; exit 0
fi
print -r -- "port $*" >> "$INSTALL_TEST_CALLS"
[[ -z "${INSTALL_TEST_FAIL:-}" ]] || exit "$INSTALL_TEST_FAIL"
if [[ "$1" == -N && "$2" == install ]]; then
  shift 2
  for name in "$@"; do print 'exit 0' > "${0:h}/$name"; chmod +x "${0:h}/$name"; done
fi
''')
    executable(fakebin / 'sudo', 'if [[ "$1" == -n ]]; then exit 0; fi\nprint -r -- "sudo" >> "$INSTALL_TEST_CALLS"\nexec "$@"\n')
    env['MACPORTS_BIN'] = str(ports)
    env.pop('INSTALL_TEST_FAIL')
    executable(fakebin / 'xcrun', 'exit 0\n')
    executable(fakebin / 'arch', 'exit 0\n')
    executable(fakebin / 'sysctl', 'print 0\n')
    calls.unlink(missing_ok=True)
    result = subprocess.run(['zsh', str(requirements)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    # Only the missing ports are installed, as root through sudo.
    assert calls.read_text().splitlines() == ['sudo', 'port -N install bison cabextract'], calls.read_text()
    calls.unlink()
    result = subprocess.run(['zsh', str(requirements)], env=env, capture_output=True, text=True)
    assert result.returncode == 0 and not calls.exists(), result.stderr
    # A failed install stops setup.
    (ports / 'bison').unlink()
    env['INSTALL_TEST_FAIL'] = '37'
    assert subprocess.run(['zsh', str(requirements)], env=env, capture_output=True).returncode != 0
    env.pop('INSTALL_TEST_FAIL')
    executable(ports / 'bison', 'exit 0\n')
    executable(fakebin / 'cabextract', 'exit 0\n')
    env['INSTALL_TEST_FAIL'] = '37'

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
        'IMAGE': base / 'image.sparsebundle',
    }
    (base / 'image.sparsebundle').mkdir()
    (scripts / 'env.sh').write_text(''.join(f'{key}={shlex.quote(str(value))}\n'
                                         for key, value in envfile.items()))
    guided = (root / 'scripts/install-guided.sh').read_text().replace('exec </dev/tty', ': # Test input is supplied through stdin')
    (scripts / 'install-guided.sh').write_text(guided)
    shutil.copy(root / 'scripts/tools/installer-ui.zsh', tools / 'installer-ui.zsh')
    env['SW_INSTALLER_UI'] = 'terminal'
    names = ['04-launcher.sh', '05-webview2.sh', '06-settings.sh', 'install-dxmt.sh',
             'build-signin-tools.sh', '09-mac-launcher.sh', '10-fresh-signin.sh', '01-storage.sh']
    # Setup creates the new prefix.
    executable(project / 'setup.sh', f'mkdir -p {shlex.quote(str(desktop))}\nprint setup >> "$INSTALL_TEST_CALLS"\n')
    executable(scripts / 'open-dashboard.sh', 'exit 0\n')
    for name in names:
        executable(scripts / name, f'print {name} >> "$INSTALL_TEST_CALLS"\n'
                   f'if [[ "${{INSTALL_TEST_FAIL_STAGE:-}}" == {name} ]]; then exit 37; fi\n')
    executable(fakebin / 'wineserver', 'print -r -- "stop:$1" >> "$INSTALL_TEST_CALLS"\n')
    executable(fakebin / 'wine', 'print -r -- "wine:$1" >> "$INSTALL_TEST_CALLS"\n')
    (tools / 'configure-shortcut.py').write_text('import os\nfrom pathlib import Path\nPath(os.environ["INSTALL_TEST_CALLS"]).open("a").write("configure\\n")\n')
    # A completed vendor installation provides the shortcut when preparation finishes.
    with (scripts / 'build-signin-tools.sh').open('a') as output:
        output.write(f'[[ -n "${{INSTALL_TEST_NO_SHORTCUT:-}}" ]] || touch {shlex.quote(str(desktop / "SOLIDWORKS Design.lnk"))}\n')
    (tools / 'require-stopped.py').write_text('import sys\nsys.exit(37)\n')
    msi = base / 'launcher.msi'
    msi.touch()
    calls.unlink()
    env.pop('INSTALL_TEST_FAIL')
    wizard = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                            input=f'\nhttps://example.com/\n{msi}\n\n', capture_output=True, text=True)
    assert wizard.returncode == 0, wizard.stderr
    full_run = ['01-storage.sh', 'setup', '04-launcher.sh', '05-webview2.sh',
            '06-settings.sh', 'stop:-k', 'stop:-w', 'install-dxmt.sh',
            'build-signin-tools.sh', 'stop:-k', 'stop:-w', 'install-dxmt.sh',
            'configure', '09-mac-launcher.sh', '10-fresh-signin.sh']
    assert calls.read_text().splitlines() == full_run
    # Every run starts from a new prefix: after a warning, the old one (with SOLIDWORKS) is deleted.
    calls.unlink()
    (prefix / 'drive_c/old-file').touch()
    again = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                           input=f'reinstall\n\nhttps://example.com/\n{msi}\n\n', capture_output=True, text=True)
    assert again.returncode == 0, again.stderr
    assert 'SolidWorks is already installed' in again.stdout and not (prefix / 'drive_c/old-file').exists()
    assert calls.read_text().splitlines() == full_run
    # Something that is not a Wine prefix is never deleted.
    calls.unlink()
    shutil.rmtree(prefix)
    (prefix / 'keep').mkdir(parents=True)
    kept = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                          input=f'\nhttps://example.com/\n{msi}\n', capture_output=True, text=True)
    assert kept.returncode == 1 and (prefix / 'keep').exists() and 'does not look like a Wine prefix' in kept.stderr
    shutil.rmtree(prefix)
    desktop.mkdir(parents=True)
    calls.unlink()
    env['INSTALL_TEST_FAIL_STAGE'] = '05-webview2.sh'
    failed = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=env,
                            input=f'\nhttps://example.com/\n{msi}\n', capture_output=True, text=True)
    assert failed.returncode == 37
    # A failure stops the Wine that setup started.
    assert calls.read_text().splitlines() == ['01-storage.sh', 'setup', '04-launcher.sh', '05-webview2.sh', 'stop:-k'], calls.read_text()
    assert not (project / 'cache/install-state/runtime').exists()
    assert 'Setup stopped while installing WebView2' in failed.stderr

    # Dialog mode: answers come from macOS dialogs (a fake osascript), defaulting to Maker Cloud.
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
    shutil.rmtree(project / 'cache/installers', ignore_errors=True)
    calls.unlink()
    wizard = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=dialogs,
                            input='', capture_output=True, text=True)
    assert wizard.returncode == 0, wizard.stderr
    steps = calls.read_text().splitlines()
    assert steps[:2] == ['01-storage.sh', 'dialog:Start'] and 'browser:https://www.solidworks.com/maker-cloud' in steps, steps
    assert f'dialog:launcher:{base}/home/Downloads/3DEXPERIENCELauncher.msi' in steps and steps[-2:] == ['dialog:Open SolidWorks', '10-fresh-signin.sh']
    # Quit (AppleScript "User canceled") at the welcome stops quietly with status 130.
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    executable(fakebin / 'osascript', 'print -u2 "execution error: User canceled. (-128)"\nexit 1\n')
    calls.unlink()
    quit = subprocess.run(['zsh', str(scripts / 'install-guided.sh')], env=dialogs,
                          input='', capture_output=True, text=True)
    assert quit.returncode == 130 and calls.read_text().splitlines() == ['01-storage.sh'] and 'Setup stopped' not in quit.stderr

    # Window mode: the installer window talks to the script over stdin/stderr. A fake window
    # answers each prompt; the dashboard browser is closed once SOLIDWORKS is installed.
    executable(scripts / 'open-dashboard.sh', 'print -r -- "browser:$1" >> "$INSTALL_TEST_CALLS"\n'
               'trap \'print browser-closed >> "$INSTALL_TEST_CALLS"; exit 0\' TERM\n'
               'while true; do sleep 0.1; done\n')

    window_process = [None]
    def run_window(answer, **extra):
        calls.unlink(missing_ok=True)
        window = dict(env, SW_INSTALLER_UI='app', HOME=str(base / 'home'), **extra)
        window.pop('INSTALL_TEST_FAIL_STAGE', None)
        process = subprocess.Popen(['zsh', str(scripts / 'install-guided.sh')], env=window, text=True,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        window_process[0] = process
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

    # Existing installation: Update must never enter Chrome, reset setup, or delete CAD.
    (desktop / 'SOLIDWORKS Design.lnk').touch()
    sentinel = prefix / 'drive_c/keep.SLDPRT'
    sentinel.write_text('preserve CAD')
    executable(project / 'install.sh', 'print -r -- "update:$*" >> "$INSTALL_TEST_CALLS"\n')
    executable(scripts / 'update-wine.sh', 'print update-wine >> "$INSTALL_TEST_CALLS"\n')
    for choice in ['update', 'update-wine']:
        code, events = run_window(lambda fields: choice if fields[0] == 'existing' else 'ok' if fields[0] == 'message' else None)
        assert code == 0 and sentinel.read_text() == 'preserve CAD', events
        assert [e[0] for e in events].count('existing') == 1
        assert not any(e[0] in ('url', 'msi') for e in events)
        assert calls.read_text().splitlines() == ['01-storage.sh', 'update:--update'] + (['update-wine'] if choice == 'update-wine' else [])
    code, events = run_window(lambda fields: '@@quit' if fields[0] == 'existing' else None)
    assert code == 130 and calls.read_text().splitlines() == ['01-storage.sh']
    assert sentinel.read_text() == 'preserve CAD'
    # Choosing Reinstall still requires the separate explicit deletion confirmation.
    code, events = run_window(lambda fields: 'reinstall' if fields[0] == 'existing' else '@@quit' if fields[0] == 'message' else None)
    assert code == 130 and sentinel.read_text() == 'preserve CAD'
    confirmation = next(e for e in events if e[0] == 'message')
    assert confirmation[1] == 'Delete and Reinstall'

    (desktop / 'SOLIDWORKS Design.lnk').unlink(missing_ok=True)
    shutil.rmtree(project / 'cache/installers', ignore_errors=True)
    answers = {'message': 'ok', 'url': 'https://www.solidworks.com/maker-cloud', 'msi': str(msi)}
    code, events = run_window(lambda fields: answers.get(fields[0]))
    assert code == 0, events
    kinds = [fields[0] for fields in events]
    welcome = events[kinds.index('message')]
    assert welcome[:3] == ['message', 'Start', 'Welcome'] and kinds[-1] == 'finished', events
    assert events[kinds.index('url')][:2] == ['url', 'https://www.solidworks.com/maker-cloud']
    assert events[kinds.index('msi')][1] == f'{base}/home/Downloads/3DEXPERIENCELauncher.msi'
    assert '\\n' in welcome[3], 'multi-line text is escaped onto one line'
    order = ['launcher', 'wine', 'components', 'start', 'solidworks', 'finish']
    steps = [fields[1] for fields in events if fields[0] == 'stage']
    assert steps == sorted(steps, key=order.index) and steps[-1] == 'finish', steps
    # The hands-on steps (browser, Launcher file) come before the long Wine preparation.
    assert kinds.index('msi') < next(i for i, fields in enumerate(events) if fields[:3] == ['stage', 'wine', 'preparing Wine']), events
    # The final launch is detached from the window, so it may land just after the exit.
    for _ in range(50):
        if '10-fresh-signin.sh' in calls.read_text():
            break
        time.sleep(0.1)
    lines = calls.read_text().splitlines()
    assert lines.index('browser-closed') < lines.index('configure') and lines[-1] == '10-fresh-signin.sh', lines
    # A reinstall offers the Launcher copy kept from the last installation.
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    code, events = run_window(lambda fields: answers.get(fields[0]))
    assert code == 0 and next(fields for fields in events if fields[0] == 'msi')[1] == str(project / 'cache/installers/3DEXPERIENCELauncher.msi'), events
    for _ in range(50):
        if '10-fresh-signin.sh' in calls.read_text():
            break
        time.sleep(0.1)
    # Relaunch Chrome on the Launcher download page reopens Chrome only if it was closed,
    # and the page keeps waiting for the file.
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    relaunched = []
    def relaunch_at_msi(fields):
        if fields[0] == 'msi' and not relaunched:
            relaunched.append(1)
            for _ in range(50):
                if calls.exists() and 'browser:' in calls.read_text():
                    break
                time.sleep(0.1)
            os.kill(int((project / 'logs/dashboard-browser.pid').read_text()), signal.SIGTERM)
            for _ in range(50):
                if 'browser-closed' in calls.read_text():
                    break
                time.sleep(0.1)
            window_process[0].stdin.write('@@relaunch\n@@relaunch\n' + str(msi) + '\n')
            window_process[0].stdin.flush()
            return None
        return answers.get(fields[0])
    code, events = run_window(relaunch_at_msi)
    assert code == 0 and [fields[0] for fields in events].count('msi') == 1, events
    for _ in range(50):
        if '10-fresh-signin.sh' in calls.read_text():
            break
        time.sleep(0.1)
    lines = calls.read_text().splitlines()
    assert sum(line.startswith('browser:') for line in lines) == 2, lines
    # Quitting from the window stops quietly, without a failure, and closes the browser.
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
    # Wine has not started yet at that point, so only the browser needs closing.
    assert calls.read_text().splitlines()[-1] == 'browser-closed', calls.read_text()
    # Start from Chrome / Install SOLIDWORKS: no Continue button; the script follows the
    # SOLIDWORKS installer itself (fake ps/lsof stand in for the Wine processes).
    processes = base / 'processes'
    executable(fakebin / 'ps', 'if [[ -n "${INSTALL_TEST_PS:-}" ]]; then cat "$INSTALL_TEST_PS" 2>/dev/null; exit 0; fi\nexec /bin/ps "$@"\n')
    executable(fakebin / 'lsof', 'pid="$2"\nif [[ " ${INSTALL_TEST_PREFIX_PIDS:-} " == *" $pid "* ]]; then print -r -- "p$pid"; print -r -- "n$INSTALL_TEST_PREFIX/drive_c/x"; fi\n')
    installer_line = '4242 C:\\ProgramData\\DassaultSystemes\\SOLIDWORKSSetup.exe /install\n'
    background = ('4243 C:\\windows\\system32\\svchost.exe -k netsvcs\n'
                  '4244 Z:\\Users\\me\\OtherWine\\Installer.Exe -RunAsInvoker\n'
                  '4245 C:\\Program Files\\Dassault Systemes\\3DEXPERIENCE Launcher\\3DEXPERIENCELauncherSysTray.exe\n')
    watch = dict(INSTALL_TEST_NO_SHORTCUT='1', INSTALL_TEST_PS=str(processes),
                 INSTALL_TEST_PREFIX_PIDS='4242 4243 4245', INSTALL_TEST_PREFIX=str(prefix), SW_WATCH_INTERVAL='0.05')
    (desktop / 'SOLIDWORKS Design.lnk').unlink(missing_ok=True)
    processes.write_text(background)
    waits = []
    def install_flow(fields):
        if fields[0] == 'wait':
            waits.append(fields)
            if fields[1] == 'Install SolidWorks from Chrome':
                assert fields[4] == 'browser', fields
                if len(waits) == 1:
                    # Only the Launcher's own background programs run: still waiting.
                    time.sleep(0.4)
                    assert len(waits) == 1, waits
                    # Chrome is closed; Relaunch Chrome opens it again.
                    pid = int((project / 'logs/dashboard-browser.pid').read_text())
                    os.kill(pid, signal.SIGTERM)
                    for _ in range(50):
                        if 'browser-closed' in calls.read_text():
                            break
                        time.sleep(0.1)
                    window_process[0].stdin.write('@@relaunch\n')
                    window_process[0].stdin.flush()
                    for _ in range(50):
                        if calls.read_text().count('browser:') == 2:
                            break
                        time.sleep(0.1)
                    assert calls.read_text().count('browser:') == 2, calls.read_text()
                processes.write_text(background + installer_line)
            elif len(waits) == 2:
                # The installer closes before SOLIDWORKS is installed.
                processes.write_text(background)
            else:
                (desktop / 'SOLIDWORKS Design.lnk').touch()
                time.sleep(0.3)
                processes.write_text(background)
            return None
        return {'message': 'ok', 'url': 'https://example.com/', 'msi': str(msi)}.get(fields[0])
    code, events = run_window(install_flow, **watch)
    assert code == 0, events
    titles = [fields[1] for fields in waits]
    assert titles == ['Install SolidWorks from Chrome', 'Installing SolidWorks',
                      'Install SolidWorks from Chrome', 'Installing SolidWorks'], waits
    assert waits[1][3] == 'Running SOLIDWORKSSetup.exe' and 'closed before SolidWorks finished' in waits[2][3], waits
    notes = [fields[1] for fields in events if fields[0] == 'notify']
    assert any('Close the installer window' in note for note in notes), notes
    steps = [fields[1] for fields in events if fields[0] == 'stage']
    assert steps[-1] == 'finish' and steps.index('start') < steps.index('solidworks'), steps
    # The Launcher service is started before anyone is sent to the dashboard's Install button.
    assert 'wine:wineboot' in calls.read_text().splitlines(), calls.read_text()
    for _ in range(50):
        if '10-fresh-signin.sh' in calls.read_text():
            break
        time.sleep(0.1)
    assert calls.read_text().splitlines()[-1] == '10-fresh-signin.sh'
    # Quitting while waiting for the installer (the window sends TERM) stops the Wine services.
    (desktop / 'SOLIDWORKS Design.lnk').unlink()
    processes.write_text(background)
    def quit_at_start(fields):
        if fields[0] == 'wait':
            window_process[0].terminate()
            return None
        return {'message': 'ok', 'url': 'https://example.com/', 'msi': str(msi)}.get(fields[0])
    code, events = run_window(quit_at_start, **watch)
    lines = calls.read_text().splitlines()
    assert code == 130 and lines[-3:] == ['wine:wineboot', 'browser-closed', 'stop:-k'], (lines, events)
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
