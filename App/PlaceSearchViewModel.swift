import Combine
import Foundation
import MapKit

final class PlaceSearchViewModel: NSObject, ObservableObject {
    @Published var searchText: String = "" {
        didSet {
            updateQueryFragment()
        }
    }

    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    @MainActor
    func coordinate(for completion: MKLocalSearchCompletion) async throws -> WaypointCoordinate {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()

        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noResults
        }

        let coordinate = item.placemark.coordinate
        let label = label(for: item, fallback: completion.title)
        return WaypointCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            label: label
        )
    }

    func clearResults() {
        completions = []
        errorMessage = nil
    }

    private func updateQueryFragment() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil

        guard !trimmed.isEmpty else {
            completer.queryFragment = ""
            completions = []
            isSearching = false
            return
        }

        isSearching = true
        completer.queryFragment = trimmed
    }

    private func label(for item: MKMapItem, fallback: String) -> String {
        if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        if let title = item.placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        return fallback
    }
}

extension PlaceSearchViewModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        DispatchQueue.main.async { [weak self] in
            self?.completions = results
            self?.isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.completions = []
            self?.isSearching = false
            self?.errorMessage = error.localizedDescription
        }
    }
}

enum PlaceSearchError: LocalizedError {
    case noResults

    var errorDescription: String? {
        switch self {
        case .noResults:
            return "No matching place was found."
        }
    }
}
