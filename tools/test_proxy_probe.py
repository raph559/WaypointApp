import unittest

from tools.apple_wloc import (
    WLOC_RESPONSE_PREFIX,
    encode_length_delimited_field,
    encode_location,
    extract_wifi_locations_from_response_body,
)
from tools.mitm_location_probe import (
    is_location_candidate_host,
    rewrite_wloc_response_if_configured,
    should_dump_body,
)
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


class MitmLocationProbeTests(unittest.TestCase):
    def test_marks_legacy_wloc_hosts(self):
        self.assertTrue(is_location_candidate_host("gs-loc.apple.com"))
        self.assertTrue(is_location_candidate_host("gs-loc-cn.apple.com"))

    def test_marks_maps_location_service_hosts_seen_from_ios(self):
        self.assertTrue(is_location_candidate_host("gsp-ssl.ls.apple.com"))
        self.assertTrue(is_location_candidate_host("gspe19-ssl.ls.apple.com"))
        self.assertTrue(is_location_candidate_host("gspe19-2-ssl.ls.apple.com"))
        self.assertTrue(is_location_candidate_host("gsp64-ssl.ls.apple.com"))
        self.assertTrue(is_location_candidate_host("gsp10-ssl.apple.com"))

    def test_marks_mapkit_and_wps_hosts(self):
        self.assertTrue(is_location_candidate_host("cdn.apple-mapkit.com"))
        self.assertTrue(is_location_candidate_host("wps.apple.com"))
        self.assertTrue(is_location_candidate_host("iphone-ld.apple.com"))

    def test_ignores_unrelated_hosts(self):
        self.assertFalse(is_location_candidate_host("example.com"))
        self.assertFalse(is_location_candidate_host("gateway.icloud.com"))
        self.assertFalse(is_location_candidate_host("api-safari-aeus2b.smoot.apple.com"))

    def test_dumps_small_location_post_bodies(self):
        self.assertTrue(should_dump_body("gsp-ssl.ls.apple.com", "POST", "/dispatcher.arpc", 993))
        self.assertTrue(should_dump_body("gs-loc.apple.com", "POST", "/clls/wloc", 1200))
        self.assertTrue(should_dump_body("gsp64-ssl.ls.apple.com", "POST", "/hvr/v3/use", 268))

    def test_dumps_unknown_low_level_location_post_paths(self):
        self.assertTrue(should_dump_body("wps.apple.com", "POST", "/any/new/path", 1200))
        self.assertTrue(should_dump_body("iphone-ld.apple.com", "POST", "/lookup", 1200))

    def test_does_not_dump_gets_empty_bodies_or_large_bodies(self):
        self.assertFalse(should_dump_body("gsp-ssl.ls.apple.com", "GET", "/tile.vf", 1024))
        self.assertFalse(should_dump_body("gsp-ssl.ls.apple.com", "POST", "/dispatcher.arpc", 0))
        self.assertFalse(should_dump_body("gsp-ssl.ls.apple.com", "POST", "/dispatcher.arpc", 2_000_001))
        self.assertFalse(should_dump_body("gsp-ssl.ls.apple.com", "POST", "/unrelated", 100))

    def test_rewrites_wloc_response_only_when_spoofing_is_configured(self):
        body = self.build_wloc_response_body("aa:bb:cc:dd:ee:ff", 50.1, 2.1)

        unchanged, unchanged_count = rewrite_wloc_response_if_configured(
            "gs-loc.apple.com",
            "/clls/wloc",
            body,
            {},
        )
        self.assertEqual(unchanged_count, 0)
        self.assertEqual(unchanged, body)

        rewritten, rewritten_count = rewrite_wloc_response_if_configured(
            "gs-loc.apple.com",
            "/clls/wloc",
            body,
            {
                "WAYPOINT_SPOOF_ENABLED": "1",
                "WAYPOINT_SPOOF_LAT": "48.85837",
                "WAYPOINT_SPOOF_LON": "2.294481",
            },
        )
        self.assertEqual(rewritten_count, 1)
        [location] = extract_wifi_locations_from_response_body(rewritten)
        self.assertEqual(round(location["latitude"], 6), 48.85837)
        self.assertEqual(round(location["longitude"], 6), 2.294481)

    def build_wloc_response_body(self, bssid, latitude, longitude):
        wifi_device = bytearray()
        wifi_device += encode_length_delimited_field(1, bssid.encode("ascii"))
        wifi_device += encode_length_delimited_field(2, encode_location(latitude, longitude))
        payload = encode_length_delimited_field(2, bytes(wifi_device))
        return WLOC_RESPONSE_PREFIX + len(payload).to_bytes(2, "big") + payload


if __name__ == "__main__":
    unittest.main()
