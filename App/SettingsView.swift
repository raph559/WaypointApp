import Foundation
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var settings: WaypointSettingsStore
    let client: WaypointControlClient
    let keychain: WaypointKeychain

    @Environment(\.dismiss) private var dismiss
    @State private var showingPairing = false
    @State private var isTestingConnection = false
    @State private var isSendingManualCoordinate = false
    @State private var healthMessage: String?
    @State private var settingsError: String?
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var labelText = ""

    var body: some View {
        NavigationStack {
            Form {
                pairingSection
                connectionSection
                manualCoordinateSection

                if let settingsError {
                    Section {
                        Text(settingsError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadLastCoordinate)
            .sheet(isPresented: $showingPairing) {
                PairingView(settings: settings, client: client)
            }
        }
    }

    private var pairingSection: some View {
        Section {
            if settings.isPaired {
                LabeledContent("Server", value: settings.serverURL)
                LabeledContent("Client ID", value: settings.clientID)
                LabeledContent("Client Name", value: settings.clientName.isEmpty ? "Unnamed" : settings.clientName)
            } else {
                Text("No Waypoint server is paired.")
                    .foregroundStyle(.secondary)
            }

            Button {
                showingPairing = true
            } label: {
                Label(settings.isPaired ? "Change Pairing" : "Pair Device", systemImage: "qrcode")
            }

            if settings.isPaired {
                Button(role: .destructive) {
                    forgetPairing()
                } label: {
                    Label("Forget Pairing", systemImage: "trash")
                }
            }
        } header: {
            Text("Pairing")
        }
    }

    private var connectionSection: some View {
        Section {
            Button {
                Task {
                    await testConnection()
                }
            } label: {
                if isTestingConnection {
                    HStack {
                        ProgressView()
                        Text("Testing Connection")
                    }
                } else {
                    Label("Test Connection", systemImage: "heart.text.square")
                }
            }
            .disabled(isTestingConnection || !settings.isPaired)

            if let healthMessage {
                Text(healthMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Server Health")
        } footer: {
            Text("Checks the paired server with /v1/health.")
        }
    }

    private var manualCoordinateSection: some View {
        Section {
            TextField("Latitude", text: $latitudeText)
                .keyboardType(.numbersAndPunctuation)

            TextField("Longitude", text: $longitudeText)
                .keyboardType(.numbersAndPunctuation)

            TextField("Label", text: $labelText)
                .textInputAutocapitalization(.words)

            Button {
                Task {
                    await sendManualCoordinate()
                }
            } label: {
                if isSendingManualCoordinate {
                    HStack {
                        ProgressView()
                        Text("Setting Location")
                    }
                } else {
                    Label("Set Manual Coordinate", systemImage: "location.fill")
                }
            }
            .disabled(isSendingManualCoordinate || !settings.isPaired)
        } header: {
            Text("Manual Coordinate")
        } footer: {
            Text("Enter decimal degrees and send them directly to the paired Waypoint server.")
        }
    }

    private func loadLastCoordinate() {
        if let latitude = settings.lastLatitude {
            latitudeText = String(format: "%.6f", latitude)
        }

        if let longitude = settings.lastLongitude {
            longitudeText = String(format: "%.6f", longitude)
        }

        labelText = settings.lastLabel ?? ""
    }

    private func testConnection() async {
        isTestingConnection = true
        settingsError = nil
        healthMessage = nil

        do {
            _ = try await client.health()
            healthMessage = "Server healthy."
        } catch {
            settingsError = error.localizedDescription
        }

        isTestingConnection = false
    }

    private func forgetPairing() {
        settingsError = nil
        healthMessage = nil

        do {
            try keychain.deletePrivateKey()
            settings.clearPairing()
            latitudeText = ""
            longitudeText = ""
            labelText = ""
            healthMessage = "Pairing forgotten on this device only."
        } catch {
            settingsError = error.localizedDescription
        }
    }

    private func sendManualCoordinate() async {
        guard let coordinate = manualCoordinate else {
            settingsError = "Enter latitude from -90 to 90 and longitude from -180 to 180."
            return
        }

        isSendingManualCoordinate = true
        settingsError = nil
        healthMessage = nil

        do {
            try await client.setTarget(coordinate)
            healthMessage = "Manual coordinate applied."
        } catch {
            settingsError = error.localizedDescription
        }

        isSendingManualCoordinate = false
    }

    private var manualCoordinate: WaypointCoordinate? {
        guard
            let latitude = parseCoordinate(latitudeText),
            let longitude = parseCoordinate(longitudeText),
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }

        let label = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        return WaypointCoordinate(
            latitude: latitude,
            longitude: longitude,
            label: label.isEmpty ? nil : label
        )
    }

    private func parseCoordinate(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
}

#Preview {
    let settings = WaypointSettingsStore()
    SettingsView(
        settings: settings,
        client: WaypointControlClient(settings: settings),
        keychain: WaypointKeychain()
    )
}
