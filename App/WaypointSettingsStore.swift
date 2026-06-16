import Combine
import Foundation

final class WaypointSettingsStore: ObservableObject {
    @Published var serverURL: String {
        didSet { userDefaults.set(serverURL, forKey: Keys.serverURL) }
    }

    @Published var clientID: String {
        didSet { userDefaults.set(clientID, forKey: Keys.clientID) }
    }

    @Published var clientName: String {
        didSet { userDefaults.set(clientName, forKey: Keys.clientName) }
    }

    @Published var lastLatitude: Double? {
        didSet { userDefaults.setOptionalDouble(lastLatitude, forKey: Keys.lastLatitude) }
    }

    @Published var lastLongitude: Double? {
        didSet { userDefaults.setOptionalDouble(lastLongitude, forKey: Keys.lastLongitude) }
    }

    @Published var lastLabel: String? {
        didSet { userDefaults.setOptionalString(lastLabel, forKey: Keys.lastLabel) }
    }

    @Published var lastAppliedAt: Date? {
        didSet { userDefaults.setOptionalDate(lastAppliedAt, forKey: Keys.lastAppliedAt) }
    }

    var isPaired: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let userDefaults: UserDefaults

    private enum Keys {
        static let serverURL = "waypoint.serverURL"
        static let clientID = "waypoint.clientID"
        static let clientName = "waypoint.clientName"
        static let lastLatitude = "waypoint.lastLatitude"
        static let lastLongitude = "waypoint.lastLongitude"
        static let lastLabel = "waypoint.lastLabel"
        static let lastAppliedAt = "waypoint.lastAppliedAt"
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        serverURL = userDefaults.string(forKey: Keys.serverURL) ?? ""
        clientID = userDefaults.string(forKey: Keys.clientID) ?? ""
        clientName = userDefaults.string(forKey: Keys.clientName) ?? ""
        lastLatitude = userDefaults.optionalDouble(forKey: Keys.lastLatitude)
        lastLongitude = userDefaults.optionalDouble(forKey: Keys.lastLongitude)
        lastLabel = userDefaults.string(forKey: Keys.lastLabel)
        lastAppliedAt = userDefaults.object(forKey: Keys.lastAppliedAt) as? Date
    }

    func savePairing(serverURL: String, clientID: String, clientName: String) {
        self.serverURL = serverURL
        self.clientID = clientID
        self.clientName = clientName
    }

    func clearPairing() {
        serverURL = ""
        clientID = ""
        clientName = ""
        lastLatitude = nil
        lastLongitude = nil
        lastLabel = nil
        lastAppliedAt = nil
    }

    func saveLastCoordinate(_ coordinate: WaypointCoordinate) {
        lastLatitude = coordinate.latitude
        lastLongitude = coordinate.longitude
        lastLabel = coordinate.label
        lastAppliedAt = Date()
    }
}

private extension UserDefaults {
    func optionalDouble(forKey key: String) -> Double? {
        object(forKey: key) == nil ? nil : double(forKey: key)
    }

    func setOptionalDouble(_ value: Double?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        set(value, forKey: key)
    }

    func setOptionalString(_ value: String?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        set(value, forKey: key)
    }

    func setOptionalDate(_ value: Date?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        set(value, forKey: key)
    }
}
