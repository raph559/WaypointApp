import Foundation

enum SimulationEventKind: Equatable {
    case started
    case moved
    case stopped
    case connectionLost
}

struct SimulationEvent: Identifiable, Equatable {
    let id = UUID()
    let kind: SimulationEventKind
    let coordinate: SelectedCoordinate?

    var title: String {
        switch kind {
        case .started: return "Spoof started"
        case .moved: return "Spoof moved"
        case .stopped: return "Spoof stopped"
        case .connectionLost: return "Spoof connection lost"
        }
    }

    var detail: String {
        if let coordinate {
            return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        }

        switch kind {
        case .stopped: return "Real GPS restored"
        case .connectionLost: return "Open Waypoint to reconnect"
        case .started, .moved: return "Location updated"
        }
    }

    var accessibilityAnnouncement: String {
        "\(title). \(detail)."
    }
}
