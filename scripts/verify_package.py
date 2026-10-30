import io
import plistlib
import subprocess
import sys
import tarfile
from pathlib import PurePosixPath
from verify_macho import ARMV7, ARM64, ARM64E, EXECUTABLE_TARGETS, verify_macho

package, mode = sys.argv[1:]
control = subprocess.check_output(['dpkg-deb', '-f', package], text=True)
assert 'Package: com.shiro.daemon\n' in control
assert 'Architecture: all\n' in control
payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', package])
with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
    entries = {str(PurePosixPath(item.name)): item for item in archive.getmembers()}
    root = 'var/jb'
    for name in ['Applications/Shiro.app/Shiro', 'usr/bin/shirod', 'usr/lib/shirostatus.dylib', 'usr/lib/shirostatus-modern.dylib']:
        item = entries[f'{root}/{name}']
        assert item.mode == 0o755 and item.uid == 0 and item.gid == 0, name
        targets = EXECUTABLE_TARGETS
        if name == 'usr/lib/shirostatus.dylib':
            targets = {ARMV7: 0x50000, ARM64: 0x70000, ARM64E: 0xc0000}
        elif name == 'usr/lib/shirostatus-modern.dylib':
            targets = {ARM64: 0x70000, ARM64E: 0xe0000}
        verify_macho(archive.extractfile(item).read(), targets, signed=mode != '--unsigned',
                     app_entitlements=mode != '--unsigned' and name == 'Applications/Shiro.app/Shiro')
    info = plistlib.loads(archive.extractfile(entries[f'{root}/Applications/Shiro.app/Info.plist']).read())
    assert info['MinimumOSVersion'] == '5.0'
    assert info['CFBundleIdentifier'] == 'com.shiro.app'
    fonts = ['Rubik-Regular.ttf', 'Rubik-Medium.ttf', 'Rubik-Bold.ttf']
    assert info['UIAppFonts'] == fonts
    for font in fonts + ['Rubik-LICENSE.txt']:
        assert entries[f'{root}/Applications/Shiro.app/{font}'].size > 0
    version = subprocess.check_output(['dpkg-deb', '-f', package, 'Version'], text=True).strip()
    assert info['CFBundleShortVersionString'] == version
    assert info['CFBundleVersion'] == version
    assert f'#define SHIRO_VERSION @"v{version}"' in open('app/support/app_common.h').read()
    launch = plistlib.loads(archive.extractfile(entries[f'{root}/Library/LaunchDaemons/com.shiro.shirod.plist']).read())
    assert launch['ProgramArguments'] == ['/var/jb/usr/bin/shirod']
    assert launch.get('UserName', 'root') == 'root'
    assert f'{root}/usr/lib/shiro-launchd.sh' in entries
    assert f'{root}/usr/lib/shiro-status.sh' in entries
    assert f'{root}/Applications/Shiro.app/roots.pem' in entries
    assert f'{root}/Applications/Shiro.app/Icon.png' in entries
    assert not any('build/' in name or '..' in PurePosixPath(name).parts for name in entries)
print(f'{package}: layout, metadata, modes, ownership, architectures, ABI and signatures passed ({mode})')
