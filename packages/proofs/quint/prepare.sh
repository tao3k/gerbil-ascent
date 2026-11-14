#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
set -euo pipefail
tool=.cache/ascent/tools/quint
mkdir -p "$tool"
if [[ ! -x "$tool/node_modules/.bin/quint" ]] || ! cmp -s packages/proofs/quint/package-lock.json "$tool/package-lock.json" || ! cmp -s packages/proofs/quint/package.json "$tool/package.json"; then
  cp packages/proofs/quint/package.json packages/proofs/quint/package-lock.json "$tool/"
  (cd "$tool"; npm ci --ignore-scripts --no-audit --no-fund)
fi
[[ "$("$tool/node_modules/.bin/quint" --version)" = 0.33.0 ]]
export QUINT_HOME="$PWD/.cache/ascent/tools/quint-backends"
jar="$QUINT_HOME/apalache-dist-0.62.1/apalache/lib/apalache.jar"
if [[ ! -f "$jar" ]]; then
  node - <<'JS'
const {fetchApalache} = require('./.cache/ascent/tools/quint/node_modules/@informalsystems/quint/dist/src/apalache.js');
fetchApalache('0.62.1', 2).then(result => {
  if (result.isLeft()) {console.error(result.value); process.exit(1)}
}).catch(error => {console.error(error); process.exit(1)});
JS
fi
actual=$(shasum -a 256 "$jar" | awk '{print $1}')
[[ "$actual" = "$(cat packages/proofs/quint/backend.sha256)" ]] || { echo 'Quint backend checksum mismatch' >&2; exit 2; }
