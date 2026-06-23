#!/usr/bin/env bash
# server_up_test.sh — actually turn the dedicated server ON and prove it listens.
# Runs the staged pck in the pinned runtime image with the SAME exec line the
# quadlet uses, then waits for server.gd's "LOOPSRV ready" log line.
#
# Needs podman and a pullable runtime image. When the image can't be pulled (no
# ghcr access, offline), it SKIPS by default so dev boxes / generic CI still pass.
# Set LOOP_REQUIRE_SERVER_UP=1 to turn a skip into a failure (use this in the
# project's own CI, which has packages:read for the org image).
#
# Overrides: LOOP_TEST_IMAGE (default: the quadlet's Image=), LOOP_TEST_PCK
# (default: the staged pck), LOOP_TEST_PORT (default: 54400, what server.gd binds),
# LOOP_TEST_TIMEOUT (default: 90s to allow a first-run image pull + boot).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
quadlet="$here/quadlet/loop-slice-server.container"

require="${LOOP_REQUIRE_SERVER_UP:-0}"
image="${LOOP_TEST_IMAGE:-$(grep -oE '^Image=.*' "$quadlet" | cut -d= -f2-)}"
pck="${LOOP_TEST_PCK:-$here/stage/opt/org.v-sekai/loop-slice/0.1/bin/loop-slice.pck}"
port="${LOOP_TEST_PORT:-54400}"
timeout_s="${LOOP_TEST_TIMEOUT:-90}"
name="loopsrv-test-$$"

skip() { printf 'SKIP: %s\n' "$1"; [ "$require" = 1 ] && { printf 'FAIL: LOOP_REQUIRE_SERVER_UP=1 forbids skipping\n'; exit 1; }; exit 0; }
cleanup() { podman rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

command -v podman >/dev/null 2>&1 || skip "podman not installed"
[ -s "$pck" ] || skip "staged pck not found at $pck (run: GODOT=... PCK_ONLY=1 ./stage.sh)"
[ -n "$image" ] || skip "no runtime image (set LOOP_TEST_IMAGE)"

echo "image: $image"
echo "pck:   $pck"
echo "port:  $port"

# Pull up front so a registry-auth failure is a clean skip, not a run failure.
if ! timeout 300 podman pull "$image" >/dev/null 2>&1; then
  skip "cannot pull $image (no ghcr access / offline)"
fi

# Boot the server with the quadlet's exact exec line, pck bind-mounted at /game.
podman run -d --name "$name" --rm \
  -v "$pck":/game/loop-slice.pck:ro,z \
  -p "$port:$port/udp" \
  -e LOOP_DB=/tmp/loop_profiles.db \
  "$image" \
  /usr/local/bin/godot --headless --main-pack /game/loop-slice.pck --script res://server.gd \
  >/dev/null 2>&1 || skip "podman run failed to start the container"

echo "waiting up to ${timeout_s}s for 'LOOPSRV ready'..."
deadline=$((SECONDS + timeout_s))
while [ "$SECONDS" -lt "$deadline" ]; do
  logs="$(podman logs "$name" 2>&1)"
  if printf '%s' "$logs" | grep -q 'LOOPSRV ready'; then
    line="$(printf '%s' "$logs" | grep 'LOOPSRV ready' | head -1)"
    echo "PASS: server is up — $line"
    # Confirm the container is still running (didn't crash right after listening).
    if podman inspect -f '{{.State.Running}}' "$name" 2>/dev/null | grep -q true; then
      echo "PASS: container still running"
      exit 0
    fi
    echo "FAIL: container exited right after listening"; exit 1
  fi
  if printf '%s' "$logs" | grep -q 'listen failed'; then
    echo "FAIL: server reported 'listen failed'"; printf '%s\n' "$logs" | tail -20; exit 1
  fi
  sleep 2
done

echo "FAIL: timed out waiting for the server to come up"
podman logs "$name" 2>&1 | tail -30
exit 1
