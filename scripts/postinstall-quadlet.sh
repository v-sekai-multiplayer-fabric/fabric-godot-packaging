#!/bin/sh
# A quadlet under /usr/share/containers/systemd/ becomes a .service via the
# generator on daemon-reload. Not auto-started — hosting is an explicit choice.
set -e
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  echo "loop-slice: to host the server, run: systemctl enable --now loop-slice-server"
fi
exit 0
