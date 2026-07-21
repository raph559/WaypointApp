import SwiftUI
import UIKit

extension CellularStartView {
    var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index <= progressIndex ? presentation.color : Color.secondary.opacity(0.18))
                    .frame(width: index == progressIndex ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: progressIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start progress")
        .accessibilityValue("Step \(progressIndex + 1) of 3")
    }

    @ViewBuilder
    var actions: some View {
        switch model.cellularLaunchState {
        case .needsLocalDevVPN:
            VStack(spacing: 11) {
                Link(destination: localDevVPNAppStoreURL) {
                    Label("Install LocalDevVPN", systemImage: "arrow.down.app.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    model.checkLocalDevVPNInstallation()
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

        case .needsPairing:
            VStack(spacing: 11) {
                Button {
                    isChoosingPairingFile = true
                } label: {
                    Label("Choose Pairing File", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isPreparing)

                if model.isSideStoreAvailable {
                    Button {
                        isSideStoreConfirmationPresented = true
                    } label: {
                        Label("Import with SideStore", systemImage: "arrow.up.forward.app.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isPreparing)
                }

                if model.isPreparing {
                    ProgressView("Importing pairing record…")
                        .font(.footnote)
                }

                Text(model.isSideStoreAvailable
                    ? "Use a pairing file created for this iPhone. SideStore is optional."
                    : "Use a pairing file created for this iPhone.")
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

                Link(destination: localDevVPNAppStoreURL) {
                    Label("View LocalDevVPN in App Store", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

        case .succeeded:
            if !model.notificationWarningsEnabled {
                if model.disconnectAlertsDenied {
                    Link(destination: URL(string: UIApplication.openNotificationSettingsURLString)!) {
                        Label("Open Notification Settings", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        model.setDisconnectAlertsEnabled(true)
                    } label: {
                        Label("Enable Disconnect Alerts", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isUpdatingDisconnectAlerts)
                }
            }

        default:
            EmptyView()
        }
    }
}
