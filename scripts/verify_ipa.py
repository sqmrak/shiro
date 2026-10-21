import plistlib
import sys
import zipfile
from pathlib import PurePosixPath
from verify_macho import EXECUTABLE_TARGETS, verify_macho

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert all(name.startswith('Payload/Shiro.app/') or name == 'Payload/' for name in names)
    assert all('..' not in PurePosixPath(name).parts for name in names)
    prefix = 'Payload/Shiro.app/'
    info = plistlib.loads(archive.read(prefix + 'Info.plist'))
    assert info['CFBundleExecutable'] == 'Shiro'
    assert info['CFBundleIdentifier'] == 'com.shiro.app'
    assert info['MinimumOSVersion'] == '5.0'
    source = plistlib.load(open('packaging/Info.plist', 'rb'))
    assert info['CFBundleShortVersionString'] == source['CFBundleShortVersionString']
    assert info['CFBundleVersion'] == source['CFBundleVersion']
    binary_info = archive.getinfo(prefix + 'Shiro')
    assert (binary_info.external_attr >> 16) & 0o777 == 0o755
    binary = archive.read(binary_info)
    verify_macho(binary, EXECUTABLE_TARGETS)
    for resource in ['Icon.png', 'Icon@2x.png', 'Icon-60@3x.png', 'shiro_fox.png', 'roots.pem', 'LICENSE']:
        assert prefix + resource in names
print(f'{sys.argv[1]}: zip, layout, executable modes, armv7/arm64/arm64e, iOS 5/7/14 targets and signature records passed')
