#!/usr/bin/env bash
set -euo pipefail

TAILSCALE_IF="tailscale0"
MITM_PORT="8080"
API_PORT="8765"
CHAIN="WAYPOINT_GSLOC"

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
