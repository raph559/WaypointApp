import Foundation
import UIKit

extension AppModel {
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

    func beginResendLoop(for sessionID: UUID) {
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

    func simulationConnectionFailed(
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
}

