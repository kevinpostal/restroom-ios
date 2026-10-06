import XCTest
@testable import Restroom

final class PottyPinsDecodingTests: XCTestCase {
    /// Verbatim shape from the live `GET /api/posts` dump; extra keys ignored, null pins and null coordinates dropped.
    private let json = """
    [
      {"id": 12, "name": "Chick-fil-A", "address": "3401 S Bristol St, Santa Ana, CA",
       "latitude": 33.6998222, "longitude": -117.8850177, "imageUrl": "https://pottypins.com/x.jpg",
       "hoursData": {"mon": "6:30-22:00"},
       "restrooms": [
         {"id": 31, "name": "Men's", "pin": "9999"},
         {"id": 32, "name": "Women's", "pin": "1234"}
       ]},
      {"id": 13, "name": "McDonald's", "address": "Irvine, CA",
       "latitude": 33.6949323, "longitude": -117.7998092, "imageUrl": null, "hoursData": null,
       "restrooms": [{"id": 40, "name": "Unisex", "pin": null}]},
      {"id": 14, "name": "Carl’s Jr.", "address": null, "latitude": null, "longitude": null,
       "restrooms": [{"id": 50, "name": "Unisex", "pin": "0000"}]}
    ]
    """

    func testFlattenKeepsOnlyPinnedRooms() throws {
        let list = try JSONDecoder().decode([PottyPinsAPI.Location].self, from: Data(json.utf8))
        let pins = PottyPinsAPI.flatten(list)
        XCTAssertEqual(pins, [
            DoorPin(name: "Chick-fil-A", latitude: 33.6998222, longitude: -117.8850177, pin: "9999"),
            DoorPin(name: "Chick-fil-A", latitude: 33.6998222, longitude: -117.8850177, pin: "1234"),
        ])
    }

    func testMissingRestroomsArrayIsEmpty() throws {
        let list = try JSONDecoder().decode([PottyPinsAPI.Location].self, from: Data(#"[{"name":"X","latitude":1,"longitude":2}]"#.utf8))
        XCTAssertEqual(PottyPinsAPI.flatten(list), [])
    }
}
