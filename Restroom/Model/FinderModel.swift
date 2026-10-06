import CoreLocation
import Foundation

enum LoadState: Equatable {
    case idle, loading, loaded, empty
    case failed(String)
}

@MainActor
final class FinderModel: ObservableObject {
    @Published var restrooms: [Restroom] = []
    @Published var center: CLLocationCoordinate2D?
    @Published var centerLabel: String = "Near you"
    @Published var state: LoadState = .idle
    @Published var selected: Restroom?
    @Published var query: String = ""

    private let api: RestroomProvider
    private let pins: PinProvider
    private let places: PlaceResolver
    private var inflight: Task<Void, Never>?

    /// Refuge and PottyPins geocode independently; 75 m covers a storefront without bleeding into the next block.
    static let pinMatchMeters: CLLocationDistance = 75

    init(api: RestroomProvider = RefugeAPI.shared, pins: PinProvider = PottyPinsAPI.shared,
         places: PlaceResolver = LocalSearchResolver()) {
        self.api = api
        self.pins = pins
        self.places = places
    }

    func useCurrentLocation(_ loc: CLLocation) {
        center = loc.coordinate
        centerLabel = "Near you"
        reload()
    }

    func search(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        state = .loading
        guard let place = await places.resolve(q) else {
            state = .failed("No place named “\(q)”")
            return
        }
        center = place.coordinate
        centerLabel = place.name
        reload()
    }

    func reload() {
        guard let center else { return }
        inflight?.cancel()
        state = .loading
        inflight = Task { [api, pins] in
            do {
                let result = try await api.nearby(center, perPage: 50)
                guard !Task.isCancelled else { return }
                restrooms = result
                state = result.isEmpty ? .empty : .loaded
                // Codes are a bonus: the list is already visible, and a PottyPins failure never touches `state`.
                guard !result.isEmpty, let doorPins = try? await pins.pins(), !doorPins.isEmpty, !Task.isCancelled else { return }
                restrooms = Self.attach(doorPins, to: result)
                if let s = selected { selected = restrooms.first { $0.id == s.id } ?? s }
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Copies each restroom with the nearest pin within `pinMatchMeters`; ties keep PottyPins order.
    static func attach(_ pins: [DoorPin], to list: [Restroom]) -> [Restroom] {
        let located = pins.map { (pin: $0, location: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) }
        return list.map { restroom in
            let here = CLLocation(latitude: restroom.latitude, longitude: restroom.longitude)
            var best: (pin: DoorPin, meters: CLLocationDistance)?
            for p in located {
                let d = p.location.distance(from: here)
                if d <= pinMatchMeters, best.map({ d < $0.meters }) ?? true { best = (p.pin, d) }
            }
            guard let best else { return restroom }
            var r = restroom
            r.pin = best.pin.pin
            return r
        }
    }

    /// Awaitable form for tests.
    func reloadAndWait() async {
        reload()
        await inflight?.value
    }
}
