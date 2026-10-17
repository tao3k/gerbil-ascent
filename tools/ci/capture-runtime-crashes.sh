#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set -euo pipefail
directory="${1:?usage: capture-runtime-crashes.sh DIRECTORY}"
executable="$(readlink -f "$(command -v gxi)")"
{
  uname -a
  file "$executable"
  sha256sum "$executable"
  cat /proc/sys/kernel/core_pattern
} > "$directory/runtime.txt"

shopt -s nullglob
cores=("$directory"/core.*)
printf 'NATIVE-CORES count=%s\n' "${#cores[@]}"
status=0
for core in "${cores[@]}"; do
  file "$core" > "$core.file.txt"
  sha256sum "$core" > "$core.sha256"
  if ! timeout 60s gdb --batch -nx \
    -ex 'set auto-load safe-path /nonexistent' \
    -ex 'set pagination off' -ex 'set print elements 32' \
    -ex 'info sharedlibrary' -ex 'info proc mappings' \
    -ex 'thread apply all bt full' -ex 'info registers' \
    -ex 'x/32i $pc-32' -ex 'x/32gx $sp' \
    "$executable" "$core" > "$core.gdb.txt" 2>&1; then
    status=1
  fi
  cat "$core.file.txt" "$core.gdb.txt"
done
exit "$status"
