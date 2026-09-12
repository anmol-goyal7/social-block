#!/usr/bin/env bash
# Removes social-block.
#   sudo ./uninstall.sh            keeps /etc/social-block/config
#   sudo ./uninstall.sh --purge    removes the config too
set -euo pipefail

purge=0
case ${1:-} in
  '') ;;
  --purge) purge=1 ;;
  *) echo "uninstall.sh: unknown argument \"$1\"" >&2; exit 2 ;;
esac
[[ $EUID -eq 0 ]] || { echo "uninstall.sh: run me with sudo" >&2; exit 1; }

systemctl disable --now social-block.service 2>/dev/null || true

# "off" honours lock: during a locked window it refuses, and so does this.
if [[ -x /usr/local/bin/social-block ]] && [[ -f /etc/social-block/config ]]; then
  if ! /usr/local/bin/social-block off >/dev/null; then
    echo "uninstall.sh: the block is locked right now — wait for the window to end (or see the README's escape hatch), then run me again" >&2
    systemctl enable --now social-block.service 2>/dev/null || true
    exit 3
  fi
fi

rm -f /usr/local/bin/social-block /etc/systemd/system/social-block.service
systemctl daemon-reload
rm -rf /var/lib/social-block
if (( purge )); then rm -rf /etc/social-block; fi

echo "social-block removed. /etc/hosts.social-block-orig was left in place."
if (( ! purge )); then echo "config kept at /etc/social-block/config (use --purge to remove it)"; fi
