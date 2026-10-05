import XCTest
@testable import Restroom

final class RestroomDecodingTests: XCTestCase {
    private let fixture = """
    [{"id":2755,"name":"Me Bar/Sky Bar ","street":"17 W. 32nd St.","city":"New York","state":"NY",
      "accessible":false,"unisex":true,"directions":"top floor!","comment":"rooftop bar",
      "latitude":40.7478833,"longitude":-73.9864795,"created_at":"2014-02-02T20:52:55.055Z",
      "updated_at":"2014-02-02T20:52:55.055Z","downvote":1,"upvote":0,"country":"US",
      "changing_table":false,"edit_id":2755,"approved":true,"distance":0.054,"bearing":"236.46"},
     {"id":9,"name":"Park","street":"","city":"Oakland","state":"CA","accessible":true,"unisex":false,
      "directions":"","comment":"","latitude":37.8,"longitude":-122.27,"downvote":0,"upvote":3,
      "country":"US","changing_table":true,"approved":true,"distance":1.5,"bearing":"10"}]
    """

    func testDecodesLiveShape() throws {
        let list = try JSONDecoder().decode([Restroom].self, from: Data(fixture.utf8))
        XCTAssertEqual(list.count, 2)
        let bar = list[0]
        XCTAssertFalse(bar.changingTable)
        XCTAssertEqual(bar.distanceMeters!, 86.9, accuracy: 0.1)
        XCTAssertEqual(bar.amenities, [.unisex])
        XCTAssertEqual(bar.addressLine, "17 W. 32nd St., New York, NY")
        XCTAssertEqual(bar.downvote, 1)
    }

    func testAddressOmitsEmptyStreet() throws {
        let list = try JSONDecoder().decode([Restroom].self, from: Data(fixture.utf8))
        XCTAssertEqual(list[1].addressLine, "Oakland, CA")
        XCTAssertEqual(list[1].amenities, [.accessible, .changingTable])
    }
}
