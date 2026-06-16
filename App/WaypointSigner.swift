import CryptoKit
import Foundation
import Security

enum WaypointSigner {
    static func generatePrivateKey() -> Curve25519.Signing.PrivateKey {
        Curve25519.Signing.PrivateKey()
    }

    static func publicKeyBase64URL(from privateKey: Curve25519.Signing.PrivateKey) -> String {
        base64URLEncoded(privateKey.publicKey.rawRepresentation)
    }

    static func canonicalRequest(
        method: String,
        path: String,
        timestamp: Int,
        nonce: String,
        body: Data
    ) -> String {
        [
            "WAYPOINT-V1",
            method,
            path,
            String(timestamp),
            nonce,
            sha256Hex(of: body),
        ].joined(separator: "\n")
    }

    static func signedHeaders(
        privateKey: Curve25519.Signing.PrivateKey,
        clientID: String,
        method: String,
        path: String,
        body: Data,
        date: Date = Date()
    ) throws -> [String: String] {
        let timestamp = Int(date.timeIntervalSince1970)
        let nonce = try nonceBase64URL()
        let canonical = canonicalRequest(
            method: method,
            path: path,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )
        let signature = try privateKey.signature(for: Data(canonical.utf8))

        return [
            "X-Waypoint-Client": clientID,
            "X-Waypoint-Timestamp": String(timestamp),
            "X-Waypoint-Nonce": nonce,
            "X-Waypoint-Signature": base64URLEncoded(signature),
        ]
    }

    private static func nonceBase64URL() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw WaypointAPIError.randomGenerationFailed
        }
        return base64URLEncoded(Data(bytes))
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
