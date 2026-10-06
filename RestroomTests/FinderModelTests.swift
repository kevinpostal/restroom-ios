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

@MainActor
final class FinderModelTests: XCTestCase {
    private let here = CLLocation(latitude: 37.33, longitude: -122.0)

    func testEmptyResultYieldsEmptyState() async {
        let m = FinderModel(api: FakeProvider(result: .success([])), pins: noPins)
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .empty)
        XCTAssertTrue(m.restrooms.isEmpty)
    }

    func testOfflineYieldsFailedMessage() async {
        let m = FinderModel(api: FakeProvider(result: .failure(.offline)), pins: noPins)
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .failed("You're offline"))
    }

    func testUseCurrentLocationLoadsAndLabels() async {
        let list = [Restroom(id: 1, name: "A", distanceMiles: 0.2), Restroom(id: 2, name: "B", distanceMiles: 0.9)]
        let m = FinderModel(api: FakeProvider(result: .success(list)), pins: noPins)
        m.centerLabel = "Elsewhere"
        m.useCurrentLocation(here)
        await m.reloadAndWait()
        XCTAssertEqual(m.centerLabel, "Near you")
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.id), [1, 2])
    }

    func testReloadWithoutCenterStaysIdle() async {
        let m = FinderModel(api: FakeProvider(result: .success([])), pins: noPins)
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .idle)
    }

    func testPinWithin75mAttaches() async {
        let near = Restroom(id: 1, name: "Near", latitude: 37.33, longitude: -122.0, distanceMiles: 0.1)
        let far = Restroom(id: 2, name: "Far", latitude: 37.3327, longitude: -122.0, distanceMiles: 0.3)   // ~300 m north
        let pins = FakePins(result: .success([DoorPin(name: "Near", latitude: 37.33018, longitude: -122.0, pin: "4321")]))  // ~20 m
        let m = FinderModel(api: FakeProvider(result: .success([near, far])), pins: pins)
        m.selected = far
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.access), [.code("4321"), nil])
        XCTAssertEqual(m.selected?.id, 2)
    }

    func testPinFailureKeepsList() async {
        let list = [Restroom(id: 1, name: "A", latitude: 37.33, longitude: -122.0, distanceMiles: 0.2)]
        let m = FinderModel(api: FakeProvider(result: .success(list)), pins: FakePins(result: .failure(.offline)))
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.access), [nil])
    }
}
