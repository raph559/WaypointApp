import Foundation
import UIKit
import UserNotifications

@MainActor
final class SimulationNotificationMonitor {
    static let shared = SimulationNotificationMonitor()

    private static let activeSessionMarkerKey = "activeSimulationSessionID"
    private static let watchdogDelay: TimeInterval = 30

    private let center = UNUserNotificationCenter.current()
    private var activeSessionID: UUID?
    private var refreshGeneration = UUID()
    private var pendingWatchdogIDs = Set<String>()

    private init() {}

    func beginSession(_ sessionID: UUID) {
        invalidateInMemorySession(clearMarker: false)
        activeSessionID = sessionID
        UserDefaults.standard.set(sessionID.uuidString, forKey: Self.activeSessionMarkerKey)
        recordHeartbeat(for: sessionID)
    }

    func recordHeartbeat(for sessionID: UUID) {
        guard activeSessionID == sessionID else { return }

        let generation = UUID()
        refreshGeneration = generation
        let requestID = "app.waypoint.simulation-watchdog.\(UUID().uuidString)"
        pendingWatchdogIDs.insert(requestID)

        let content = UNMutableNotificationContent()
        content.title = "Waypoint cannot confirm the spoof"
        content.body = "The developer connection has not checked in. Your iPhone may be using its real location—open Waypoint to verify."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.watchdogDelay,
            repeats: false
        )
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)

        Task { [weak self] in
            guard let self, await notificationsAreAuthorized() else {
                self?.pendingWatchdogIDs.remove(requestID)
                return
            }

            guard activeSessionID == sessionID, refreshGeneration == generation else {
                pendingWatchdogIDs.remove(requestID)
                return
            }

            do {
                try await center.add(request)
            } catch {
                pendingWatchdogIDs.remove(requestID)
                return
            }

            guard activeSessionID == sessionID, refreshGeneration == generation else {
                center.removePendingNotificationRequests(withIdentifiers: [requestID])
                pendingWatchdogIDs.remove(requestID)
                return
            }

            let obsoleteIDs = pendingWatchdogIDs.filter { $0 != requestID }
            center.removePendingNotificationRequests(withIdentifiers: Array(obsoleteIDs))
            pendingWatchdogIDs = [requestID]
        }
    }

    func endSession(_ sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        invalidateInMemorySession(clearMarker: true)
    }

    func reportUnexpectedStop(for sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        invalidateInMemorySession(clearMarker: true)

        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = "Waypoint spoof stopped"
        content.body = "The developer connection ended. Your iPhone may now be using its real location."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "app.waypoint.simulation-ended.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        Task { [weak self] in
            guard let self, await notificationsAreAuthorized() else { return }
            try? await center.add(request)
        }
    }

    func consumeStaleSessionMarker() -> Bool {
        guard UserDefaults.standard.string(forKey: Self.activeSessionMarkerKey) != nil else {
            return false
        }

        invalidateInMemorySession(clearMarker: true)
        return true
    }

    private func notificationsAreAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func invalidateInMemorySession(clearMarker: Bool) {
        activeSessionID = nil
        refreshGeneration = UUID()
        center.removeAllPendingNotificationRequests()
        pendingWatchdogIDs.removeAll()

        if clearMarker {
            UserDefaults.standard.removeObject(forKey: Self.activeSessionMarkerKey)
        }
    }
}
