#!/usr/bin/env bash
# packaging_test.sh — fast, dependency-light checks on the packaging recipe.
# Guards the regressions fixed alongside the quadlet leg; no GODOT/engine build,
# no network. Run from anywhere: ./test/packaging_test.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
quadlet="$here/quadlet/loop-slice-server.container"
nfpm="$here/nfpm.yaml"
nfpm_q="$here/nfpm-quadlet.yaml"

pass=0 fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
# check <description> <command...> — passes if the command succeeds.
check()    { if "${@:2}" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
# refute <description> <command...> — passes if the command FAILS.
refute()   { if "${@:2}" >/dev/null 2>&1; then bad "$1"; else ok "$1"; fi; }

echo "quadlet/loop-slice-server.container"
# EnvironmentFile must be an absolute path with no leading '-'. Quadlet's key is
# not systemd's, so a '-' prefix becomes a relative path and breaks --env-file.
check  "EnvironmentFile is absolute"            grep -Eq '^EnvironmentFile=/'                 "$quadlet"
refute "EnvironmentFile has no systemd '-' marker" grep -Eq '^EnvironmentFile=-'              "$quadlet"
# Runtime image must be digest-pinned; :latest is blocklisted.
check  "Image is digest-pinned (@sha256:)"      grep -Eq '^Image=[^[:space:]]+@sha256:[0-9a-f]{64}$' "$quadlet"
refute "Image is not :latest"                   grep -Eq '^Image=[^[:space:]]+:latest$'       "$quadlet"
# The bind mount and --main-pack must agree on where the pck lands.
check  "pck bind mount -> /game"                grep -Eq '^Volume=/usr/share/loop-slice:/game:ro,z$' "$quadlet"
check  "Exec reads /game/loop-slice.pck"        grep -q -- '--main-pack /game/loop-slice.pck' "$quadlet"
# Must launch the authority script, not the client main scene. --main-pack alone
# boots res://main.tscn (the client); the server is server.gd via --script.
check  "Exec runs server.gd via --script"       grep -q -- '--script res://server.gd' "$quadlet"
refute "Exec has no bare --server flag"         grep -Eq -- '(^|[[:space:]])--server([[:space:]]|$)' "$quadlet"
# Published port must match LOOP_PORT (server.gd binds LOOP_PORT, default 54400);
# a quadlet can't read the env at generate time, so the two are kept in lockstep.
check  "PublishPort matches bound port 54400"   grep -Eq '^PublishPort=54400:54400/udp$' "$quadlet"
check  "Environment LOOP_PORT matches PublishPort" grep -Eq '^Environment=LOOP_PORT=54400$' "$quadlet"

echo "mutual Conflicts: (native vs quadlet)"
check  "nfpm.yaml conflicts with quadlet pkg"   grep -q 'v-sekai-loop-slice-server-quadlet'   "$nfpm"
check  "nfpm-quadlet.yaml conflicts with native" grep -Eq '^[[:space:]]+- v-sekai-loop-slice$' "$nfpm_q"

# Bonus: if podman's quadlet generator is present, prove the unit actually
# generates with the corrected --env-file (catches the original bug end-to-end).
gen="$(command -v /usr/libexec/podman/quadlet 2>/dev/null || true)"
[ -x "$gen" ] || gen="$(command -v quadlet 2>/dev/null || true)"
if [ -n "$gen" ]; then
  echo "podman quadlet generator dry-run"
  out="$(QUADLET_UNIT_DIRS="$here/quadlet" "$gen" --dryrun 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q -- '--env-file /etc/default/loop-slice-server'; then
    ok "generated unit uses --env-file /etc/default/loop-slice-server"
  else
    bad "generated unit missing correct --env-file"
  fi
  if printf '%s' "$out" | grep -Eq -- '--env-file [^ ]*/-/'; then
    bad "generated unit has broken relative --env-file path"
  else
    ok "generated unit has no broken relative --env-file path"
  fi
else
  echo "podman quadlet generator not found — skipping dry-run check"
fi

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
