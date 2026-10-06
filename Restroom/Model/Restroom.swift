import CoreLocation
import Foundation

struct Restroom: Identifiable, Decodable, Equatable {
    let id: Int
    let name: String
    let street: String
    let city: String
    let state: String
    let country: String
    let accessible: Bool
    let unisex: Bool
    let changingTable: Bool
    let directions: String
    let comment: String
    let latitude: Double
    let longitude: Double
    let upvote: Int
    let downvote: Int
    let approved: Bool
    /// From Refuge for the fetch centre; `FinderModel` recomputes it when serving cached pages for another centre.
    var distanceMiles: Double?
    /// PottyPins door pin attached by `FinderModel.attach`; never decoded.
    var pin: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, street, city, state, country, accessible, unisex, directions, comment
        case latitude, longitude, upvote, downvote, approved
        case changingTable = "changing_table"
        case distanceMiles = "distance"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        street = try c.decodeIfPresent(String.self, forKey: .street) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        accessible = try c.decodeIfPresent(Bool.self, forKey: .accessible) ?? false
        unisex = try c.decodeIfPresent(Bool.self, forKey: .unisex) ?? false
        changingTable = try c.decodeIfPresent(Bool.self, forKey: .changingTable) ?? false
        directions = try c.decodeIfPresent(String.self, forKey: .directions) ?? ""
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        upvote = try c.decodeIfPresent(Int.self, forKey: .upvote) ?? 0
        downvote = try c.decodeIfPresent(Int.self, forKey: .downvote) ?? 0
        approved = try c.decodeIfPresent(Bool.self, forKey: .approved) ?? true
        distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles)
    }

    init(id: Int, name: String, street: String = "", city: String = "", state: String = "",
         accessible: Bool = false, unisex: Bool = false, changingTable: Bool = false,
         directions: String = "", comment: String = "",
         latitude: Double = 0, longitude: Double = 0, distanceMiles: Double? = nil) {
        self.id = id; self.name = name; self.street = street; self.city = city; self.state = state
        self.country = ""; self.accessible = accessible; self.unisex = unisex
        self.changingTable = changingTable; self.directions = directions; self.comment = comment
        self.latitude = latitude; self.longitude = longitude; self.upvote = 0; self.downvote = 0
        self.approved = true; self.distanceMiles = distanceMiles
    }

    /// A PottyPins pin wins over anything mined from Refuge text.
    var access: Access? { pin.flatMap(Access.fromPin) ?? Access.parse(directions + " " + comment) }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    var addressLine: String {
        [street, city, state]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var amenities: [Amenity] {
        var out: [Amenity] = []
        if accessible { out.append(.accessible) }
        if unisex { out.append(.unisex) }
        if changingTable { out.append(.changingTable) }
        return out
    }

    var distanceMeters: Double? { distanceMiles.map { $0 * 1609.344 } }

    /// < 0.1 mi → feet to the nearest 10; else miles to one decimal. Metric locales: m / km.
    var distanceText: String? {
        guard let m = distanceMeters else { return nil }
        if Locale.current.measurementSystem == .us {
            let miles = m / 1609.344
            if miles < 0.1 {
                let feet = (miles * 5280 / 10).rounded() * 10
                return "\(Int(feet)) ft"
            }
            return String(format: "%.1f mi", miles)
        }
        if m < 1000 { return "\(Int((m / 10).rounded() * 10)) m" }
        return String(format: "%.1f km", m / 1000)
    }

    /// `distanceText` with units spelled out for VoiceOver ("0.4 miles", "300 feet").
    var distanceSpoken: String? {
        guard let t = distanceText else { return nil }
        let units = [" mi": " miles", " ft": " feet", " km": " kilometers", " m": " meters"]
        for (abbr, word) in units where t.hasSuffix(abbr) { return String(t.dropLast(abbr.count)) + word }
        return t
    }
}
