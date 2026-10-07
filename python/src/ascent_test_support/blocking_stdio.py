# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Exec a non-Gambit command with blocking inherited standard streams.

Gambit's inherited descriptors can carry O_NONBLOCK through ``gerbil env``.
Rust's ordinary logging and panic diagnostics expect blocking pipes. Restore
that contract at the process boundary, preserving bytes, arguments and exits.
"""
import os
import sys


def main() -> None:
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        raise SystemExit("blocking_stdio: expected a command")
    for descriptor in (0, 1, 2):
        os.set_blocking(descriptor, True)
    os.execvp(command[0], command)


if __name__ == "__main__":
    main()
