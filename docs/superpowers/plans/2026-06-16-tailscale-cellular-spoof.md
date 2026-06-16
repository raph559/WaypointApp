# Tailscale Cellular Spoof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the working Waypoint WLOC spoof from the laptop Wi-Fi proxy path to the VPS so the iPhone can spoof location on cellular through Tailscale without using a full exit node.

**Architecture:** The VPS becomes a Tailscale app connector for `gs-loc.apple.com` and `gs-loc-cn.apple.com`. Tailscale routes only those Apple location lookup domains to the VPS, the VPS transparently redirects routed HTTPS traffic into mitmproxy, and the existing `tools/mitm_location_probe.py` addon rewrites Apple WLOC responses.

**Tech Stack:** Tailscale App Connector, Linux systemd, iptables NAT, Python 3 virtualenv, mitmproxy transparent mode, existing Waypoint WLOC Python addon and `unittest` tests.

---

## References

- Tailscale App Connectors: https://tailscale.com/docs/features/app-connectors
- Tailscale App Connector setup: https://tailscale.com/docs/features/app-connectors/how-to/setup
- mitmproxy transparent mode: https://docs.mitmproxy.org/stable/howto/transparent/
- Design spec: `docs/superpowers/specs/2026-06-16-tailscale-cellular-spoof-design.md`

## Current Tailnet Context

- Laptop: `raph-laptop`, Tailscale IP `100.104.37.57`
- VPS: `vps`, Tailscale IP `100.78.165.105`
- iPhone: `iphone171`; reconnect Tailscale before cellular validation
- Existing trusted laptop mitmproxy CA path: `C:\Users\raphr\.mitmproxy`

## File Structure

- Create: `tools/test_vps_deploy_assets.py`
  - Validates that deploy assets stay narrow and keep the expected mitmproxy transparent configuration.
- Create: `deploy/waypoint-vps/waypoint-spoof.env.example`
  - Example environment file for the target spoof coordinate and Python unbuffered logs.
- Create: `deploy/waypoint-vps/waypoint-mitm.service`
  - systemd unit for running mitmdump in transparent mode on the VPS.
- Create: `deploy/waypoint-vps/waypoint-transparent-iptables.sh`
  - Idempotent IPv4 NAT setup for redirecting HTTPS traffic arriving from `tailscale0` into mitmproxy and blocking direct public access to the listener port.
- Create: `deploy/waypoint-vps/verify-vps.sh`
  - VPS diagnostic helper for tailscaled, route state, firewall state, and Waypoint service logs.
- Create: `docs/tailscale-cellular.md`
  - Copy-pasteable runbook for Tailscale policy, VPS install, CA copy, iPhone setup, validation, and rollback.
- No iOS app files change in this implementation.

### Task 1: Add Deploy Asset Tests

**Files:**
- Create: `tools/test_vps_deploy_assets.py`

- [ ] **Step 1: Write the failing tests**

Create `tools/test_vps_deploy_assets.py` with this content:

```python
from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
DEPLOY_DIR = REPO_ROOT / "deploy" / "waypoint-vps"


class VpsDeployAssetTests(unittest.TestCase):
    def test_env_example_contains_eiffel_tower_default(self):
        env_text = (DEPLOY_DIR / "waypoint-spoof.env.example").read_text(encoding="utf-8")

        self.assertIn("WAYPOINT_SPOOF_ENABLED=1", env_text)
        self.assertIn("WAYPOINT_SPOOF_LAT=48.858370", env_text)
        self.assertIn("WAYPOINT_SPOOF_LON=2.294481", env_text)
        self.assertIn("PYTHONUNBUFFERED=1", env_text)

    def test_systemd_service_runs_transparent_gsloc_only_mitmproxy(self):
        service = (DEPLOY_DIR / "waypoint-mitm.service").read_text(encoding="utf-8")

        self.assertIn("User=waypoint-mitm", service)
        self.assertIn("WorkingDirectory=/opt/waypoint", service)
        self.assertIn("Environment=HOME=/opt/waypoint", service)
        self.assertIn("EnvironmentFile=/etc/waypoint/waypoint-spoof.env", service)
        self.assertIn("--mode transparent", service)
        self.assertIn("--listen-port 8080", service)
        self.assertIn("--allow-hosts=^gs-loc(-cn)?[.]apple[.]com(:443)?$", service)
        self.assertIn("-s /opt/waypoint/tools/mitm_location_probe.py", service)
        self.assertNotIn("--listen-host 0.0.0.0", service)

    def test_iptables_script_redirects_only_tailscale_https_to_local_listener(self):
        script = (DEPLOY_DIR / "waypoint-transparent-iptables.sh").read_text(encoding="utf-8")

        self.assertIn("TAILSCALE_IF=\"tailscale0\"", script)
        self.assertIn("LISTEN_PORT=\"8080\"", script)
        self.assertIn("net.ipv4.ip_forward=1", script)
        self.assertIn("net.ipv4.conf.all.send_redirects=0", script)
        self.assertIn("-i \"$TAILSCALE_IF\" -p tcp --dport 443", script)
        self.assertIn("--to-ports \"$LISTEN_PORT\"", script)
        self.assertIn("-p tcp --dport \"$LISTEN_PORT\" -j DROP", script)
        self.assertNotIn("--dport 80", script)
        self.assertNotIn("OUTPUT", script)

    def test_verify_script_checks_expected_vps_state(self):
        script = (DEPLOY_DIR / "verify-vps.sh").read_text(encoding="utf-8")

        self.assertIn("systemctl is-active --quiet tailscaled", script)
        self.assertIn("ip link show tailscale0", script)
        self.assertIn("iptables -t nat -S", script)
        self.assertIn("journalctl -u waypoint-mitm.service", script)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
python -m unittest tools.test_vps_deploy_assets
```

Expected: `FAILED` because `deploy/waypoint-vps/waypoint-spoof.env.example` does not exist yet.

### Task 2: Add VPS Deploy Assets

**Files:**
- Create: `deploy/waypoint-vps/waypoint-spoof.env.example`
- Create: `deploy/waypoint-vps/waypoint-mitm.service`
- Create: `deploy/waypoint-vps/waypoint-transparent-iptables.sh`
- Create: `deploy/waypoint-vps/verify-vps.sh`

- [ ] **Step 1: Create the deploy directory**

Run:

```powershell
New-Item -ItemType Directory -Force deploy\waypoint-vps
```

Expected: `deploy\waypoint-vps` exists.

- [ ] **Step 2: Add the environment example**

Create `deploy/waypoint-vps/waypoint-spoof.env.example` with this content:

```env
WAYPOINT_SPOOF_ENABLED=1
WAYPOINT_SPOOF_LAT=48.858370
WAYPOINT_SPOOF_LON=2.294481
PYTHONUNBUFFERED=1
```

- [ ] **Step 3: Add the systemd service**

Create `deploy/waypoint-vps/waypoint-mitm.service` with this content:

```ini
[Unit]
Description=Waypoint gs-loc transparent MITM
After=network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=waypoint-mitm
Group=waypoint-mitm
WorkingDirectory=/opt/waypoint
EnvironmentFile=/etc/waypoint/waypoint-spoof.env
Environment=HOME=/opt/waypoint
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/waypoint/.venv/bin/mitmdump --mode transparent --listen-port 8080 --showhost --set block_global=false --set flow_detail=0 --allow-hosts=^gs-loc(-cn)?[.]apple[.]com(:443)?$ -s /opt/waypoint/tools/mitm_location_probe.py
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Add the transparent iptables setup script**

Create `deploy/waypoint-vps/waypoint-transparent-iptables.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

TAILSCALE_IF="tailscale0"
LISTEN_PORT="8080"
CHAIN="WAYPOINT_GSLOC"

if ! ip link show "$TAILSCALE_IF" >/dev/null 2>&1; then
  echo "Missing interface: $TAILSCALE_IF" >&2
  exit 1
fi

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.send_redirects=0

iptables -t nat -N "$CHAIN" 2>/dev/null || true
iptables -t nat -F "$CHAIN"
iptables -t nat -A "$CHAIN" -p tcp --dport 443 -j REDIRECT --to-ports "$LISTEN_PORT"

if ! iptables -t nat -C PREROUTING -i "$TAILSCALE_IF" -p tcp --dport 443 -j "$CHAIN" 2>/dev/null; then
  iptables -t nat -A PREROUTING -i "$TAILSCALE_IF" -p tcp --dport 443 -j "$CHAIN"
fi

if ! iptables -C INPUT -i "$TAILSCALE_IF" -p tcp --dport "$LISTEN_PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -i "$TAILSCALE_IF" -p tcp --dport "$LISTEN_PORT" -j ACCEPT
fi

if ! iptables -C INPUT -i lo -p tcp --dport "$LISTEN_PORT" -j ACCEPT 2>/dev/null; then
  iptables -I INPUT 1 -i lo -p tcp --dport "$LISTEN_PORT" -j ACCEPT
fi

if ! iptables -C INPUT -p tcp --dport "$LISTEN_PORT" -j DROP 2>/dev/null; then
  iptables -A INPUT -p tcp --dport "$LISTEN_PORT" -j DROP
fi

echo "Waypoint transparent redirect is active:"
iptables -t nat -S | grep "$CHAIN"
```

- [ ] **Step 5: Add the VPS verification helper**

Create `deploy/waypoint-vps/verify-vps.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "== tailscaled =="
systemctl is-active --quiet tailscaled
systemctl status tailscaled --no-pager --lines=5

echo
echo "== tailscale status =="
tailscale status

echo
echo "== tailscale0 =="
ip link show tailscale0

echo
echo "== IPv4 forwarding =="
sysctl net.ipv4.ip_forward

echo
echo "== Waypoint NAT rules =="
iptables -t nat -S | grep WAYPOINT_GSLOC

echo
echo "== waypoint-mitm service =="
systemctl status waypoint-mitm.service --no-pager --lines=20

echo
echo "== recent spoof logs =="
journalctl -u waypoint-mitm.service -n 80 --no-pager
```

- [ ] **Step 6: Run tests and verify GREEN**

Run:

```powershell
python -m unittest tools.test_vps_deploy_assets
```

Expected: `Ran 4 tests` and `OK`.

- [ ] **Step 7: Run the existing WLOC tests**

Run:

```powershell
python -m unittest tools.test_apple_wloc tools.test_proxy_probe tools.test_vps_deploy_assets
```

Expected: all tests pass.

- [ ] **Step 8: Commit deploy assets**

Run:

```powershell
git add tools/test_vps_deploy_assets.py deploy/waypoint-vps/waypoint-spoof.env.example deploy/waypoint-vps/waypoint-mitm.service deploy/waypoint-vps/waypoint-transparent-iptables.sh deploy/waypoint-vps/verify-vps.sh
git commit -m "Add VPS transparent spoof deploy assets"
```

Expected: commit succeeds with the test file and the four deploy files.

### Task 3: Add Cellular Tailscale Runbook

**Files:**
- Create: `docs/tailscale-cellular.md`

- [ ] **Step 1: Create the runbook**

Create `docs/tailscale-cellular.md` with this content:

````markdown
# Waypoint Cellular Spoofing With Tailscale

This runbook moves the working Waypoint WLOC spoof from the laptop Wi-Fi proxy to the VPS named `vps` on the tailnet. The goal is to spoof Apple CoreLocation lookups on cellular while keeping normal iPhone traffic direct through cellular.

## Target

- VPS Tailscale IP: `100.78.165.105`
- Tailscale app connector tag: `tag:waypoint-gsloc`
- App connector domains:
  - `gs-loc.apple.com`
  - `gs-loc-cn.apple.com`
- Transparent mitmproxy listener port: `8080`
- Default spoof coordinate: Eiffel Tower, `48.858370,2.294481`

## Tailnet Policy

Open the Tailscale admin console, go to Access controls, and merge these sections into the existing policy:

```json
{
  "tagOwners": {
    "tag:waypoint-gsloc": []
  },
  "autoApprovers": {
    "routes": {
      "0.0.0.0/0": ["tag:waypoint-gsloc"],
      "::/0": ["tag:waypoint-gsloc"]
    }
  },
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["autogroup:internet"],
      "ip": ["*"]
    },
    {
      "src": ["autogroup:member"],
      "dst": ["tag:waypoint-gsloc"],
      "ip": ["tcp:53", "udp:53"]
    }
  ],
  "nodeAttrs": [
    {
      "target": ["*"],
      "app": {
        "tailscale.com/app-connectors": [
          {
            "name": "Waypoint gs-loc",
            "connectors": ["tag:waypoint-gsloc"],
            "domains": [
              "gs-loc.apple.com",
              "gs-loc-cn.apple.com"
            ]
          }
        ]
      }
    }
  ]
}
```

The `autoApprovers` entry follows Tailscale's custom app connector guidance. It permits this tag to auto-approve discovered app connector routes; it does not make the iPhone use the VPS as an exit node by itself.

## Configure The VPS As An App Connector

SSH to the VPS and run:

```bash
sudo tailscale up --advertise-connector --advertise-tags=tag:waypoint-gsloc
sudo sysctl -w net.ipv4.ip_forward=1
```

Expected:

```text
Success.
net.ipv4.ip_forward = 1
```

Open the Tailscale Apps admin page and add a custom app:

- Name: `Waypoint gs-loc`
- Target: `Custom`
- Domains: `gs-loc.apple.com, gs-loc-cn.apple.com`
- Connectors: `tag:waypoint-gsloc`

The app connector should show a green active indicator after the VPS is configured and the policy is saved.

## Install Waypoint On The VPS

On the VPS:

```bash
sudo apt update
sudo apt install -y git python3-venv python3-pip iptables
id -u waypoint-mitm >/dev/null 2>&1 || sudo adduser --system --group --home /opt/waypoint waypoint-mitm
sudo install -d -m 755 -o waypoint-mitm -g waypoint-mitm /opt/waypoint /etc/waypoint
```

From the laptop PowerShell, upload the exact committed source tree without needing GitHub credentials on the VPS:

```powershell
$env:WAYPOINT_VPS_SSH = "root@100.78.165.105"
git archive --format=tar --output waypoint-vps.tar HEAD
scp waypoint-vps.tar "${env:WAYPOINT_VPS_SSH}:/tmp/waypoint-vps.tar"
ssh $env:WAYPOINT_VPS_SSH "sudo rm -rf /opt/waypoint.new /opt/waypoint.old; sudo install -d -m 755 -o waypoint-mitm -g waypoint-mitm /opt/waypoint.new; sudo -u waypoint-mitm tar -xf /tmp/waypoint-vps.tar -C /opt/waypoint.new; if [ -d /opt/waypoint/.mitmproxy ]; then sudo cp -a /opt/waypoint/.mitmproxy /opt/waypoint.new/.mitmproxy; fi; if [ -d /opt/waypoint ]; then sudo mv /opt/waypoint /opt/waypoint.old; fi; sudo mv /opt/waypoint.new /opt/waypoint; sudo chown -R waypoint-mitm:waypoint-mitm /opt/waypoint"
Remove-Item waypoint-vps.tar
```

On the VPS:

```bash
cd /opt/waypoint
sudo -u waypoint-mitm python3 -m venv .venv
sudo -u waypoint-mitm .venv/bin/python -m pip install --upgrade pip
sudo -u waypoint-mitm .venv/bin/python -m pip install mitmproxy
sudo -u waypoint-mitm .venv/bin/python -m unittest tools.test_apple_wloc tools.test_proxy_probe
sudo install -m 600 -o root -g root deploy/waypoint-vps/waypoint-spoof.env.example /etc/waypoint/waypoint-spoof.env
sudo install -m 644 -o root -g root deploy/waypoint-vps/waypoint-mitm.service /etc/systemd/system/waypoint-mitm.service
sudo install -m 755 -o root -g root deploy/waypoint-vps/waypoint-transparent-iptables.sh /usr/local/sbin/waypoint-transparent-iptables
sudo install -m 755 -o root -g root deploy/waypoint-vps/verify-vps.sh /usr/local/sbin/waypoint-verify-vps
```

## Copy The Existing mitmproxy CA

From the laptop PowerShell:

```powershell
$env:WAYPOINT_VPS_SSH = "root@100.78.165.105"
scp C:\Users\raphr\.mitmproxy\mitmproxy-ca.pem "${env:WAYPOINT_VPS_SSH}:/tmp/mitmproxy-ca.pem"
scp C:\Users\raphr\.mitmproxy\mitmproxy-ca-cert.pem "${env:WAYPOINT_VPS_SSH}:/tmp/mitmproxy-ca-cert.pem"
```

On the VPS:

```bash
sudo install -d -m 700 -o waypoint-mitm -g waypoint-mitm /opt/waypoint/.mitmproxy
sudo install -m 600 -o waypoint-mitm -g waypoint-mitm /tmp/mitmproxy-ca.pem /opt/waypoint/.mitmproxy/mitmproxy-ca.pem
sudo install -m 644 -o waypoint-mitm -g waypoint-mitm /tmp/mitmproxy-ca-cert.pem /opt/waypoint/.mitmproxy/mitmproxy-ca-cert.pem
```

This keeps using the CA the iPhone already trusts.

## Start The Transparent Proxy

On the VPS:

```bash
sudo waypoint-transparent-iptables
sudo systemctl daemon-reload
sudo systemctl enable --now waypoint-mitm.service
sudo waypoint-verify-vps
```

Expected:

- `net.ipv4.ip_forward = 1`
- `WAYPOINT_GSLOC` appears in `iptables -t nat -S`
- `waypoint-mitm.service` is `active (running)`

## iPhone Setup

1. Turn Wi-Fi off.
2. Open Tailscale on the iPhone.
3. Connect to the tailnet.
4. Do not select the VPS as an exit node.
5. Confirm iPhone Location Services precise location is enabled for Maps.

## Validate

On the VPS, watch logs:

```bash
sudo journalctl -u waypoint-mitm.service -f
```

On the iPhone:

1. Open Safari to `https://ifconfig.me`.
2. Confirm the shown public IP is not the VPS public IP.
3. Open Maps.
4. Press the location arrow.
5. Open Compass if Maps does not refresh quickly.

Expected VPS log:

```text
SPOOFED WLOC RESPONSE https://gs-loc.apple.com/clls/wloc
```

Expected iPhone behavior:

- Maps places the phone at the Eiffel Tower.
- Safari still browses normally.
- Snapchat and TikTok still load content because their traffic is not routed into mitmproxy.

## Roll Back

On the VPS:

```bash
sudo systemctl disable --now waypoint-mitm.service
sudo iptables -t nat -D PREROUTING -i tailscale0 -p tcp --dport 443 -j WAYPOINT_GSLOC 2>/dev/null || true
sudo iptables -t nat -F WAYPOINT_GSLOC 2>/dev/null || true
sudo iptables -t nat -X WAYPOINT_GSLOC 2>/dev/null || true
sudo iptables -D INPUT -i tailscale0 -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -i lo -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -p tcp --dport 8080 -j DROP 2>/dev/null || true
```

In the Tailscale admin console, remove the `Waypoint gs-loc` custom app.

## Stop Conditions

Stop and collect evidence before changing architecture if:

- The app connector never shows active.
- `journalctl` shows no `gs-loc` traffic after multiple Maps refreshes on cellular.
- `journalctl` shows unrelated hosts being intercepted.
- Safari's public IP becomes the VPS public IP, which means a full exit-node path is active.
- iPhone uses IPv6 for `gs-loc` and the IPv4 redirect never sees the traffic.
````

- [ ] **Step 2: Run documentation smoke checks**

Run:

```powershell
Select-String -Path docs\tailscale-cellular.md -Pattern 'gs-loc.apple.com','tag:waypoint-gsloc','waypoint-mitm.service','WAYPOINT_GSLOC' -SimpleMatch
```

Expected: each pattern is found at least once.

- [ ] **Step 3: Commit the runbook**

Run:

```powershell
git add docs/tailscale-cellular.md
git commit -m "Document Tailscale cellular spoof setup"
```

Expected: commit succeeds with only `docs/tailscale-cellular.md`.

### Task 4: Push Repo Changes

**Files:**
- No file changes.

- [ ] **Step 1: Run full local verification**

Run:

```powershell
python -m unittest tools.test_apple_wloc tools.test_proxy_probe tools.test_vps_deploy_assets
git status --short
```

Expected:

```text
OK
```

and no uncommitted files except ignored runtime logs.

- [ ] **Step 2: Push to GitHub**

Run:

```powershell
git push
```

Expected: `main -> main`.

### Task 5: Configure The VPS

**Files:**
- No repo file changes.

- [ ] **Step 1: Confirm SSH access**

Run from laptop PowerShell:

```powershell
$env:WAYPOINT_VPS_SSH = "root@100.78.165.105"
ssh $env:WAYPOINT_VPS_SSH "hostname; tailscale status | head -n 5"
```

Expected: the command prints the VPS hostname and includes the laptop/iPhone/VPS tailnet devices. If root login is refused, set `WAYPOINT_VPS_SSH` to the working SSH user and rerun the same command.

- [ ] **Step 2: Install base packages and prepare user**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "sudo apt update && sudo apt install -y git python3-venv python3-pip iptables && (id -u waypoint-mitm >/dev/null 2>&1 || sudo adduser --system --group --home /opt/waypoint waypoint-mitm) && sudo install -d -m 755 -o waypoint-mitm -g waypoint-mitm /opt/waypoint /etc/waypoint"
```

Expected: packages are installed and `waypoint-mitm` exists.

- [ ] **Step 3: Upload the current Waypoint source tree**

Run:

```powershell
git archive --format=tar --output waypoint-vps.tar HEAD
scp waypoint-vps.tar "${env:WAYPOINT_VPS_SSH}:/tmp/waypoint-vps.tar"
ssh $env:WAYPOINT_VPS_SSH "sudo rm -rf /opt/waypoint.new /opt/waypoint.old; sudo install -d -m 755 -o waypoint-mitm -g waypoint-mitm /opt/waypoint.new; sudo -u waypoint-mitm tar -xf /tmp/waypoint-vps.tar -C /opt/waypoint.new; if [ -d /opt/waypoint/.mitmproxy ]; then sudo cp -a /opt/waypoint/.mitmproxy /opt/waypoint.new/.mitmproxy; fi; if [ -d /opt/waypoint ]; then sudo mv /opt/waypoint /opt/waypoint.old; fi; sudo mv /opt/waypoint.new /opt/waypoint; sudo chown -R waypoint-mitm:waypoint-mitm /opt/waypoint"
Remove-Item waypoint-vps.tar
```

Expected: `/opt/waypoint` contains the current local `HEAD` source and does not require GitHub credentials on the VPS.

- [ ] **Step 4: Install Python dependencies**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "cd /opt/waypoint && sudo -u waypoint-mitm python3 -m venv .venv && sudo -u waypoint-mitm .venv/bin/python -m pip install --upgrade pip && sudo -u waypoint-mitm .venv/bin/python -m pip install mitmproxy"
```

Expected: mitmproxy installs in `/opt/waypoint/.venv`.

- [ ] **Step 5: Run VPS repo tests**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "cd /opt/waypoint && sudo -u waypoint-mitm .venv/bin/python -m unittest tools.test_apple_wloc tools.test_proxy_probe tools.test_vps_deploy_assets"
```

Expected: all tests pass.

- [ ] **Step 6: Copy the existing mitmproxy CA to the VPS**

Run:

```powershell
scp C:\Users\raphr\.mitmproxy\mitmproxy-ca.pem "${env:WAYPOINT_VPS_SSH}:/tmp/mitmproxy-ca.pem"
scp C:\Users\raphr\.mitmproxy\mitmproxy-ca-cert.pem "${env:WAYPOINT_VPS_SSH}:/tmp/mitmproxy-ca-cert.pem"
ssh $env:WAYPOINT_VPS_SSH "sudo install -d -m 700 -o waypoint-mitm -g waypoint-mitm /opt/waypoint/.mitmproxy && sudo install -m 600 -o waypoint-mitm -g waypoint-mitm /tmp/mitmproxy-ca.pem /opt/waypoint/.mitmproxy/mitmproxy-ca.pem && sudo install -m 644 -o waypoint-mitm -g waypoint-mitm /tmp/mitmproxy-ca-cert.pem /opt/waypoint/.mitmproxy/mitmproxy-ca-cert.pem"
```

Expected: CA files exist in `/opt/waypoint/.mitmproxy`.

- [ ] **Step 7: Install service and firewall helpers**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "cd /opt/waypoint && sudo install -m 600 -o root -g root deploy/waypoint-vps/waypoint-spoof.env.example /etc/waypoint/waypoint-spoof.env && sudo install -m 644 -o root -g root deploy/waypoint-vps/waypoint-mitm.service /etc/systemd/system/waypoint-mitm.service && sudo install -m 755 -o root -g root deploy/waypoint-vps/waypoint-transparent-iptables.sh /usr/local/sbin/waypoint-transparent-iptables && sudo install -m 755 -o root -g root deploy/waypoint-vps/verify-vps.sh /usr/local/sbin/waypoint-verify-vps"
```

Expected: four install commands succeed.

### Task 6: Configure Tailscale App Connector

**Files:**
- No repo file changes.

- [ ] **Step 1: Save the tailnet policy**

Open https://login.tailscale.com/admin/acls and merge the JSON sections from `docs/tailscale-cellular.md`.

Expected: Tailscale policy editor saves without errors.

- [ ] **Step 2: Advertise the VPS as connector**

Run from laptop PowerShell:

```powershell
ssh $env:WAYPOINT_VPS_SSH "sudo tailscale up --advertise-connector --advertise-tags=tag:waypoint-gsloc && sudo sysctl -w net.ipv4.ip_forward=1"
```

Expected: command succeeds and prints `net.ipv4.ip_forward = 1`.

- [ ] **Step 3: Add custom app in Tailscale Apps**

Open https://login.tailscale.com/admin/apps and create:

```text
Name: Waypoint gs-loc
Target: Custom
Domains: gs-loc.apple.com, gs-loc-cn.apple.com
Connectors: tag:waypoint-gsloc
```

Expected: the app connector entry shows active/green.

- [ ] **Step 4: Start Waypoint transparent proxy**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "sudo waypoint-transparent-iptables && sudo systemctl daemon-reload && sudo systemctl enable --now waypoint-mitm.service && sudo waypoint-verify-vps"
```

Expected: `waypoint-mitm.service` is active and `WAYPOINT_GSLOC` appears in the NAT rules.

### Task 7: Cellular Validation

**Files:**
- No repo file changes.

- [ ] **Step 1: Start live logs**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "sudo journalctl -u waypoint-mitm.service -f"
```

Expected: live log stream opens and waits.

- [ ] **Step 2: Confirm iPhone route state**

On the iPhone:

1. Turn Wi-Fi off.
2. Open Tailscale.
3. Connect to the tailnet.
4. Confirm no exit node is selected.

Expected: Tailscale is connected on cellular only.

- [ ] **Step 3: Confirm non-location traffic stays direct**

On the iPhone open Safari to:

```text
https://ifconfig.me
```

Expected: public IP is the cellular carrier IP, not the VPS public IP.

- [ ] **Step 4: Trigger CoreLocation**

On the iPhone:

1. Open Maps.
2. Tap the current-location arrow.
3. Open Compass if Maps does not refresh within 30 seconds.

Expected VPS log contains:

```text
SPOOFED WLOC RESPONSE https://gs-loc.apple.com/clls/wloc
```

- [ ] **Step 5: Confirm app behavior**

On the iPhone:

1. Confirm Maps places the phone at the Eiffel Tower.
2. Search in Safari.
3. Load TikTok feed.
4. Load Snapchat messages.

Expected: Maps location is spoofed and the other apps still load network content.

### Task 8: Rollback Or Fallback Decision

**Files:**
- No repo file changes unless fallback is approved.

- [ ] **Step 1: Roll back if unrelated traffic is intercepted**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "sudo systemctl disable --now waypoint-mitm.service; sudo iptables -t nat -D PREROUTING -i tailscale0 -p tcp --dport 443 -j WAYPOINT_GSLOC 2>/dev/null || true; sudo iptables -t nat -F WAYPOINT_GSLOC 2>/dev/null || true; sudo iptables -t nat -X WAYPOINT_GSLOC 2>/dev/null || true; sudo iptables -D INPUT -i tailscale0 -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true; sudo iptables -D INPUT -i lo -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true; sudo iptables -D INPUT -p tcp --dport 8080 -j DROP 2>/dev/null || true"
```

Expected: service stops, NAT chain is removed, and listener-port INPUT guard rules are removed.

- [ ] **Step 2: Collect evidence before changing design**

Run:

```powershell
ssh $env:WAYPOINT_VPS_SSH "sudo journalctl -u waypoint-mitm.service -n 200 --no-pager; ip route; sudo iptables -t nat -S; tailscale status"
```

Expected: output shows whether the app connector routed `gs-loc`, whether the firewall redirected it, and whether unrelated hosts appeared.

- [ ] **Step 3: Stop for user approval if fallback is needed**

Report the evidence and ask before implementing manual subnet routes or exit-node mode.
