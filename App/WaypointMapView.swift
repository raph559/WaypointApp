import MapKit
import SwiftUI
import UIKit

@MainActor
struct WaypointMapView: View {
    @StateObject private var settings: WaypointSettingsStore
    @StateObject private var search = PlaceSearchViewModel()

    @State private var cameraPosition: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var selectedLabel: String
    @State private var isApplying = false
    @State private var mapMessage: String?
    @State private var mapMessageStyle: MapMessageStyle = .info
    @State private var showingSettings = false
    @FocusState private var searchFocused: Bool

    private let keychain: WaypointKeychain
    private let client: WaypointControlClient

    init() {
        let settings = WaypointSettingsStore()
        let keychain = WaypointKeychain()
        self.init(settings: settings, keychain: keychain)
    }

    init(settings: WaypointSettingsStore, keychain: WaypointKeychain) {
        let initialCoordinate = CLLocationCoordinate2D(
            latitude: settings.lastLatitude ?? 48.8566,
            longitude: settings.lastLongitude ?? 2.3522
        )
        let initialLabel = settings.lastLabel ?? "Waypoint target"

        _settings = StateObject(wrappedValue: settings)
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _selectedLabel = State(initialValue: initialLabel)
        _cameraPosition = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: initialCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        )

        self.keychain = keychain
        self.client = WaypointControlClient(settings: settings, keychain: keychain)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    searchOverlay
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                coordinatePanel
            }
            .navigationTitle("Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, client: client, keychain: keychain)
            }
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                Marker(selectedLabel, systemImage: "mappin.circle.fill", coordinate: selectedCoordinate)
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let coordinate = proxy.convert(value.location, from: .local) else {
                            return
                        }
                        movePin(to: coordinate, label: "Dropped pin", recenter: false)
                    }
            )
        }
    }

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search for a place", text: $search.searchText)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($searchFocused)
                    .submitLabel(.search)

                if search.isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !search.searchText.isEmpty {
                    Button {
                        search.searchText = ""
                        search.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            if !search.completions.isEmpty && searchFocused {
                Divider()
                completionList
            } else if let error = search.errorMessage, searchFocused {
                Divider()
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
    }

    private var completionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(search.completions.enumerated()), id: \.offset) { index, completion in
                    Button {
                        select(completion)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(completion.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < search.completions.count - 1 {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
    }

    private var coordinatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedLabel)
                        .font(.headline)
                        .lineLimit(1)

                    Text("Tap the map to move the pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                statusChip
            }

            HStack(spacing: 12) {
                coordinateReadout(title: "Latitude", value: selectedCoordinate.latitude)
                coordinateReadout(title: "Longitude", value: selectedCoordinate.longitude)
            }

            TextField("Label", text: $selectedLabel)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)

            if let mapMessage {
                Text(mapMessage)
                    .font(.footnote)
                    .foregroundStyle(mapMessageStyle.tint)
            }

            Button {
                Task {
                    await applySelectedCoordinate()
                }
            } label: {
                Label(isApplying ? "Setting Location" : setButtonTitle, systemImage: setButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isApplying)
        }
        .padding(14)
        .background(.regularMaterial)
    }

    private var statusChip: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.14), in: Capsule())
    }

    private func coordinateReadout(title: String, value: CLLocationDegrees) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(format: "%.6f", value))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var status: MapStatus {
        guard settings.isPaired else {
            return .offline
        }

        if isSelectedCoordinateApplied {
            return .applied
        }

        return .paired
    }

    private var isSelectedCoordinateApplied: Bool {
        guard let lastLatitude = settings.lastLatitude, let lastLongitude = settings.lastLongitude else {
            return false
        }

        return abs(lastLatitude - selectedCoordinate.latitude) < 0.000001 &&
            abs(lastLongitude - selectedCoordinate.longitude) < 0.000001
    }

    private var setButtonTitle: String {
        settings.isPaired ? "Set Location" : "Pair in Settings"
    }

    private var setButtonIcon: String {
        settings.isPaired ? "location.fill" : "link"
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        Task {
            do {
                let coordinate = try await search.coordinate(for: completion)
                movePin(
                    to: CLLocationCoordinate2D(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ),
                    label: coordinate.label ?? completion.title,
                    recenter: true
                )
                search.searchText = ""
                search.clearResults()
                searchFocused = false
            } catch {
                mapMessage = error.localizedDescription
                mapMessageStyle = .error
            }
        }
    }

    private func movePin(to coordinate: CLLocationCoordinate2D, label: String, recenter: Bool) {
        selectedCoordinate = coordinate
        selectedLabel = label
        mapMessage = nil
        mapMessageStyle = .info

        guard recenter else {
            return
        }

        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
        }
    }

    private func applySelectedCoordinate() async {
        guard settings.isPaired else {
            showingSettings = true
            return
        }

        isApplying = true
        mapMessage = nil
        mapMessageStyle = .info

        let coordinate = WaypointCoordinate(
            latitude: selectedCoordinate.latitude,
            longitude: selectedCoordinate.longitude,
            label: selectedLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        do {
            try await client.setTarget(coordinate)
            mapMessage = "Location applied to the paired Waypoint server."
            mapMessageStyle = .success
        } catch {
            mapMessage = error.localizedDescription
            mapMessageStyle = .error
        }

        isApplying = false
    }
}

private enum MapStatus {
    case offline
    case paired
    case applied

    var title: String {
        switch self {
        case .offline:
            return "Offline"
        case .paired:
            return "Paired"
        case .applied:
            return "Applied"
        }
    }

    var systemImage: String {
        switch self {
        case .offline:
            return "wifi.slash"
        case .paired:
            return "link"
        case .applied:
            return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .offline:
            return .red
        case .paired:
            return .blue
        case .applied:
            return .green
        }
    }
}

private enum MapMessageStyle {
    case info
    case success
    case error

    var tint: Color {
        switch self {
        case .info:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    WaypointMapView()
}
