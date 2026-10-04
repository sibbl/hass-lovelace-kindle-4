"""Hardware-independent regressions; run with python3 -m unittest discover -s tests -v."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
UTILS = ROOT / 'extensions/homeassistant/utils.sh'


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.env = dict(os.environ, PATH=str(self.path) + ':' + os.environ['PATH'])

    def run_download(self, mock, timeout=4):
        wget = self.path / 'wget'
        wget.write_text('#!/bin/sh\n' + mock)
        wget.chmod(0o755)
        script = '''
. "$1"
TMPFILE="$2/image.tmp"
IMAGE_URI=http://example.invalid/image
BASIC_AUTH_USERNAME=private-user
BASIC_AUTH_PASSWORD=private-password
DOWNLOAD_TIMEOUT=3
RESULT=$(download_image 2>&1)
STATUS=$?
printf '%s' "$RESULT"
exit "$STATUS"
'''
        return subprocess.run(['sh', '-c', script, 'sh', str(UTILS), str(self.path)],
                              env=self.env, capture_output=True, text=True, timeout=timeout)

    def test_success_does_not_wait_for_watchdog(self):
        start = time.monotonic()
        result = self.run_download('printf image > "$4"\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(time.monotonic() - start, 1.5)

    def test_timeout_and_cleanup(self):
        result = self.run_download('exec sleep 30\n', timeout=6)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.path / 'image.tmp').exists())

    def test_size_limit(self):
        result = self.run_download('exec dd if=/dev/zero of="$4" bs=65536 count=80\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.path / 'image.tmp').exists())

    def test_empty_response_rejected(self):
        result = self.run_download(': > "$4"\n')
        self.assertNotEqual(result.returncode, 0)

    def test_credentials_not_logged(self):
        result = self.run_download('echo "$2" >&2\nexit 1\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('private-user', result.stdout + result.stderr)
        self.assertNotIn('private-password', result.stdout + result.stderr)

    def test_watchdog_sleep_is_reaped(self):
        sleep = self.path / 'sleep'
        sleep.write_text('''#!/bin/sh
trap 'kill "$CHILD"; wait "$CHILD"; echo stopped > "''' + str(self.path / 'timer.stopped') + '''"; exit 0' TERM
/bin/sleep "$@" &
CHILD=$!
wait "$CHILD"
''')
        sleep.chmod(0o755)
        result = self.run_download('/bin/sleep 0.2\nprintf image > "$4"\n')
        self.assertEqual(result.returncode, 0)
        self.assertEqual((self.path / 'timer.stopped').read_text().strip(), 'stopped')


class DaemonTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.daemon = self.path / 'daemon.sh'
        source = (ROOT / 'extensions/homeassistant/daemon.sh').read_text()
        # This runner exposes a host /proc with PIDs that differ from child PIDs.
        # Model cmdline/cwd explicitly; process launches and signals remain real.
        self.proc = self.path / 'proc'
        self.proc.mkdir()
        self.daemon.write_text(source.replace('/mnt/us/extensions/homeassistant', str(self.path))
                               .replace('/proc/', str(self.proc) + '/'))
        # Deliberately non-executable, like the repository scripts.
        (self.path / 'script.sh').write_text('''#!/bin/sh
mkdir -p "proc/$$"
ln -s "$PWD" "proc/$$/cwd"
printf 'sh\\000%s\\000' "$PWD/script.sh" > "proc/$$/cmdline"
trap 'rm -rf "proc/$$"; exit 0' TERM INT
while :; do sleep 0.1; done
''')
        self.pidfile = self.path / 'homeassistant.pid'
        self.addCleanup(lambda: self.control('stop'))

    def control(self, action):
        return subprocess.run(['sh', str(self.daemon), action], capture_output=True, text=True, timeout=15)

    def start(self):
        result = self.control('start')
        self.assertEqual(result.returncode, 0, result.stderr)
        time.sleep(0.1)
        return self.pidfile.read_text()

    def test_repeated_start_and_stop(self):
        pid = self.start()
        self.assertEqual(self.control('status').returncode, 0)
        self.assertEqual(self.control('start').returncode, 0)
        self.assertEqual(self.pidfile.read_text(), pid)
        self.assertEqual(self.control('stop').returncode, 0)
        self.assertEqual(self.control('status').returncode, 1)

    def test_unrelated_script_survives_stop(self):
        other = self.path / 'other'
        other.mkdir()
        script = other / 'script.sh'
        script.write_text('#!/bin/sh\nexec sleep 60\n')
        process = subprocess.Popen(['sh', str(script)])
        self.addCleanup(process.wait)
        self.addCleanup(process.terminate)
        self.pidfile.write_text(str(process.pid))
        self.assertEqual(self.control('stop').returncode, 0)
        self.assertIsNone(process.poll())

    def test_malformed_pid_is_not_passed_to_kill(self):
        for pid in ['0', '00', '01', '-1', '1', '12 34', '', 'abc']:
            self.pidfile.write_text(pid)
            self.assertEqual(self.control('status').returncode, 1)
            self.assertEqual(self.control('stop').returncode, 0)

    def test_control_lock_prevents_second_start(self):
        lock = self.path / 'homeassistant.pid.lock'
        lock.mkdir()
        self.assertNotEqual(self.control('start').returncode, 0)
        self.assertFalse(self.pidfile.exists())
        lock.rmdir()

    def test_simultaneous_starts_are_serialized(self):
        commands = [subprocess.Popen(['sh', str(self.daemon), 'start'],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    for _ in range(2)]
        for command in commands:
            command.communicate(timeout=5)
        self.assertEqual(sorted(command.returncode for command in commands), [0, 1])
        self.assertEqual(self.control('status').returncode, 0)

    def test_restart_replaces_owned_process(self):
        old_pid = self.start()
        self.assertEqual(self.control('restart').returncode, 0)
        self.assertNotEqual(self.pidfile.read_text(), old_pid)
        time.sleep(0.1)


if __name__ == '__main__':
    unittest.main()
