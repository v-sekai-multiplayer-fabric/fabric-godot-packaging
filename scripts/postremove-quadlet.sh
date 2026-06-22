#!/bin/sh
set -e
case "${1:-}" in 0|remove|purge) ;; *) exit 0 ;; esac
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now loop-slice-server.service 2>/dev/null || true
  systemctl daemon-reload || true
fi
exit 0
