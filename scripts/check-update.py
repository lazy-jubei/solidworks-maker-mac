#!/usr/bin/env python3
"""Exercise data preservation, source rollback, and stopped-prefix runtime updates."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tarfile
from tempfile import TemporaryDirectory
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('updater', ROOT / 'scripts/tools/update-project.py')
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def put(path, text='new', executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


def refuse(source, target):
    try:
        updater.update(source, target)
    except (ValueError, OSError):
        return
    raise AssertionError('Unsafe update accepted')


with TemporaryDirectory(prefix='sw-update-check-') as tmp:
    base = Path(tmp).resolve()
    source, target = base / 'release', base / 'nested/install with spaces'
    for name in ['install.sh', 'setup.sh', 'scripts/env.sh', 'scripts/update.sh', 'scripts/new/nested.sh']:
        put(source / name, executable=True)
    put(target / 'scripts/env.sh', 'old env')
    put(target / 'scripts/obsolete.sh', 'old script')
    put(target / updater.MANIFEST, json.dumps(['scripts/env.sh', 'scripts/obsolete.sh']))
    # Include files inside and outside the Wine image, plus caches and user config.
    preserved = ['config.local.zsh', 'cache/package.tar.xz', 'tools/helper', 'logs/a.log',
                 'swwine.sparsebundle/bands/1', 'prefix-11.16/drive_c/models/part.SLDPRT',
                 'my-part.SLDPRT', 'scripts/local-custom.sh']
    for name in preserved:
        put(target / name, 'user content')
    updater.update(source, target)
    assert all((target / name).read_text() == 'user content' for name in preserved)
    assert not (target / 'scripts/obsolete.sh').exists()
    assert (target / 'scripts/new/nested.sh').stat().st_mode & 0o111
    backup = next((target / '.sw-update-backups').iterdir())
    assert (backup / 'scripts/env.sh').read_text() == 'old env'
    assert (backup / 'scripts/obsolete.sh').read_text() == 'old script'
    # A failed replacement restores files and manifest, including removed sources.
    before = {p.relative_to(target): p.read_bytes() for p in target.rglob('*')
              if p.is_file() and '.sw-update-backups' not in p.parts}
    put(source / 'scripts/env.sh', 'next env')
    real_replace = os.replace
    count = [0]
    def fail_replace(src, dst):
        count[0] += 1
        if count[0] == 3:
            raise OSError('injected write failure')
        return real_replace(src, dst)
    with patch.object(updater.os, 'replace', fail_replace):
        refuse(source, target)
    assert all((target / name).read_bytes() == data for name, data in before.items())
    # Refuse protected manifests, symlinks, and directory conflicts before writes.
    manifest = (target / updater.MANIFEST).read_bytes()
    for bad in ['../outside', 'config.local.zsh', 'swwine.sparsebundle/bands/1', '/absolute']:
        (target / updater.MANIFEST).write_text(json.dumps([bad]))
        refuse(source, target)
    (target / updater.MANIFEST).write_bytes(manifest)
    (source / 'scripts/link').symlink_to(source / 'install.sh')
    refuse(source, target)
    (source / 'scripts/link').unlink()
    linked = base / 'linked install'
    linked.symlink_to(target)
    refuse(source, linked)
    external = base / 'external'
    external.mkdir()
    (target / 'scripts/new/nested.sh').unlink()
    (target / 'scripts/new').rmdir()
    (target / 'scripts/new').symlink_to(external, target_is_directory=True)
    refuse(source, target)
    assert not list(external.iterdir())
    (target / 'scripts/new').unlink()
    (target / '.git').mkdir()
    refuse(source, target)
    refuse(source, base / 'missing/nested/install')

    # Run the real one-command entry point against a fake release download. It
    # must update an old extracted installation without opening the reinstall UI.
    download = base / 'download/solidworks-maker-mac-v0.4.0'
    shutil.copytree(source, download)
    shutil.copy2(ROOT / 'scripts/tools/update-project.py', download / 'scripts/update-project.tmp')
    (download / 'scripts/tools').mkdir()
    (download / 'scripts/update-project.tmp').rename(download / 'scripts/tools/update-project.py')
    put(download / 'scripts/09-mac-launcher.sh', '#!/bin/zsh\nprint refreshed >> "$BOOT_CALLS"\n', True)
    put(download / 'scripts/install-guided.sh', '#!/bin/zsh\nprint REINSTALL >> "$BOOT_CALLS"\nexit 77\n', True)
    archive = base / 'release.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(download, arcname=download.name)
    checksum = base / 'SHA256SUMS'
    checksum.write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + '  solidworks-maker-mac.tar.gz\n')
    fakebin = base / 'fakebin'
    put(fakebin / 'uname', '#!/bin/zsh\nprint Darwin\n', True)
    put(fakebin / 'curl', '''#!/bin/zsh
while (( $# )); do
  if [[ "$1" == -o ]]; then
    if [[ "$2" == */SHA256SUMS ]]; then cp "$BOOT_SUMS" "$2"; else cp "$BOOT_ARCHIVE" "$2"; fi
    exit
  fi
  shift
done
exit 2
''', True)
    installed = base / 'old extracted/install'
    put(installed / 'scripts/env.sh', 'old env')
    put(installed / 'config.local.zsh', 'settings')
    put(installed / 'swwine.sparsebundle/bands/1', 'Wine and CAD')
    boot_calls = base / 'boot-calls'
    boot_env = dict(os.environ, PATH=str(fakebin)+os.pathsep+os.environ['PATH'],
                    SW_INSTALL_DIR=str(installed), BOOT_CALLS=str(boot_calls),
                    BOOT_ARCHIVE=str(archive), BOOT_SUMS=str(checksum))
    def bootstrap():
        return subprocess.run(['zsh', str(ROOT / 'install.sh')], env=boot_env, capture_output=True, text=True)
    result = bootstrap()
    assert result.returncode == 0, result.stderr
    assert boot_calls.read_text().splitlines() == ['refreshed']
    assert (installed / 'config.local.zsh').read_text() == 'settings'
    assert (installed / 'swwine.sparsebundle/bands/1').read_text() == 'Wine and CAD'
    assert not (installed / '.sw-update-lock').exists()
    checksum.write_text('0'*64+'  solidworks-maker-mac.tar.gz\n')
    failed = bootstrap()
    assert failed.returncode != 0 and boot_calls.read_text().splitlines() == ['refreshed']
    assert not (installed / '.sw-update-lock').exists()
    # A stale/concurrent update lock must block the bootstrap before any replacement.
    (installed / '.sw-update-lock').mkdir()
    assert bootstrap().returncode != 0
    (installed / '.sw-update-lock').rmdir()

    # Exercise the real runtime orchestration with fake mutation stages. A running
    # prefix refusal must precede all builds/deployments; no reset stage is supplied.
    project, volume = base / 'runtime project', base / 'Wine volume'
    scripts = project / 'scripts'
    shutil.copytree(ROOT / 'scripts/tools', scripts / 'tools', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    shutil.copy2(ROOT / 'scripts/update-wine.sh', scripts / 'update-wine.sh')
    prefix, app = volume / 'prefix', volume / 'Wine.app'
    image = project / 'swwine.sparsebundle'
    image.mkdir()
    put(prefix / 'system.reg', 'registry')
    put(prefix / 'drive_c/models/keep.SLDPRT', 'CAD')
    calls = base / 'runtime-calls'
    env = dict(os.environ, UPDATE_TEST_CALLS=str(calls))
    variables = {'ROOT': project, 'VOL': volume, 'IMAGE': image, 'WINEPREFIX': prefix, 'WINE_APP': app}
    put(scripts / 'env.sh', ''.join(f'export {k}={shlex.quote(str(v))}\n' for k, v in variables.items()))
    put(app / 'Contents/Resources/wine/bin/wine', '#!/bin/zsh\nexit 0\n', True)
    put(app / 'Contents/Resources/wine/bin/wineserver', '#!/bin/zsh\nprint -r -- "stop:$1" >> "$UPDATE_TEST_CALLS"\n', True)
    stages = ['01-storage.sh', 'tools/check-setup-requirements.sh', '02-wine.sh',
              'build-shell32.sh', 'install-ntdll-shim.sh', 'build-mac-gdi.sh', 'build-button-capture.sh',
              'install-windows-fonts.sh', 'build-signin-tools.sh', 'install-dxmt.sh',
              '06-settings.sh', '09-mac-launcher.sh']
    for name in stages:
        put(scripts / name, '#!/bin/zsh\nset -eu\n'
            f'print {shlex.quote(name)} >> "$UPDATE_TEST_CALLS"\n'
            f'[[ "${{UPDATE_TEST_FAIL:-}}" != {shlex.quote(name)} ]]\n', True)
    put(scripts / 'tools/require-stopped.py', 'import os,sys\nsys.exit(9 if os.environ.get("UPDATE_TEST_ACTIVE") else 0)\n')
    def runtime(**extra):
        calls.unlink(missing_ok=True)
        return subprocess.run(['zsh', str(scripts / 'update-wine.sh')], env=dict(env, **extra), capture_output=True, text=True)
    active = runtime(UPDATE_TEST_ACTIVE='1')
    assert active.returncode == 9 and calls.read_text().splitlines() == ['01-storage.sh']
    result = runtime()
    assert result.returncode == 0, result.stderr
    lines = calls.read_text().splitlines()
    assert [n for n in lines if not n.startswith('stop:')] == stages
    assert lines[lines.index('install-dxmt.sh')-2:lines.index('install-dxmt.sh')] == ['stop:-k', 'stop:-w']
    assert (prefix / 'drive_c/models/keep.SLDPRT').read_text() == 'CAD'
    failed = runtime(UPDATE_TEST_FAIL='install-dxmt.sh')
    assert failed.returncode != 0 and calls.read_text().splitlines()[-2:] == ['stop:-k', 'stop:-w']
    assert '06-settings.sh' not in calls.read_text()
    assert not (project / '.sw-update-lock').exists()
    shutil.rmtree(app)
    mismatch = runtime()
    assert mismatch.returncode != 0 and calls.read_text().splitlines() == ['01-storage.sh']

print('Passed: managed update preservation, rollback, obsolete cleanup, unsafe destinations, runtime ordering/failure and active-prefix refusal.')
