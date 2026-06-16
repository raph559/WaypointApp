#!/usr/bin/env bash
set -euo pipefail

CONTROL_ENV_FILE="${WAYPOINT_CONTROL_ENV_FILE:-/etc/waypoint/waypoint-control.env}"

_WAYPOINT_CONTROL_PORT_WAS_SET="${WAYPOINT_CONTROL_PORT+x}"
_WAYPOINT_CONTROL_PORT_OVERRIDE="${WAYPOINT_CONTROL_PORT-}"

if [[ -f "$CONTROL_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$CONTROL_ENV_FILE"
fi

if [[ -n "$_WAYPOINT_CONTROL_PORT_WAS_SET" ]]; then
  WAYPOINT_CONTROL_PORT="$_WAYPOINT_CONTROL_PORT_OVERRIDE"
fi

TAILSCALE_IF="${TAILSCALE_IF:-tailscale0}"
MITM_PORT="${MITM_PORT:-8080}"
API_PORT="${API_PORT:-${WAYPOINT_CONTROL_PORT:-8765}}"
CHAIN="${CHAIN:-WAYPOINT_GSLOC}"

if ! ip link show "$TAILSCALE_IF" >/dev/null 2>&1; then
  echo "Missing interface: $TAILSCALE_IF" >&2
  exit 1
fi

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.send_redirects=0

iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"
iptables -t nat -A "$CHAIN" -p tcp --dport 443 -j REDIRECT --to-ports "$MITM_PORT"

if ! iptables -t nat -C PREROUTING -i "$TAILSCALE_IF" -p tcp --dport 443 -j "$CHAIN" 2>/dev/null; then
  iptables -t nat -A PREROUTING -i "$TAILSCALE_IF" -p tcp --dport 443 -j "$CHAIN"
fi

if ! iptables -C INPUT -i "$TAILSCALE_IF" -p tcp --dport "$MITM_PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -i "$TAILSCALE_IF" -p tcp --dport "$MITM_PORT" -j ACCEPT
fi

if ! iptables -C INPUT -i "$TAILSCALE_IF" -p tcp --dport "$API_PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -i "$TAILSCALE_IF" -p tcp --dport "$API_PORT" -j ACCEPT
fi

if ! iptables -C INPUT -p tcp --dport "$MITM_PORT" -j DROP 2>/dev/null; then
  iptables -A INPUT -p tcp --dport "$MITM_PORT" -j DROP
fi

if ! iptables -C INPUT -p tcp --dport "$API_PORT" -j DROP 2>/dev/null; then
  iptables -A INPUT -p tcp --dport "$API_PORT" -j DROP
fi

iptables -t nat -S | grep "$CHAIN"
