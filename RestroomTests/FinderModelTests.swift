import CoreLocation
import XCTest
@testable import Restroom

private struct FakeProvider: RestroomProvider {
    let result: Result<[Restroom], RefugeError>
    func nearby(_ center: CLLocationCoordinate2D, perPage: Int) async throws -> [Restroom] {
        try result.get()
    }
}

private struct FakePins: PinProvider {
    let result: Result<[DoorPin], RefugeError>
    func pins() async throws -> [DoorPin] { try result.get() }
}

private let noPins = FakePins(result: .success([]))

/// Records every fetch centre; returns `page(center)`.
private actor CountingProvider: RestroomProvider {
    private(set) var centers: [CLLocationCoordinate2D] = []
    private let page: @Sendable (CLLocationCoordinate2D) -> [Restroom]
    init(_ page: @escaping @Sendable (CLLocationCoordinate2D) -> [Restroom]) { self.page = page }
    func nearby(_ center: CLLocationCoordinate2D, perPage: Int) async throws -> [Restroom] {
        centers.append(center)
        return page(center)
    }
    func calls(near c: CLLocationCoordinate2D) -> Int {
        centers.filter { abs($0.latitude - c.latitude) < 1e-9 && abs($0.longitude - c.longitude) < 1e-9 }.count
    }
}

@MainActor
final class FinderModelTests: XCTestCase {
    private let here = CLLocation(latitude: 37.33, longitude: -122.0)

    func testEmptyResultYieldsEmptyState() async {
        let m = FinderModel(api: FakeProvider(result: .success([])), pins: noPins, store: nil)
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .empty)
        XCTAssertTrue(m.restrooms.isEmpty)
    }

    func testOfflineYieldsFailedMessage() async {
        let m = FinderModel(api: FakeProvider(result: .failure(.offline)), pins: noPins, store: nil)
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .failed("You're offline"))
    }

    func testUseCurrentLocationLoadsAndLabels() async {
        let list = [Restroom(id: 1, name: "A", latitude: 37.331, longitude: -122.0), Restroom(id: 2, name: "B", latitude: 37.34, longitude: -122.0)]
        let m = FinderModel(api: FakeProvider(result: .success(list)), pins: noPins, store: nil)
        m.centerLabel = "Elsewhere"
        m.useCurrentLocation(here)
        await m.reloadAndWait()
        XCTAssertEqual(m.centerLabel, "Near you")
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.id), [1, 2])
    }

    func testReloadWithoutCenterStaysIdle() async {
        let m = FinderModel(api: FakeProvider(result: .success([])), pins: noPins, store: nil)
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .idle)
    }

    func testPinWithin75mAttaches() async {
        let near = Restroom(id: 1, name: "Near", latitude: 37.33, longitude: -122.0, distanceMiles: 0.1)
        let far = Restroom(id: 2, name: "Far", latitude: 37.3327, longitude: -122.0, distanceMiles: 0.3)   // ~300 m north
        let pins = FakePins(result: .success([DoorPin(name: "Near", latitude: 37.33018, longitude: -122.0, pin: "4321")]))  // ~20 m
        let m = FinderModel(api: FakeProvider(result: .success([near, far])), pins: pins, store: nil)
        m.selected = far
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.access), [.code("4321"), nil])
        XCTAssertEqual(m.selected?.id, 2)
    }

    func testPinFailureKeepsList() async {
        let list = [Restroom(id: 1, name: "A", latitude: 37.33, longitude: -122.0, distanceMiles: 0.2)]
        let m = FinderModel(api: FakeProvider(result: .success(list)), pins: FakePins(result: .failure(.offline)), store: nil)
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.access), [nil])
    }

    func testExploreKeepsRowsWhileReloading() async {
        let list = [Restroom(id: 1, name: "A", distanceMiles: 0.2)]
        let m = FinderModel(api: FakeProvider(result: .success(list)), pins: noPins, store: nil)
        m.useCurrentLocation(here)
        await m.settle()
        XCTAssertEqual(m.state, .loaded)
        m.explore(CLLocationCoordinate2D(latitude: 37.34, longitude: -122.01))
        XCTAssertEqual(m.state, .loaded, "no Loading… flash while panning")
        XCTAssertEqual(m.restrooms.map(\.id), [1])
        XCTAssertEqual(m.centerLabel, "This area")
        XCTAssertEqual(m.center?.latitude, 37.34)
        await m.settle()
        XCTAssertEqual(m.state, .loaded)
    }

    func testSameCellIsServedFromCacheWithLocalDistances() async {
        let api = CountingProvider { _ in [Restroom(id: 1, name: "A", latitude: 37.331, longitude: -122.0, distanceMiles: 9)] }
        let m = FinderModel(api: api, pins: noPins, store: nil)
        m.useCurrentLocation(here)
        await m.settle()
        XCTAssertEqual(m.restrooms.first?.distanceMiles ?? 0, 0.069, accuracy: 0.01, "re-ranked from the real centre, not Refuge's figure")
        m.explore(CLLocationCoordinate2D(latitude: 37.3315, longitude: -121.9995))   // same 0.01° cell
        await m.settle()
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.first?.distanceMiles ?? 0, 0.044, accuracy: 0.01)
        let primary = await api.calls(near: here.coordinate)
        let second = await api.calls(near: CLLocationCoordinate2D(latitude: 37.3315, longitude: -121.9995))
        XCTAssertEqual(primary, 1)
        XCTAssertEqual(second, 0, "cache hit: no fetch for the panned centre")
    }

    func testRefreshBypassesCacheAndReportsBusy() async {
        let api = CountingProvider { _ in [Restroom(id: 1, name: "A", latitude: 37.331, longitude: -122.0)] }
        let m = FinderModel(api: api, pins: noPins, store: nil)
        m.useCurrentLocation(here)
        XCTAssertTrue(m.busy)
        await m.settle()
        XCTAssertFalse(m.busy)
        m.reload()                                  // same cell → cache hit, no fetch, never busy
        XCTAssertFalse(m.busy)
        await m.settle()
        m.refresh()
        XCTAssertTrue(m.busy)
        XCTAssertEqual(m.state, .loaded, "rows stay while refreshing")
        await m.settle()
        XCTAssertFalse(m.busy)
        let fetches = await api.calls(near: here.coordinate)
        XCTAssertEqual(fetches, 2)
    }

    func testPanIntoPrefetchedNeighbourUnionsPages() async {
        // Each page carries one restroom at its fetch centre, so a neighbour's page is distinguishable.
        let api = CountingProvider { c in [Restroom(id: Int(c.latitude * 1e4) &* 31 &+ Int(c.longitude * 1e4), name: "at", latitude: c.latitude, longitude: c.longitude)] }
        let m = FinderModel(api: api, pins: noPins, store: nil)
        m.useCurrentLocation(here)
        await m.settle()
        XCTAssertEqual(m.restrooms.count, 1)
        // Let the ring prefetch (8 cells) finish, then pan one cell north.
        var tries = 0
        while await api.centers.count < 9, tries < 100 {
            tries += 1
            try? await Task.sleep(for: .milliseconds(20))
        }
        let north = Cell(here.coordinate).ring[0].center
        m.explore(north)
        await m.settle()
        XCTAssertEqual(m.state, .loaded)
        XCTAssertGreaterThanOrEqual(m.restrooms.count, 2, "union of the centre page and its cached neighbours")
        XCTAssertEqual(m.restrooms.first?.latitude ?? 0, north.latitude, accuracy: 1e-9, "nearest to the new centre first")
        let fetchesAtNorth = await api.calls(near: north)
        XCTAssertEqual(fetchesAtNorth, 1, "served by the prefetch, not a second fetch")
    }

    func testDiskStoreWarmsNextLaunchAndRevalidates() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tiles-\(UUID().uuidString).json")
        let diskStore = TileStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = CountingProvider { _ in [Restroom(id: 7, name: "Saved", latitude: 37.331, longitude: -122.0)] }
        let first = FinderModel(api: api, pins: noPins, store: diskStore)
        first.useCurrentLocation(here)
        await first.settle()
        try? await Task.sleep(for: .milliseconds(300))   // store writes asynchronously

        // Age the saved page past the fresh window but inside the serve window.
        var saved = diskStore.load()
        let cell = Cell(here.coordinate)
        guard let entry = saved[cell] else { return XCTFail("centre page not persisted; saved \(saved.count)") }
        saved[cell] = .init(at: Date().addingTimeInterval(-FinderModel.freshTTL - 60), list: entry.list)
        diskStore.save(saved)
        try? await Task.sleep(for: .milliseconds(300))

        struct SlowProvider: RestroomProvider {
            func nearby(_ center: CLLocationCoordinate2D, perPage: Int) async throws -> [Restroom] {
                try await Task.sleep(for: .milliseconds(500))
                return [Restroom(id: 8, name: "Fresh", latitude: 37.331, longitude: -122.0)]
            }
        }
        let second = FinderModel(api: SlowProvider(), pins: noPins, store: diskStore)
        second.useCurrentLocation(here)
        XCTAssertTrue(second.busy, "stale page is revalidated")
        for _ in 0..<20 where second.restrooms.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(second.restrooms.map(\.id), [7], "stale page served before the network answers")
        XCTAssertEqual(second.state, .loaded)
        await second.settle()
        XCTAssertEqual(second.restrooms.first?.id, 8, "fresh page replaces the stale centre; ring pages still union in")
    }
}
