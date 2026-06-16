# Tailscale Cellular VPS Runbook

Waypoint uses the iPhone app as a map-first controller and sends selected coordinates to a VPS over Tailscale. The VPS hosts the control API and transparent MITM spoofing path.

## Install runtime dependencies

From the deployed checkout on the VPS:

```bash
cd /opt/waypoint
sudo -u waypoint-mitm /opt/waypoint/.venv/bin/pip install mitmproxy cryptography qrcode
```

## Install waypoint-control.service

Create the state and runtime directories, then install the control API environment and service files:

```bash
sudo install -d -o waypoint-mitm -g waypoint-mitm /etc/waypoint /run/waypoint
sudo install -m 0640 -o waypoint-mitm -g waypoint-mitm deploy/waypoint-vps/waypoint-control.env.example /etc/waypoint/waypoint-control.env
sudo install -m 0644 deploy/waypoint-vps/waypoint-control.service /etc/systemd/system/waypoint-control.service
sudo systemctl daemon-reload
sudo systemctl enable waypoint-control.service
```

Edit `/etc/waypoint/waypoint-control.env` if the VPS Tailscale IP or port differs from `100.78.165.105:8765`.

## Start waypoint-control.service

```bash
sudo systemctl start waypoint-control.service
sudo systemctl status waypoint-control.service --no-pager --lines=20
curl -s http://100.78.165.105:8765/v1/health
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
