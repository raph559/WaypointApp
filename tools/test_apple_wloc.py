import gzip
import unittest

from tools.apple_wloc import (
    WLOC_RESPONSE_PREFIX,
    encode_length_delimited_field,
    encode_location,
    encode_varint_field,
    iter_proto_fields,
    decode_location,
    extract_wifi_locations_from_response_body,
    rewrite_wloc_response_body,
)


class AppleWLocRewriteTests(unittest.TestCase):
    def test_rewrites_all_wifi_locations_in_response_body(self):
        body = self.build_response_body(
            [
                ("aa:bb:cc:dd:ee:ff", 50.12345678, 2.12345678),
                ("11:22:33:44:55:66", 51.12345678, 3.12345678),
            ]
        )

        rewritten, rewritten_count = rewrite_wloc_response_body(body, 48.85837, 2.294481)

        self.assertEqual(rewritten_count, 2)
        self.assertTrue(rewritten.startswith(WLOC_RESPONSE_PREFIX))
        self.assertEqual(int.from_bytes(rewritten[8:10], "big"), len(rewritten) - 10)

        locations = extract_wifi_locations_from_response_body(rewritten)
        self.assertEqual([item["bssid"] for item in locations], ["aa:bb:cc:dd:ee:ff", "11:22:33:44:55:66"])
        self.assertEqual([round(item["latitude"], 6) for item in locations], [48.85837, 48.85837])
        self.assertEqual([round(item["longitude"], 6) for item in locations], [2.294481, 2.294481])

    def test_rewrites_gzip_encoded_response_body(self):
        body = self.build_response_body(
            [
                ("aa:bb:cc:dd:ee:ff", 50.12345678, 2.12345678),
            ]
        )
        encoded = gzip.compress(body)

        rewritten, rewritten_count = rewrite_wloc_response_body(encoded, 48.85837, 2.294481)

        self.assertEqual(rewritten_count, 1)
        self.assertTrue(rewritten.startswith(b"\x1f\x8b"))
        locations = extract_wifi_locations_from_response_body(gzip.decompress(rewritten))
        self.assertEqual(round(locations[0]["latitude"], 6), 48.85837)
        self.assertEqual(round(locations[0]["longitude"], 6), 2.294481)

    def test_rewrites_auxiliary_field_22_locations_in_response_body(self):
        body = self.build_response_body([])
        payload = body[len(WLOC_RESPONSE_PREFIX) + 2 :]
        payload += self.build_auxiliary_location_record(50.47384643, 2.980484)
        payload += self.build_auxiliary_location_record(50.48288726, 2.97959327)
        body = WLOC_RESPONSE_PREFIX + len(payload).to_bytes(2, "big") + payload

        rewritten, rewritten_count = rewrite_wloc_response_body(body, 48.85837, 2.294481)

        self.assertEqual(rewritten_count, 2)
        locations = self.extract_auxiliary_locations(rewritten)
        self.assertEqual([round(item["latitude"], 6) for item in locations], [48.85837, 48.85837])
        self.assertEqual([round(item["longitude"], 6) for item in locations], [2.294481, 2.294481])

    def test_leaves_non_wloc_response_body_unchanged(self):
        original = b"not-a-wloc-response"

        rewritten, rewritten_count = rewrite_wloc_response_body(original, 48.85837, 2.294481)

        self.assertEqual(rewritten_count, 0)
        self.assertEqual(rewritten, original)

    def build_response_body(self, bssid_locations):
        payload = bytearray()
        for bssid, latitude, longitude in bssid_locations:
            wifi_device = bytearray()
            wifi_device += encode_length_delimited_field(1, bssid.encode("ascii"))
            wifi_device += encode_length_delimited_field(2, encode_location(latitude, longitude))
            payload += encode_length_delimited_field(2, bytes(wifi_device))
        return WLOC_RESPONSE_PREFIX + len(payload).to_bytes(2, "big") + bytes(payload)

    def build_auxiliary_location_record(self, latitude, longitude):
        record = bytearray()
        record += encode_varint_field(1, 2080)
        record += encode_varint_field(2, 2)
        record += encode_varint_field(3, 1411855360)
        record += encode_varint_field(4, 305)
        record += encode_length_delimited_field(5, encode_location(latitude, longitude))
        record += encode_varint_field(6, 18500)
        record += encode_varint_field(7, 1350)
        return encode_length_delimited_field(22, bytes(record))

    def extract_auxiliary_locations(self, response_body):
        payload_start = len(WLOC_RESPONSE_PREFIX) + 2
        payload_len = int.from_bytes(response_body[len(WLOC_RESPONSE_PREFIX) : payload_start], "big")
        payload = response_body[payload_start : payload_start + payload_len]
        locations = []
        for field in iter_proto_fields(payload):
            if field.number != 22 or field.wire_type != 2:
                continue
            record = payload[field.value_slice]
            for nested in iter_proto_fields(record):
                if nested.number == 5 and nested.wire_type == 2:
                    locations.append(decode_location(record[nested.value_slice]))
        return locations


if __name__ == "__main__":
    unittest.main()
