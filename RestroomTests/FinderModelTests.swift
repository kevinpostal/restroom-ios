import CoreLocation
import XCTest
@testable import Restroom

private struct FakeProvider: RestroomProvider {
    let result: Result<[Restroom], RefugeError>
    func nearby(_ center: CLLocationCoordinate2D, perPage: Int) async throws -> [Restroom] {
        try result.get()
    }
}

@MainActor
final class FinderModelTests: XCTestCase {
    private let here = CLLocation(latitude: 37.33, longitude: -122.0)

    func testEmptyResultYieldsEmptyState() async {
        let m = FinderModel(api: FakeProvider(result: .success([])))
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .empty)
        XCTAssertTrue(m.restrooms.isEmpty)
    }

    func testOfflineYieldsFailedMessage() async {
        let m = FinderModel(api: FakeProvider(result: .failure(.offline)))
        m.center = here.coordinate
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .failed("You're offline"))
    }

    func testUseCurrentLocationLoadsAndLabels() async {
        let list = [Restroom(id: 1, name: "A", distanceMiles: 0.2), Restroom(id: 2, name: "B", distanceMiles: 0.9)]
        let m = FinderModel(api: FakeProvider(result: .success(list)))
        m.centerLabel = "Elsewhere"
        m.useCurrentLocation(here)
        await m.reloadAndWait()
        XCTAssertEqual(m.centerLabel, "Near you")
        XCTAssertEqual(m.state, .loaded)
        XCTAssertEqual(m.restrooms.map(\.id), [1, 2])
    }

    func testReloadWithoutCenterStaysIdle() async {
        let m = FinderModel(api: FakeProvider(result: .success([])))
        await m.reloadAndWait()
        XCTAssertEqual(m.state, .idle)
    }
}
