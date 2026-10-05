import CoreLocation
import Foundation

protocol RestroomProvider: Sendable {
    func nearby(_ center: CLLocationCoordinate2D, perPage: Int) async throws -> [Restroom]
}

enum RefugeError: LocalizedError, Equatable {
    case http(Int)
    case decoding
    case offline

    var errorDescription: String? {
        switch self {
        case .http(let status): return "Server returned \(status)"
        case .decoding: return "Couldn't read restroom data"
        case .offline: return "You're offline"
        }
    }
}

actor RefugeAPI: RestroomProvider {
    static let shared = RefugeAPI()

    private let base = URL(string: "https://www.refugerestrooms.org/api/v1/restrooms/by_location")!

    func nearby(_ center: CLLocationCoordinate2D, perPage: Int = 50) async throws -> [Restroom] {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "lat", value: String(center.latitude)),
            .init(name: "lng", value: String(center.longitude)),
            .init(name: "per_page", value: String(perPage)),
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let e as URLError where e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
            throw RefugeError.offline
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RefugeError.http(http.statusCode)
        }
        let list: [Restroom]
        do { list = try JSONDecoder().decode([Restroom].self, from: data) }
        catch { throw RefugeError.decoding }
        return list
            .filter(\.approved)
            .sorted { ($0.distanceMiles ?? .infinity) < ($1.distanceMiles ?? .infinity) }
    }
}
