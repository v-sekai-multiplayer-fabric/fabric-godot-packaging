#!/bin/sh
# Wire the relocatable /opt tree into the system: PATH symlinks + the server
# account/unit.  FHS §3.13: /opt apps own /opt/<vendor>/...; integration via
# symlinks.  The dedicated server is installed but NOT auto-enabled — hosting is
# an explicit choice (systemctl enable --now loop-slice-server).
set -e

LOOP_VER="0.1"
BIN="/opt/org.v-sekai/loop-slice/${LOOP_VER}/bin"

# Symlink the client + server launchers onto PATH.
for app in loop-slice loop-slice-server; do
  [ -x "${BIN}/${app}" ] && ln -sf "${BIN}/${app}" "/usr/local/bin/${app}"
done

# Create the unprivileged 'loop-slice' service account from sysusers.d.
if command -v systemd-sysusers >/dev/null 2>&1; then
  systemd-sysusers /usr/lib/sysusers.d/loop-slice-server.conf || true
fi

# Register the server unit (left disabled). daemon-reload picks up the new file.
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  echo "loop-slice: to host a server, run: systemctl enable --now loop-slice-server"
fi

exit 0
