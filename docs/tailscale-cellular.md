# Tailscale Cellular VPS Runbook

Waypoint uses the iPhone app as a map-first controller and sends selected coordinates to a VPS over Tailscale. The VPS hosts the control API and transparent MITM spoofing path.

## Install runtime dependencies

From the deployed checkout on the VPS:

```bash
cd /opt/waypoint
sudo -u waypoint-mitm /opt/waypoint/.venv/bin/pip install mitmproxy cryptography qrcode
```

## Install waypoint-control.service

Create the persistent state directory, then install the control API environment and service files:

```bash
sudo install -d -o waypoint-mitm -g waypoint-mitm /etc/waypoint
sudo install -m 0640 -o waypoint-mitm -g waypoint-mitm deploy/waypoint-vps/waypoint-control.env.example /etc/waypoint/waypoint-control.env
sudo install -m 0644 deploy/waypoint-vps/waypoint-control.service /etc/systemd/system/waypoint-control.service
sudo systemctl daemon-reload
sudo systemctl enable waypoint-control.service
```

Edit `/etc/waypoint/waypoint-control.env` if the VPS Tailscale IP or port differs from `100.78.165.105:8765`. The helper scripts source this file by default, and explicit environment variables still override it.

`/run/waypoint` is tmpfs and is managed by `waypoint-control.service` through systemd `RuntimeDirectory=waypoint`. Start `waypoint-control.service` before running `waypoint_pair.py` so the runtime directory exists with the right owner and permissions.

## Install waypoint-mitm.service and helpers

Install the spoofing environment, transparent MITM service, and operational helper scripts:

```bash
sudo install -m 0640 -o waypoint-mitm -g waypoint-mitm deploy/waypoint-vps/waypoint-spoof.env.example /etc/waypoint/waypoint-spoof.env
sudo install -m 0644 deploy/waypoint-vps/waypoint-mitm.service /etc/systemd/system/waypoint-mitm.service
sudo install -m 0755 deploy/waypoint-vps/waypoint-transparent-iptables.sh /usr/local/sbin/waypoint-transparent-iptables.sh
sudo install -m 0755 deploy/waypoint-vps/verify-vps.sh /usr/local/sbin/verify-vps.sh
sudo systemctl daemon-reload
sudo systemctl enable waypoint-mitm.service
```

Edit `/etc/waypoint/waypoint-spoof.env` if you want a different initial fallback coordinate. The control API writes `/etc/waypoint/target.json`, which is the live target consumed by the MITM service.

## Configure transparent routing

Run the iptables helper after Tailscale is up:

```bash
sudo /usr/local/sbin/waypoint-transparent-iptables.sh
```

The helper redirects HTTPS traffic from `tailscale0` to the local MITM port and allows the control API port only on the Tailscale interface. It reads `WAYPOINT_CONTROL_PORT` from `/etc/waypoint/waypoint-control.env` unless an environment override is supplied.

## Start waypoint-control.service

```bash
sudo systemctl start waypoint-control.service
sudo systemctl status waypoint-control.service --no-pager --lines=20
curl -s http://100.78.165.105:8765/v1/health
```

## Start waypoint-mitm.service

```bash
sudo systemctl start waypoint-mitm.service
sudo systemctl status waypoint-mitm.service --no-pager --lines=20
```

## Pair the app

Generate a pairing QR or token from the VPS:

```bash
sudo -u waypoint-mitm /opt/waypoint/.venv/bin/python /opt/waypoint/tools/waypoint_pair.py --runtime-dir /run/waypoint --server http://100.78.165.105:8765
```

Open Waypoint on the iPhone while connected to Tailscale, then use the app pairing flow to scan the QR code or enter the pairing token.

## Validate target updates

Pick a coordinate in the app and send it to the controller. On the VPS, validate that the control API wrote the target file:

```bash
cat /etc/waypoint/target.json
```

The JSON should contain the selected latitude and longitude. The MITM service reads this `target.json` file when spoofing Apple location responses.

## Verify the VPS

Run the bundled verification helper after the services are started:

```bash
sudo /usr/local/sbin/verify-vps.sh
```
