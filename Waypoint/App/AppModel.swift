import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var pairingState: SetupCheckState = .required
    @Published private(set) var tunnelState: SetupCheckState = .required
    @Published private(set) var developerImageState: SetupCheckState = .required
    @Published private(set) var isPreparing = false
    @Published private(set) var preparationMessage = ""
    @Published private(set) var simulatedCoordinate: SelectedCoordinate?
    @Published private(set) var isChangingSimulation = false
    @Published private(set) var simulationEvent: SimulationEvent?
    @Published private(set) var cellularHandoffState: CellularHandoffState = .idle
    @Published private(set) var cellularLaunchState: CellularLaunchState = .idle
    @Published private(set) var isLocalDevVPNInstalled = false
    @Published private(set) var isSideStoreAvailable = false
    @Published private(set) var disconnectAlertsEnabled = false
    @Published private(set) var disconnectAlertsDenied = false
    @Published private(set) var isUpdatingDisconnectAlerts = false
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

    private let bridge = DeviceBridge()
    private let feedbackGenerator = UINotificationFeedbackGenerator()
    private var resendTask: Task<Void, Never>?
    private var cellularHandoffTask: Task<Void, Never>?
    private var cellularHandoffOperationID: UUID?
    private var cellularLaunchTask: Task<Void, Never>?
    private var cellularLaunchOperationID: UUID?
    private var pendingCellularCoordinate: SelectedCoordinate?
    private var simulationSessionID: UUID?
    private var isStoppingSimulation = false
    private var isApplicationActive = true
    private var didLeaveForLocalDevVPN = false
    private var pendingLaunchRoute: GuidedLaunchRoute?
    private var disconnectAlertsPreference = false
    private var hasStoredDisconnectAlertsPreference = false
    private var notificationSettingsOperationID: UUID?
    private static let keepAliveKey = "backgroundKeepAliveEnabled"
    private static let disconnectAlertsKey = "disconnectAlertsEnabled"
    private static let pairingCallbackScheme = "waypoint-pairing-c7f2e8b4"

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

    func refreshLocalState() {
        refreshLocalDevVPNAvailability()
        refreshSideStoreAvailability()
        refreshDisconnectAlertSettings()
        pairingState = PairingFileStore.exists ? .ready : .required

        if SimulationNotificationMonitor.shared.consumeStaleSessionMarker() {
            publishSimulationEvent(.connectionLost)
            presentError(
                title: "Previous Spoof Session Ended",
                message: "Waypoint was closed while spoofing. The developer connection is no longer being maintained, so verify your location before continuing."
            )
        }

        if !PairingFileStore.exists {
            tunnelState = .required
            developerImageState = .required
        }
    }

    func setDisconnectAlertsEnabled(_ enabled: Bool) {
        let operationID = UUID()
        notificationSettingsOperationID = operationID
        hasStoredDisconnectAlertsPreference = true
        disconnectAlertsPreference = enabled
        UserDefaults.standard.set(enabled, forKey: Self.disconnectAlertsKey)

        guard enabled else {
            disconnectAlertsEnabled = false
            disconnectAlertsDenied = false
            isUpdatingDisconnectAlerts = false
            SimulationNotificationMonitor.shared.setAlertsEnabled(false)
            notificationSettingsOperationID = nil
            return
        }

        isUpdatingDisconnectAlerts = true
        Task { [weak self] in
            guard let self else { return }
            let authorization = await SimulationNotificationMonitor.shared.requestAuthorization()
            applyDisconnectAlertAuthorization(authorization, operationID: operationID)
        }
    }

    func requestPairingFromSideStore() {
        guard let url = sideStorePairingURL() else {
            presentError(
                title: "SideStore Import Unavailable",
                message: "Waypoint could not create the SideStore import request. Use Choose Pairing File instead."
            )
            return
        }
        UIApplication.shared.open(url) { [weak self] didOpen in
            guard !didOpen else { return }
            Task { @MainActor in
                self?.pairingImportFailed(
                    "SideStore could not be opened. Use Choose Pairing File instead."
                )
            }
        }
    }

    func beginAdaptiveLaunch(at coordinate: SelectedCoordinate) {
        let route: GuidedLaunchRoute
        switch CellularPathMonitor.shared.activeConnection {
        case .wifi:
            route = .wifi
        case .cellular:
            route = .cellular
        case .unknown, .offline:
            return
        }
        beginGuidedLaunch(at: coordinate, route: route)
    }

    func checkLocalDevVPNInstallation() {
        continueGuidedLaunchAfterLocalDevVPNIfNeeded()
    }

    private func refreshLocalDevVPNAvailability() {
        guard let url = localDevVPNEnableURL() else {
            isLocalDevVPNInstalled = false
            return
        }
        isLocalDevVPNInstalled = UIApplication.shared.canOpenURL(url)
    }

    private func refreshSideStoreAvailability() {
        guard let url = sideStorePairingURL() else {
            isSideStoreAvailable = false
            return
        }
        isSideStoreAvailable = UIApplication.shared.canOpenURL(url)
    }

    private func sideStorePairingURL() -> URL? {
        var components = URLComponents()
        components.scheme = "sidestore"
        components.host = "pairing"
        components.queryItems = [URLQueryItem(name: "urlname", value: Self.pairingCallbackScheme)]
        return components.url
    }

    private func localDevVPNEnableURL() -> URL? {
        var components = URLComponents()
        components.scheme = "localdevvpn"
        components.host = "enable"
        components.queryItems = [
            URLQueryItem(name: "scheme", value: Self.pairingCallbackScheme)
        ]
        return components.url
    }

    private func continueGuidedLaunchAfterLocalDevVPNIfNeeded() {
        guard let operationID = cellularLaunchOperationID,
              case .needsLocalDevVPN = cellularLaunchState else {
            return
        }

        refreshLocalDevVPNAvailability()
        guard isLocalDevVPNInstalled else { return }

        if PairingFileStore.exists {
            startCellularPreflight(operationID: operationID)
        } else {
            cellularLaunchState = .needsPairing
        }
    }

    private func refreshDisconnectAlertSettings() {
        let operationID = UUID()
        notificationSettingsOperationID = operationID
        isUpdatingDisconnectAlerts = true

        Task { [weak self] in
            guard let self else { return }
            let authorization = await SimulationNotificationMonitor.shared.authorizationState()
            guard notificationSettingsOperationID == operationID else { return }

            if !hasStoredDisconnectAlertsPreference {
                hasStoredDisconnectAlertsPreference = true
                disconnectAlertsPreference = authorization == .authorized
                UserDefaults.standard.set(disconnectAlertsPreference, forKey: Self.disconnectAlertsKey)
            }

            applyDisconnectAlertAuthorization(authorization, operationID: operationID)
        }
    }

    private func applyDisconnectAlertAuthorization(
        _ authorization: SimulationNotificationAuthorization,
        operationID: UUID
    ) {
        guard notificationSettingsOperationID == operationID else { return }

        let enabled = disconnectAlertsPreference && authorization == .authorized
        disconnectAlertsEnabled = enabled
        disconnectAlertsDenied = disconnectAlertsPreference && authorization == .denied
        isUpdatingDisconnectAlerts = false
        notificationSettingsOperationID = nil
        SimulationNotificationMonitor.shared.setAlertsEnabled(enabled)
    }

    private func beginGuidedLaunch(at coordinate: SelectedCoordinate, route: GuidedLaunchRoute) {
        guard coordinate.isValid,
              simulatedCoordinate == nil,
              !isChangingSimulation,
              !isPreparing,
              cellularLaunchOperationID == nil else {
            return
        }

        let operationID = UUID()
        refreshLocalDevVPNAvailability()
        cellularLaunchOperationID = operationID
        pendingCellularCoordinate = coordinate
        pendingLaunchRoute = route
        if !isLocalDevVPNInstalled {
            cellularLaunchState = .needsLocalDevVPN
        } else {
            cellularLaunchState = PairingFileStore.exists
                ? .cachingSupportFiles("Checking one-time files…")
                : .needsPairing
        }
        isCellularStartPresented = true
        isSetupPresented = false
        didLeaveForLocalDevVPN = false
        _ = CellularPathMonitor.shared

        if isLocalDevVPNInstalled, PairingFileStore.exists {
            startCellularPreflight(operationID: operationID)
        }
    }

    func cancelCellularLaunch() {
        guard canCancelCellularLaunch else { return }
        let operationID = cellularLaunchOperationID
        let needsBridgeCleanup: Bool
        if case .preparingDevice = cellularLaunchState {
            needsBridgeCleanup = true
        } else {
            needsBridgeCleanup = false
        }

        cellularLaunchTask?.cancel()

        if needsBridgeCleanup, let operationID {
            pendingCellularCoordinate = nil
            pendingLaunchRoute = nil
            cellularLaunchState = .idle
            isCellularStartPresented = false
            didLeaveForLocalDevVPN = false
            cellularLaunchTask = Task { [weak self] in
                guard let self else { return }
                await bridge.disconnect()
                guard cellularLaunchOperationID == operationID else { return }
                invalidateConnectionReadiness()
                cellularLaunchTask = nil
                cellularLaunchOperationID = nil
            }
            return
        }

        cellularLaunchTask = nil
        cellularLaunchOperationID = nil
        pendingCellularCoordinate = nil
        pendingLaunchRoute = nil
        cellularLaunchState = .idle
        isCellularStartPresented = false
        didLeaveForLocalDevVPN = false
    }

    func retryCellularLaunch() {
        guard case .failed = cellularLaunchState,
              let operationID = cellularLaunchOperationID,
              pendingCellularCoordinate != nil else {
            return
        }

        if simulatedCoordinate != nil, simulationSessionID != nil {
            waitForOfflineThenRetryHandoff(operationID: operationID)
        } else if PairingFileStore.exists {
            startCellularPreflight(operationID: operationID)
        } else {
            cellularLaunchState = .needsPairing
        }
    }

    func replacePairingForCellularLaunch() {
        guard canReplacePairingForCellularLaunch else { return }
        cellularLaunchTask?.cancel()
        cellularLaunchTask = nil
        pairingState = .required
        tunnelState = .required
        developerImageState = .required
        preparationMessage = "Choose a fresh pairing record"
        cellularLaunchState = .needsPairing
    }

    func closeCellularLaunch() {
        cellularLaunchTask?.cancel()
        cellularLaunchTask = nil
        cellularLaunchOperationID = nil
        pendingCellularCoordinate = nil
        pendingLaunchRoute = nil
        cellularLaunchState = .idle
        isCellularStartPresented = false
        didLeaveForLocalDevVPN = false
    }

    func finishCellularLaunch() {
        guard case .succeeded = cellularLaunchState else { return }
        closeCellularLaunch()
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == Self.pairingCallbackScheme else {
            return
        }

        let callbackHost = url.host?.lowercased()
        if callbackHost != "pairingfile" {
            guard callbackHost == nil,
                  url.path.isEmpty || url.path == "/",
                  url.query == nil else {
                return
            }
            localDevVPNDidReturn()
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name.lowercased() == "data" })?.value else {
            pairingImportFailed("SideStore returned an invalid pairing callback.")
            return
        }

        guard simulatedCoordinate == nil else {
            presentError(title: "Stop Spoofing First", message: "Stop the active spoof before replacing the pairing file.")
            return
        }

        guard canAcceptPairingImport else { return }
        let expectedOperationID = cellularLaunchOperationID
        isPreparing = true

        Task {
            defer { isPreparing = false }
            await bridge.disconnect()
            guard cellularLaunchOperationID == expectedOperationID else { return }
            do {
                try PairingFileStore.importBase64(payload)
                pairingDidChange()
                continueCellularLaunchAfterPairingIfNeeded()
            } catch {
                pairingImportFailed(error.localizedDescription)
            }
        }
    }

    func importPairingFile(_ result: Result<[URL], Error>) {
        guard simulatedCoordinate == nil else {
            presentError(title: "Stop Spoofing First", message: "Stop the active spoof before replacing the pairing file.")
            return
        }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard canAcceptPairingImport else { return }
            let expectedOperationID = cellularLaunchOperationID
            isPreparing = true
            Task {
                defer { isPreparing = false }
                await bridge.disconnect()
                guard cellularLaunchOperationID == expectedOperationID else { return }
                do {
                    try PairingFileStore.importFile(at: url)
                    pairingDidChange()
                    continueCellularLaunchAfterPairingIfNeeded()
                } catch {
                    pairingImportFailed(error.localizedDescription)
                }
            }
        case .failure(let error):
            let cocoaError = error as NSError
            guard !(cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError) else {
                return
            }
            pairingImportFailed(error.localizedDescription)
        }
    }

    func prepareDevice() async {
        guard !isPreparing else { return }
        guard cellularLaunchOperationID == nil else { return }
        guard simulatedCoordinate == nil else {
            presentError(title: "Spoof Is Active", message: "Stop spoofing before reconnecting or preparing the device.")
            return
        }

        do {
            try await prepareDeviceCore()
        } catch {
            await recordPreparationFailure(error)
            presentError(title: "Device Preparation Failed", error: error)
        }
    }

    func startSimulation(at coordinate: SelectedCoordinate) async {
        guard cellularLaunchOperationID == nil else { return }
        guard coordinate.isValid else {
            presentError(title: "Invalid Location", message: "Choose a valid point on the map.")
            return
        }

        if !isReady {
            await prepareDevice()
        }
        guard isReady else {
            isSetupPresented = true
            return
        }

        guard !isChangingSimulation else { return }
        if simulatedCoordinate == nil {
            if case .failed = cellularHandoffState {
                cancelCellularHandoffWork(resetState: true)
            }
        }
        guard !cellularHandoffState.pausesLocationWrites else { return }

        let previousCoordinate = simulatedCoordinate
        let previousSessionID = simulationSessionID

        if previousCoordinate == nil {
            cancelCellularHandoffWork(resetState: true)
        }

        isChangingSimulation = true
        resendTask?.cancel()
        resendTask = nil
        simulationSessionID = nil

        do {
            try await bridge.setLocation(coordinate)

            if let previousSessionID {
                SimulationNotificationMonitor.shared.endSession(previousSessionID)
            }

            let sessionID = UUID()
            simulationSessionID = sessionID
            simulatedCoordinate = coordinate
            UIApplication.shared.isIdleTimerDisabled = true
            SimulationNotificationMonitor.shared.beginSession(sessionID)

            if backgroundKeepAliveEnabled {
                do {
                    try BackgroundKeepAlive.shared.start()
                } catch {
                    presentError(
                        title: "Background Keepalive Unavailable",
                        message: "The location was set, but background reliability may be reduced.\n\n\(error.localizedDescription)"
                    )
                }
            }
            beginResendLoop(for: sessionID)
            publishSimulationEvent(previousCoordinate == nil ? .started : .moved, coordinate: coordinate)
        } catch {
            if previousCoordinate != nil, let previousSessionID {
                simulationConnectionFailed(
                    error,
                    notificationSessionID: previousSessionID,
                    requireCurrentSession: false
                )
            } else {
                invalidateConnectionReadiness()
                isSetupPresented = true
                presentError(title: "Location Simulation Failed", error: error)
            }
        }
        isChangingSimulation = false
    }

    func stopSimulation() async {
        guard cellularLaunchOperationID == nil else { return }
        guard !isChangingSimulation else { return }

        cancelCellularHandoffWork(resetState: true)
        let sessionID = simulationSessionID
        isChangingSimulation = true
        isStoppingSimulation = true
        simulationSessionID = nil
        resendTask?.cancel()
        resendTask = nil

        if let sessionID {
            SimulationNotificationMonitor.shared.endSession(sessionID)
        }

        var didConfirmStop = false

        do {
            try await bridge.clearLocation()
            didConfirmStop = true
        } catch {
            invalidateConnectionReadiness()
            presentError(
                title: "Could Not Confirm Real Location",
                message: "Waypoint lost the simulation connection. Disconnect LocalDevVPN or reboot if another app still reports the simulated point.\n\n\(error.localizedDescription)"
            )
        }

        simulatedCoordinate = nil
        BackgroundKeepAlive.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if didConfirmStop {
            publishSimulationEvent(.stopped)
        }
        isStoppingSimulation = false
        isChangingSimulation = false
    }

    func applicationBecameActive() {
        isApplicationActive = true
        refreshLocalDevVPNAvailability()
        refreshSideStoreAvailability()
        refreshDisconnectAlertSettings()
        if isLocalDevVPNInstalled,
           case .needsLocalDevVPN = cellularLaunchState {
            continueGuidedLaunchAfterLocalDevVPNIfNeeded()
        }
        if case .openingLocalDevVPN = cellularLaunchState,
           didLeaveForLocalDevVPN {
            localDevVPNDidReturn()
        }
        guard cellularLaunchOperationID == nil else { return }
        guard !cellularHandoffState.pausesLocationWrites else { return }
        guard let coordinate = simulatedCoordinate,
              let sessionID = simulationSessionID else { return }

        Task {
            do {
                try await bridge.setLocation(coordinate)
                guard simulationSessionID == sessionID else { return }
                SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
            } catch {
                guard simulationSessionID == sessionID else { return }
                simulationConnectionFailed(error, notificationSessionID: sessionID)
            }
        }
    }

    func applicationBecameInactive() {
        isApplicationActive = false
        if case .openingLocalDevVPN = cellularLaunchState {
            didLeaveForLocalDevVPN = true
        }
    }

    /// Tests whether the already-open DVT location session survives the switch
    /// from Airplane Mode back to cellular. This deliberately never reconnects:
    /// iOS rejects a fresh developer connection when cellular is the only
    /// physical interface, while an existing session may survive the handoff.
    func armCellularHandoff() {
        guard !isChangingSimulation,
              !cellularHandoffState.isInProgress,
              let coordinate = simulatedCoordinate,
              let sessionID = simulationSessionID else {
            return
        }

        cellularHandoffTask?.cancel()
        resendTask?.cancel()
        resendTask = nil
        _ = CellularPathMonitor.shared

        let operationID = UUID()
        cellularHandoffOperationID = operationID
        cellularHandoffState = .arming
        SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)

        cellularHandoffTask = Task { [weak self] in
            guard let self else { return }

            // A cancelled resend may already be inside the serial bridge queue.
            // Fence it before the user changes network state.
            await bridge.waitUntilIdle()
            guard !Task.isCancelled,
                  cellularHandoffOperationID == operationID,
                  simulationSessionID == sessionID else {
                return
            }

            let baselineDeadline = Date().addingTimeInterval(8)
            while !CellularPathMonitor.shared.isOffline(stableFor: 1),
                  Date() < baselineDeadline {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      cellularHandoffOperationID == operationID,
                      simulationSessionID == sessionID else {
                    return
                }
            }

            guard CellularPathMonitor.shared.isOffline(stableFor: 1) else {
                cellularHandoffPathCheckFailed(
                    "Waypoint could not confirm the offline starting state. Turn Airplane Mode on, keep Wi-Fi off, then try the handoff again.",
                    operationID: operationID,
                    sessionID: sessionID
                )
                return
            }

            let pathDeadline = Date().addingTimeInterval(30)
            var lastDisplayedSecond: Int?
            var lastHeartbeatDate = Date()

            while !CellularPathMonitor.shared.isCellularOnly(stableFor: 2),
                  Date() < pathDeadline {
                let remaining = max(1, Int(ceil(pathDeadline.timeIntervalSinceNow)))
                if lastDisplayedSecond != remaining {
                    cellularHandoffState = .waiting(secondsRemaining: remaining)
                    lastDisplayedSecond = remaining
                }

                if Date().timeIntervalSince(lastHeartbeatDate) >= 10 {
                    SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
                    lastHeartbeatDate = Date()
                }

                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      cellularHandoffOperationID == operationID,
                      simulationSessionID == sessionID else {
                    return
                }
            }

            guard CellularPathMonitor.shared.isCellularOnly(stableFor: 2) else {
                cellularHandoffPathCheckFailed(
                    "A stable cellular-only path was not detected within 30 seconds. Keep Wi-Fi off, confirm 4G/5G is working, then try again.",
                    operationID: operationID,
                    sessionID: sessionID
                )
                return
            }

            cellularHandoffState = .verifying
            SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)

            do {
                // Reuse the retained LocationSimulation client. Calling
                // bridge.connect here would create a new socket that iOS rejects
                // on a cellular-only path.
                for probe in 1...3 {
                    guard CellularPathMonitor.shared.isCellularOnly(stableFor: 2) else {
                        cellularHandoffPathCheckFailed(
                            "The cellular-only path changed during verification. Keep Wi-Fi off and try the handoff again.",
                            operationID: operationID,
                            sessionID: sessionID
                        )
                        return
                    }

                    try await bridge.setLocation(coordinate)
                    SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)

                    guard CellularPathMonitor.shared.isCellularOnly() else {
                        cellularHandoffPathCheckFailed(
                            "Wi-Fi connected or cellular data dropped during verification. The cellular handoff was not confirmed.",
                            operationID: operationID,
                            sessionID: sessionID
                        )
                        return
                    }

                    if probe < 3 {
                        try await Task.sleep(for: .seconds(2))
                    }
                }
                guard !Task.isCancelled,
                      cellularHandoffOperationID == operationID,
                      simulationSessionID == sessionID else {
                    return
                }

                guard CellularPathMonitor.shared.isCellularOnly(stableFor: 2) else {
                    cellularHandoffPathCheckFailed(
                        "The cellular-only path was not stable through the final check.",
                        operationID: operationID,
                        sessionID: sessionID
                    )
                    return
                }

                SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
                cellularHandoffState = .succeeded
                cellularHandoffTask = nil
                cellularHandoffOperationID = nil
                startBackgroundKeepAliveIfNeeded()
                beginResendLoop(for: sessionID)
                publishSimulationEvent(.cellularReady)
                if case .handoff = cellularLaunchState {
                    cellularLaunchState = .succeeded
                }
            } catch {
                guard !Task.isCancelled,
                      cellularHandoffOperationID == operationID,
                      simulationSessionID == sessionID else {
                    return
                }

                cellularHandoffState = .failed(error.localizedDescription)
                cellularHandoffTask = nil
                cellularHandoffOperationID = nil
                if case .handoff = cellularLaunchState {
                    cellularLaunchState = .failed(
                        "The retained spoof session stopped responding when mobile data returned. Turn Airplane Mode on and try the guided start again."
                    )
                }
                simulationConnectionFailed(
                    error,
                    notificationSessionID: sessionID,
                    duringCellularHandoff: true
                )
            }
        }
    }

    func cancelCellularHandoff() {
        guard cellularHandoffState.isInProgress else { return }
        let sessionID = simulationSessionID

        switch cellularHandoffState {
        case .arming:
            cancelCellularHandoffWork(resetState: true)
            if let sessionID, simulatedCoordinate != nil {
                beginResendLoop(for: sessionID)
            }
        case .waiting, .verifying:
            cancelCellularHandoffWork(resetState: false)
            cellularHandoffState = .failed(
                "The handoff was cancelled after the network transition began. Location writes remain paused until you return to Airplane Mode or Wi-Fi and explicitly resume."
            )
            if let sessionID {
                SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
            }
        case .idle, .succeeded, .failed:
            return
        }
    }

    func resumeSimulationAfterHandoffFailure() {
        guard case .failed = cellularHandoffState,
              let sessionID = simulationSessionID,
              simulatedCoordinate != nil else {
            return
        }

        cellularHandoffState = .idle
        SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
        beginResendLoop(for: sessionID)
    }

    func showError(title: String, error: Error) {
        presentError(title: title, error: error)
    }

    func resetDeveloperImage() {
        guard simulatedCoordinate == nil,
              cellularLaunchOperationID == nil,
              !isPreparing else { return }
        isPreparing = true
        Task {
            defer { isPreparing = false }
            await bridge.disconnect()
            do {
                try DeveloperImageStore.removeAll()
                tunnelState = .required
                developerImageState = .required
                preparationMessage = "Developer image files removed"
            } catch {
                presentError(title: "Could Not Reset Developer Image", error: error)
            }
        }
    }

    private func continueCellularLaunchAfterPairingIfNeeded() {
        guard let operationID = cellularLaunchOperationID,
              case .needsPairing = cellularLaunchState else {
            return
        }
        startCellularPreflight(operationID: operationID)
    }

    private func startCellularPreflight(operationID: UUID) {
        cellularLaunchTask?.cancel()
        cellularLaunchTask = nil
        refreshLocalDevVPNAvailability()
        guard isLocalDevVPNInstalled else {
            cellularLaunchState = .needsLocalDevVPN
            return
        }
        cancelCellularHandoffWork(resetState: simulatedCoordinate == nil)
        cellularLaunchState = .cachingSupportFiles("Checking one-time files…")

        cellularLaunchTask = Task { [weak self] in
            guard let self else { return }

            do {
                for artifact in DeveloperImageStore.artifacts where !DeveloperImageStore.isPresent(artifact) {
                    guard cellularLaunchOperationID == operationID else { return }
                    cellularLaunchState = .cachingSupportFiles("Downloading \(artifact.label)…")
                    try await DeveloperImageStore.download(artifact)
                    try Task.checkCancellation()
                }

                guard cellularLaunchOperationID == operationID else { return }
                cellularLaunchState = .cachingSupportFiles("Finishing one-time setup…")
                guard cellularLaunchOperationID == operationID else { return }
                cellularLaunchState = .openingLocalDevVPN
                didLeaveForLocalDevVPN = false
                let didOpen = await openLocalDevVPN()
                try Task.checkCancellation()

                guard cellularLaunchOperationID == operationID else { return }
                cellularLaunchTask = nil
                if !didOpen {
                    if isLocalDevVPNInstalled {
                        failCellularLaunch(
                            "LocalDevVPN could not be opened. Update it from the App Store, then try again.",
                            operationID: operationID
                        )
                    } else {
                        cellularLaunchState = .needsLocalDevVPN
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                let connectionAdvice = pendingLaunchRoute == .wifi
                    ? "Check your Wi-Fi connection and try again."
                    : "Turn mobile data on and try again."
                failCellularLaunch(
                    "Waypoint could not download its one-time support files. \(connectionAdvice)\n\n\(error.localizedDescription)",
                    operationID: operationID
                )
            }
        }
    }

    private func openLocalDevVPN() async -> Bool {
        guard let url = localDevVPNEnableURL(),
              UIApplication.shared.canOpenURL(url) else {
            isLocalDevVPNInstalled = false
            return false
        }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url) { didOpen in
                continuation.resume(returning: didOpen)
            }
        }
    }

    private func localDevVPNDidReturn() {
        guard case .openingLocalDevVPN = cellularLaunchState,
              let operationID = cellularLaunchOperationID else {
            return
        }

        didLeaveForLocalDevVPN = false
        cellularLaunchTask?.cancel()
        cellularLaunchState = .settlingLocalDevVPN
        cellularLaunchTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  cellularLaunchOperationID == operationID else {
                return
            }

            if pendingLaunchRoute == .wifi {
                await startGuidedSimulationOnWiFi(operationID: operationID)
            } else {
                await waitForOfflineAndStart(operationID: operationID)
            }
        }
    }

    private func startGuidedSimulationOnWiFi(operationID: UUID) async {
        guard cellularLaunchOperationID == operationID,
              pendingLaunchRoute == .wifi,
              let coordinate = pendingCellularCoordinate else {
            return
        }

        guard CellularPathMonitor.shared.activeConnection == .wifi else {
            failCellularLaunch(
                "Wi-Fi disconnected before Waypoint could start. Reconnect Wi-Fi and try again, or close this guide to use mobile data.",
                operationID: operationID
            )
            return
        }

        do {
            cellularLaunchState = .preparingDevice
            try await prepareDeviceCore()
            try Task.checkCancellation()

            guard cellularLaunchOperationID == operationID,
                  pendingLaunchRoute == .wifi else { return }
            cellularLaunchState = .startingSpoof
            try await establishGuidedSimulation(at: coordinate, operationID: operationID)
            try Task.checkCancellation()

            guard cellularLaunchOperationID == operationID,
                  simulatedCoordinate != nil,
                  let sessionID = simulationSessionID else {
                return
            }

            startBackgroundKeepAliveIfNeeded()
            beginResendLoop(for: sessionID)
            cellularLaunchTask = nil
            cellularLaunchState = .succeeded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  cellularLaunchOperationID == operationID else { return }
            if case .preparingDevice = cellularLaunchState {
                await recordPreparationFailure(error)
            } else {
                invalidateConnectionReadiness()
                await bridge.disconnect()
            }
            failCellularLaunch(
                "Waypoint could not start the spoof on Wi-Fi. Confirm LocalDevVPN and Developer Mode are enabled, then try again.\n\n\(error.localizedDescription)",
                operationID: operationID
            )
        }
    }

    private func waitForOfflineAndStart(operationID: UUID) async {
        cellularLaunchState = .waitingForAirplaneMode

        while cellularLaunchOperationID == operationID {
            if isApplicationActive,
               CellularPathMonitor.shared.isOffline(stableFor: 1) {
                break
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }

        guard !Task.isCancelled,
              cellularLaunchOperationID == operationID,
              let coordinate = pendingCellularCoordinate else {
            return
        }

        do {
            cellularLaunchState = .preparingDevice
            try await prepareDeviceCore()
            try Task.checkCancellation()

            guard cellularLaunchOperationID == operationID else { return }
            cellularLaunchState = .startingSpoof
            try await establishGuidedSimulation(at: coordinate, operationID: operationID)
            try Task.checkCancellation()

            guard cellularLaunchOperationID == operationID,
                  simulatedCoordinate != nil,
                  simulationSessionID != nil else {
                return
            }

            cellularLaunchState = .handoff
            cellularLaunchTask = nil
            armCellularHandoff()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  cellularLaunchOperationID == operationID else { return }
            if case .preparingDevice = cellularLaunchState {
                await recordPreparationFailure(error)
            } else {
                invalidateConnectionReadiness()
                await bridge.disconnect()
            }
            failCellularLaunch(
                "Waypoint could not start the spoof. Confirm Developer Mode is enabled, then try again.\n\n\(error.localizedDescription)",
                operationID: operationID
            )
        }
    }

    private func waitForOfflineThenRetryHandoff(operationID: UUID) {
        cellularLaunchTask?.cancel()
        cellularLaunchState = .waitingForAirplaneMode
        cellularLaunchTask = Task { [weak self] in
            guard let self else { return }

            while cellularLaunchOperationID == operationID {
                if isApplicationActive,
                   CellularPathMonitor.shared.isOffline(stableFor: 1) {
                    break
                }

                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled,
                  cellularLaunchOperationID == operationID,
                  simulatedCoordinate != nil,
                  simulationSessionID != nil else {
                return
            }

            cellularLaunchState = .handoff
            cellularLaunchTask = nil
            armCellularHandoff()
        }
    }

    private func prepareDeviceCore() async throws {
        guard !isPreparing else {
            throw DeviceBridgeError.message("Device preparation is already running.")
        }
        guard PairingFileStore.exists else {
            pairingState = .required
            throw DeviceBridgeError.message("Import this iPhone’s pairing record first.")
        }

        isPreparing = true
        defer { isPreparing = false }

        pairingState = .ready
        tunnelState = .checking
        developerImageState = .required
        preparationMessage = "Connecting through LocalDevVPN…"

        try await bridge.connect(pairingFile: PairingFileStore.fileURL)
        try Task.checkCancellation()
        tunnelState = .ready
        developerImageState = .checking
        preparationMessage = "Checking the developer image…"

        if try await bridge.isDeveloperImageMounted() {
            try Task.checkCancellation()
            developerImageState = .ready
            preparationMessage = "Device ready"
            return
        }

        for artifact in DeveloperImageStore.artifacts where !DeveloperImageStore.isPresent(artifact) {
            preparationMessage = "Downloading \(artifact.label)…"
            try await DeveloperImageStore.download(artifact)
            try Task.checkCancellation()
        }

        preparationMessage = "Mounting the developer image…"
        try await bridge.mountDeveloperImage(DeveloperImageStore.paths)
        try Task.checkCancellation()

        guard try await bridge.isDeveloperImageMounted() else {
            throw DeviceBridgeError.message("The mount request finished, but iOS did not report a mounted developer image.")
        }

        developerImageState = .ready
        preparationMessage = "Device ready"
    }

    private func recordPreparationFailure(_ error: Error) async {
        await bridge.disconnect()
        if !tunnelState.isReady {
            tunnelState = .failed(error.localizedDescription)
        } else {
            tunnelState = .required
            developerImageState = .failed(error.localizedDescription)
        }
        preparationMessage = "Setup needs attention"
    }

    private func establishGuidedSimulation(
        at coordinate: SelectedCoordinate,
        operationID: UUID
    ) async throws {
        guard coordinate.isValid,
              simulatedCoordinate == nil,
              simulationSessionID == nil,
              cellularLaunchOperationID == operationID else {
            throw DeviceBridgeError.message("The guided start is no longer current.")
        }

        isChangingSimulation = true
        defer { isChangingSimulation = false }
        resendTask?.cancel()
        resendTask = nil

        try await bridge.setLocation(coordinate)
        try Task.checkCancellation()

        guard cellularLaunchOperationID == operationID else {
            try? await bridge.clearLocation()
            throw CancellationError()
        }

        let sessionID = UUID()
        simulationSessionID = sessionID
        simulatedCoordinate = coordinate
        UIApplication.shared.isIdleTimerDisabled = true
        SimulationNotificationMonitor.shared.beginSession(sessionID)
        publishSimulationEvent(.started, coordinate: coordinate)
    }

    private func startBackgroundKeepAliveIfNeeded() {
        guard backgroundKeepAliveEnabled else { return }
        do {
            try BackgroundKeepAlive.shared.start()
        } catch {
            presentError(
                title: "Background Keepalive Unavailable",
                message: "The spoof is active, but background reliability may be reduced.\n\n\(error.localizedDescription)"
            )
        }
    }

    private func failCellularLaunch(_ message: String, operationID: UUID) {
        guard cellularLaunchOperationID == operationID else { return }
        cellularLaunchTask = nil
        cellularLaunchState = .failed(message)
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.error)
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private var canAcceptPairingImport: Bool {
        guard !isPreparing else { return false }
        guard cellularLaunchOperationID != nil else { return true }
        if case .needsPairing = cellularLaunchState { return true }
        return false
    }

    private func pairingImportFailed(_ message: String) {
        if let operationID = cellularLaunchOperationID {
            failCellularLaunch(
                "Waypoint could not import the pairing record. Choose a fresh pairing record for this iPhone, then try again.\n\n\(message)",
                operationID: operationID
            )
        } else {
            presentError(title: "Pairing Import Failed", message: message)
        }
    }

    private func pairingDidChange() {
        pairingState = .ready
        tunnelState = .required
        developerImageState = .required
        preparationMessage = "Pairing file imported"
    }

    private func beginResendLoop(for sessionID: UUID) {
        guard !cellularHandoffState.pausesLocationWrites else { return }
        resendTask?.cancel()
        resendTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled,
                      let self,
                      !self.cellularHandoffState.pausesLocationWrites,
                      self.simulationSessionID == sessionID,
                      let coordinate = self.simulatedCoordinate else {
                    return
                }

                if case .succeeded = self.cellularHandoffState,
                   !CellularPathMonitor.shared.isCellularOnly() {
                    self.cellularHandoffState = .failed(
                        "The phone is no longer on a cellular-only path. Location writes are paused so Waypoint does not make an unsafe cellular-only reconnect attempt."
                    )
                    SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
                    if case .succeeded = self.cellularLaunchState {
                        self.cellularLaunchState = .failed(
                            "The cellular-only path changed before setup finished."
                        )
                    }
                    return
                }

                do {
                    try await self.bridge.setLocation(coordinate)
                    guard !Task.isCancelled, self.simulationSessionID == sessionID else { return }
                    SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
                } catch {
                    guard !Task.isCancelled, self.simulationSessionID == sessionID else { return }
                    self.simulationConnectionFailed(error, notificationSessionID: sessionID)
                    return
                }
            }
        }
    }

    private func simulationConnectionFailed(
        _ error: Error,
        notificationSessionID: UUID,
        requireCurrentSession: Bool = true,
        duringCellularHandoff: Bool = false
    ) {
        if requireCurrentSession, simulationSessionID != notificationSessionID { return }
        guard !isStoppingSimulation, simulatedCoordinate != nil else { return }

        resendTask?.cancel()
        resendTask = nil
        cancelCellularHandoffWork(resetState: !duringCellularHandoff)
        simulationSessionID = nil
        simulatedCoordinate = nil
        BackgroundKeepAlive.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        SimulationNotificationMonitor.shared.reportUnexpectedStop(for: notificationSessionID)
        invalidateConnectionReadiness()
        if !duringCellularHandoff {
            isSetupPresented = true
        }
        publishSimulationEvent(.connectionLost)
        if duringCellularHandoff {
            cellularHandoffState = .idle
            if cellularLaunchOperationID == nil {
                presentError(
                    title: "Cellular Handoff Failed",
                    message: "The retained developer session stopped responding during the handoff test, so the spoof may have stopped. A new session cannot be opened on cellular alone. Leave Wi-Fi off, reconnect LocalDevVPN while cellular is on, enable Airplane Mode again, then prepare and restart the spoof.\n\n\(error.localizedDescription)"
                )
            } else if case .handoff = cellularLaunchState {
                cellularLaunchState = .failed(
                    "The spoof connection ended when mobile data returned. Turn Airplane Mode on and try again.\n\n\(error.localizedDescription)"
                )
            }
        } else {
            presentError(
                title: "Simulation Connection Ended",
                message: "The developer connection closed, so iOS may have returned to the real location.\n\n\(error.localizedDescription)"
            )
        }
    }

    private func cellularHandoffPathCheckFailed(
        _ message: String,
        operationID: UUID,
        sessionID: UUID
    ) {
        guard cellularHandoffOperationID == operationID,
              simulationSessionID == sessionID else {
            return
        }

        cellularHandoffState = .failed(message)
        cellularHandoffTask = nil
        cellularHandoffOperationID = nil
        SimulationNotificationMonitor.shared.recordHeartbeat(for: sessionID)
        if case .handoff = cellularLaunchState {
            cellularLaunchState = .failed(message)
        }
    }

    private func cancelCellularHandoffWork(resetState: Bool) {
        cellularHandoffTask?.cancel()
        cellularHandoffTask = nil
        cellularHandoffOperationID = nil
        if resetState {
            cellularHandoffState = .idle
        }
    }

    private func presentError(title: String, error: Error) {
        presentError(title: title, message: error.localizedDescription)
    }

    private func presentError(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    private func publishSimulationEvent(
        _ kind: SimulationEventKind,
        coordinate: SelectedCoordinate? = nil
    ) {
        let event = SimulationEvent(kind: kind, coordinate: coordinate)
        simulationEvent = event

        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(kind == .connectionLost ? .error : .success)
        UIAccessibility.post(notification: .announcement, argument: event.accessibilityAnnouncement)
    }

    private func invalidateConnectionReadiness() {
        tunnelState = .required
        developerImageState = .required
        preparationMessage = "Reconnect LocalDevVPN and prepare the device again"
    }
}

private enum GuidedLaunchRoute {
    case wifi
    case cellular
}
