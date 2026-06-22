#!/bin/sh
# Undo what postinstall wired up.  The /opt tree itself is removed by the package
# manager (it owns those files); we only clean the PATH symlinks we added and
# stop the server unit.
set -e

# Only run on FINAL removal, not during an upgrade.  On rpm upgrade the old
# package's postremove runs AFTER the new postinstall, so unconditional cleanup
# would delete the symlinks/units the new package just created.
#   rpm postun: $1 = remaining instances (0 = final removal)
#   deb postrm: $1 = remove|purge|upgrade|deconfigure|...
case "${1:-}" in
  0|remove|purge) ;;   # final removal — proceed
  *) exit 0 ;;         # upgrade or other — leave everything in place
esac

# Stop and deregister the server unit (its unit file is removed by the package
# manager). Harmless if it was never enabled.
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now loop-slice-server.service || true
  systemctl daemon-reload || true
fi

for app in loop-slice loop-slice-server; do
  link="/usr/local/bin/${app}"
  [ -L "${link}" ] && rm -f "${link}"
done

exit 0
