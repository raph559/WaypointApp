import CryptoKit
import Foundation

final class WaypointControlClient {
    private let settings: WaypointSettingsStore
    private let keychain: WaypointKeychain
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(settings: WaypointSettingsStore, keychain: WaypointKeychain = WaypointKeychain()) {
        self.settings = settings
        self.keychain = keychain
        self.urlSession = .shared
    }

    func health() async throws -> WaypointHealthResponse {
        let settingsSnapshot = await settingsSnapshot()
        let baseURL = try configuredServerURL(from: settingsSnapshot.serverURL)
        let url = try endpoint(baseURL: baseURL, path: "/v1/health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await send(request)
        let response: WaypointHealthResponse = try decode(data)
        guard response.ok else {
            throw WaypointAPIError.serverRejected(message: response.error)
        }
        return response
    }

    func pair(serverURL: URL, code: String, clientName: String) async throws {
        let baseURL = try validatedServerURL(serverURL)
        let privateKey = try loadOrCreatePrivateKey()
        let clientID = "ios-\(UUID().uuidString.lowercased())"
        let publicKey = WaypointSigner.publicKeyBase64URL(from: privateKey)
        let payload = WaypointPairRequest(
            code: code,
            clientID: clientID,
            clientName: clientName,
            publicKey: publicKey
        )
        let body = try encode(payload)
        let url = try endpoint(baseURL: baseURL, path: "/v1/pair")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await send(request)
        let response: WaypointPairResponse = try decode(data)
        guard response.ok, response.clientID == clientID else {
            throw WaypointAPIError.serverRejected(message: response.error)
        }

        await MainActor.run {
            settings.savePairing(
                serverURL: normalizedServerURLString(baseURL),
                clientID: clientID,
                clientName: clientName
            )
        }
    }

    func setTarget(_ coordinate: WaypointCoordinate) async throws {
        let settingsSnapshot = await settingsSnapshot()
        guard settingsSnapshot.isPaired else {
            throw WaypointAPIError.unpaired
        }
        guard let privateKey = try keychain.loadPrivateKey() else {
            throw WaypointAPIError.missingPrivateKey
        }

        let body = try encode(WaypointTargetRequest(coordinate: coordinate))
        let baseURL = try configuredServerURL(from: settingsSnapshot.serverURL)
        let path = "/v1/target"
        let url = try endpoint(baseURL: baseURL, path: path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let headers = try WaypointSigner.signedHeaders(
            privateKey: privateKey,
            clientID: settingsSnapshot.clientID,
            method: "POST",
            path: path,
            body: body,
            date: Date()
        )
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let data = try await send(request)
        let response: WaypointTargetResponse = try decode(data)
        guard response.ok else {
            throw WaypointAPIError.serverRejected(message: response.error)
        }
        await MainActor.run {
            settings.saveLastCoordinate(coordinate)
        }
    }

    private func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let privateKey = try keychain.loadPrivateKey() {
            return privateKey
        }

        let privateKey = WaypointSigner.generatePrivateKey()
        try keychain.savePrivateKey(privateKey)
        return privateKey
    }

    private func settingsSnapshot() async -> WaypointSettingsSnapshot {
        await MainActor.run {
            WaypointSettingsSnapshot(
                serverURL: settings.serverURL,
                clientID: settings.clientID
            )
        }
    }

    private func configuredServerURL(from serverURL: String) throws -> URL {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw WaypointAPIError.invalidServerURL
        }
        return try validatedServerURL(url)
    }

    private func validatedServerURL(_ url: URL) throws -> URL {
        guard
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            throw WaypointAPIError.invalidServerURL
        }
        return url
    }

    private func endpoint(baseURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WaypointAPIError.invalidServerURL
        }
        components.path = path
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw WaypointAPIError.invalidServerURL
        }
        return url
    }

    private func normalizedServerURLString(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw WaypointAPIError.encodingFailed(error)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WaypointAPIError.decodingFailed(error)
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw WaypointAPIError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WaypointAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(WaypointErrorResponse.self, from: data).error)
            throw WaypointAPIError.invalidStatus(code: httpResponse.statusCode, message: message)
        }
        return data
    }
}

private struct WaypointPairResponse: Codable {
    let ok: Bool
    let clientID: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case clientID = "client_id"
        case error
    }
}

private struct WaypointTargetResponse: Codable {
    let ok: Bool
    let target: WaypointCoordinate?
    let error: String?
}

private struct WaypointErrorResponse: Codable {
    let ok: Bool?
    let error: String?
}

private struct WaypointSettingsSnapshot: Sendable {
    let serverURL: String
    let clientID: String

    var isPaired: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
