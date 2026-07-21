import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct CellularStartView: View {
    @EnvironmentObject var model: AppModel

    @State var isChoosingPairingFile = false
    @State var isSideStoreConfirmationPresented = false
    @State private var successDismissTask: Task<Void, Never>?

    let localDevVPNAppStoreURL = URL(string: "https://apps.apple.com/app/id6755608044")!

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
        .onChange(of: model.disconnectAlertsEnabled) { _, _ in
            updateSuccessDismissal()
        }
        .onDisappear {
            successDismissTask?.cancel()
            successDismissTask = nil
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
