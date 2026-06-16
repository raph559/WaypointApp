#!/usr/bin/env bash
set -euo pipefail

CONTROL_ENV_FILE="${WAYPOINT_CONTROL_ENV_FILE:-/etc/waypoint/waypoint-control.env}"

_WAYPOINT_CONTROL_HOST_WAS_SET="${WAYPOINT_CONTROL_HOST+x}"
_WAYPOINT_CONTROL_HOST_OVERRIDE="${WAYPOINT_CONTROL_HOST-}"
_WAYPOINT_CONTROL_PORT_WAS_SET="${WAYPOINT_CONTROL_PORT+x}"
_WAYPOINT_CONTROL_PORT_OVERRIDE="${WAYPOINT_CONTROL_PORT-}"

if [[ -f "$CONTROL_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CONTROL_ENV_FILE"
fi

if [[ -n "$_WAYPOINT_CONTROL_HOST_WAS_SET" ]]; then
  WAYPOINT_CONTROL_HOST="$_WAYPOINT_CONTROL_HOST_OVERRIDE"
fi

if [[ -n "$_WAYPOINT_CONTROL_PORT_WAS_SET" ]]; then
  WAYPOINT_CONTROL_PORT="$_WAYPOINT_CONTROL_PORT_OVERRIDE"
fi

CONTROL_HOST="${WAYPOINT_CONTROL_HOST:-100.78.165.105}"
CONTROL_PORT="${WAYPOINT_CONTROL_PORT:-8765}"
CONTROL_HEALTH_URL="${WAYPOINT_CONTROL_HEALTH_URL:-http://${CONTROL_HOST}:${CONTROL_PORT}/v1/health}"

echo "== tailscaled =="
systemctl is-active --quiet tailscaled
systemctl status tailscaled --no-pager --lines=5

echo
echo "== tailscale0 =="
ip link show tailscale0

echo
echo "== IPv4 forwarding =="
sysctl net.ipv4.ip_forward

echo
echo "== NAT rules =="
iptables -t nat -S | grep WAYPOINT_GSLOC

echo
echo "== control API health =="
curl -s "$CONTROL_HEALTH_URL" || true

echo
echo "== waypoint-control =="
systemctl status waypoint-control.service --no-pager --lines=20

echo
echo "== waypoint-mitm =="
systemctl status waypoint-mitm.service --no-pager --lines=20

echo
echo "== recent control logs =="
journalctl -u waypoint-control.service -n 80 --no-pager

echo
echo "== recent mitm logs =="
journalctl -u waypoint-mitm.service -n 80 --no-pager
