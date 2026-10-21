import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'packaging/status.sh'
REMOVE = re.search(r'^shiro_status_remove\(\) \{\n.*?^\}\n',
                   (ROOT / 'packaging/DEBIAN/postrm').read_text(), re.M | re.S).group(0)


class StatusInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='shiro-status-install-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / 'source.dylib'
        self.filter = self.base / 'source.plist'
        self.dest = self.base / 'DynamicLibraries'
        self.source.write_bytes(b'signed status extension fixture')
        self.filter.write_text('{ Filter = { Bundles = ("com.apple.springboard"); }; };')

    def install(self, rootless=False, success=True):
        result = subprocess.run(['/bin/sh', '-c',
            '. "$1"; shiro_status_install "$2" "$3" "$4" "$5"', 'test',
            str(HELPER), str(self.source), str(self.filter), str(self.dest),
            '1' if rootless else '0'], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)

    def remove(self):
        subprocess.run(['/bin/sh', '-c', REMOVE + '\nshiro_status_remove "$1"',
                        'test', str(self.dest)], check=True)

    def test_rootful_uses_real_files(self):
        self.install()
        binary = self.dest / 'shirostatus.dylib'
        self.assertFalse(binary.is_symlink())
        self.assertEqual(binary.read_bytes(), self.source.read_bytes())
        self.assertEqual(binary.stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.dest / 'shirostatus.plist').stat().st_mode & 0o777, 0o644)
        self.remove()
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_rootless_links_binary_and_copies_filter(self):
        self.install(rootless=True)
        self.assertEqual(os.readlink(self.dest / 'shirostatus.dylib'), str(self.source))
        self.assertFalse((self.dest / 'shirostatus.plist').is_symlink())
        self.remove()
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_upgrade_replaces_legacy_payload_links(self):
        self.dest.mkdir()
        (self.dest / 'shirostatus.dylib').symlink_to('/var/jb/usr/lib/shirostatus.dylib')
        (self.dest / 'shirostatus.plist').symlink_to('/var/jb/usr/lib/shirostatus.plist')
        self.install()
        self.assertFalse((self.dest / 'shirostatus.dylib').is_symlink())
        self.source.write_bytes(b'updated extension')
        self.install()
        self.assertEqual((self.dest / 'shirostatus.dylib').read_bytes(), b'updated extension')

    def test_foreign_files_are_preserved(self):
        self.dest.mkdir()
        binary = self.dest / 'shirostatus.dylib'
        binary.write_bytes(b'unmanaged')
        self.install(success=False)
        self.remove()
        self.assertEqual(binary.read_bytes(), b'unmanaged')

    def test_foreign_symlink_is_preserved(self):
        self.dest.mkdir()
        binary = self.dest / 'shirostatus.dylib'
        binary.symlink_to(self.source)
        self.install(success=False)
        self.remove()
        self.assertTrue(binary.is_symlink())

    def test_stale_staging_file_is_preserved(self):
        self.dest.mkdir()
        stage = self.dest / 'shirostatus.dylib.dpkg-new'
        stage.write_bytes(b'previous staging')
        self.install(success=False)
        self.assertEqual(stage.read_bytes(), b'previous staging')

    def test_missing_source_does_not_replace_extension(self):
        self.install()
        before = (self.dest / 'shirostatus.dylib').read_bytes()
        self.source.unlink()
        self.install(success=False)
        self.assertEqual((self.dest / 'shirostatus.dylib').read_bytes(), before)

    def test_removes_old_links_without_payload_helper(self):
        self.dest.mkdir()
        for name in ['shirostatus.dylib', 'shirostatus.plist']:
            (self.dest / name).symlink_to('/var/jb/usr/lib/' + name)
        self.remove()
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_postrm_upgrade_keeps_current_installation(self):
        script = (ROOT / 'packaging/DEBIAN/postrm').read_text()
        guard = re.search(r'^case .*?esac$', script, re.M).group(0)
        for action, expected in [('upgrade', 0), ('remove', 9), ('purge', 9)]:
            result = subprocess.run(['/bin/sh', '-c', guard + '\nexit 9', 'test', action])
            self.assertEqual(result.returncode, expected)

    def test_launchd_pid_uses_only_the_exact_running_job(self):
        helper = ROOT / 'packaging/launchd.sh'
        cases = [
            ('PID Status Label\n474 - com.shiro.shirod\n', '474'),
            ('474 - com.shiro.shirod.other\n', None),
            ('- 0 com.shiro.shirod\n', None),
            ('1 - com.shiro.shirod\n', None),
            ('0 - com.shiro.shirod\n', None),
            ('474 - com.shiro.shirod extra\n', None),
            ('474 - com.senko.senkod\n', None),
        ]
        for jobs, expected in cases:
            env = dict(os.environ, SHIRO_TEST_JOBS=jobs)
            result = subprocess.run(['/bin/sh', '-c',
                '. "$1"; launchctl_cmd() { printf "%s" "$SHIRO_TEST_JOBS"; }; launchd_job_pid',
                'test', str(helper)], env=env, capture_output=True, text=True)
            if expected is None:
                self.assertNotEqual(result.returncode, 0)
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)


if __name__ == '__main__':
    unittest.main()
