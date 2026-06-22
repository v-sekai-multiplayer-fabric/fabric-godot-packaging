#!/usr/bin/env bash
# Pin the quadlet's runtime Image= to an immutable digest — :latest is blocklisted.
# Rewrites quadlet/loop-slice-server.container in place.
#
# Digest resolution order:
#   1. $RUNTIME_DIGEST            (sha256:...; explicit override / CI input)
#   2. skopeo inspect            (needs ghcr creds or packages:read; CI logs in first)
#   3. latest successful godot-images `build` run log  (repo scope only — the
#      build prints `pushing manifest for <img>:latest@sha256:<digest>`)
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
unit="$here/quadlet/loop-slice-server.container"
img=ghcr.io/v-sekai-multiplayer-fabric/zone-godot-runtime
images_repo=v-sekai-multiplayer-fabric/godot-images

digest="${RUNTIME_DIGEST:-}"

if [ -z "$digest" ] && command -v skopeo >/dev/null 2>&1; then
  digest=$(skopeo inspect --format '{{.Digest}}' "docker://${img}:latest" 2>/dev/null || true)
fi

if [ -z "$digest" ] && command -v gh >/dev/null 2>&1; then
  rid=$(gh run list -R "$images_repo" --workflow build.yml --status success --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  if [ -n "$rid" ]; then
    jid=$(gh run view -R "$images_repo" "$rid" --json jobs -q '.jobs[]|select(.name|test("runtime")).databaseId' 2>/dev/null | head -1 || true)
    [ -n "$jid" ] && digest=$(gh api "repos/$images_repo/actions/jobs/$jid/logs" 2>/dev/null \
      | grep -oE 'zone-godot-runtime[^ ]*@sha256:[0-9a-f]{64}' | grep -oE 'sha256:[0-9a-f]{64}' | head -1 || true)
  fi
fi

[ -n "$digest" ] || { echo "pin-runtime-digest: could not resolve a digest; set RUNTIME_DIGEST=sha256:..." >&2; exit 1; }
echo "$digest" | grep -qE '^sha256:[0-9a-f]{64}$' || { echo "pin-runtime-digest: bad digest '$digest'" >&2; exit 1; }

# Replace whatever Image= currently is (tag or digest) with the resolved digest.
sed -i -E "s#^Image=${img}([@:][^[:space:]]*)?\$#Image=${img}@${digest}#" "$unit"
grep -q "^Image=${img}@${digest}\$" "$unit" || { echo "pin-runtime-digest: failed to rewrite Image= in $unit" >&2; exit 1; }
echo "pin-runtime-digest: pinned ${img}@${digest}"
