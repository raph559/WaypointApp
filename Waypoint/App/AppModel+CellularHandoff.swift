import Foundation

extension AppModel {
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

    func cancelCellularHandoffWork(resetState: Bool) {
        cellularHandoffTask?.cancel()
        cellularHandoffTask = nil
        cellularHandoffOperationID = nil
        if resetState {
            cellularHandoffState = .idle
        }
    }
}

