#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

set -euo pipefail

release_root="${1:?usage: install-gerbil-v19-release.sh RELEASE_ROOT}"
revision=1cfb032c7a1612637da6205f5f8a15683eba3ba0
gambit_revision=ea114fc3d2f120abbe20393c1f9aeafdd3f8c89f

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    release_os=linux
    release_arch=x86_64
    tag=gerbil-v0.19-1cfb032c7a1612637da6205f5f8a15683eba3ba0-linux-x86_64-portable-full-single-host-unlimited-multiple-vms-patch9599b09b82f8
    sha256=143c691fee5af4f9f631fd339f69a66f562e42e0bfc1d4ee2cda5fa8d35c35ee
    ;;
  Darwin-arm64)
    release_os=darwin
    release_arch=aarch64
    tag=gerbil-v0.19-1cfb032c7a1612637da6205f5f8a15683eba3ba0-darwin-aarch64-gcc16-arm64-aot-tools-single-host-unlimited-multiple-vms-patch618d76f9eb72
    sha256=0e18d063f888a73d9f9692d441fb3776898114e8440eada6876937d289578183
    ;;
  *)
    printf 'unsupported Gerbil release host: %s-%s\n' "$(uname -s)" "$(uname -m)" >&2
    exit 64
    ;;
esac

archive="$tag.tar.gz"
download="${GERBIL_RELEASE_ARCHIVE_CACHE:-${RUNNER_TEMP:?}}/$archive"
mkdir -p "$release_root" "$(dirname "$download")"
if [ ! -f "$download" ]; then
  curl --fail --location --retry 3 --output "$download" \
    "https://github.com/tao3k/gerbil-bazel/releases/download/$tag/$archive"
fi
# Every restored archive must satisfy the pinned digest before extraction.
echo "$sha256  $download" | shasum -a 256 --check
tar -xzf "$download" -C "$release_root" --strip-components=1

jq -e --arg revision "$revision" --arg os "$release_os" --arg arch "$release_arch" \
  '.schema == "gerbil-bazel.toolchain-release.v1" and
   .upstreamRevision == $revision and
   .platform.os == $os and .platform.arch == $arch' \
  "$release_root/gerbil-toolchain-release.json" >/dev/null

source "$release_root/activate"
# Admit the same continuation ownership repair and VM capabilities on each OS.
if ! jq -e --arg revision "$revision" --arg gambit "$gambit_revision" \
  '.sourceRevision == $revision and .singleHostMode == "unlimited" and
   ((["--enable-single-host=0", "--enable-multiple-vms", "--enable-smp",
      ("--with-gambit=" + $gambit)] - .configureArguments) | length == 0)' \
  "$release_root/gerbil-build-receipt.json" >/dev/null ||
   ! grep -Eq '^#define ___MULTIPLE_VMS([[:space:]]|$)' "$GERBIL_HOME/include/gambit.h" ||
   ! grep -Eq '^#define ___INVALIDATE_STACK_OVERFLOW_UNDO([[:space:]]|$)' "$GERBIL_HOME/include/gambit.h"; then
  printf 'SDK-ADMISSION-ERROR: require Gerbil %s / Gambit %s, SMP, multiple VMs and continuation undo invalidation; inspect %s\n' \
    "$revision" "$gambit_revision" "$release_root/gerbil-build-receipt.json" >&2
  exit 65
fi
printf 'CI-GERBIL-SDK gerbil=%s gambit=%s\n' "$revision" "$gambit_revision"
echo "$GERBIL_PREFIX/bin" >> "${GITHUB_PATH:?}"
{
  echo "GERBIL_PREFIX=$GERBIL_PREFIX"
  echo "GERBIL_HOME=$GERBIL_HOME"
  echo "GAMBOPT=$GAMBOPT"
} >> "${GITHUB_ENV:?}"

"$GERBIL_PREFIX/bin/gerbil" --version
"$GERBIL_PREFIX/bin/gerbil" interactive -e '(displayln "gerbil-ready")'
