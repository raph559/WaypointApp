import Foundation
import Security

struct WaypointCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let label: String?
    let updatedAt: String?
    let updatedBy: String?

    init(
        latitude: Double,
        longitude: Double,
        label: String? = nil,
        updatedAt: String? = nil,
        updatedBy: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case label
        case updatedAt = "updated_at"
        case updatedBy = "updated_by"
    }
}

struct WaypointTargetRequest: Codable {
    let latitude: Double
    let longitude: Double
    let label: String?

    init(coordinate: WaypointCoordinate) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        label = coordinate.label
    }
}

struct WaypointHealthResponse: Codable {
    let ok: Bool
    let paired: Bool
    let target: WaypointCoordinate?
    let error: String?
}

struct WaypointPairingPayload: Codable {
    let serverURL: String
    let code: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case code
        case expiresAt = "expires_at"
    }
}

struct WaypointPairRequest: Codable {
    let code: String
    let clientID: String
    let clientName: String
    let publicKey: String

    enum CodingKeys: String, CodingKey {
        case code
        case clientID = "client_id"
        case clientName = "client_name"
        case publicKey = "public_key"
    }
}

enum WaypointAPIError: LocalizedError {
    case invalidServerURL
    case unpaired
    case missingPrivateKey
    case invalidPrivateKey
    case randomGenerationFailed
    case encodingFailed(Error)
    case decodingFailed(Error)
    case requestFailed(Error)
    case invalidResponse
    case invalidStatus(code: Int, message: String?)
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The Waypoint server URL is missing or invalid."
        case .unpaired:
            return "This device is not paired with a Waypoint server."
        case .missingPrivateKey:
            return "The Waypoint signing key is missing."
        case .invalidPrivateKey:
            return "The stored Waypoint signing key is invalid."
        case .randomGenerationFailed:
            return "Failed to generate secure random bytes."
        case .encodingFailed(let error):
            return "Failed to encode the Waypoint request: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode the Waypoint response: \(error.localizedDescription)"
        case .requestFailed(let error):
            return "The Waypoint request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "The Waypoint server returned an invalid response."
        case .invalidStatus(let code, let message):
            if let message, !message.isEmpty {
                return "The Waypoint server returned HTTP \(code): \(message)"
            }
            return "The Waypoint server returned HTTP \(code)."
        case .keychainStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? "The Keychain operation failed with status \(status)."
        }
    }
}
