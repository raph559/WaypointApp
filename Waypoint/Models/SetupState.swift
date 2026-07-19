import Foundation

enum SetupCheckState: Equatable {
    case required
    case checking
    case ready
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

