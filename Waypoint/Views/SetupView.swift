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
                Group {
                    if model.isSideStoreAvailable {
                        Menu {
                            Button {
                                isChoosingPairingFile = true
                            } label: {
                                Label("Choose Pairing File", systemImage: "folder")
                            }

                            Button {
                                isSideStoreConfirmationPresented = true
                            } label: {
                                Label("Import with SideStore", systemImage: "arrow.up.forward.app")
                            }
                        } label: {
                            pairingImportLabel
                        }
                    } else {
                        Button {
                            isChoosingPairingFile = true
                        } label: {
                            pairingImportLabel
                        }
                    }
                }
                .disabled(model.isPreparing || model.simulatedCoordinate != nil)

                if !model.isLocalDevVPNInstalled {
                    Link(destination: localDevVPNAppStoreURL) {
                        Label("Install LocalDevVPN", systemImage: "arrow.down.app.fill")
                    }
                }
            } header: {
                Text("Device Setup")
            } footer: {
                Text(model.isSideStoreAvailable ? "Files is recommended. SideStore is optional." : "Import a pairing record created for this iPhone.")
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
            } header: {
                Text("Alerts")
            } footer: {
                Text("Warns you if Waypoint can no longer confirm the spoof.")
            }

            Section {
                Toggle("Keep Spoof Active", isOn: $model.backgroundKeepAliveEnabled)
            } header: {
                Text("Background")
            } footer: {
                Text("Helps maintain the spoof when you switch apps. Uses more battery.")
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
            "Import with SideStore?",
            isPresented: $isSideStoreConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Open SideStore") {
                model.requestPairingFromSideStore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SideStore passes the pairing record through a callback URL that may appear in its logs. Use Choose Pairing File for better privacy.")
        }
    }

    private var pairingImportLabel: some View {
        Label(
            model.pairingState.isReady ? "Replace Pairing Record" : "Import Pairing Record",
            systemImage: "doc.badge.plus"
        )
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
