import MapKit
import SwiftUI

@MainActor
struct MapSpoofView: View {
    @EnvironmentObject private var model: AppModel

    @StateObject private var placeSearch = PlaceSearchController()
    @State private var selection: SelectedCoordinate
    @State private var cameraPosition: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isSearchPresented = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchOperationID: UUID?
    @State private var displayedEvent: SimulationEvent?
    @State private var eventDismissTask: Task<Void, Never>?

    private static let storedCoordinateKey = "selectedCoordinate"
    private static let defaultCoordinate = SelectedCoordinate(latitude: 48.8566, longitude: 2.3522)

    init() {
        let initial = Self.loadStoredCoordinate() ?? Self.defaultCoordinate
        let region = MKCoordinateRegion(
            center: initial.coreLocationCoordinate,
            latitudinalMeters: 6_000,
            longitudinalMeters: 6_000
        )

        _selection = State(initialValue: initial)
        _cameraPosition = State(initialValue: .region(region))
        _visibleRegion = State(initialValue: region)
    }

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 9) {
                if let event = displayedEvent {
                    eventBanner(event)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let active = model.simulatedCoordinate {
                    activeBanner(active)
                        .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal)
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
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search a place or address"
        ) {
            searchSuggestions
        }
        .onSubmit(of: .search) {
            searchSubmittedText()
        }
        .onChange(of: searchText) { _, query in
            guard isSearchPresented else { return }

            if isSearching {
                searchTask?.cancel()
                placeSearch.cancelAll()
                searchOperationID = nil
                isSearching = false
            }
            placeSearch.update(query: query, region: visibleRegion)
        }
        .onChange(of: isSearchPresented) { _, presented in
            if presented {
                placeSearch.update(query: searchText, region: visibleRegion)
            } else {
                placeSearch.clearSuggestions()
            }
        }
        .onChange(of: selection) { _, coordinate in
            Self.store(coordinate)
        }
        .onChange(of: model.simulationEvent) { _, event in
            show(event)
        }
        .onDisappear {
            searchTask?.cancel()
            eventDismissTask?.cancel()
            placeSearch.cancelAll()
        }
    }

    private var searchSuggestions: some View {
        Group {
            if placeSearch.isCompleting && placeSearch.suggestions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding places…")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(placeSearch.suggestions) { suggestion in
                Button {
                    selectSuggestion(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.red)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)

                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if placeSearch.completionFailed,
               !searchText.isEmpty,
               placeSearch.suggestions.isEmpty {
                Label("Suggestions temporarily unavailable", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
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
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                placeSearch.update(region: context.region)
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

    private func eventBanner(_ event: SimulationEvent) -> some View {
        HStack(spacing: 11) {
            Image(systemName: eventSymbol(event.kind))
                .font(.headline)
                .foregroundStyle(eventColor(event.kind))
                .frame(width: 28, height: 28)
                .background(eventColor(event.kind).opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
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

    private func eventSymbol(_ kind: SimulationEventKind) -> String {
        switch kind {
        case .started: return "location.fill"
        case .moved: return "mappin.and.ellipse"
        case .stopped: return "location.slash.fill"
        case .connectionLost: return "exclamationmark.triangle.fill"
        }
    }

    private func eventColor(_ kind: SimulationEventKind) -> Color {
        switch kind {
        case .started: return .green
        case .moved: return .blue
        case .stopped: return .gray
        case .connectionLost: return .red
        }
    }

    private func show(_ event: SimulationEvent?) {
        guard let event else { return }
        eventDismissTask?.cancel()

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            displayedEvent = event
        }

        eventDismissTask = Task {
            try? await Task.sleep(for: .seconds(event.kind == .connectionLost ? 4 : 2.6))
            guard !Task.isCancelled, displayedEvent?.id == event.id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                displayedEvent = nil
            }
        }
    }

    private func searchSubmittedText() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        beginSearch(fallbackName: query) {
            try await placeSearch.resolve(query: query, region: visibleRegion)
        }
    }

    private func selectSuggestion(_ suggestion: PlaceSuggestion) {
        let region = visibleRegion
        beginSearch(fallbackName: suggestion.title) {
            try await placeSearch.resolve(suggestion, region: region)
        }
    }

    private func beginSearch(
        fallbackName: String,
        operation: @escaping @MainActor () async throws -> MKMapItem
    ) {
        searchTask?.cancel()
        placeSearch.cancelAll()

        let operationID = UUID()
        searchOperationID = operationID
        isSearching = true

        searchTask = Task { @MainActor in
            defer {
                if searchOperationID == operationID {
                    searchOperationID = nil
                    isSearching = false
                }
            }

            do {
                let item = try await operation()
                try Task.checkCancellation()
                guard searchOperationID == operationID else { return }

                let coordinate = item.placemark.coordinate
                select(coordinate)

                withAnimation(.easeInOut(duration: 0.35)) {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            latitudinalMeters: 2_000,
                            longitudinalMeters: 2_000
                        )
                    )
                }

                isSearchPresented = false
                searchText = item.name ?? fallbackName
                placeSearch.clearSuggestions()
            } catch {
                guard !Task.isCancelled else { return }
                model.showError(title: "Search Failed", error: error)
            }
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
