import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct CellularStartView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isChoosingPairingFile = false
    @State private var isSideStoreConfirmationPresented = false
    @State private var successDismissTask: Task<Void, Never>?

    private let pairingTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList,
        .json,
        .data
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    progressDots

                    VStack(spacing: 20) {
                        Image(systemName: presentation.symbol)
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(presentation.color)
                            .frame(width: 84, height: 84)
                            .background(presentation.color.opacity(0.12), in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)

                        VStack(spacing: 9) {
                            Text(presentation.title)
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)

                            Text(presentation.message)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if presentation.showsActivity {
                            ProgressView()
                                .controlSize(.regular)
                                .accessibilityLabel(presentation.activityLabel)
                        }
                    }
                    .frame(maxWidth: 480)

                    actions
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 30)
                .padding(.bottom, 36)
            }
            .navigationTitle(model.isLaunchingOnWiFi ? "Start Spoofing" : "Start on Mobile Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    toolbarAction
                }
            }
        }
        .interactiveDismissDisabled(true)
        .confirmationDialog(
            "Import from SideStore?",
            isPresented: $isSideStoreConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Continue to SideStore") {
                model.requestPairingFromSideStore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pairing records are sensitive. SideStore sends yours through a callback URL that may appear in SideStore debug logs. Choose Files instead if you prefer the safer option.")
        }
        .fileImporter(
            isPresented: $isChoosingPairingFile,
            allowedContentTypes: pairingTypes,
            allowsMultipleSelection: false,
            onCompletion: model.importPairingFile
        )
        .onAppear {
            updateSuccessDismissal()
        }
        .onChange(of: model.cellularLaunchState) { _, _ in
            updateSuccessDismissal()
        }
        .onDisappear {
            successDismissTask?.cancel()
            successDismissTask = nil
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= progressIndex ? presentation.color : Color.secondary.opacity(0.18))
                    .frame(width: index == progressIndex ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: progressIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cellular start progress")
        .accessibilityValue("Step \(progressIndex + 1) of 3")
    }

    @ViewBuilder
    private var actions: some View {
        switch model.cellularLaunchState {
        case .needsPairing:
            VStack(spacing: 11) {
                Button {
                    isSideStoreConfirmationPresented = true
                } label: {
                    Label("Import from SideStore", systemImage: "arrow.up.forward.app.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isPreparing)

                Button {
                    isChoosingPairingFile = true
                } label: {
                    Label("Choose from Files", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isPreparing)

                if model.isPreparing {
                    ProgressView("Importing pairing record…")
                        .font(.footnote)
                }

                Text("Your pairing record is stored only on this iPhone. Files import offers the best privacy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .failed:
            VStack(spacing: 11) {
                Button {
                    model.retryCellularLaunch()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if model.canReplacePairingForCellularLaunch {
                    Button {
                        model.replacePairingForCellularLaunch()
                    } label: {
                        Label("Replace Pairing Record", systemImage: "doc.badge.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Link(destination: URL(string: "https://github.com/jkcoxson/LocalDevVPN")!) {
                    Label("LocalDevVPN Help", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

        case .succeeded:
            if !model.notificationWarningsEnabled {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("Enable Notifications in Settings", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var toolbarAction: some View {
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

    private var presentation: StepPresentation {
        switch model.cellularLaunchState {
        case .idle:
            return StepPresentation(
                symbol: "antenna.radiowaves.left.and.right",
                color: .blue,
                title: "Getting Ready",
                message: "Waypoint is preparing the start guide.",
                showsActivity: true
            )

        case .needsPairing:
            return StepPresentation(
                symbol: "doc.badge.plus",
                color: .blue,
                title: "One-Time Setup",
                message: "Waypoint needs this iPhone’s pairing record once. Developer Mode must already be enabled in Settings.",
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
                    : "The spoof is active. Stop warnings are off because notifications were not allowed.",
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

    private var progressIndex: Int {
        switch model.cellularLaunchState {
        case .idle, .needsPairing, .cachingSupportFiles, .openingLocalDevVPN,
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

    private func updateSuccessDismissal() {
        successDismissTask?.cancel()
        successDismissTask = nil

        guard case .succeeded = model.cellularLaunchState,
              model.notificationWarningsEnabled else { return }

        successDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(2_500))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  case .succeeded = model.cellularLaunchState else {
                return
            }
            model.finishCellularLaunch()
        }
    }
}

private struct StepPresentation {
    let symbol: String
    let color: Color
    let title: String
    let message: String
    let showsActivity: Bool
    var activityLabel: String = "Working"
}
