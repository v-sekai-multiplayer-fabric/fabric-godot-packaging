#!/usr/bin/env bash
# build-quadlet.sh — pin the runtime digest, stage the game, then wrap the
# loop-slice dedicated-server QUADLET as .rpm + .deb with nFPM.
#   GODOT=godot.linuxbsd.editor.double.x86_64 packaging build-quadlet.sh
# Set RUNTIME_DIGEST=sha256:... to pin a specific image; otherwise the latest
# zone-godot-runtime digest is resolved automatically (see pin-runtime-digest.sh).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LOOP_PKG_VERSION="${LOOP_PKG_VERSION:-0.1.0}"
dist="$here/dist"; mkdir -p "$dist"

"$here/bin/pin-runtime-digest.sh"      # rewrite Image= to a digest (no :latest)
"$here/stage.sh"                       # export the game -> stage/.../loop-slice.pck

cd "$here"
for fmt in rpm deb; do
  nfpm pkg -f nfpm-quadlet.yaml -p "$fmt" -t "dist/"
done

echo "=== built quadlet packages ==="
ls -la "$dist"/*quadlet* 2>/dev/null
