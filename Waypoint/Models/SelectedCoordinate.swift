import CoreLocation
import Foundation

struct SelectedCoordinate: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coreLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValid: Bool {
        CLLocationCoordinate2DIsValid(coreLocationCoordinate)
            && (-90.0...90.0).contains(latitude)
            && (-180.0...180.0).contains(longitude)
    }
}

