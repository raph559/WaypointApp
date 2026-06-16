#!/usr/bin/env bash
set -euo pipefail

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
curl -s http://100.78.165.105:8765/v1/health || true

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
