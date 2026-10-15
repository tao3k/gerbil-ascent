# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The upstream Rust VM boundary preserves real host descriptors and streams."""
import subprocess
import sys
import unittest

class NativeHostStreams(unittest.TestCase):
    def test_descriptor_state_and_failure_recovery_use_upstream_runtime(self):
        code = r"""
import fcntl, os
from ascent import Engine, EngineError
read, write = os.pipe()
os.set_inheritable(write, False)
before = {fd: (fcntl.fcntl(fd, fcntl.F_GETFL),os.get_inheritable(fd)) for fd in (0,1,2,read,write)}
engine=Engine()
try:
    engine.dsl('(def bad (',trusted=True)
except EngineError:
    pass
else:
    raise AssertionError('malformed source accepted')
with engine.dsl('(def (answer) 7)',trusted=True) as module:
    with module.call('answer') as value: assert value.graph['root']['value']=='7'
assert before == {fd: (fcntl.fcntl(fd, fcntl.F_GETFL),os.get_inheritable(fd)) for fd in before}
os.write(write,b'unchanged')
assert os.read(read,9)==b'unchanged'
engine.shutdown()
print('descriptor recovery verified')
"""
        result=subprocess.run([sys.executable,'-c',code],capture_output=True,timeout=20,check=True)
        self.assertEqual(result.stdout,b'descriptor recovery verified\n')

    def test_output_and_host_input_survive_native_port_changes_and_failure(self):
        code = r"""
import fcntl, os
from ascent import Engine, EngineError
os.set_inheritable(1,False)
os.write(1,b'host-output:')
os.write(2,b'host-error:')
inheritable={fd:os.get_inheritable(fd) for fd in (0,1,2)}
before={fd:fcntl.fcntl(fd,fcntl.F_GETFL) for fd in (0,1,2)}
engine=Engine()
with engine.dsl('(def (fail) (close-input-port (current-input-port)) (error "native failure"))',trusted=True) as module:
    try: module.call('fail')
    except EngineError: pass
    else: raise AssertionError('native failure swallowed')
assert before=={fd:fcntl.fcntl(fd,fcntl.F_GETFL) for fd in (0,1,2)}
assert inheritable=={fd:os.get_inheritable(fd) for fd in (0,1,2)}
os.write(1,os.read(0,10))
"""
        result=subprocess.run([sys.executable,'-c',code],input=b'host-input',capture_output=True,timeout=20,check=True)
        self.assertEqual(result.stdout,b'host-output:host-input')
        self.assertEqual(result.stderr,b'host-error:')
