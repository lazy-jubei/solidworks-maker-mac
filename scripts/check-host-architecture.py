#!/usr/bin/env python3
"""Check CPU-specific setup and launch decisions using isolated fake Wine binaries."""
import os
from pathlib import Path
import runpy
import shutil
import subprocess
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent
server_patch = root / 'scripts/patches/wineserver-window-list.py'
server_edits = runpy.run_path(str(server_patch))['PATCHES']


def executable(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/bin/zsh\nset -eu\n' + body)
    path.chmod(0o755)


with TemporaryDirectory(prefix='sw-host-check-') as temporary:
    for host in ['arm64', 'intel', 'no-arm-feature']:
        project = Path(temporary) / (host + ' checkout')
        scripts = project / 'scripts'
        scripts.mkdir(parents=True)
        for name in ['02-wine.sh', 'run-solidworks.sh']:
            shutil.copy2(root / 'scripts' / name, scripts / name)
        # Replace only the system-query executable so tests can simulate physical hosts.
        (scripts / 'env.sh').write_text((root / 'scripts/env.sh').read_text()
                                       .replace('/usr/sbin/sysctl', 'sysctl'))
        tools = scripts / 'tools'
        tools.mkdir()
        (tools / 'require-stopped.py').write_text('# Isolated test prefix; no processes are started.\n')
        patches = scripts / 'patches'
        patches.mkdir()
        shutil.copy2(server_patch, patches / server_patch.name)
        (patches / 'wow64cpu-rosetta-trampoline.py').write_text(
            'from pathlib import Path\nimport sys\n'
            'Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes()+b"-rosetta")\n')
        volume = project / 'volume'
        prefix = volume / 'prefix'
        (prefix / 'drive_c').mkdir(parents=True)
        wine_app = volume / 'wine-staging-11.16/Wine Staging.app'
        resources = wine_app / 'Contents/Resources/wine'
        cpu = resources / 'lib/wine/x86_64-windows/wow64cpu.dll'
        cpu.parent.mkdir(parents=True)
        cpu.write_bytes(b'stock')
        server_backup = resources / 'bin/wineserver.stock'
        server_backup.parent.mkdir(parents=True)
        original_server = bytearray(max(offset + len(bytes.fromhex(before)) for offset, before, _ in server_edits))
        original_server[:8] = bytes.fromhex('cffaedfe07000001')
        for offset, before, _ in server_edits:
            original = bytes.fromhex(before)
            original_server[offset:offset + len(original)] = original
        server_backup.write_bytes(original_server)
        server = server_backup.with_name('wineserver')
        server.write_bytes(original_server)
        server.chmod(0o755)
        executable(volume / 'bin/winetricks', 'exit 0\n')
        cache = project / 'cache'
        cache.mkdir()
        (cache / 'wine-staging-11.16-osx64.tar.xz').touch()
        fakebin = project / 'bin'
        fakebin.mkdir()
        executable(fakebin / 'sysctl', 'print 1\n' if host == 'arm64' else
                   ('print 0\n' if host == 'intel' else 'exit 1\n'))
        executable(fakebin / 'curl', 'exit 0\n')
        executable(fakebin / 'xattr', 'exit 0\n')
        executable(fakebin / 'codesign', 'exit 0\n')
        executable(fakebin / 'wine', 'print -r -- "${SW_REPORT_ARM64:-unset}" > "$HOST_TEST_RESULT"\n')
        result_file = project / 'result'
        env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ['PATH'],
                   SW_PROJECT_ROOT=str(project), SW_CONFIG_FILE='/dev/null',
                   SW_VOL=str(volume), SW_PREFIX=str(prefix), SW_TENANT='TEST_TENANT',
                   SW_HOST_ARM64='1', SW_REPORT_ARM64='1', HOST_TEST_RESULT=str(result_file))
        install = subprocess.run(['zsh', str(scripts / '02-wine.sh')], env=env,
                                 capture_output=True, text=True)
        assert install.returncode == 0, install.stderr
        assert cpu.read_bytes() == (b'stock-rosetta' if host == 'arm64' else b'stock')
        assert Path(str(cpu) + '.stock').exists() == (host == 'arm64')
        patched_server = server.read_bytes()
        for offset, _, after in server_edits:
            replacement = bytes.fromhex(after)
            assert patched_server[offset:offset + len(replacement)] == replacement
        assert server_backup.read_bytes() == original_server
        launch = subprocess.run(['zsh', str(scripts / 'run-solidworks.sh')], env=env,
                                capture_output=True, text=True)
        assert launch.returncode == 0, launch.stderr
        assert result_file.read_text().strip() == '1'

print('Passed: physical Apple Silicon, Intel and missing ARM sysctl; Rosetta-only patch selection and ARM64 host reporting at launch on every host. No Wine or CAD executed.')
