import MapKit
import SwiftUI

extension MapSpoofView {
    func eventBanner(_ event: SimulationEvent) -> some View {
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

    func activeBanner(_ coordinate: SelectedCoordinate) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(activeStatusColor)
                .frame(width: 9, height: 9)
            Text(activeStatusText(for: coordinate))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var activeStatusColor: Color {
        switch model.cellularHandoffState {
        case .arming, .waiting, .verifying, .failed:
            return .orange
        case .idle, .succeeded:
            return .red
        }
    }

    private func activeStatusText(for coordinate: SelectedCoordinate) -> String {
        let formatted = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        switch model.cellularHandoffState {
        case .arming, .waiting, .verifying:
            return "Switching to mobile data…"
        case .failed:
            return "Spoof unverified — updates paused"
        case .succeeded:
            return "Spoofing on mobile data · \(formatted)"
        case .idle:
            return "Spoofing \(formatted)"
        }
    }

    private func eventSymbol(_ kind: SimulationEventKind) -> String {
        switch kind {
        case .started: return "location.fill"
        case .moved: return "mappin.and.ellipse"
        case .cellularReady: return "checkmark.circle.fill"
        case .stopped: return "location.slash.fill"
        case .connectionLost: return "exclamationmark.triangle.fill"
        }
    }

    private func eventColor(_ kind: SimulationEventKind) -> Color {
        switch kind {
        case .started: return .green
        case .moved: return .blue
        case .cellularReady: return .green
        case .stopped: return .gray
        case .connectionLost: return .red
        }
    }

    func show(_ event: SimulationEvent?) {
        guard let event else { return }
        eventDismissTask?.cancel()

        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            displayedEvent = event
        }

        eventDismissTask = Task {
            let duration: TimeInterval
            switch event.kind {
            case .cellularReady:
                duration = 5
            case .connectionLost:
                duration = 4
            case .started, .moved, .stopped:
                duration = 2.6
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, displayedEvent?.id == event.id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                displayedEvent = nil
            }
        }
    }

    func searchSubmittedText() {
        guard !model.isCellularHandoffInProgress,
              !model.isCellularLaunchRunning else { return }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        beginSearch(fallbackName: query) {
            try await placeSearch.resolve(query: query, region: visibleRegion)
        }
    }

    func selectSuggestion(_ suggestion: PlaceSuggestion) {
        guard !model.isCellularHandoffInProgress,
              !model.isCellularLaunchRunning else { return }
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

    func select(_ coordinate: CLLocationCoordinate2D) {
        guard !model.isCellularHandoffInProgress,
              !model.isCellularLaunchRunning else { return }
        let value = SelectedCoordinate(coordinate)
        guard value.isValid else { return }
        selection = value
    }
}
