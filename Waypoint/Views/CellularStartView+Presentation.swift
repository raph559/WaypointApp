import SwiftUI

extension CellularStartView {
    @ViewBuilder
    var toolbarAction: some View {
        if model.canCancelCellularLaunch {
            Button("Cancel") {
                model.cancelCellularLaunch()
            }
        } else {
            switch model.cellularLaunchState {
            case .failed:
                Button("Close") {
                    model.closeCellularLaunch()
                }
            case .succeeded:
                Button("Close") {
                    model.finishCellularLaunch()
                }
            default:
                EmptyView()
            }
        }
    }

    var presentation: StepPresentation {
        switch model.cellularLaunchState {
        case .idle:
            return StepPresentation(
                symbol: "antenna.radiowaves.left.and.right",
                color: .blue,
                title: "Getting Ready",
                message: "Waypoint is preparing the start guide.",
                showsActivity: true
            )

        case .needsLocalDevVPN:
            return StepPresentation(
                symbol: "network.badge.shield.half.filled",
                color: .blue,
                title: "Install LocalDevVPN",
                message: "Waypoint needs LocalDevVPN to connect to this iPhone. Install it, then return—setup will continue automatically.",
                showsActivity: false
            )

        case .needsPairing:
            return StepPresentation(
                symbol: "doc.badge.plus",
                color: .blue,
                title: "One-Time Setup",
                message: "Import this iPhone’s pairing record. Developer Mode must already be enabled in Settings.",
                showsActivity: false
            )

        case .cachingSupportFiles(let message):
            return StepPresentation(
                symbol: "arrow.down.circle.fill",
                color: .blue,
                title: "Getting Waypoint Ready",
                message: model.isLaunchingOnWiFi
                    ? "\(message) Keep Wi-Fi connected. The first download is about 17 MB."
                    : "\(message) Keep mobile data on. The first download is about 17 MB.",
                showsActivity: true
            )

        case .openingLocalDevVPN:
            return StepPresentation(
                symbol: "network.badge.shield.half.filled",
                color: .blue,
                title: "Connecting LocalDevVPN",
                message: "Waypoint will return automatically when the connection has started.",
                showsActivity: true
            )

        case .settlingLocalDevVPN:
            return StepPresentation(
                symbol: "network.badge.shield.half.filled",
                color: .blue,
                title: "Waiting for LocalDevVPN",
                message: model.isLaunchingOnWiFi
                    ? "Keep Wi-Fi connected for one more moment."
                    : "Keep mobile data on for one more moment.",
                showsActivity: true
            )

        case .waitingForAirplaneMode:
            return StepPresentation(
                symbol: "airplane",
                color: .blue,
                title: "Turn On Airplane Mode",
                message: "Keep Wi-Fi off. Waypoint will continue automatically as soon as the phone is offline.",
                showsActivity: true,
                activityLabel: "Waiting for Airplane Mode"
            )

        case .preparingDevice:
            return StepPresentation(
                symbol: "iphone",
                color: .blue,
                title: "Preparing Your iPhone",
                message: model.isLaunchingOnWiFi
                    ? "Keep Waypoint open for a moment."
                    : "Keep Airplane Mode on and Wi-Fi off.",
                showsActivity: true
            )

        case .startingSpoof:
            return StepPresentation(
                symbol: "location.fill",
                color: .blue,
                title: "Starting Your Spoof",
                message: model.isLaunchingOnWiFi
                    ? "Using your current Wi-Fi connection."
                    : "Stay in Airplane Mode for one more moment.",
                showsActivity: true
            )

        case .handoff:
            return handoffPresentation

        case .succeeded:
            return StepPresentation(
                symbol: "checkmark.circle.fill",
                color: .green,
                title: model.isLaunchingOnWiFi ? "Spoof Active" : "Spoof Active on Mobile Data",
                message: model.notificationWarningsEnabled
                    ? (model.isLaunchingOnWiFi ? "You can now use other apps." : "You can now use other apps on 4G/5G.")
                    : "The spoof is active. Stop alerts are off.",
                showsActivity: false
            )

        case .failed(let message):
            return StepPresentation(
                symbol: "exclamationmark.triangle.fill",
                color: .orange,
                title: "Couldn’t Finish Setup",
                message: message,
                showsActivity: false
            )
        }
    }

    private var handoffPresentation: StepPresentation {
        switch model.cellularHandoffState {
        case .idle, .arming:
            return StepPresentation(
                symbol: "antenna.radiowaves.left.and.right",
                color: .blue,
                title: "Preparing Mobile Data",
                message: "Keep Airplane Mode on and Wi-Fi off for one more moment.",
                showsActivity: true
            )

        case .waiting(let secondsRemaining):
            return StepPresentation(
                symbol: "antenna.radiowaves.left.and.right",
                color: .blue,
                title: "Turn Off Airplane Mode",
                message: "Keep Wi-Fi off. Waypoint is waiting up to \(secondsRemaining) seconds for 4G/5G.",
                showsActivity: true,
                activityLabel: "Waiting for mobile data"
            )

        case .verifying:
            return StepPresentation(
                symbol: "antenna.radiowaves.left.and.right",
                color: .blue,
                title: "Checking Mobile Data",
                message: "Keep Wi-Fi off and leave Waypoint open while it verifies the connection.",
                showsActivity: true
            )

        case .succeeded:
            return StepPresentation(
                symbol: "checkmark.circle.fill",
                color: .green,
                title: "Spoof Active on Mobile Data",
                message: "You can now use other apps on 4G/5G.",
                showsActivity: false
            )

        case .failed(let message):
            return StepPresentation(
                symbol: "exclamationmark.triangle.fill",
                color: .orange,
                title: "Couldn’t Switch to Mobile Data",
                message: message,
                showsActivity: false
            )
        }
    }

    var progressIndex: Int {
        switch model.cellularLaunchState {
        case .idle, .needsLocalDevVPN, .needsPairing, .cachingSupportFiles, .openingLocalDevVPN,
             .settlingLocalDevVPN:
            return 0
        case .waitingForAirplaneMode, .preparingDevice, .startingSpoof:
            return 1
        case .handoff, .succeeded:
            return 2
        case .failed:
            return model.simulatedCoordinate == nil ? 0 : 2
        }
    }
}

struct StepPresentation {
    let symbol: String
    let color: Color
    let title: String
    let message: String
    let showsActivity: Bool
    var activityLabel: String = "Working"
}
