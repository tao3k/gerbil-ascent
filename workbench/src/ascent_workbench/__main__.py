# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Commands owned by the downstream qualification project."""
import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("formal", "native-tests"))
    args, rest = parser.parse_known_args()
    if args.command == "formal":
        from .formal import main as run
    else:
        from .native_tests import main as run
    sys.argv = [sys.argv[0], *rest]
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
