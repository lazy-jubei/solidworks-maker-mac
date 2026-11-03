#!/usr/bin/env python3
"""Publication checks for tracked setup-kit sources; not a security audit."""
import ast
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
paths = [Path(p) for p in paths if p]
if not paths:
    raise SystemExit('No tracked files; stage the intended release first.')
forbidden = {'cache', 'logs', 'tmp', 'output', 'dist', 'build', '.claude'}
patterns = [
    rb'gh[pousr]_[A-Za-z0-9]{20,}',
    rb'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----',
    rb'eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}',
    rb'/Users/[A-Za-z0-9._-]+/',
    rb'(?:192\.168\.|100\.85\.)\d+\.\d+',
    rb'(?i)(?:password|passwd)\s*[:=]\s*[\x22\x27][^\x22\x27\n]{4,}[\x22\x27]',
    rb'(?i)(?:SW_TENANT|TENANT)\s*=\s*[\x22\x27]OI\d+',
]
for relative in paths:
    path = root / relative
    if path.is_symlink() or forbidden.intersection(relative.parts) or 'config.local' in path.name:
        raise SystemExit(f'Private/runtime path tracked: {relative}')
    if any(p.endswith('.sparsebundle') for p in relative.parts) or path.suffix in {'.exe','.dll','.so','.msi','.log','.dmg'}:
        raise SystemExit(f'Runtime binary tracked: {relative}')
    if path.stat().st_size > 10_000_000:
        raise SystemExit(f'Oversized file: {relative}')
    data = path.read_bytes()
    if path.suffix != '.png':
        for pattern in patterns:
            if re.search(pattern, data):
                raise SystemExit(f'Potential private content in {relative}; review locally (value omitted)')
    if path.suffix == '.py':
        ast.parse(data, filename=str(relative))
    elif path.suffix == '.sh' or path.name.endswith('.zsh'):
        subprocess.run(['zsh','-n',str(path)],check=True)
    elif path.suffix == '.json':
        json.loads(data)
# Local Markdown links must resolve in the release checkout.
for relative in paths:
    if relative.suffix != '.md': continue
    for link in re.findall(r'\]\(([^)]+)\)', (root/relative).read_text()):
        if '://' in link or link.startswith('#'): continue
        target=link.split('#',1)[0]
        if not (root/relative.parent/target).exists():
            raise SystemExit(f'Broken local link in {relative}: {target}')
subprocess.run([sys.executable,str(root/'scripts/check-launcher-config.py')],check=True)
subprocess.run([sys.executable,str(root/'scripts/check-setup.py')],check=True)
subprocess.run([sys.executable,str(root/'scripts/check-storage.py')],check=True)
subprocess.run([sys.executable,str(root/'scripts/check-installer.py')],check=True)
subprocess.run([sys.executable,str(root/'scripts/check-host-architecture.py')],check=True)
subprocess.run([sys.executable,str(root/'scripts/check-single-launch.py')],check=True)
print(f'Passed: {len(paths)} tracked files, syntax, local links and publication-content checks.')
