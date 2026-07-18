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
    private var resendTask: Task<Void, Never>?
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

    func refreshLocalState() {
        pairingState = PairingFileStore.exists ? .ready : .required
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

        isChangingSimulation = true
        do {
            try await bridge.setLocation(coordinate)
            simulatedCoordinate = coordinate
            UIApplication.shared.isIdleTimerDisabled = true
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
            beginResendLoop()
        } catch {
            invalidateConnectionReadiness()
            isSetupPresented = true
            presentError(title: "Location Simulation Failed", error: error)
        }
        isChangingSimulation = false
    }

    func stopSimulation() async {
        guard !isChangingSimulation else { return }
        isChangingSimulation = true
        resendTask?.cancel()
        resendTask = nil

        do {
            try await bridge.clearLocation()
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
        isChangingSimulation = false
    }

    func applicationBecameActive() {
        guard let coordinate = simulatedCoordinate else { return }
        Task {
            do {
                try await bridge.setLocation(coordinate)
            } catch {
                simulationConnectionFailed(error)
            }
        }
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

    private func beginResendLoop() {
        resendTask?.cancel()
        resendTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled,
                      let self,
                      let coordinate = self.simulatedCoordinate else {
                    return
                }

                do {
                    try await self.bridge.setLocation(coordinate)
                } catch {
                    self.simulationConnectionFailed(error)
                    return
                }
            }
        }
    }

    private func simulationConnectionFailed(_ error: Error) {
        resendTask?.cancel()
        resendTask = nil
        simulatedCoordinate = nil
        BackgroundKeepAlive.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        invalidateConnectionReadiness()
        isSetupPresented = true
        presentError(
            title: "Simulation Connection Ended",
            message: "The developer connection closed, so iOS may have returned to the real location.\n\n\(error.localizedDescription)"
        )
    }

    private func presentError(title: String, error: Error) {
        presentError(title: title, message: error.localizedDescription)
    }

    private func presentError(title: String, message: String) {
        alert = AppAlert(title: title, message: message)
    }

    private func invalidateConnectionReadiness() {
        tunnelState = .required
        developerImageState = .required
        preparationMessage = "Reconnect LocalDevVPN and prepare the device again"
    }
}
