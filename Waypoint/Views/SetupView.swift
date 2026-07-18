import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChoosingPairingFile = false

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
                    title: "Pairing file",
                    detail: pairingDetail,
                    state: model.pairingState
                )
                setupRow(
                    title: "LocalDevVPN",
                    detail: tunnelDetail,
                    state: model.tunnelState
                )
                setupRow(
                    title: "Developer image",
                    detail: developerImageDetail,
                    state: model.developerImageState
                )
            } header: {
                Text("Device readiness")
            } footer: {
                Text("Developer Mode must be enabled. LocalDevVPN stays on-device; it gives Waypoint a loopback path to Apple's developer service.")
            }

            Section(model.pairingState.isReady ? "1. Replace pairing" : "1. Import pairing") {
                Button {
                    isChoosingPairingFile = true
                } label: {
                    Label(
                        model.pairingState.isReady ? "Replace from Files" : "Choose pairing file",
                        systemImage: "doc.badge.plus"
                    )
                }
                .disabled(model.simulatedCoordinate != nil)

                Button {
                    model.requestPairingFromSideStore()
                } label: {
                    Label("Direct SideStore callback", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.simulatedCoordinate != nil)

                Text("Files import is safer. SideStore's direct callback places the pairing record in a custom URL and may include it in SideStore debug logs; use it only if you accept that risk.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("2. Connect and prepare") {
                Text("Connect LocalDevVPN first, then return here. The first preparation downloads Apple's personalized developer image files; after a reboot, prepare again to remount them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await model.prepareDevice() }
                } label: {
                    HStack {
                        Label(
                            model.isReady ? "Check again" : "Prepare device",
                            systemImage: model.isReady ? "checkmark.shield" : "wrench.and.screwdriver"
                        )
                        Spacer()
                        if model.isPreparing { ProgressView() }
                    }
                }
                .disabled(model.isPreparing || !model.pairingState.isReady)

                if !model.preparationMessage.isEmpty {
                    Text(model.preparationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Remove downloaded developer image", role: .destructive) {
                    model.resetDeveloperImage()
                }
                .disabled(model.isPreparing || model.simulatedCoordinate != nil)
            }

            Section("Background reliability") {
                Toggle("Keep simulation alive", isOn: $model.backgroundKeepAliveEnabled)
                Text("While spoofing, Waypoint can use low-accuracy location updates and silent, mixed audio to keep the developer connection alive after you switch apps. iOS may show location activity and this uses extra battery.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label("Connection-loss notifications", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.medium))
                Text("Allow notifications when first starting a spoof. Waypoint will warn if its heartbeat stops for about 30 seconds or if it detects that the developer connection ended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Done") { dismiss() }
                    .disabled(!model.isReady)
            }
        }
        .navigationTitle("Set up Waypoint")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!model.isReady)
        .fileImporter(
            isPresented: $isChoosingPairingFile,
            allowedContentTypes: pairingTypes,
            allowsMultipleSelection: false,
            onCompletion: model.importPairingFile
        )
    }

    private var pairingDetail: String {
        detail(for: model.pairingState, ready: "Imported", required: "Choose a pairing file")
    }

    private var tunnelDetail: String {
        detail(for: model.tunnelState, ready: "Connected", required: "Connect LocalDevVPN")
    }

    private var developerImageDetail: String {
        detail(for: model.developerImageState, ready: "Mounted", required: "Prepare after each reboot")
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
