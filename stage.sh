#!/usr/bin/env bash
# stage.sh — assemble the relocatable /opt/org.v-sekai/loop-slice tree that the
# native packagers wrap.  Build-system-agnostic: it exports the Godot game with
# the merged double-precision build, then lays the finished artifacts into the
# vendor layout, so the same tree feeds nfpm (deb/rpm) today and pkgbuild/WiX
# later if those channels are ever wanted.  brew/scoop stay dev/user channels;
# this is the system/deploy channel into /opt.
#
# Modelled on sinew-mocap/packaging/stage.sh, adapted from C++ build/ artifacts
# to a Godot export.
#
# Usage: ./stage.sh [STAGE_DIR]   (default: ./stage)
#
# Required: GODOT — path to the merged double-precision editor that owns the
#   matching double export templates (e.g. godot.linuxbsd.editor.double.x86_64
#   from v-sekai-multiplayer-fabric/godot-images).  The export fails without the
#   double templates installed for this editor.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The loop-slice project is checked out beside this repo (clone godot-loop-slice
# next to fabric-packaging). Override with LOOP_SRC for any other location.
root="${LOOP_SRC:-$(cd "$here/../godot-loop-slice" 2>/dev/null && pwd || true)}"
[ -n "$root" ] && [ -f "$root/project.godot" ] || {
  echo "godot-loop-slice not found beside this repo; set LOOP_SRC to its path" >&2
  exit 1
}
stage="${1:-$here/stage}"
vendor="$stage/opt/org.v-sekai"

LOOP_VER="${LOOP_VER:-0.1}"                       # major.minor channel dir
GODOT="${GODOT:-}"
bindst="$vendor/loop-slice/$LOOP_VER/bin"
sharedst="$vendor/loop-slice/$LOOP_VER/share/loop-slice"

[ -n "$GODOT" ] && command -v "$GODOT" >/dev/null 2>&1 || {
  echo "set GODOT to the merged double editor, e.g. GODOT=godot.linuxbsd.editor.double.x86_64" >&2
  exit 1
}

say() { printf '  %-22s %s\n' "$1" "$2"; }

rm -rf "$stage"
mkdir -p "$bindst" "$sharedst"

# ── Quadlet path: pck only ────────────────────────────────────────────────────
# The dedicated-server quadlet runs the published zone-godot-runtime image's
# godot with --main-pack, so it needs ONLY the exported pck — no standalone
# Linux export template. export-pack produces that without a template.
if [ -n "${PCK_ONLY:-}" ]; then
  ( cd "$root" && "$GODOT" --headless --import . >/dev/null 2>&1 || true )
  ( cd "$root" && "$GODOT" --headless --export-pack "Linux/X11" "build/linux/loop-slice.pck" )
  [ -s "$root/build/linux/loop-slice.pck" ] || { echo "pck export missing/empty — check the Linux/X11 preset for $GODOT" >&2; exit 1; }
  install -m644 "$root/build/linux/loop-slice.pck" "$bindst/loop-slice.pck"; say loop-slice.pck ok
  echo "staged (pck-only) -> $stage"
  exit 0
fi

# ── Export the Linux/X11 build (binary + sidecar pck, embed_pck=false) ────────
# The exported executable auto-mounts loop-slice.pck when colocated, so both go
# in bin/ together.  --import first so a clean checkout has its .godot cache.
( cd "$root" && "$GODOT" --headless --import . >/dev/null 2>&1 || true )
rm -f "$root/build/linux/loop-slice.x86_64"   # don't let a stale stub satisfy the check below
( cd "$root" && "$GODOT" --headless --export-release "Linux/X11" "build/linux/loop-slice.x86_64" )
file "$root/build/linux/loop-slice.x86_64" 2>/dev/null | grep -q ELF || { echo "Linux export missing or not a real binary — check the double templates for $GODOT" >&2; exit 1; }

install -m755 "$root/build/linux/loop-slice.x86_64" "$bindst/loop-slice.x86_64";  say loop-slice.x86_64 ok
install -m644 "$root/build/linux/loop-slice.pck"     "$bindst/loop-slice.pck";     say loop-slice.pck ok

# server_host.txt is read at runtime by the client (after $LOOP_HOST); ship it so
# an admin can repoint a packaged client without re-exporting.
install -m644 "$root/server_host.txt" "$sharedst/server_host.txt";                 say server_host.txt ok

# ── Launch wrappers placed beside the binary ──────────────────────────────────
# Client: boots the main scene (main.tscn); OpenXR engages when a runtime is
# present, flatscreen otherwise — the same client the slice ships.
cat > "$bindst/loop-slice" <<EOF
#!/bin/sh
exec "/opt/org.v-sekai/loop-slice/$LOOP_VER/bin/loop-slice.x86_64" "\$@"
EOF
chmod 755 "$bindst/loop-slice"; say loop-slice ok

# Server: the headless authority — runs server.gd as the main loop, exactly as
# the README's flatscreen instructions do with the editor binary.
cat > "$bindst/loop-slice-server" <<EOF
#!/bin/sh
exec "/opt/org.v-sekai/loop-slice/$LOOP_VER/bin/loop-slice.x86_64" --headless --script res://server.gd "\$@"
EOF
chmod 755 "$bindst/loop-slice-server"; say loop-slice-server ok

# ── Desktop entry for the client (staged into /usr/share/applications) ────────
mkdir -p "$stage/usr/share/applications"
cat > "$stage/usr/share/applications/org.v-sekai.loop-slice.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Loot-Action Loop Slice
Comment=The instanced loot-action core-loop vertical slice
Exec=/usr/local/bin/loop-slice
Terminal=false
Categories=Game;
EOF
say loop-slice.desktop ok

echo "staged -> $stage"
find "$vendor" -maxdepth 4 -type d | sed "s|$stage||"
