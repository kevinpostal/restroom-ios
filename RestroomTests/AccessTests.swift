import XCTest
@testable import Restroom

final class AccessTests: XCTestCase {
    /// Live Refuge phrasings observed in Midtown Manhattan results, plus keypad edge cases.
    func testParseRefugeText() {
        let cases: [(String, Access?)] = [
            ("There's a code: 125", .code("125")),
            ("Code is 1234#", .code("1234#")),
            ("you need a bathroom code, it's on the receipt", .onReceipt),
            ("The bathroom code is on the receipt", .onReceipt),
            ("You have to ask for a code", .askStaff),
            ("must ask for a code", .askStaff),
            ("You need to get the bathroom code or buy something", .askStaff),
            ("keypad by the door", .askStaff),
            ("you don't need a code or anything", nil),
            ("top floor!", nil),
            ("", nil),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(Access.parse(text), expected, text)
        }
    }

    func testFromPin() {
        XCTAssertEqual(Access.fromPin("9999"), .code("9999"))
        XCTAssertEqual(Access.fromPin("2844 (+ ENTER)"), .code("2844 (+ ENTER)"))
        XCTAssertEqual(Access.fromPin("No PIN required"), .open)
        XCTAssertNil(Access.fromPin("  "))
    }

    func testSpokenSpellsKeypadDigits() {
        XCTAssertEqual(Access.code("125").spoken, "Door code 1 2 5")
        XCTAssertEqual(Access.code("2844 (+ ENTER)").spoken, "Door code 2844 (+ ENTER)")
        XCTAssertEqual(Access.onReceipt.spoken, "Code on receipt")
    }

    func testPinBeatsText() {
        var r = Restroom(id: 1, name: "A", comment: "ask for the code")
        XCTAssertEqual(r.access, .askStaff)
        r.pin = "7777"
        XCTAssertEqual(r.access, .code("7777"))
    }
}
