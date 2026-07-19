import Foundation

enum CellularLaunchState: Equatable {
    case idle
    case needsPairing
    case cachingSupportFiles(String)
    case openingLocalDevVPN
    case settlingLocalDevVPN
    case waitingForAirplaneMode
    case preparingDevice
    case startingSpoof
    case handoff
    case succeeded
    case failed(String)

    var canCancelSafely: Bool {
        switch self {
        case .needsPairing, .cachingSupportFiles, .openingLocalDevVPN,
             .settlingLocalDevVPN, .waitingForAirplaneMode, .preparingDevice:
            return true
        case .idle, .startingSpoof, .handoff, .succeeded, .failed:
            return false
        }
    }
}
