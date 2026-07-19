import Foundation

enum CellularHandoffState: Equatable {
    case idle
    case arming
    case waiting(secondsRemaining: Int)
    case verifying
    case succeeded
    case failed(String)

    var isInProgress: Bool {
        switch self {
        case .arming, .waiting, .verifying:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }

    var pausesLocationWrites: Bool {
        switch self {
        case .arming, .waiting, .verifying, .failed:
            return true
        case .idle, .succeeded:
            return false
        }
    }
}
