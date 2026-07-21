import Foundation
import UIKit

extension AppModel {
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
}

