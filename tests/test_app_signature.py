import plistlib
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from verify_macho import ARM64, verify_macho


def executable(entitlements):
    blob = b''
    entries = b''
    if entitlements is not None:
        data = plistlib.dumps(entitlements)
        blob = struct.pack('>II', 0xfade7171, len(data) + 8) + data
        entries = struct.pack('>II', 5, 20)
    signature = struct.pack('>III', 0xfade0cc0, 12 + len(entries) + len(blob), bool(entries)) + entries + blob
    header = struct.pack('<8I', 0xfeedfacf, *ARM64, 2, 2, 32, 0, 0)
    commands = struct.pack('<4I', 0x25, 16, 0x70000, 0) + struct.pack('<4I', 0x1d, 16, 64, len(signature))
    image = header + commands + signature
    return struct.pack('>7I', 0xcafebabe, 1, *ARM64, 28, len(image), 0) + image


class AppSignatureTests(unittest.TestCase):
    def test_socket_entitlement_is_required(self):
        targets = {ARM64: 0x70000}
        verify_macho(executable({'com.apple.private.security.no-sandbox': True}), targets, app_entitlements=True)
        for value in (None, {}, {'com.apple.private.security.no-sandbox': False}):
            with self.subTest(value=value), self.assertRaises(AssertionError):
                verify_macho(executable(value), targets, app_entitlements=True)


if __name__ == '__main__':
    unittest.main()
