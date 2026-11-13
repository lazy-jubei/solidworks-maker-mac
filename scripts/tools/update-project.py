#!/usr/bin/env python3
"""Install managed source files, with rollback; never copy/delete runtime or user data."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tempfile

MANIFEST = '.sw-project-files.json'
PROTECTED = {'cache', 'logs', 'tools', 'build', 'dist', 'tmp', 'output', '.git',
             '.sw-update-backups', '.sw-update-lock', 'config.local.zsh', '.env', MANIFEST}


def safe_name(name):
    p = PurePosixPath(name)
    return (bool(p.parts) and not p.is_absolute() and '..' not in p.parts
            and p.parts[0] not in PROTECTED
            and not p.parts[0].endswith('.sparsebundle')
            and not p.parts[0].startswith(('prefix', '.env.')))


def update(source, target):
    source, target = source.resolve(), target.absolute()
    if target.is_symlink() or (target / '.git').exists():
        raise ValueError('Use git to update a development checkout; automatic updates require an extracted installation.')
    if not (target / 'scripts/env.sh').is_file():
        raise ValueError('This folder is not an existing SOLIDWORKS Maker installation.')
    incoming = {}
    for path in source.rglob('*'):
        name = path.relative_to(source).as_posix()
        if path.is_symlink():
            raise ValueError(f'Symlink in release: {name}')
        if path.is_file():
            if name == MANIFEST:
                continue
            if not safe_name(name):
                raise ValueError(f'Protected path in release: {name}')
            incoming[name] = path
    if not {'install.sh', 'setup.sh', 'scripts/env.sh', 'scripts/update.sh'} <= incoming.keys():
        raise ValueError('Incomplete project download.')
    if (target / MANIFEST).is_symlink():
        raise ValueError('Symlink in installed-file manifest.')
    old = json.loads((target / MANIFEST).read_text()) if (target / MANIFEST).exists() else []
    if not isinstance(old, list) or any(not isinstance(n, str) or not safe_name(n) for n in old):
        raise ValueError('Invalid installed-file manifest.')
    names = sorted(set(incoming) | set(old))
    # Reject links and file/directory conflicts before backing up or replacing anything.
    for name in names + [MANIFEST, '.sw-update-backups']:
        dst = target / name
        parents = []
        for parent in dst.parents:
            if parent == target:
                break
            parents.append(parent)
        if dst.is_symlink() or any(p.is_symlink() for p in parents):
            raise ValueError(f'Symlink in update destination: {name}')
        if name != '.sw-update-backups' and dst.exists() and not dst.is_file():
            raise ValueError(f'File conflict: {name}')
        for parent in dst.parents:
            if parent == target:
                break
            if parent.exists() and not parent.is_dir():
                raise ValueError(f'Parent is not a directory: {name}')
    backups = target / '.sw-update-backups'
    backups.mkdir(exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-'), dir=backups))
    existed = []
    for name in names + [MANIFEST]:
        dst = target / name
        if dst.exists():
            saved = backup / name
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dst, saved)
            existed.append(name)
    (backup / 'backup-files.json').write_text(json.dumps(existed, indent=2) + '\n')
    changed = []
    try:
        # Stage on the target filesystem; os.replace never truncates a running script.
        with tempfile.TemporaryDirectory(prefix='.sw-update-', dir=target) as staging:
            staged = Path(staging)
            for name, src in incoming.items():
                out = staged / name
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, out)
            (staged / MANIFEST).write_text(json.dumps(sorted(incoming), indent=2) + '\n')
            for name in names + [MANIFEST]:
                dst = target / name
                changed.append(name)
                if name in incoming or name == MANIFEST:
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    os.replace(staged / name, dst)
                elif dst.exists():
                    # Only obsolete files from a prior managed install may be removed.
                    dst.unlink()
    except BaseException:
        for name in reversed(changed):
            dst = target / name
            if name in existed:
                shutil.copy2(backup / name, dst)
            elif dst.exists():
                dst.unlink()
        raise
    print(f'Updated {len(incoming)} project files. Previous sources: {backup}')
    print('Wine, the installed SOLIDWORKS prefix, local settings and CAD files were preserved.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('target', type=Path)
    args = parser.parse_args()
    try:
        update(args.source, args.target)
    except (OSError, ValueError) as error:
        parser.exit(1, f'Update stopped: {error}\n')
