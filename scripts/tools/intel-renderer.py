#!/usr/bin/env python3
"""Manage the app-local WineMetalGL DLLs and their Wine launcher state."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


MODULE_FILES = (
    'x86_64-unix/libwinemetalgl.dylib', 'x86_64-unix/winemetalgl.so',
    'x86_64-windows/opengl32.dll', 'x86_64-windows/winemetalgl.dll',
    'i386-windows/opengl32.dll', 'i386-windows/winemetalgl.dll',
)
APP_FILES = {Path(path).name: path for path in MODULE_FILES if path.startswith('x86_64-windows/')}
OVERRIDES = {'sldworks.exe': 'native,builtin', 'sldProcMon.exe': 'builtin'}


def digest(path):
    with path.open('rb') as source:
        checksum = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b''):
            checksum.update(block)
        return checksum.hexdigest()


def read_manifest(package):
    manifest = {}
    for line in (package / 'SHA256SUMS.txt').read_text().splitlines():
        checksum, name = line.split(maxsplit=1)
        if name in manifest or name not in MODULE_FILES or not re.fullmatch('[a-f0-9]{64}', checksum):
            raise ValueError('Invalid WineMetalGL package manifest')
        manifest[name] = checksum
    if set(manifest) != set(MODULE_FILES):
        raise ValueError('Incomplete WineMetalGL package')
    for name, checksum in manifest.items():
        if digest(package / name) != checksum:
            raise ValueError(f'WineMetalGL package checksum failed for {name}')
    return manifest


class Installation:
    def __init__(self, prefix):
        self.prefix = prefix.resolve()
        self.cad = self.prefix / ('drive_c/Program Files/Dassault Systemes/'
                                  'SOLIDWORKS 3DEXPERIENCE R2026x/SOLIDWORKS')
        self.directory = self.prefix / '.sw-intel-renderer'
        self.state_file = self.directory / 'state.json'
        self.package = self.directory / 'wine-module'

    @staticmethod
    def registry(key, name, kind, action, value=None):
        command = ['wine', 'reg', action, key, '/v', name]
        if action == 'add':
            command += ['/t', kind, '/d', value, '/f']
        elif action == 'delete':
            command += ['/f']
        result = subprocess.run(command, capture_output=True, text=True, check=action != 'query')
        if action != 'query':
            return None
        if result.returncode == 1:
            return None
        result.check_returncode()
        found = re.search(rf'^\s*{re.escape(name)}\s+{kind}(?:[ \t]+([^\r\n]*))?$', result.stdout, re.I | re.M)
        if not found:
            raise ValueError(f'Unexpected registry type for {name}')
        return found.group(1) or ''

    def override(self, app, action, value=None):
        key = rf'HKCU\Software\Wine\AppDefaults\{app}\DllOverrides'
        return self.registry(key, 'opengl32', 'REG_SZ', action, value)

    def pipeline(self, action, value=None):
        key = r'HKCU\Software\SolidWorks\SOLIDWORKS 2026\Performance'
        return self.registry(key, 'Use Performance Pipeline 2020', 'REG_DWORD', action, value)

    def state(self):
        return json.loads(self.state_file.read_text()) if self.state_file.is_file() else None

    def save_state(self, state):
        temporary = self.state_file.with_suffix('.tmp')
        temporary.write_text(json.dumps(state) + '\n')
        temporary.replace(self.state_file)

    def check_targets(self, manifest):
        for filename, name in APP_FILES.items():
            target = self.cad / filename
            if target.is_symlink() or (target.exists() and
                (not target.is_file() or manifest is None or digest(target) != manifest[name])):
                raise ValueError(f'Found an unmanaged SolidWorks DLL at {target}')

    def check(self):
        if not self.directory.exists():
            return
        state = self.state()
        if not state or not state['active']:
            raise ValueError('WineMetalGL setup is incomplete')
        manifest = read_manifest(self.package)
        if manifest != state['manifest']:
            raise ValueError('Installed WineMetalGL package has changed')
        self.check_targets(manifest)
        if not all((self.cad / name).is_file() for name in APP_FILES):
            raise ValueError('SolidWorks is missing a WineMetalGL DLL')
        print(self.package)

    def enable(self, package):
        if not (self.cad / 'sldworks.exe').is_file():
            raise ValueError('SolidWorks must be installed before enabling WineMetalGL')
        manifest = read_manifest(package)
        state = self.state()
        existing_pipeline = {}
        if state and manifest != state['manifest']:
            existing_pipeline = {key: state[key] for key in ('previous_pipeline', 'pipeline_initialized')
                                 if key in state}
            self.disable(restore_pipeline=False)
            state = None
        if not state:
            self.check_targets(None)
            previous = {app: self.override(app, 'query') for app in OVERRIDES}
            self.directory.mkdir(exist_ok=True)
            state = {'previous': previous, 'manifest': manifest, 'active': False, **existing_pipeline}
        if 'previous_pipeline' not in state:
            state['previous_pipeline'] = self.pipeline('query')
        self.check_targets(manifest)
        for app, value in OVERRIDES.items():
            current = self.override(app, 'query')
            if current not in (state['previous'][app], value):
                raise ValueError(f'The OpenGL override for {app} changed outside the installer')
        state['active'] = False
        self.save_state(state)
        try:
            installed = read_manifest(self.package)
        except (OSError, ValueError):
            installed = None
        if installed != manifest:
            if self.package.exists():
                shutil.rmtree(self.package)
            shutil.copytree(package, self.package)
        for app, value in OVERRIDES.items():
            self.override(app, 'add', value)
        for filename, name in APP_FILES.items():
            target = self.cad / filename
            with tempfile.TemporaryDirectory(dir=self.cad) as directory:
                temporary = Path(directory) / filename
                shutil.copy2(self.package / name, temporary)
                temporary.replace(target)
        if not state.get('pipeline_initialized'):
            self.pipeline('add', '0x1')
            state['pipeline_initialized'] = True
        state['active'] = True
        self.save_state(state)
        self.check()

    def disable(self, restore_pipeline=True):
        state = self.state()
        if not state:
            if self.directory.exists():
                shutil.rmtree(self.directory)
            return
        self.check_targets(state['manifest'])
        state['active'] = False
        self.save_state(state)
        for filename in APP_FILES:
            (self.cad / filename).unlink(missing_ok=True)
        for app, value in OVERRIDES.items():
            previous = state['previous'][app]
            if self.override(app, 'query') == value and previous != value:
                if previous is None:
                    self.override(app, 'delete')
                else:
                    self.override(app, 'add', previous)
        if restore_pipeline and 'previous_pipeline' in state and self.pipeline('query') == '0x1':
            previous = state['previous_pipeline']
            if previous is None:
                self.pipeline('delete')
            elif previous != '0x1':
                self.pipeline('add', previous)
        shutil.rmtree(self.directory)


if __name__ == '__main__':
    try:
        mode = sys.argv[1]
        installation = Installation(Path(os.environ['WINEPREFIX']))
        if mode == 'check':
            installation.check()
        elif mode == 'enable':
            installation.enable(Path(sys.argv[2]))
        elif mode == 'disable':
            installation.disable()
        else:
            raise ValueError(f'Unknown WineMetalGL operation {mode}')
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f'{error}. Use the installer window to update Wine or disable its experimental Intel renderer.')
