import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingPairingFile = false
    @State private var isSideStoreConfirmationPresented = false

    private let localDevVPNAppStoreURL = URL(string: "https://apps.apple.com/app/id6755608044")!

    private let pairingTypes: [UTType] = [
        UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
        UTType(filenameExtension: "mobiledevicepair", conformingTo: .data)!,
        .propertyList,
        .json,
        .data
    ]

    var body: some View {
        List {
            Section {
                setupRow(
                    title: "Pairing Record",
                    detail: pairingDetail,
                    state: model.pairingState
                )
                setupRow(
                    title: "LocalDevVPN",
                    detail: tunnelDetail,
                    state: localDevVPNState
                )
                setupRow(
                    title: "Developer Support",
                    detail: developerImageDetail,
                    state: model.developerImageState
                )
            } header: {
                Text("Status")
            }

            Section {
                Menu {
                    Button {
                        isChoosingPairingFile = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }

                    Button {
                        isSideStoreConfirmationPresented = true
                    } label: {
                        Label("Import from SideStore", systemImage: "arrow.up.forward.app")
                    }
                } label: {
                    Label(
                        model.pairingState.isReady ? "Replace Pairing Record" : "Import Pairing Record",
                        systemImage: "doc.badge.plus"
                    )
                }
                .disabled(model.isPreparing || model.simulatedCoordinate != nil)

                if !model.isLocalDevVPNInstalled {
                    Link(destination: localDevVPNAppStoreURL) {
                        Label("Install LocalDevVPN", systemImage: "arrow.down.app.fill")
                    }
                }

                Button {
                    Task { await model.prepareDevice() }
                } label: {
                    HStack {
                        Label(
                            model.isReady ? "Check Again" : "Prepare iPhone",
                            systemImage: model.isReady ? "checkmark.shield" : "wrench.and.screwdriver"
                        )
                        Spacer()
                        if model.isPreparing { ProgressView() }
                    }
                }
                .disabled(
                    model.isPreparing ||
                    !model.pairingState.isReady ||
                    !model.isLocalDevVPNInstalled
                )

                if model.isPreparing, !model.preparationMessage.isEmpty {
                    Text(model.preparationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Device Setup")
            } footer: {
                Text("Choose Files for the most private pairing import.")
            }

            Section {
                Toggle(
                    "Notify If Spoof Stops",
                    isOn: Binding(
                        get: { model.disconnectAlertsEnabled },
                        set: { model.setDisconnectAlertsEnabled($0) }
                    )
                )
                .disabled(model.isUpdatingDisconnectAlerts)

                if model.disconnectAlertsDenied {
                    Link(destination: URL(string: UIApplication.openNotificationSettingsURLString)!) {
                        Label("Open Notification Settings", systemImage: "bell.badge")
                    }
                }

                Toggle("Keep Spoof Active", isOn: $model.backgroundKeepAliveEnabled)
            } header: {
                Text("Reliability")
            } footer: {
                Text("Alerts warn you if Waypoint can no longer confirm the spoof.")
            }

            Section {
                Button("Reset Support Files", role: .destructive) {
                    model.resetDeveloperImage()
                }
                .disabled(model.isPreparing || model.simulatedCoordinate != nil)
            } header: {
                Text("Troubleshooting")
            } footer: {
                Text("Use this only if device preparation keeps failing.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .fileImporter(
            isPresented: $isChoosingPairingFile,
            allowedContentTypes: pairingTypes,
            allowsMultipleSelection: false,
            onCompletion: model.importPairingFile
        )
        .confirmationDialog(
            "Import from SideStore?",
            isPresented: $isSideStoreConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Import from SideStore") {
                model.requestPairingFromSideStore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pairing records are sensitive. SideStore sends yours through a callback URL that may appear in debug logs. Choose Files for better privacy.")
        }
    }

    private var pairingDetail: String {
        detail(for: model.pairingState, ready: "Imported", required: "Missing")
    }

    private var tunnelDetail: String {
        detail(for: localDevVPNState, ready: "Connected", required: "Ready to connect")
    }

    private var localDevVPNState: SetupCheckState {
        model.isLocalDevVPNInstalled ? model.tunnelState : .failed("Not installed")
    }

    private var developerImageDetail: String {
        detail(for: model.developerImageState, ready: "Ready", required: "Not checked")
    }

    private func detail(for state: SetupCheckState, ready: String, required: String) -> String {
        switch state {
        case .required: return required
        case .checking: return "Checking…"
        case .ready: return ready
        case .failed(let message): return message
        }
    }

    private func setupRow(title: String, detail: String, state: SetupCheckState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(for: state))
                .foregroundStyle(color(for: state))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 2)
    }

    private func symbol(for state: SetupCheckState) -> String {
        switch state {
        case .required: return "circle"
        case .checking: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for state: SetupCheckState) -> Color {
        switch state {
        case .required: return .secondary
        case .checking: return .blue
        case .ready: return .green
        case .failed: return .orange
        }
    }
}
