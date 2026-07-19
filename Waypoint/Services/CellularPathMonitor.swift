import Foundation
import Network

/// Observes a real cellular path independently of LocalDevVPN. The handoff
/// must not report success merely because its retained local socket still works
/// in Airplane Mode or because Wi-Fi reconnected behind the scenes.
final class CellularPathMonitor: @unchecked Sendable {
    static let shared = CellularPathMonitor()

    private let cellularMonitor = NWPathMonitor(requiredInterfaceType: .cellular)
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let cellularQueue = DispatchQueue(label: "app.waypoint.cellular-path")
    private let wifiQueue = DispatchQueue(label: "app.waypoint.wifi-path")
    private let lock = NSLock()
    private var hasCellularSample = false
    private var hasWiFiSample = false
    private var cellularIsSatisfied = false
    private var wifiIsSatisfied = false
    private var cellularOnlySince: Date?

    func isCellularOnly(stableFor duration: TimeInterval = 0) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard hasCellularSample,
              hasWiFiSample,
              cellularIsSatisfied,
              !wifiIsSatisfied,
              let cellularOnlySince else {
            return false
        }

        return Date().timeIntervalSince(cellularOnlySince) >= duration
    }

    var hasObservedOfflineBaseline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasCellularSample &&
            hasWiFiSample &&
            !cellularIsSatisfied &&
            !wifiIsSatisfied
    }

    private init() {
        cellularMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.update(cellular: path.status == .satisfied)
        }
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.update(wifi: path.status == .satisfied)
        }
        cellularMonitor.start(queue: cellularQueue)
        wifiMonitor.start(queue: wifiQueue)
    }

    private func update(cellular: Bool? = nil, wifi: Bool? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if let cellular {
            hasCellularSample = true
            cellularIsSatisfied = cellular
        }
        if let wifi {
            hasWiFiSample = true
            wifiIsSatisfied = wifi
        }

        if hasCellularSample &&
            hasWiFiSample &&
            cellularIsSatisfied &&
            !wifiIsSatisfied {
            if cellularOnlySince == nil {
                cellularOnlySince = Date()
            }
        } else {
            cellularOnlySince = nil
        }
    }
}
