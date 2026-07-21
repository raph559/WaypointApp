import Foundation
import UIKit

extension AppModel {
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

    func continueGuidedLaunchAfterLocalDevVPNIfNeeded() {
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


    func continueCellularLaunchAfterPairingIfNeeded() {
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
}

