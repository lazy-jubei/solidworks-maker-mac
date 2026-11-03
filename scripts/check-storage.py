#!/usr/bin/env python3
"""Exercise image/mount guards with fake hdiutil; never mount or detach an image."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('image_mount', root / 'scripts/tools/image-mount-state.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def entry(image, volume):
    return {'image-path': str(image), 'system-entities': [{'mount-point': str(volume)}]}


with TemporaryDirectory(prefix='sw-storage-check-') as temporary:
    base = Path(temporary).resolve()
    for case in ('mounted', 'fresh', 'ordinary', 'wrong-image', 'elsewhere', 'bad-attach', 'bad-inventory'):
        folder = base / case
        project = folder / 'project with spaces'
        scripts = project / 'scripts'
        tools = scripts / 'tools'
        tools.mkdir(parents=True)
        shutil.copy2(root / 'scripts/01-storage.sh', scripts / '01-storage.sh')
        shutil.copy2(root / 'scripts/tools/image-mount-state.py', tools / 'image-mount-state.py')
        image, volume, cache = folder / 'image.sparsebundle', folder / 'mounted volume', project / 'cache'
        state, calls = folder / 'state.json', folder / 'calls.jsonl'
        (scripts / 'env.sh').write_text('\n'.join(f'{k}={shlex.quote(str(v))}' for k, v in {
            'ROOT': project, 'IMAGE': image, 'VOL': volume, 'CACHE': cache, 'IMAGE_SIZE': '200g',
        }.items()) + '\n')
        images = []
        if case in ('mounted', 'ordinary', 'wrong-image'):
            volume.mkdir()
            (volume / 'keep.txt').write_text('preserve me')
        if case == 'mounted':
            image.mkdir()
            images = [entry(image, volume)]
        elif case == 'wrong-image':
            images = [entry(folder / 'other.sparsebundle', volume)]
        elif case == 'elsewhere':
            images = [entry(image, folder / 'elsewhere')]
        elif case == 'bad-inventory':
            images = None
        state.write_text(json.dumps({'images': images}))
        bin_dir = folder / 'bin'
        bin_dir.mkdir()
        mock = bin_dir / 'hdiutil'
        mock.write_text('''#!/usr/bin/env python3
import json,os,plistlib,sys
from pathlib import Path
args=sys.argv[1:];state=Path(os.environ['STORAGE_TEST_STATE'])
with open(os.environ['STORAGE_TEST_CALLS'],'a') as f:f.write(json.dumps(args)+'\\n')
if args[0]=='info':sys.stdout.buffer.write(plistlib.dumps(json.loads(state.read_text())))
elif args[0]=='create':Path(args[-1]).mkdir()
elif args[0]=='attach':
    point=args[args.index('-mountpoint')+1];Path(point).mkdir()
    image=args[1] if os.environ['STORAGE_TEST_CASE']!='bad-attach' else args[1]+'.wrong'
    state.write_text(json.dumps({'images':[{'image-path':image,'system-entities':[{'mount-point':point}]}]}))
else:sys.exit('Unexpected hdiutil operation')
''')
        mock.chmod(0o755)
        # Keep even temporary sparsebundle creation entirely inside this fixture.
        temp_stub = bin_dir / 'mktemp'
        temp_stub.write_text('#!/usr/bin/env python3\nimport os,tempfile\nprint(tempfile.mkdtemp(dir=os.environ["STORAGE_TEST_FOLDER"]))\n')
        temp_stub.chmod(0o755)
        env = dict(os.environ, STORAGE_TEST_STATE=str(state), STORAGE_TEST_CALLS=str(calls),
                   STORAGE_TEST_CASE=case, STORAGE_TEST_FOLDER=str(folder))
        env['PATH'] = str(bin_dir) + os.pathsep + env['PATH']
        result = subprocess.run(['zsh', str(scripts / '01-storage.sh')], env=env, capture_output=True, text=True)
        operations = [json.loads(line) for line in calls.read_text().splitlines()]
        if case in ('mounted', 'fresh'):
            assert result.returncode == 0, (case, result.stderr)
            assert (volume / 'tmp').is_dir() and (volume / 'bin').is_dir()
            if case == 'mounted':
                assert all(op[0] == 'info' for op in operations)
                assert (volume / 'keep.txt').read_text() == 'preserve me'
            else:
                attach = next(op for op in operations if op[0] == 'attach')
                assert attach[attach.index('-mountpoint') + 1] == str(volume)
                assert image.is_dir()
        else:
            assert result.returncode != 0, case
            assert not (volume / 'tmp').exists() and not (volume / 'bin').exists()
            if case != 'bad-attach':
                assert not cache.exists() and all(op[0] == 'info' for op in operations)
            if case in ('ordinary', 'wrong-image'):
                assert (volume / 'keep.txt').read_text() == 'preserve me'

    alias = base / 'image alias'
    alias.symlink_to(base / 'mounted/image.sparsebundle', target_is_directory=True)
    assert module.mount_state([entry(alias, base / 'mounted/mounted volume')],
                              str(base / 'mounted/image.sparsebundle'),
                              str(base / 'mounted/mounted volume')) == 'mounted'

print('Passed: matching/fresh mounts, explicit mount point, alias paths, ordinary/foreign mounts, attached-elsewhere and post-attach refusal.')
