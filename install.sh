#!/usr/bin/env bash
# Installs social-block system-wide.
#   sudo ./install.sh                                  asks for your hours
#   sudo ./install.sh --from 22:00 --until 06:00 --days weekdays
#   sudo ./install.sh --no-prompt                      22:00-06:00 daily
# Re-running it upgrades the code and keeps your existing config.
set -euo pipefail

BIN=/usr/local/bin/social-block
UNIT=/etc/systemd/system/social-block.service
CONF_DIR=/etc/social-block
CONF=$CONF_DIR/config
STATE=/var/lib/social-block
ORIG=/etc/hosts.social-block-orig

from='' until='' days='' prompt=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --from)      from=$2;  shift 2 ;;
    --until)     until=$2; shift 2 ;;
    --days)      days=$2;  shift 2 ;;
    --no-prompt) prompt=0; shift ;;
    -h|--help)   sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown argument \"$1\" (try --help)" >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "install.sh: run me with sudo" >&2; exit 1; }
[[ -d /run/systemd/system ]] || { echo "install.sh: this needs systemd (no /run/systemd/system)" >&2; exit 1; }
date --version 2>/dev/null | grep -q GNU || { echo "install.sh: this needs GNU date (coreutils)" >&2; exit 1; }
cd "$(dirname "$(readlink -f "$0")")"

install -Dm755 bin/social-block "$BIN"
install -Dm644 systemd/social-block.service "$UNIT"
install -d -m755 "$STATE"

# Validates one "START-END DAYS" line the way the tool itself will.
valid_schedule() {
  local tmp rc=0
  tmp=$(mktemp)
  printf '[schedule]\n%s\n' "$1" > "$tmp"
  "$BIN" check "$tmp" >/dev/null 2>&1 || rc=$?
  # The tool names the file and line in its errors; neither means anything here.
  if (( rc != 0 )); then "$BIN" check "$tmp" 2>&1 | sed "s|^${tmp##*/}:[0-9]*: |  |" || true; fi
  rm -f "$tmp"
  return "$rc"
}

# The config is the user's once it exists; re-running the installer upgrades
# the code and leaves it alone.
if [[ -f $CONF ]]; then
  echo "keeping existing $CONF"
else
  if [[ -z $from$until$days && $prompt -eq 1 && -t 0 ]]; then
    echo "When should the block be active? (24-hour clock; Enter keeps the default)"
    while :; do
      read -rp "  Block from  [22:00]: " from;  from=${from:-22:00}
      read -rp "  Block until [06:00]: " until; until=${until:-06:00}
      read -rp "  Days [daily]  (daily, weekdays, weekends, mon-fri, sat,sun): " days; days=${days:-daily}
      valid_schedule "$from-$until $days" && break
      echo "  let's try that again"
    done
  fi
  from=${from:-22:00} until=${until:-06:00} days=${days:-daily}
  line="$from-$until $days"
  valid_schedule "$line" || { echo "install.sh: \"$line\" is not a valid schedule" >&2; exit 1; }
  install -d -m755 "$CONF_DIR"
  # config.example is the template; its one live schedule line becomes yours.
  sed "s|^22:00-06:00 daily\$|$line|" config.example > "$CONF"
  chmod 644 "$CONF"
  echo "wrote $CONF"
fi

# One pristine copy of /etc/hosts, taken once, never overwritten.
[[ -e $ORIG ]] || cp -a /etc/hosts "$ORIG"

systemctl daemon-reload
systemctl enable --now social-block.service

echo
"$BIN" status
cat <<'MSG'

If your browser uses DNS-over-HTTPS ("secure DNS") it never reads /etc/hosts
and this block does nothing there. Check with:  social-block doctor
MSG
