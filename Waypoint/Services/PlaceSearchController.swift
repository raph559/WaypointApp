import Combine
import MapKit

struct PlaceSuggestion: Identifiable {
    let id = UUID()
    let completion: MKLocalSearchCompletion

    var title: String { completion.title }
    var subtitle: String { completion.subtitle }
}

@MainActor
final class PlaceSearchController: NSObject, ObservableObject {
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var isCompleting = false
    @Published private(set) var completionFailed = false

    private let completer = MKLocalSearchCompleter()
    private var currentSearch: MKLocalSearch?
    private var currentQuery = ""

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func update(query: String, region: MKCoordinateRegion) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        completer.region = region

        guard !query.isEmpty else {
            clearSuggestions()
            return
        }

        currentQuery = query
        completionFailed = false
        isCompleting = true
        completer.queryFragment = query
    }

    func update(region: MKCoordinateRegion) {
        completer.region = region
    }

    func clearSuggestions() {
        currentQuery = ""
        completer.cancel()
        completer.queryFragment = ""
        suggestions = []
        isCompleting = false
        completionFailed = false
    }

    func cancelAll() {
        clearSuggestions()
        currentSearch?.cancel()
        currentSearch = nil
    }

    func resolve(_ suggestion: PlaceSuggestion, region: MKCoordinateRegion) async throws -> MKMapItem {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        request.region = region
        return try await firstMapItem(for: request)
    }

    func resolve(query: String, region: MKCoordinateRegion) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        return try await firstMapItem(for: request)
    }

    private func firstMapItem(for request: MKLocalSearch.Request) async throws -> MKMapItem {
        currentSearch?.cancel()

        let search = MKLocalSearch(request: request)
        currentSearch = search
        defer {
            if currentSearch === search {
                currentSearch = nil
            }
        }

        let response = try await search.start()
        try Task.checkCancellation()

        guard let item = response.mapItems.first else {
            throw PlaceSearchError.noResults
        }
        return item
    }
}

extension PlaceSearchController: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let query = completer.queryFragment
        let results = completer.results
        Task { @MainActor [weak self] in
            guard let self, currentQuery == query else { return }
            suggestions = results.prefix(8).map(PlaceSuggestion.init)
            isCompleting = false
            completionFailed = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let query = completer.queryFragment
        Task { @MainActor [weak self] in
            guard let self, currentQuery == query else { return }
            suggestions = []
            isCompleting = false
            completionFailed = true
        }
    }
}

enum PlaceSearchError: LocalizedError {
    case noResults

    var errorDescription: String? {
        "No matching place was found."
    }
}
