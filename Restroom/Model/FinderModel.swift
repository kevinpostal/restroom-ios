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
    /// True while a network fetch for the current centre is in flight (cache hits never set it).
    @Published private(set) var busy = false
    /// "ADA only" toggle: list, pins and the Nearest button see only wheelchair-accessible restrooms.
    /// Parks are never ADA-verified, so they drop out too. Remembered across launches.
    @Published var adaOnly: Bool {
        didSet { defaults?.set(adaOnly, forKey: Self.adaOnlyKey) }
    }
    static let adaOnlyKey = "adaOnly"
    private let defaults: UserDefaults?

    /// What the list and map show: `restrooms`, narrowed by the ADA toggle.
    var visible: [Restroom] { adaOnly ? restrooms.filter(\.accessible) : restrooms }

    private let api: RestroomProvider
    private let pins: PinProvider
    private let places: PlaceResolver
    private let parks: PlaceProvider
    private var inflight: Task<Void, Never>?

    /// Refuge and PottyPins geocode independently; 75 m covers a storefront without bleeding into the next block.
    static let pinMatchMeters: CLLocationDistance = 75

    /// Pages of nearest results keyed by the ~1 km grid cell they were fetched in. A load unions the centre
    /// cell with its 8 neighbours and re-ranks locally, so a pan into cached ground is instant.
    /// Fresh (< 10 min) pages are final; older ones up to a day are shown at once and refetched behind them.
    private var cache: [Cell: TileStore.Entry] = [:]
    private let store: TileStore?
    private var prefetching: Task<Void, Never>?
    static let freshTTL: TimeInterval = 10 * 60
    static let serveTTL: TimeInterval = 24 * 60 * 60

    init(api: RestroomProvider = RefugeAPI.shared, pins: PinProvider = PottyPinsAPI.shared,
         places: PlaceResolver = LocalSearchResolver(), parks: PlaceProvider = ParkPlaces(), store: TileStore? = .disk,
         defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        adaOnly = defaults?.bool(forKey: Self.adaOnlyKey) ?? false
        self.api = api
        self.pins = pins
        self.places = places
        self.parks = parks
        self.store = store
        let now = Date()
        cache = (store?.load() ?? [:]).filter { now.timeIntervalSince($0.value.at) < Self.serveTTL }
        Task { _ = try? await pins.pins() }   // warm the door-code cache before the first results land
    }

    private func age(_ cell: Cell) -> TimeInterval? { cache[cell].map { Date().timeIntervalSince($0.at) } }
    private func isFresh(_ cell: Cell) -> Bool { age(cell).map { $0 < Self.freshTTL } ?? false }
    private func isServable(_ cell: Cell) -> Bool { age(cell).map { $0 < Self.serveTTL } ?? false }

    func useCurrentLocation(_ loc: CLLocation) {
        center = loc.coordinate
        centerLabel = "Near you"
        reload()
    }

    /// "Nearest" button: search around `loc` and open the closest verified restroom once rows land.
    /// Parks only count when no verified restroom is in range.
    func findNearest(from loc: CLLocation) {
        openNearestOnPublish = true
        useCurrentLocation(loc)
    }
    private var openNearestOnPublish = false

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

    /// Refresh button: drop the cached page for this spot and fetch it again, keeping rows on screen.
    func refresh() {
        guard let center else { return }
        cache[Cell(center)] = nil
        reload(keepingResults: true)
    }

    func reload(keepingResults: Bool = false) {
        guard let center else { return }
        inflight?.cancel()
        busy = false
        let cell = Cell(center)
        if isFresh(cell) {
            inflight = Task { await publish(around: center) }
            prefetch(around: cell)
            return
        }
        // Refuge serialises requests per client; stop background fetches so this one isn't queued behind them.
        prefetching?.cancel()
        // Stale-but-servable pages (this cell, or neighbours when panning) go on screen now; the fetch replaces them.
        let canServe = isServable(cell) || (keepingResults && cell.ring.contains { isServable($0) })
        if !canServe && !(keepingResults && state == .loaded) { state = .loading }
        busy = true
        inflight = Task {
            defer { if !Task.isCancelled { busy = false } }
            do {
                if canServe { await publish(around: center) }
                let page = try await fetchPage(at: center)
                guard !Task.isCancelled else { return }
                store(page, in: cell)
                await publish(around: center)
                prefetch(around: cell)
            } catch {
                guard !Task.isCancelled else { return }
                if restrooms.isEmpty || !canServe { state = .failed(error.localizedDescription) }
                openNearestOnPublish = false
            }
        }
    }

    private func store(_ page: [Restroom], in cell: Cell) {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.at) < Self.serveTTL }
        cache[cell] = .init(at: now, list: page)
        store?.save(cache)
    }

    /// Union of servable pages for the centre cell and its ring, ranked by distance from `center`, then door codes.
    private func publish(around center: CLLocationCoordinate2D) async {
        let cell = Cell(center)
        var seen = Set<Int>()
        var pool: [Restroom] = []
        for c in [cell] + cell.ring {
            guard isServable(c), let hit = cache[c] else { continue }
            for r in hit.list where seen.insert(r.id).inserted { pool.append(r) }
        }
        let result = Self.rank(pool, from: center)
        restrooms = result
        state = result.isEmpty ? .empty : .loaded
        let candidates = adaOnly ? result.filter(\.accessible) : result
        if openNearestOnPublish, let nearest = candidates.first(where: { $0.kind == .restroom }) ?? candidates.first {
            openNearestOnPublish = false
            selected = nearest
        }
        // Codes are a bonus: the list is already visible, and a PottyPins failure never touches `state`.
        guard !result.isEmpty, let doorPins = try? await pins.pins(), !doorPins.isEmpty, !Task.isCancelled else { return }
        restrooms = Self.attach(doorPins, to: result)
        if let s = selected { selected = restrooms.first { $0.id == s.id } ?? s }
    }

    /// Fetches the ring cells not yet cached, one at a time at utility priority; a new reload restarts it.
    private func prefetch(around cell: Cell) {
        prefetching?.cancel()
        let missing = cell.ring.filter { !isFresh($0) }
        guard !missing.isEmpty else { return }
        prefetching = Task(priority: .utility) {
            for c in missing {
                guard !Task.isCancelled, let page = try? await fetchPage(at: c.center) else { return }
                store(page, in: c)
            }
        }
    }

    /// Refuge radius is implicit (nearest N); parks are asked for within a cell-and-a-half so the ring union stays coherent.
    static let parkRadius: CLLocationDistance = 1_600

    /// One tile page: Refuge restrooms plus parks/campgrounds, fetched concurrently. Refuge errors propagate;
    /// the park lookup is a bonus and its failure just yields restrooms alone.
    private func fetchPage(at center: CLLocationCoordinate2D) async throws -> [Restroom] {
        async let refuge = api.nearby(center, perPage: Self.pageSize)
        async let nearbyParks = parks.places(near: center, radius: Self.parkRadius)
        let page = try await refuge
        let extras = (try? await nearbyParks) ?? []
        return page + extras
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
    init(x: Int, y: Int) { self.x = x; self.y = y }

    var center: CLLocationCoordinate2D {
        .init(latitude: Double(x) * Self.size, longitude: Double(y) * Self.size)
    }

    /// The 8 surrounding cells, nearest-first for prefetch order (edges before corners).
    var ring: [Cell] {
        [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)].map { Cell(x: x + $0.0, y: y + $0.1) }
    }
}
