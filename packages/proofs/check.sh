#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
for source in packages/proofs/lean/*.lean; do
  echo "LEAN-CHECK $source"
  elan run leanprover/lean4:v4.34.1 lean "$source"
done
if [[ -n "${TLC_JAR:-}" ]]; then
  tlc=(java -XX:+UseParallelGC -Xmx1g -cp "$TLC_JAR" tlc2.TLC)
else
  tlc=("${TLC_BIN:-tlc}")
fi
depth="${ASCENT_PROOF_EXPLORATION_DEPTH:-2}"
[[ "$depth" =~ ^[0-9]+$ ]] && (( depth >= 2 )) || { echo 'Exploration depth must be an integer >= 2' >&2; exit 2; }
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
for model in PositiveNonmembershipSession SessionTransaction; do
  sed "s/ExplorationDepth = [0-9][0-9]*/ExplorationDepth = $depth/" "packages/proofs/tla/$model.cfg" > "$temp/$model.cfg"
  echo "TLA-CHECK $model exploration=$depth (not a protocol limit)"
  "${tlc[@]}" -workers 2 -config "$temp/$model.cfg" -metadir "$temp/$model" "packages/proofs/tla/$model.tla"
done
for mutation in early stale; do
  sed "s/Mutation = \"none\"/Mutation = \"$mutation\"/" "$temp/SessionTransaction.cfg" > "$temp/$mutation.cfg"
  if "${tlc[@]}" -workers 2 -config "$temp/$mutation.cfg" -metadir "$temp/$mutation" packages/proofs/tla/SessionTransaction.tla > "$temp/$mutation.log" 2>&1; then
    cat "$temp/$mutation.log"
    echo "Missing counterexample for $mutation" >&2
    exit 1
  else
    code=$?
  fi
  cat "$temp/$mutation.log"
  case "$mutation" in
    early) [[ "$code" = 12 ]] && grep -q 'Invariant AtomicSnapshot is violated' "$temp/$mutation.log" ;;
    stale) [[ "$code" = 13 ]] && grep -q 'Action property NoStaleCommit is violated' "$temp/$mutation.log" ;;
  esac
  echo "COUNTEREXAMPLE-OK $mutation"
done
echo 'FORMAL-CHECK-OK'
