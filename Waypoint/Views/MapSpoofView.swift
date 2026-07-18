import MapKit
import SwiftUI

struct MapSpoofView: View {
    @EnvironmentObject private var model: AppModel

    @State private var selection: SelectedCoordinate
    @State private var cameraPosition: MapCameraPosition
    @State private var searchText = ""
    @State private var isSearching = false

    private static let storedCoordinateKey = "selectedCoordinate"
    private static let defaultCoordinate = SelectedCoordinate(latitude: 48.8566, longitude: 2.3522)

    init() {
        let initial = Self.loadStoredCoordinate() ?? Self.defaultCoordinate
        _selection = State(initialValue: initial)
        _cameraPosition = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: initial.coreLocationCoordinate,
                    latitudinalMeters: 6_000,
                    longitudinalMeters: 6_000
                )
            )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea(edges: .bottom)

            if let active = model.simulatedCoordinate {
                activeBanner(active)
                    .padding(.top, 8)
                    .padding(.horizontal)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .navigationTitle("Waypoint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.isSetupPresented = true
                } label: {
                    Image(systemName: model.isReady ? "checkmark.shield.fill" : "gearshape.fill")
                        .foregroundStyle(model.isReady ? .green : .primary)
                }
                .accessibilityLabel("Device setup")
            }
        }
        .searchable(text: $searchText, prompt: "Search a place or address")
        .onSubmit(of: .search) {
            Task { await search() }
        }
        .onChange(of: selection) { _, coordinate in
            Self.store(coordinate)
        }
    }

    private var map: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: .all) {
                if let active = model.simulatedCoordinate,
                   active != selection {
                    Marker("Active spoof", coordinate: active.coreLocationCoordinate)
                        .tint(.blue)
                }

                Annotation("Selected location", coordinate: selection.coreLocationCoordinate, anchor: .bottom) {
                    draggablePin(proxy: proxy)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .coordinateSpace(name: "WaypointMap")
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                select(coordinate)
            }
        }
    }

    private func draggablePin(proxy: MapProxy) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, .white)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("WaypointMap"))
                .onChanged { value in
                    guard let coordinate = proxy.convert(value.location, from: .named("WaypointMap")) else { return }
                    select(coordinate)
                }
        )
        .accessibilityLabel("Selected location pin")
        .accessibilityHint("Drag to choose a simulated location")
    }

    private var controls: some View {
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
                    if model.isReady {
                        Task { await model.startSimulation(at: selection) }
                    } else {
                        model.isSetupPresented = true
                    }
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isChangingSimulation)

                if model.simulatedCoordinate != nil {
                    Button(role: .destructive) {
                        Task { await model.stopSimulation() }
                    } label: {
                        Label("Stop", systemImage: "location.slash.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isChangingSimulation)
                }
            }

            if model.simulatedCoordinate != nil {
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

    private var primaryButtonTitle: String {
        if !model.isReady { return "Set up device" }
        if model.simulatedCoordinate != nil { return "Move spoof here" }
        return "Start spoofing"
    }

    private var primaryButtonSymbol: String {
        if !model.isReady { return "gearshape.fill" }
        return model.simulatedCoordinate == nil ? "location.fill" : "mappin.and.ellipse"
    }

    private func activeBanner(_ coordinate: SelectedCoordinate) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
            Text("Spoofing \(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate else {
                throw MapSearchError.noResults
            }

            select(coordinate)
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 2_000,
                    longitudinalMeters: 2_000
                )
            )
        } catch {
            model.showError(title: "Search Failed", error: error)
        }
    }

    private func select(_ coordinate: CLLocationCoordinate2D) {
        let value = SelectedCoordinate(coordinate)
        guard value.isValid else { return }
        selection = value
    }

    private static func loadStoredCoordinate() -> SelectedCoordinate? {
        guard let data = UserDefaults.standard.data(forKey: storedCoordinateKey),
              let coordinate = try? JSONDecoder().decode(SelectedCoordinate.self, from: data),
              coordinate.isValid else {
            return nil
        }
        return coordinate
    }

    private static func store(_ coordinate: SelectedCoordinate) {
        guard let data = try? JSONEncoder().encode(coordinate) else { return }
        UserDefaults.standard.set(data, forKey: storedCoordinateKey)
    }
}

private enum MapSearchError: LocalizedError {
    case noResults

    var errorDescription: String? {
        "No matching place was found."
    }
}
