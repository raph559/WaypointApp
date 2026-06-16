import hashlib
import unittest

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

from tools.waypoint_security import (
    SignedRequestVerifier,
    b64url_decode,
    b64url_encode,
    canonical_request,
    generate_pairing_code,
)


BODY = b'{"latitude":48.85837,"longitude":2.294481,"label":"Eiffel Tower"}'
METHOD = "POST"
PATH = "/v1/target"
TIMESTAMP = 1_781_607_200
NONCE_TEXT = "abc123nonce"


class WaypointSecurityTests(unittest.TestCase):
    def test_base64url_round_trips_without_padding(self):
        data = b"\xfb\xef\xffabc123nonce"

        encoded = b64url_encode(data)

        self.assertNotIn("=", encoded)
        self.assertNotIn("+", encoded)
        self.assertNotIn("/", encoded)
        self.assertEqual(b64url_decode(encoded), data)

    def test_canonical_request_includes_body_hash(self):
        nonce = b64url_encode(NONCE_TEXT.encode("utf-8"))
        expected = "\n".join(
            [
                "WAYPOINT-V1",
                METHOD,
                PATH,
                str(TIMESTAMP),
                nonce,
                hashlib.sha256(BODY).hexdigest(),
            ]
        )

        self.assertEqual(canonical_request(METHOD, PATH, TIMESTAMP, nonce, BODY), expected)

    def test_verify_signed_request_accepts_valid_signature(self):
        private_key = Ed25519PrivateKey.generate()
        public_key_b64 = self._public_key_b64(private_key)
        headers = self._signed_headers(private_key)

        verifier = SignedRequestVerifier(allowed_skew_seconds=120)

        self.assertTrue(verifier.verify(public_key_b64, METHOD, PATH, BODY, headers, now=TIMESTAMP))

    def test_verify_signed_request_rejects_bad_signature(self):
        private_key = Ed25519PrivateKey.generate()
        public_key_b64 = self._public_key_b64(private_key)
        headers = self._signed_headers(private_key)
        headers["X-Waypoint-Signature"] = b64url_encode(b"x" * 64)

        verifier = SignedRequestVerifier(allowed_skew_seconds=120)

        self.assertFalse(verifier.verify(public_key_b64, METHOD, PATH, BODY, headers, now=TIMESTAMP))

    def test_verify_signed_request_rejects_old_timestamp(self):
        private_key = Ed25519PrivateKey.generate()
        public_key_b64 = self._public_key_b64(private_key)
        headers = self._signed_headers(private_key)

        verifier = SignedRequestVerifier(allowed_skew_seconds=120)

        self.assertFalse(
            verifier.verify(public_key_b64, METHOD, PATH, BODY, headers, now=TIMESTAMP + 121)
        )

    def test_verify_signed_request_rejects_reused_nonce(self):
        private_key = Ed25519PrivateKey.generate()
        public_key_b64 = self._public_key_b64(private_key)
        headers = self._signed_headers(private_key)

        verifier = SignedRequestVerifier(allowed_skew_seconds=120)

        self.assertTrue(verifier.verify(public_key_b64, METHOD, PATH, BODY, headers, now=TIMESTAMP))
        self.assertFalse(verifier.verify(public_key_b64, METHOD, PATH, BODY, headers, now=TIMESTAMP))

    def test_pairing_code_is_crockford_base32_and_ten_characters(self):
        alphabet = set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

        for _ in range(100):
            code = generate_pairing_code()
            self.assertEqual(len(code), 10)
            self.assertLessEqual(set(code), alphabet)

    def _signed_headers(
        self,
        private_key: Ed25519PrivateKey,
        *,
        body: bytes = BODY,
        timestamp: int = TIMESTAMP,
        nonce_text: str = NONCE_TEXT,
    ) -> dict[str, str]:
        nonce = b64url_encode(nonce_text.encode("utf-8"))
        canonical = canonical_request(METHOD, PATH, timestamp, nonce, body)
        signature = private_key.sign(canonical.encode("utf-8"))
        return {
            "X-Waypoint-Client": "iphone171",
            "X-Waypoint-Timestamp": str(timestamp),
            "X-Waypoint-Nonce": nonce,
            "X-Waypoint-Signature": b64url_encode(signature),
        }

    def _public_key_b64(self, private_key: Ed25519PrivateKey) -> str:
        public_key = private_key.public_key().public_bytes(
            encoding=Encoding.Raw,
            format=PublicFormat.Raw,
        )
        return b64url_encode(public_key)
