import CoreLocation
import MapKit

protocol PlaceResolver: Sendable {
    func resolve(_ query: String) async -> (name: String, coordinate: CLLocationCoordinate2D)?
}

struct LocalSearchResolver: PlaceResolver {
    func resolve(_ query: String) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        return (item.name ?? query, item.placemark.coordinate)
    }
}
