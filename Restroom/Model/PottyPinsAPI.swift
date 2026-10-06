import Foundation

/// One restroom pin from PottyPins, flattened from locations[].restrooms[].pin.
struct DoorPin: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let pin: String
}

protocol PinProvider: Sendable {
    func pins() async throws -> [DoorPin]
}

/// Scrapes PottyPins' undocumented dump. Shape (verified 2026-10-05): top-level array of
/// {"id","name","address","latitude": Double?,"longitude": Double?,"restrooms":[{"id","name","pin": String?}, …], …}.
/// Fetched once per process and cached; a failure is retried on the next call.
/// Any error (HTTP, shape change) is the caller's to ignore — codes are a bonus, never a requirement.
actor PottyPinsAPI: PinProvider {
    static let shared = PottyPinsAPI()

    private let url = URL(string: "https://pottypins.com/api/posts")!
    private var cached: [DoorPin]?

    struct Location: Decodable {
        let name: String
        let latitude: Double?    // null for ungeocoded entries (1 of 88 live)
        let longitude: Double?
        let restrooms: [Room]?
    }
    struct Room: Decodable {
        let pin: String?
    }

    func pins() async throws -> [DoorPin] {
        if let cached { return cached }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RefugeError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let flat = Self.flatten(try JSONDecoder().decode([Location].self, from: data))
        cached = flat
        return flat
    }

    static func flatten(_ list: [Location]) -> [DoorPin] {
        list.flatMap { loc -> [DoorPin] in
            guard let lat = loc.latitude, let lon = loc.longitude else { return [] }
            return (loc.restrooms ?? []).compactMap { room in
                guard let pin = room.pin?.trimmingCharacters(in: .whitespacesAndNewlines), !pin.isEmpty else { return nil }
                return DoorPin(name: loc.name, latitude: lat, longitude: lon, pin: pin)
            }
        }
    }
}
