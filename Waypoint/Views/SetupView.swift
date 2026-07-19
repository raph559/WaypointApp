import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingPairingFile = false
    @State private var isSideStoreConfirmationPresented = false

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
                    state: model.tunnelState
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
                .disabled(model.isPreparing || !model.pairingState.isReady)

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
                Toggle("Keep Spoof Active", isOn: $model.backgroundKeepAliveEnabled)
            } header: {
                Text("Reliability")
            } footer: {
                Text("Improves background reliability and may use more battery. Notifications warn if the spoof stops.")
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
        detail(for: model.tunnelState, ready: "Connected", required: "Not checked")
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
