#!/usr/bin/env bash
# build.sh — stage the /opt tree, then wrap it as .deb + .rpm with nFPM.
#   GODOT=godot.linuxbsd.editor.double.x86_64 packaging/build.sh
# builds both into packaging/dist/.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LOOP_PKG_VERSION="${LOOP_PKG_VERSION:-0.1.0}"
dist="$here/dist"; mkdir -p "$dist"

"$here/stage.sh"

# nFPM resolves relative `contents.src` against CWD, so run from the repo root.
cd "$here"
for fmt in deb rpm; do
  nfpm pkg -f nfpm.yaml -p "$fmt" -t "dist/"
done

echo "=== built packages ==="
ls -la "$dist"
