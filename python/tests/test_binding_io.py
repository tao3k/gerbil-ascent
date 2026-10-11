# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import subprocess
import sys
import unittest


class NativeHostStreams(unittest.TestCase):
    def test_output_and_host_input_survive_native_flag_changes_and_failure(self):
        code = '''
import fcntl, os
from ascent_engine import _preserve_host_io
os.set_inheritable(1, False)
os.write(1, b'host-output:')
os.write(2, b'host-error:')
inheritable = {fd: os.get_inheritable(fd) for fd in (0, 1, 2)}
before = {fd: fcntl.fcntl(fd, fcntl.F_GETFL) for fd in (0, 1, 2)}
try:
    with _preserve_host_io():
        assert os.read(0, 1) == b''
        fcntl.fcntl(1, fcntl.F_SETFL, fcntl.fcntl(1, fcntl.F_GETFL) | os.O_NONBLOCK)
        os.write(1, b'native-output:')
        os.write(2, b'native-error')
        raise RuntimeError('native failure')
except RuntimeError:
    pass
assert before == {fd: fcntl.fcntl(fd, fcntl.F_GETFL) for fd in (0, 1, 2)}
assert inheritable == {fd: os.get_inheritable(fd) for fd in (0, 1, 2)}
os.write(1, os.read(0, 10))
'''
        result = subprocess.run([sys.executable, '-c', code], input=b'host-input',
                                capture_output=True, timeout=10, check=True)
        self.assertEqual(result.stdout, b'host-output:native-output:host-input')
        self.assertEqual(result.stderr, b'host-error:native-error')
