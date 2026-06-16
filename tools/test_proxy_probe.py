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
