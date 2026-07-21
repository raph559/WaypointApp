import MapKit
import SwiftUI

@MainActor
struct MapSpoofView: View {
    @EnvironmentObject var model: AppModel

    @ObservedObject var pathMonitor = CellularPathMonitor.shared
    @StateObject var placeSearch = PlaceSearchController()
    @State var selection: SelectedCoordinate
    @State var cameraPosition: MapCameraPosition
    @State var visibleRegion: MKCoordinateRegion
    @State var searchText = ""
    @State var isSearching = false
    @State var isSearchPresented = false
    @State var searchTask: Task<Void, Never>?
    @State var searchOperationID: UUID?
    @State var displayedEvent: SimulationEvent?
    @State var eventDismissTask: Task<Void, Never>?
    @State var isCellularHandoffConfirmationPresented = false
    @State var isKeepaliveResumeConfirmationPresented = false

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
        searchAwareContent
            .onChange(of: selection) { _, coordinate in
                Self.store(coordinate)
            }
            .onChange(of: model.simulationEvent) { _, event in
                show(event)
            }
            .onChange(of: model.isCellularHandoffInProgress) { _, isInProgress in
                guard isInProgress else { return }
                searchTask?.cancel()
                searchOperationID = nil
                isSearching = false
                isSearchPresented = false
                placeSearch.cancelAll()
                placeSearch.clearSuggestions()
            }
            .onChange(of: model.isCellularLaunchRunning) { _, isRunning in
                guard isRunning else { return }
                searchTask?.cancel()
                searchOperationID = nil
                isSearching = false
                isSearchPresented = false
                placeSearch.cancelAll()
                placeSearch.clearSuggestions()
            }
            .onDisappear {
                searchTask?.cancel()
                eventDismissTask?.cancel()
                placeSearch.cancelAll()
            }
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
