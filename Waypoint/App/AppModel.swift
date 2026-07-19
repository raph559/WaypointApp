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
    @Published var alert: AppAlert?
    @Published var isSetupPresented = false
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
    private var simulationSessionID: UUID?
    private var isStoppingSimulation = false
    private static let keepAliveKey = "backgroundKeepAliveEnabled"
    private static let pairingCallbackScheme = "waypoint-pairing-c7f2e8b4"

    init() {
        if UserDefaults.standard.object(forKey: Self.keepAliveKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.keepAliveKey)
        }
        backgroundKeepAliveEnabled = UserDefaults.standard.bool(forKey: Self.keepAliveKey)
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

    func refreshLocalState() {
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
            isSetupPresented = true
        }
    }

    func requestPairingFromSideStore() {
        var components = URLComponents()
        components.scheme = "sidestore"
        components.host = "pairing"
        components.queryItems = [URLQueryItem(name: "urlname", value: Self.pairingCallbackScheme)]

        guard let url = components.url else {
            presentError(title: "Could Not Open SideStore", message: "The pairing-export URL could not be created.")
            return
        }
        UIApplication.shared.open(url) { [weak self] didOpen in
            guard !didOpen else { return }
            Task { @MainActor in
                self?.presentError(
                    title: "SideStore Not Found",
                    message: "Open SideStore manually, export its .mobiledevicepairing file, then use Choose File in Waypoint."
                )
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == Self.pairingCallbackScheme,
              url.host?.lowercased() == "pairingfile",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name.lowercased() == "data" })?.value else {
            return
        }

        guard simulatedCoordinate == nil else {
            presentError(title: "Stop Spoofing First", message: "Stop the active spoof before replacing the pairing file.")
            return
        }

        Task {
            await bridge.disconnect()
            do {
                try PairingFileStore.importBase64(payload)
                pairingDidChange()
                await prepareDevice()
            } catch {
                presentError(title: "Pairing Import Failed", error: error)
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
            Task {
                await bridge.disconnect()
                do {
                    try PairingFileStore.importFile(at: url)
                    pairingDidChange()
                    await prepareDevice()
                } catch {
                    presentError(title: "Pairing Import Failed", error: error)
                }
            }
        case .failure(let error):
            let cocoaError = error as NSError
            guard !(cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError) else {
                return
            }
            presentError(title: "Pairing Import Failed", error: error)
        }
    }

    func prepareDevice() async {
        guard !isPreparing else { return }
        guard simulatedCoordinate == nil else {
            presentError(title: "Spoof Is Active", message: "Stop spoofing before reconnecting or preparing the device.")
            return
        }
        guard PairingFileStore.exists else {
            pairingState = .required
            presentError(
                title: "Pairing File Required",
                message: "Import the pairing file from SideStore before preparing the device."
            )
            return
        }

        isPreparing = true
        pairingState = .ready
        tunnelState = .checking
        developerImageState = .required
        preparationMessage = "Connecting through LocalDevVPN…"

        do {
            try await bridge.connect(pairingFile: PairingFileStore.fileURL)
            tunnelState = .ready
            developerImageState = .checking
            preparationMessage = "Checking the developer image…"

            if try await bridge.isDeveloperImageMounted() {
                developerImageState = .ready
                preparationMessage = "Device ready"
                isPreparing = false
                return
            }

            for artifact in DeveloperImageStore.artifacts where !DeveloperImageStore.isPresent(artifact) {
                preparationMessage = "Downloading \(artifact.label)…"
                try await DeveloperImageStore.download(artifact)
            }

            preparationMessage = "Mounting the developer image…"
            try await bridge.mountDeveloperImage(DeveloperImageStore.paths)

            guard try await bridge.isDeveloperImageMounted() else {
                throw DeviceBridgeError.message("The mount request finished, but iOS did not report a mounted developer image.")
            }

            developerImageState = .ready
            preparationMessage = "Device ready"
        } catch {
            await bridge.disconnect()
            if !tunnelState.isReady {
                tunnelState = .failed(error.localizedDescription)
            } else {
                tunnelState = .required
                developerImageState = .failed(error.localizedDescription)
            }
            preparationMessage = "Setup needs attention"
            presentError(title: "Device Preparation Failed", error: error)
        }

        isPreparing = false
    }

    func startSimulation(at coordinate: SelectedCoordinate) async {
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
            while !CellularPathMonitor.shared.hasObservedOfflineBaseline,
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

            guard CellularPathMonitor.shared.hasObservedOfflineBaseline else {
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
                beginResendLoop(for: sessionID)
                publishSimulationEvent(.cellularReady)
            } catch {
                guard !Task.isCancelled,
                      cellularHandoffOperationID == operationID,
                      simulationSessionID == sessionID else {
                    return
                }

                cellularHandoffState = .failed(error.localizedDescription)
                cellularHandoffTask = nil
                cellularHandoffOperationID = nil
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
        guard simulatedCoordinate == nil else { return }
        Task {
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
            presentError(
                title: "Cellular Handoff Failed",
                message: "The retained developer session stopped responding during the handoff test, so the spoof may have stopped. A new session cannot be opened on cellular alone. Leave Wi-Fi off, reconnect LocalDevVPN while cellular is on, enable Airplane Mode again, then prepare and restart the spoof.\n\n\(error.localizedDescription)"
            )
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
