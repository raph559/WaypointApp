# Wi-Fi Proxy Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small local/VPS proxy probe that confirms whether iOS location traffic goes through the manual Wi-Fi HTTP proxy setting.

**Architecture:** Add a standalone Python script that accepts HTTP proxy traffic, logs target hosts, and tunnels `CONNECT` traffic without decrypting it. This first stage only answers whether `gs-loc.apple.com` reaches the proxy; if it does, a later stage can adapt the existing Go WLOC rewrite logic into a standalone proxy.

**Tech Stack:** Python 3 standard library, `unittest`, TCP sockets, threads.

---

### Task 1: Proxy Request Parsing

**Files:**
- Create: `tools/proxy_probe.py`
- Create: `tools/test_proxy_probe.py`

- [ ] **Step 1: Write failing parser tests**

```python
import unittest

from tools.proxy_probe import parse_proxy_target


class ProxyProbeParsingTests(unittest.TestCase):
    def test_parses_connect_authority(self):
        request = b"CONNECT gs-loc.apple.com:443 HTTP/1.1\r\nHost: gs-loc.apple.com:443\r\n\r\n"
        self.assertEqual(parse_proxy_target(request), ("CONNECT", "gs-loc.apple.com", 443))

    def test_parses_absolute_form_http_url(self):
        request = b"GET http://mitm.it/ HTTP/1.1\r\nHost: mitm.it\r\n\r\n"
        self.assertEqual(parse_proxy_target(request), ("GET", "mitm.it", 80))

    def test_uses_host_header_for_origin_form(self):
        request = b"GET / HTTP/1.1\r\nHost: example.test:8080\r\n\r\n"
        self.assertEqual(parse_proxy_target(request), ("GET", "example.test", 8080))

    def test_rejects_malformed_request_line(self):
        self.assertIsNone(parse_proxy_target(b"broken\r\n\r\n"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests and verify RED**

Run: `python -m unittest tools.test_proxy_probe`
Expected: failure importing `tools.proxy_probe`.

- [ ] **Step 3: Implement parser**

Create `parse_proxy_target(data: bytes) -> tuple[str, str, int] | None` with support for `CONNECT host:port`, absolute-form `http://host[:port]/...`, and origin-form requests using the `Host` header.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `python -m unittest tools.test_proxy_probe`
Expected: all tests pass.

### Task 2: Logging Tunneling Proxy

**Files:**
- Modify: `tools/proxy_probe.py`
- Modify: `README.md`

- [ ] **Step 1: Add socket proxy implementation**

Implement a threaded proxy server with:

- `CONNECT` tunnel support.
- Plain HTTP forwarding for absolute-form/origin-form requests.
- host logging for every request.
- highlighted log line when target contains `gs-loc.apple.com`.
- bind host/port CLI args, defaulting to `0.0.0.0:8888`.

- [ ] **Step 2: Document the test**

Add README instructions:

1. Run `python tools/proxy_probe.py --host 0.0.0.0 --port 8888`.
2. Set iPhone Wi-Fi HTTP proxy to the computer/VPS IP and port `8888`.
3. Open Safari to verify browsing still works.
4. Trigger Maps/location.
5. Look for `gs-loc.apple.com` in logs.

- [ ] **Step 3: Verify**

Run: `python -m unittest tools.test_proxy_probe`
Expected: all tests pass.

Run: `python tools/proxy_probe.py --help`
Expected: CLI usage displays without starting the server.
