import SwiftUI

@main
struct WaypointApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.handleIncomingURL($0) }
                .task { model.refreshLocalState() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.applicationBecameActive()
                    }
                }
        }
    }
}

