"""Real pipe controls for qualification output forwarding; no engine harness."""

import os
import subprocess
import sys
import threading
import time
import unittest

from ascent_workbench.supervision import forward_output


class OutputForwardingTests(unittest.TestCase):
    def test_supervisor_retains_nonzero_exit_with_nonblocking_stdout(self):
        payload = bytes(range(256)) * 3072
        received = bytearray()
        command = [
            sys.executable, "-c",
            "import os; os.set_blocking(1, False); "
            "from ascent_workbench.supervision import main; raise SystemExit(main())",
            "--", sys.executable, "-c",
            "import sys; sys.stdout.buffer.write(bytes(range(256)) * 3072); "
            "sys.stdout.flush(); raise SystemExit(7)",
        ]
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
            def consume():
                while chunk := child.stdout.read(1137):
                    received.extend(chunk)
                    time.sleep(0.0001)

            reader = threading.Thread(target=consume, daemon=True)
            reader.start()
            try:
                code = child.wait(timeout=10)
                errors = child.stderr.read()
            finally:
                reader.join(timeout=5)
            self.assertFalse(reader.is_alive())
            self.assertEqual(code, 7, errors.decode())
            self.assertEqual(received, payload)

    def test_backpressure_preserves_all_bytes_and_descriptor_mode(self):
        payload = bytes(range(256)) * 3072
        for blocking in (False, True):
            with self.subTest(blocking=blocking):
                read_fd, write_fd = os.pipe()
                received = bytearray()

                def consume():
                    try:
                        while chunk := os.read(read_fd, 1137):
                            received.extend(chunk)
                            time.sleep(0.0001)
                    finally:
                        os.close(read_fd)

                reader = threading.Thread(target=consume, daemon=True)
                reader.start()
                try:
                    with os.fdopen(write_fd, "wb", buffering=0) as output:
                        os.set_blocking(output.fileno(), blocking)
                        forward_output(output, payload, 5)
                        self.assertEqual(os.get_blocking(output.fileno()), blocking)
                finally:
                    reader.join(timeout=5)
                self.assertFalse(reader.is_alive())
                self.assertEqual(received, payload)

    def test_stalled_sink_rejects_without_resetting_its_deadline(self):
        read_fd, write_fd = os.pipe()
        try:
            with os.fdopen(write_fd, "wb", buffering=0) as output:
                os.set_blocking(write_fd, False)
                with self.assertRaises(BlockingIOError):
                    while True:
                        os.write(write_fd, b"x" * 65536)
                with self.assertRaises(TimeoutError):
                    forward_output(output, b"must not disappear", 0.05)
                self.assertFalse(os.get_blocking(write_fd))
        finally:
            os.close(read_fd)


if __name__ == "__main__":
    unittest.main()
