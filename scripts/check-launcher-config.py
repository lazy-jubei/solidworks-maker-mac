#!/usr/bin/env python3
"""Exercise generated launchers without mounting images or starting Wine."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import contextlib
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parent.parent
builder=root/'scripts/09-mac-launcher.sh'
code=builder.read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
with TemporaryDirectory(prefix='sw-launcher-config-') as temporary:
    temporary=Path(temporary).resolve()
    project=temporary/'checkout with spaces'
    scripts=project/'scripts'
    for name in ('env.sh','run-solidworks.sh','10-fresh-signin.sh','tools/signin-monitor.py','tools/launch-once.py',
                 'tools/MacLauncher.swift','tools/intel-renderer.py','tools/container-processes.py','tools/permission-notice.sh',
                 'tools/ConfirmDialog.cs','tools/WebViewWindow.cs','tools/WinInput.cs','tools/ExistingCad.cs'):
        target=scripts/name;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(root/'scripts'/name,target)
    main_volume=temporary/'main volume'
    main_prefix=main_volume/'main prefix'
    main_image=temporary/'main image.sparsebundle'
    config=project/'config.local.zsh'
    import shlex
    config.write_text('\n'.join('export '+name+'='+shlex.quote(str(value)) for name,value in {
        'SW_VOL':main_volume,'SW_PREFIX':main_prefix,'SW_IMAGE':main_image,
        'SW_TENANT':'test-tenant'}.items())+'\n')
    base_config=config.read_text()
    apps={}
    for mode in ('','--test'):
        with patch('pathlib.Path.home',return_value=temporary/'home'),patch.object(sys,'argv',['builder',mode,str(scripts)]),contextlib.redirect_stdout(io.StringIO()) as output:
            exec(compile(code,str(builder),'exec'),{'__name__':'__main__'})
        app=Path(output.getvalue().strip());apps[mode]=app
        subprocess.run(['zsh','-n',str(app/'Contents/Resources/launch.sh')],check=True)

    # Run the native entry point through the generated script without launching Wine.
    wine=main_volume/'wine-staging-11.16/Wine Staging.app/Contents/Resources/wine/bin/wine'
    wine.parent.mkdir(parents=True)
    wine.write_text('#!/bin/zsh\nexit 99\n')
    wine.chmod(0o755)
    runtime_entry=apps['']/'Contents/Resources/runtime/scripts/10-fresh-signin.sh'
    runtime_entry.write_text('#!/bin/zsh\nprint "Reached launcher runtime"\nexit 17\n')
    fixture_home=temporary/'home'
    subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(apps[''])],check=True)
    native=subprocess.run([str(apps['']/'Contents/MacOS/launch')],
                          env=dict(os.environ,HOME=str(fixture_home)),timeout=10)
    assert native.returncode==17,native.returncode
    assert 'Reached launcher runtime' in (fixture_home/'Library/Logs/SolidWorksWine/main-launcher.log').read_text()

    def inspect(mode):
        launch=apps[mode]/'Contents/Resources/launch.sh'
        text=launch.read_text()
        # Execute only the generated configuration code, before mount/launch/logging.
        body=text[text.index('unset SW_VOL'):text.index('if [[ ! -d "$VOL" ]]')]
        body+='\nexport VOL IMAGE\npython3 -c '+shlex.quote(
            'import os,json; print(json.dumps({k:os.environ.get(k) for k in ("VOL","IMAGE","WINEPREFIX","SW_TENANT")}))')
        return subprocess.run(['zsh','-c',body,str(launch)],capture_output=True,text=True)

    main=inspect('');assert main.returncode==0,main.stderr
    values=json.loads(main.stdout)
    assert values=={'VOL':str(main_volume),'IMAGE':str(main_image),'WINEPREFIX':str(main_prefix),'SW_TENANT':'test-tenant'},values
    fresh=inspect('--test');assert fresh.returncode==0,fresh.stderr
    values=json.loads(fresh.stdout)
    assert values['VOL']=='/Volumes/SWWineT',values
    assert values['WINEPREFIX']=='/Volumes/SWWineT/prefix-11.16',values
    assert values['IMAGE']==str(project/'swwine-test.sparsebundle'),values
    assert values['SW_TENANT']=='test-tenant',values
    with config.open('a') as file:file.write('export SW_TEST_PREFIX='+shlex.quote(str(main_prefix))+'\n')
    rejected=inspect('--test')
    assert rejected.returncode!=0 and 'different prefix' in rejected.stderr,rejected.stderr
    config.write_text(base_config+'export SW_TEST_IMAGE='+shlex.quote(str(main_image))+'\n')
    rejected=inspect('--test')
    assert rejected.returncode!=0 and 'different disk image' in rejected.stderr,rejected.stderr
    config.write_text('export SW_TENANT=test-tenant\n')
    for mode,filename in (('','swwine.sparsebundle'),('--test','swwine-test.sparsebundle')):
        result=inspect(mode);assert result.returncode==0,result.stderr
        assert json.loads(result.stdout)['IMAGE']==str(project/filename),result.stdout

    tool_dir = main_volume / 'tools'
    tool_dir.mkdir()
    for helper in ('ConfirmDialog', 'WebViewWindow', 'WinInput', 'ExistingCad'):
        (tool_dir / (helper + '.exe')).touch()
    (scripts / 'tools/launch-once.py').write_text(
        'import os\nprint(os.environ.get("SW_MAC_EMBEDDED_SIGNIN", "fallback"))\n')
    unix = wine.parent.parent / 'lib/wine/x86_64-unix'
    unix.mkdir(parents=True)
    modules = (unix / 'win32u.so', unix / 'winemac.so')
    for module in modules:
        module.write_bytes(module.name.encode())
    marker = unix / 'embedded-signin.sha256'
    marker.write_text(''.join(
        f'{hashlib.sha256(module.read_bytes()).hexdigest()}  {module.name}\n' for module in modules))

    def signin(setting):
        config.write_text(base_config + f'export SW_EMBEDDED_SIGNIN={setting}\n')
        return subprocess.run(['zsh', str(scripts / '10-fresh-signin.sh')],
                              env=dict(os.environ, SW_MAC_EMBEDDED_SIGNIN='1'),
                              capture_output=True, text=True, check=True, timeout=10)

    # Helpers without a matching source stamp are rebuilt; a failed build keeps the old copy.
    stale = signin(0)
    assert stale.stdout.strip() == 'fallback'
    assert 'Could not rebuild WebViewWindow.exe; using the existing copy.' in stale.stderr, stale.stderr
    assert (tool_dir / 'WebViewWindow.exe').exists() and not list(tool_dir.glob('*.new.exe'))
    for helper in ('ConfirmDialog', 'WebViewWindow', 'WinInput', 'ExistingCad'):
        source = (scripts / 'tools' / (helper + '.cs')).read_bytes()
        (tool_dir / (helper + '.source.sha256')).write_text(hashlib.sha256(source).hexdigest() + '\n')
    current = signin(0)
    assert current.stdout.strip() == 'fallback' and 'rebuild' not in current.stderr, current.stderr
    assert signin(1).stdout.strip() == '1'
    modules[1].write_bytes(b'updated module')
    mismatch = signin(1)
    assert mismatch.stdout.strip() == 'fallback' and 'out of date' in mismatch.stderr
    marker.unlink()
    assert signin(1).stdout.strip() == 'fallback'

print('Launcher configuration passed: custom main paths, isolated fresh prefix, shared-prefix/image refusal, default images, paths with spaces, stale helper rebuild and embedded sign-in fallback.')
