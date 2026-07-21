import SwiftUI

extension MapSpoofView {
    var controls: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.6f, %.6f", selection.latitude, selection.longitude))
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .contentTransition(.numericText())
                }

                Spacer()

                if isSearching {
                    ProgressView()
                }
            }

            HStack(spacing: 10) {
                Button {
                    if model.simulatedCoordinate != nil {
                        Task { await model.startSimulation(at: selection) }
                    } else {
                        model.beginAdaptiveLaunch(at: selection)
                    }
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    model.isChangingSimulation ||
                    model.isPreparing ||
                    (model.simulatedCoordinate == nil && !hasUsableConnection) ||
                    model.areLocationWritesPausedForCellularHandoff ||
                    model.isCellularLaunchRunning
                )

                if model.simulatedCoordinate != nil {
                    Button(role: .destructive) {
                        Task { await model.stopSimulation() }
                    } label: {
                        Label("Stop", systemImage: "location.slash.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isChangingSimulation || model.isCellularLaunchRunning)
                }
            }

            if model.simulatedCoordinate != nil {
                cellularHandoffControl

                Text("Background keepalive is \(model.backgroundKeepAliveEnabled ? "on" : "off"). Stop restores the device's real GPS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var cellularHandoffControl: some View {
        switch model.cellularHandoffState {
        case .idle:
            Button {
                isCellularHandoffConfirmationPresented = true
            } label: {
                Label("Switch to mobile data", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isChangingSimulation)

        case .arming:
            HStack(spacing: 12) {
                ProgressView()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Preparing the retained session…")
                        .font(.subheadline.weight(.semibold))
                    Text("Keep Airplane Mode on and Wi-Fi off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Cancel") {
                    model.cancelCellularHandoff()
                }
                .buttonStyle(.borderless)
            }

        case .waiting(let secondsRemaining):
            HStack(spacing: 12) {
                ProgressView()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn Airplane Mode off now")
                        .font(.subheadline.weight(.semibold))
                    Text("Keep Wi-Fi off • up to \(secondsRemaining)s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Cancel") {
                    model.cancelCellularHandoff()
                }
                .buttonStyle(.borderless)
            }

        case .verifying:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking the retained developer session…")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }

        case .succeeded:
            Label("Cellular-only handoff passed", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Button("Try cellular handoff again") {
                    isCellularHandoffConfirmationPresented = true
                }
                .buttonStyle(.bordered)

                Button("Resume normal keepalive") {
                    isKeepaliveResumeConfirmationPresented = true
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var primaryButtonTitle: String {
        if model.simulatedCoordinate != nil { return "Move spoof here" }
        switch pathMonitor.activeConnection {
        case .wifi:
            return "Start spoofing"
        case .cellular:
            return "Start on mobile data"
        case .unknown:
            return "Checking connection…"
        case .offline:
            return "No connection"
        }
    }

    private var primaryButtonSymbol: String {
        if model.simulatedCoordinate != nil { return "mappin.and.ellipse" }
        switch pathMonitor.activeConnection {
        case .wifi:
            return "location.fill"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .unknown:
            return "network"
        case .offline:
            return "wifi.slash"
        }
    }

    private var hasUsableConnection: Bool {
        switch pathMonitor.activeConnection {
        case .wifi, .cellular:
            return true
        case .unknown, .offline:
            return false
        }
    }
}
