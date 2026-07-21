import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var pairingState: SetupCheckState = .required
    @Published var tunnelState: SetupCheckState = .required
    @Published var developerImageState: SetupCheckState = .required
    @Published var isPreparing = false
    @Published var preparationMessage = ""
    @Published var simulatedCoordinate: SelectedCoordinate?
    @Published var isChangingSimulation = false
    @Published var simulationEvent: SimulationEvent?
    @Published var cellularHandoffState: CellularHandoffState = .idle
    @Published var cellularLaunchState: CellularLaunchState = .idle
    @Published var isLocalDevVPNInstalled = false
    @Published var isSideStoreAvailable = false
    @Published var disconnectAlertsEnabled = false
    @Published var disconnectAlertsDenied = false
    @Published var isUpdatingDisconnectAlerts = false
    @Published var alert: AppAlert?
    @Published var isSetupPresented = false
    @Published var isCellularStartPresented = false
    @Published var backgroundKeepAliveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backgroundKeepAliveEnabled, forKey: Self.keepAliveKey)
            if backgroundKeepAliveEnabled, simulatedCoordinate != nil {
                do {
                    try BackgroundKeepAlive.shared.start()
                } catch {
                    presentError(title: "Background Keepalive Unavailable", error: error)
                }
            } else if !backgroundKeepAliveEnabled {
                BackgroundKeepAlive.shared.stop()
            }
        }
    }

    // Implementation-only access is module-internal so responsibility extensions can share one state machine.
    let bridge = DeviceBridge()
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    var resendTask: Task<Void, Never>?
    var cellularHandoffTask: Task<Void, Never>?
    var cellularHandoffOperationID: UUID?
    var cellularLaunchTask: Task<Void, Never>?
    var cellularLaunchOperationID: UUID?
    var pendingCellularCoordinate: SelectedCoordinate?
    var simulationSessionID: UUID?
    var isStoppingSimulation = false
    var isApplicationActive = true
    var didLeaveForLocalDevVPN = false
    var pendingLaunchRoute: GuidedLaunchRoute?
    var disconnectAlertsPreference = false
    var hasStoredDisconnectAlertsPreference = false
    var notificationSettingsOperationID: UUID?
    private static let keepAliveKey = "backgroundKeepAliveEnabled"
    static let disconnectAlertsKey = "disconnectAlertsEnabled"
    static let pairingCallbackScheme = "waypoint-pairing-c7f2e8b4"

    init() {
        if UserDefaults.standard.object(forKey: Self.keepAliveKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.keepAliveKey)
        }
        backgroundKeepAliveEnabled = UserDefaults.standard.bool(forKey: Self.keepAliveKey)

        let storedDisconnectPreference = UserDefaults.standard.object(forKey: Self.disconnectAlertsKey)
        hasStoredDisconnectAlertsPreference = storedDisconnectPreference != nil
        disconnectAlertsPreference = storedDisconnectPreference as? Bool ?? false
        SimulationNotificationMonitor.shared.setAlertsEnabled(false)
    }

    var notificationWarningsEnabled: Bool {
        disconnectAlertsEnabled
    }

    var isReady: Bool {
        pairingState.isReady && tunnelState.isReady && developerImageState.isReady
    }

    var isCellularHandoffInProgress: Bool {
        cellularHandoffState.isInProgress
    }

    var areLocationWritesPausedForCellularHandoff: Bool {
        simulatedCoordinate != nil && cellularHandoffState.pausesLocationWrites
    }

    var canCancelCellularLaunch: Bool {
        cellularLaunchOperationID != nil && cellularLaunchState.canCancelSafely
    }

    var isCellularLaunchRunning: Bool {
        cellularLaunchOperationID != nil
    }

    var isLaunchingOnWiFi: Bool {
        pendingLaunchRoute == .wifi
    }

    var canReplacePairingForCellularLaunch: Bool {
        guard cellularLaunchOperationID != nil,
              simulatedCoordinate == nil,
              case .failed = cellularLaunchState else {
            return false
        }
        return true
    }


    func failCellularLaunch(_ message: String, operationID: UUID) {
        guard cellularLaunchOperationID == operationID else { return }
        cellularLaunchTask = nil
        cellularLaunchState = .failed(message)
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.error)
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func presentError(title: String, error: Error) {
        presentError(title: title, message: error.localizedDescription)
    }

    func presentError(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    func publishSimulationEvent(
        _ kind: SimulationEventKind,
        coordinate: SelectedCoordinate? = nil
    ) {
        let event = SimulationEvent(kind: kind, coordinate: coordinate)
        simulationEvent = event

        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(kind == .connectionLost ? .error : .success)
        UIAccessibility.post(notification: .announcement, argument: event.accessibilityAnnouncement)
    }

    func invalidateConnectionReadiness() {
        tunnelState = .required
        developerImageState = .required
        preparationMessage = "Reconnect LocalDevVPN and prepare the device again"
    }
}

enum GuidedLaunchRoute {
    case wifi
    case cellular
}
