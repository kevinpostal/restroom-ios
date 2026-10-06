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

    /// Pages of nearest-50 results keyed by the ~1 km grid cell they were fetched in. A load unions the
    /// centre cell with its 8 neighbours and re-ranks locally, so a pan into prefetched ground is instant.
    private var cache: [Cell: (list: [Restroom], at: Date)] = [:]
    private var prefetching: Task<Void, Never>?
    static let cacheTTL: TimeInterval = 10 * 60

    init(api: RestroomProvider = RefugeAPI.shared, pins: PinProvider = PottyPinsAPI.shared,
         places: PlaceResolver = LocalSearchResolver()) {
        self.api = api
        self.pins = pins
        self.places = places
        Task { _ = try? await pins.pins() }   // warm the door-code cache before the first results land
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

    /// Map was panned: search around the new centre, keeping the current rows on screen until new ones arrive.
    func explore(_ c: CLLocationCoordinate2D) {
        center = c
        centerLabel = "This area"
        reload(keepingResults: true)
    }

    /// Refuge caps pages at 100 and answers them as fast as 50; a bigger page covers more of the ring per round-trip.
    static let pageSize = 100

    func reload(keepingResults: Bool = false) {
        guard let center else { return }
        inflight?.cancel()
        let cell = Cell(center)
        if let hit = cache[cell], Date().timeIntervalSince(hit.at) < Self.cacheTTL {
            inflight = Task { await publish(around: center) }
            prefetch(around: cell)
            return
        }
        // Refuge serialises requests per client; stop background fetches so this one isn't queued behind them.
        prefetching?.cancel()
        if !(keepingResults && state == .loaded) { state = .loading }
        inflight = Task { [api] in
            do {
                let page = try await api.nearby(center, perPage: Self.pageSize)
                guard !Task.isCancelled else { return }
                store(page, in: cell)
                await publish(around: center)
                prefetch(around: cell)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func store(_ page: [Restroom], in cell: Cell) {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.at) < Self.cacheTTL }
        cache[cell] = (page, now)
    }

    /// Union of fresh pages for the centre cell and its ring, ranked by distance from `center`, then door codes.
    private func publish(around center: CLLocationCoordinate2D) async {
        let cell = Cell(center)
        let now = Date()
        var seen = Set<Int>()
        var pool: [Restroom] = []
        for c in [cell] + cell.ring {
            guard let hit = cache[c], now.timeIntervalSince(hit.at) < Self.cacheTTL else { continue }
            for r in hit.list where seen.insert(r.id).inserted { pool.append(r) }
        }
        let result = Self.rank(pool, from: center)
        restrooms = result
        state = result.isEmpty ? .empty : .loaded
        // Codes are a bonus: the list is already visible, and a PottyPins failure never touches `state`.
        guard !result.isEmpty, let doorPins = try? await pins.pins(), !doorPins.isEmpty, !Task.isCancelled else { return }
        restrooms = Self.attach(doorPins, to: result)
        if let s = selected { selected = restrooms.first { $0.id == s.id } ?? s }
    }

    /// Fetches the ring cells not yet cached, one at a time at utility priority; a new reload restarts it.
    private func prefetch(around cell: Cell) {
        prefetching?.cancel()
        let now = Date()
        let missing = cell.ring.filter { cache[$0].map { now.timeIntervalSince($0.at) >= Self.cacheTTL } ?? true }
        guard !missing.isEmpty else { return }
        prefetching = Task(priority: .utility) { [api] in
            for c in missing {
                guard !Task.isCancelled, let page = try? await api.nearby(c.center, perPage: Self.pageSize) else { return }
                store(page, in: c)
            }
        }
    }

    /// Nearest 50 by straight-line distance from `center`, with `distanceMiles` recomputed to match.
    static func rank(_ list: [Restroom], from center: CLLocationCoordinate2D) -> [Restroom] {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return list
            .map { r -> Restroom in
                var r = r
                r.distanceMiles = CLLocation(latitude: r.latitude, longitude: r.longitude).distance(from: here) / 1609.344
                return r
            }
            .sorted { ($0.distanceMiles ?? .infinity) < ($1.distanceMiles ?? .infinity) }
            .prefix(50)
            .map { $0 }
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
        await settle()
    }

    /// Waits for any in-flight load (tests).
    func settle() async {
        await inflight?.value
    }
}

/// ~1.1 km grid cell (0.01°) used as the results cache key; cells are centred on multiples of 0.01°.
struct Cell: Hashable {
    static let size = 0.01
    let x: Int
    let y: Int

    init(_ c: CLLocationCoordinate2D) {
        x = Int((c.latitude / Self.size).rounded())
        y = Int((c.longitude / Self.size).rounded())
    }
    private init(x: Int, y: Int) { self.x = x; self.y = y }

    var center: CLLocationCoordinate2D {
        .init(latitude: Double(x) * Self.size, longitude: Double(y) * Self.size)
    }

    /// The 8 surrounding cells, nearest-first for prefetch order (edges before corners).
    var ring: [Cell] {
        [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)].map { Cell(x: x + $0.0, y: y + $0.1) }
    }
}
