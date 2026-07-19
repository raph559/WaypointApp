import Foundation
import UIKit
import UserNotifications

enum SimulationNotificationAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
final class SimulationNotificationMonitor {
    static let shared = SimulationNotificationMonitor()

    private static let activeSessionMarkerKey = "activeSimulationSessionID"
    private static let watchdogDelay: TimeInterval = 30

    private let center = UNUserNotificationCenter.current()
    private var activeSessionID: UUID?
    private var refreshGeneration = UUID()
    private var pendingWatchdogIDs = Set<String>()
    private var alertsEnabled = false

    private init() {}

    func prepareAuthorization() async -> Bool {
        await requestAuthorization() == .authorized
    }

    func authorizationState() async -> SimulationNotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> SimulationNotificationAuthorization {
        guard await authorizationState() == .notDetermined else {
            return await authorizationState()
        }

        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationState()
    }

    func setAlertsEnabled(_ enabled: Bool) {
        alertsEnabled = enabled
        refreshGeneration = UUID()

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: Array(pendingWatchdogIDs))
            pendingWatchdogIDs.removeAll()
            return
        }

        if let activeSessionID {
            recordHeartbeat(for: activeSessionID)
        }
    }

    func beginSession(_ sessionID: UUID) {
        invalidateInMemorySession(clearMarker: false)
        activeSessionID = sessionID
        UserDefaults.standard.set(sessionID.uuidString, forKey: Self.activeSessionMarkerKey)
        recordHeartbeat(for: sessionID)
    }

    func recordHeartbeat(for sessionID: UUID) {
        guard activeSessionID == sessionID, alertsEnabled else { return }

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
            guard let self,
                  alertsEnabled,
                  activeSessionID == sessionID,
                  refreshGeneration == generation,
                  await notificationsAreAuthorized() else {
                self?.pendingWatchdogIDs.remove(requestID)
                return
            }

            do {
                try await center.add(request)
            } catch {
                pendingWatchdogIDs.remove(requestID)
                return
            }

            guard alertsEnabled,
                  activeSessionID == sessionID,
                  refreshGeneration == generation else {
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
        let shouldNotify = alertsEnabled
        invalidateInMemorySession(clearMarker: true)

        guard shouldNotify, UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = "Waypoint spoof stopped"
        content.body = "The developer connection ended. Your iPhone may now be using its real location."
        content.sound = .default

        let requestID = "app.waypoint.simulation-ended.\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: nil
        )
        let generation = refreshGeneration

        Task { [weak self] in
            guard let self,
                  alertsEnabled,
                  refreshGeneration == generation,
                  await notificationsAreAuthorized() else { return }

            do {
                try await center.add(request)
            } catch {
                return
            }

            guard alertsEnabled, refreshGeneration == generation else {
                center.removePendingNotificationRequests(withIdentifiers: [requestID])
                return
            }
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
        await authorizationState() == .authorized
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
