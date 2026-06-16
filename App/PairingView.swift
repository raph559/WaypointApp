import SwiftUI
import UIKit

@MainActor
struct PairingView: View {
    @ObservedObject var settings: WaypointSettingsStore
    let client: WaypointControlClient

    @Environment(\.dismiss) private var dismiss
    @State private var serverURLText: String
    @State private var pairingCodeText = ""
    @State private var clientNameText: String
    @State private var isPairing = false
    @State private var showingScanner = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var qrExpiresAt: String?

    init(settings: WaypointSettingsStore, client: WaypointControlClient) {
        self.settings = settings
        self.client = client
        _serverURLText = State(initialValue: settings.serverURL)
        _clientNameText = State(initialValue: settings.clientName.isEmpty ? UIDevice.current.name : settings.clientName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan Pairing QR", systemImage: "qrcode.viewfinder")
                    }

                    TextField("https://waypoint.example.com", text: $serverURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    TextField("Pairing code", text: $pairingCodeText)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)

                    TextField("Client name", text: $clientNameText)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Pairing")
                } footer: {
                    if let qrExpiresAt {
                        Text("QR expires at \(qrExpiresAt).")
                    } else {
                        Text("Scan the VPS pairing QR or enter the server URL and pairing code manually.")
                    }
                }

                Section {
                    Button {
                        Task {
                            await pair()
                        }
                    } label: {
                        if isPairing {
                            HStack {
                                ProgressView()
                                Text("Pairing")
                            }
                        } else {
                            Label("Pair Device", systemImage: "link")
                        }
                    }
                    .disabled(isPairing || !canPair)
                }

                if let successMessage {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Pair Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                QRCodeScannerView { scannedValue in
                    parseQRCode(scannedValue)
                }
            }
        }
    }

    private var canPair: Bool {
        !serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !pairingCodeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !clientNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func parseQRCode(_ value: String) {
        errorMessage = nil
        successMessage = nil

        guard let data = value.data(using: .utf8) else {
            errorMessage = "The QR code is not valid UTF-8 text."
            return
        }

        do {
            let payload = try JSONDecoder().decode(WaypointPairingPayload.self, from: data)
            serverURLText = payload.serverURL
            pairingCodeText = payload.code
            qrExpiresAt = payload.expiresAt
        } catch {
            errorMessage = "The QR code is not a valid Waypoint pairing payload."
        }
    }

    private func pair() async {
        guard
            let serverURL = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            errorMessage = "Enter a valid server URL."
            return
        }

        isPairing = true
        errorMessage = nil
        successMessage = nil
        let normalizedCode = pairingCodeText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        pairingCodeText = normalizedCode

        do {
            try await client.pair(
                serverURL: serverURL,
                code: normalizedCode,
                clientName: clientNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            successMessage = "Pairing complete."
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isPairing = false
    }
}

#Preview {
    let settings = WaypointSettingsStore()
    PairingView(settings: settings, client: WaypointControlClient(settings: settings))
}
