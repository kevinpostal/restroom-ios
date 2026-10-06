import CoreLocation
import MapKit

/// Parks and campgrounds near a point; they usually have a public restroom, so they ride along with Refuge results.
protocol PlaceProvider: Sendable {
    func places(near center: CLLocationCoordinate2D, radius: CLLocationDistance) async throws -> [Restroom]
}

/// Apple's POI index via `MKLocalPointsOfInterestRequest`: free, keyless, and fast. Items are turned into
/// `Restroom`s with `kind` .park/.campground and a stable negative id (never collides with Refuge's).
struct ParkPlaces: PlaceProvider {
    func places(near center: CLLocationCoordinate2D, radius: CLLocationDistance) async throws -> [Restroom] {
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park, .nationalPark, .campground])
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap(Self.restroom)
    }

    static func restroom(_ item: MKMapItem) -> Restroom? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let c = item.placemark.coordinate
        let kind: Restroom.Kind = item.pointOfInterestCategory == .campground ? .campground : .park
        return Restroom(id: Self.id(name: name, coordinate: c), name: name,
                        street: item.placemark.thoroughfare.map { [item.placemark.subThoroughfare, $0].compactMap { $0 }.joined(separator: " ") } ?? "",
                        city: item.placemark.locality ?? "", state: item.placemark.administrativeArea ?? "",
                        latitude: c.latitude, longitude: c.longitude, kind: kind)
    }

    /// Deterministic across launches (Swift's `hashValue` is seeded per process): FNV-1a over name + rounded coords.
    static func id(name: String, coordinate: CLLocationCoordinate2D) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in "\(name)|\(Int(coordinate.latitude * 1e5))|\(Int(coordinate.longitude * 1e5))".utf8 {
            h ^= UInt64(b); h = h &* 0x100000001b3
        }
        return -Int(h & 0x7fff_ffff_ffff)
    }
}
