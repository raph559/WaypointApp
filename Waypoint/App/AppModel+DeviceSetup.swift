import Foundation

extension AppModel {
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


    func prepareDeviceCore() async throws {
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

    func recordPreparationFailure(_ error: Error) async {
        await bridge.disconnect()
        if !tunnelState.isReady {
            tunnelState = .failed(error.localizedDescription)
        } else {
            tunnelState = .required
            developerImageState = .failed(error.localizedDescription)
        }
        preparationMessage = "Setup needs attention"
    }
}

