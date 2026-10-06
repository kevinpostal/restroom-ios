import CoreLocation
import Foundation

/// Deterministic seams for XCUITest. Active only when the app is launched with `-uitest`.
enum UITestMode {
    static var isActive: Bool { CommandLine.arguments.contains("-uitest") }
    static func flag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

    /// Apple Park; `FinderModel.rank` sorts fixtures by real distance from here (0.18, 0.27, 0.31, 0.38 mi).
    static let start = CLLocation(latitude: 37.3349, longitude: -122.0090)
}

struct FixtureProvider: RestroomProvider {
    func nearby(_ center: CLLocationCoordinate2D, perPage: Int) async throws -> [Restroom] {
        if UITestMode.flag("-uitest-fail") { throw RefugeError.offline }
        if UITestMode.flag("-uitest-slow") { try await Task.sleep(for: .seconds(3)) }   // lets tests see the loading ring
        if UITestMode.flag("-uitest-empty") { return [] }
        return [
            // Within ~250 m of Library so both pins share the 600 m selected-pin viewport (pin-to-pin UI test).
            Restroom(id: 1, name: "Happy Lemon", street: "10963 N Wolfe Road", city: "Cupertino", state: "CA",
                     accessible: true, latitude: 37.3372, longitude: -122.0075),
            Restroom(id: 2, name: "Kaiser Hospital", street: "10992 N De Anza Blvd", city: "Cupertino", state: "CA",
                     accessible: true, unisex: true, comment: "Customers only. Ask at the counter for the code.",
                     latitude: 37.3335, longitude: -122.0045),
            Restroom(id: 3, name: "Library", street: "10800 Torre Ave", city: "Cupertino", state: "CA",
                     unisex: true, changingTable: true, latitude: 37.3380, longitude: -122.0050),
            Restroom(id: 4, name: "Park Kiosk", city: "Cupertino", state: "CA",
                     latitude: 37.3310, longitude: -122.0140),
        ]
    }
}

/// Exactly Happy Lemon's coordinate (0 m match); nothing near the other fixtures.
struct FixturePins: PinProvider {
    func pins() async throws -> [DoorPin] {
        [DoorPin(name: "Happy Lemon", latitude: 37.3372, longitude: -122.0075, pin: "2580")]
    }
}

struct FixtureResolver: PlaceResolver {
    func resolve(_ query: String) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        if UITestMode.flag("-uitest-noplace") { return nil }
        return ("Union Square", CLLocationCoordinate2D(latitude: 37.7879, longitude: -122.4075))
    }
}
