import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POSTINST = (ROOT / 'packaging/DEBIAN/postinst').read_text()


def function(name):
    return re.search(r'^' + name + r'\(\) \{\n.*?^\}\n', POSTINST, re.M | re.S).group(0)


class LaunchdInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='shiro-launchd-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        (self.base / 'usr/bin').mkdir(parents=True)
        daemon = self.base / 'usr/bin/shirod'
        daemon.write_text('#!/bin/sh\n[ "$1" = --status ] || exit 1\n[ -n "$TEST_REPLY" ] || exit 1\nprintf "%s\\n" "$TEST_REPLY"\n')
        daemon.chmod(0o755)

    def run_script(self, script, reply=''):
        env = dict(os.environ, TEST_REPLY=reply, TEST_BASE=str(self.base))
        source = 'set -eu\npayload="$TEST_BASE"\njbroot=/var/jb\nsleep() { :; }\n'
        source += function('shirod_answers') + function('request_reboot') + function('launchd_restart_in_place')
        return subprocess.run(['/bin/sh', '-c', source + script], env=env, capture_output=True, text=True)

    def test_status_must_answer_and_match_the_new_pid(self):
        self.assertEqual(self.run_script('shirod_answers 44', '44').returncode, 0)
        self.assertNotEqual(self.run_script('shirod_answers 44', '43').returncode, 0)
        self.assertNotEqual(self.run_script('shirod_answers ""').returncode, 0)

    def test_missing_job_requests_reboot(self):
        script = 'launchd_job_pid() { return 1; }; launchd_loaded() { return 1; }; launchd_restart_in_place'
        result = self.run_script(script)
        self.assertEqual(result.returncode, 3)
        self.assertIn('reboots', result.stderr)

    def test_loaded_job_without_pid_can_start(self):
        script = '''launchd_job_pid() {
            if [ -f "$TEST_BASE/seen" ]; then echo 44; else : > "$TEST_BASE/seen"; return 1; fi
        }
        launchd_loaded() { return 0; }
        launchd_restart_in_place'''
        self.assertEqual(self.run_script(script, '44').returncode, 0)

    def test_respawn_must_answer_with_its_pid(self):
        script = '''launchd_job_pid() {
            if [ -f "$TEST_BASE/seen" ]; then echo 44; else : > "$TEST_BASE/seen"; echo 43; fi
        }
        kill() { :; }
        launchd_restart_in_place'''
        result = self.run_script(script, '43')
        self.assertEqual(result.returncode, 2)
        self.assertIn('did not bring shirod back', result.stderr)


if __name__ == '__main__':
    unittest.main()
