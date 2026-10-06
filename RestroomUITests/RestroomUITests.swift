import XCTest

/// Drives the app on the simulator with the `-uitest` fixtures (no network, no real location).
final class RestroomUITests: XCTestCase {
    private let wait: TimeInterval = 5
    private let largeText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ flags: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + flags
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ id: Int) -> XCUIElement { app.buttons["row.\(id)"] }

    private func search(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: wait))
        field.tap()
        field.typeText(text + "\n")
    }

    private func waitLabel(_ el: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let ok = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: el)], timeout: wait)
        XCTAssertEqual(ok, .completed, "expected label \"\(expected)\", got \"\(el.exists ? el.label : "<missing>")\"", file: file, line: line)
    }

    /// Every audit type; each non-ignored issue is reported with its element and detail.
    /// The map is full-screen, so only identifier-less elements outside the sheet (MapKit attribution,
    /// compass, user dot) are ignored; pins, map controls and everything in the sheet are audited.
    /// "Potentially inaccessible text" with no element is MapKit's own road label cut by the sheet edge
    /// (it flips with the sheet height); every app text is a SwiftUI `Text`, which always has an element.
    private func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let map = app.otherElements["map"].firstMatch
        let sheet = app.otherElements["sheet"].firstMatch
        let mapFrame = map.exists ? map.frame : .zero
        let sheetFrame = sheet.exists ? sheet.frame : .zero
        let resume = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = resume }
        try? app.performAccessibilityAudit(for: .all) { issue in
            let el = issue.element
            let ownedByApp = el.map { !$0.identifier.isEmpty || sheetFrame.contains($0.frame) } ?? true
            let insideMap = el.map { $0.identifier == "map" || mapFrame.contains($0.frame) } ?? false
            let mapLabel = el == nil && issue.compactDescription == "Potentially inaccessible text"
            let ignore = (insideMap && !ownedByApp) || mapLabel
            if !ignore {
                let location = el.map { "\($0.elementType) id=\"\($0.identifier)\" label=\"\($0.label)\" \($0.frame)" } ?? "(no element)"
                XCTFail("Accessibility audit: \(issue.compactDescription) — \(location): \(issue.detailedDescription)", file: file, line: line)
            }
            return ignore
        }
    }

    // MARK: - Flows

    func testNearbyListSortedWithDistances() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        XCTAssertEqual(app.staticTexts["header.title"].label, "Near you")
        let label = row(app, 1).label
        XCTAssertTrue(label.contains("Happy Lemon"), label)
        XCTAssertTrue(label.contains("0.2 mi"), label)
        XCTAssertTrue(label.contains("Accessible"), label)
        // The pin merge publishes a beat after the list; wait for it rather than reading the first label.
        let coded = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", "Door code 2 5 8 0"), evaluatedWith: row(app, 1))], timeout: wait)
        XCTAssertEqual(coded, .completed, row(app, 1).label)
        // Coded rows are a line taller, so the half sheet realizes only two; expand it before checking order.
        // With the park as a fifth row a swipe may scroll rows 1–2 off the top, so only the order of whatever is
        // on screen is asserted.
        for _ in 0..<3 where !row(app, 3).exists { app.collectionViews["list"].swipeUp() }
        XCTAssertTrue(row(app, 3).waitForExistence(timeout: wait))
        let visible = (1...4).map { row(app, $0) }.filter(\.exists)
        XCTAssertGreaterThanOrEqual(visible.count, 2, visible.map(\.identifier).joined(separator: ","))
        let ys = visible.map { $0.frame.minY }
        XCTAssertEqual(ys, ys.sorted(), "rows must be in distance order")
        if !row(app, 4).exists { app.collectionViews["list"].swipeUp() }
        XCTAssertTrue(row(app, 4).waitForExistence(timeout: wait), "farthest row reachable by scrolling")
        XCTAssertTrue(row(app, 4).label.contains("0.4 mi"), row(app, 4).label)
    }

    func testNearestButtonOpensClosestRestroom() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        app.buttons["header.nearest"].tap()
        let name = app.staticTexts["detail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: wait))
        XCTAssertEqual(name.label, "Happy Lemon")
        XCTAssertTrue(app.buttons["pin.1"].isSelected)
    }

    func testTapRowOpensDetailAndSelectsPin() {
        let app = launch()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: wait))
        row(app, 2).tap()
        let name = app.staticTexts["detail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: wait))
        XCTAssertEqual(name.label, "Kaiser Hospital")
        let code = app.staticTexts["detail.code"]
        XCTAssertTrue(code.waitForExistence(timeout: wait))
        XCTAssertEqual(code.label, "Ask staff for code")
        XCTAssertTrue(app.buttons["detail.directions"].isHittable)
        XCTAssertTrue(app.staticTexts["Unisex"].exists)
        XCTAssertTrue(app.buttons["pin.2"].isSelected)
        let sheet = app.otherElements["sheet"].firstMatch
        XCTAssertTrue(sheet.exists)
        XCTAssertLessThan(app.buttons["pin.2"].frame.midY, sheet.frame.minY, "selected pin sits in the map band above the sheet")
        XCTAssertTrue(app.buttons["pin.2"].isHittable)
        app.buttons["detail.close"].tap()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: wait))
        XCTAssertFalse(app.staticTexts["detail.name"].exists)
        XCTAssertFalse(app.buttons["pin.2"].isSelected)
    }

    func testPanMapSearchesThisArea() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        XCTAssertEqual(app.staticTexts["header.title"].label, "Near you")
        app.otherElements["map"].firstMatch.swipeLeft()
        waitLabel(app.staticTexts["header.title"], "This area")
        XCTAssertTrue(row(app, 1).exists, "rows stay on screen while the new area loads")
    }

    func testPanWithCardOpenClosesItAndSearches() {
        let app = launch()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: wait))
        row(app, 2).tap()
        XCTAssertTrue(app.staticTexts["detail.name"].waitForExistence(timeout: wait))
        app.otherElements["map"].firstMatch.swipeLeft()
        waitLabel(app.staticTexts["header.title"], "This area")
        XCTAssertFalse(app.staticTexts["detail.name"].exists)
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
    }

    func testParkRowTaggedAndCardExplains() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        let park = app.buttons["row.-5"]
        for _ in 0..<3 where !park.exists { app.collectionViews["list"].swipeUp() }
        XCTAssertTrue(park.waitForExistence(timeout: wait), "park from Apple POI data listed after the Refuge rows")
        XCTAssertTrue(park.label.contains("Memorial Park"), park.label)
        XCTAssertTrue(park.label.contains("Park, usually has restrooms"), park.label)
        park.tap()
        XCTAssertTrue(app.staticTexts["detail.kindNote"].waitForExistence(timeout: wait))
        XCTAssertFalse(app.staticTexts["Votes"].exists)
    }

    func testRefreshShowsLoadingRingAndKeepsRows() {
        let app = launch("-uitest-slow")
        let refresh = app.buttons["header.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: wait))
        XCTAssertEqual(refresh.value as? String, "Loading")
        XCTAssertTrue(app.otherElements["map.loading"].exists, "Searching tile on the map during the first load")
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        XCTAssertEqual(refresh.value as? String, "")
        XCTAssertFalse(app.otherElements["map.loading"].exists)
        refresh.tap()
        XCTAssertEqual(refresh.value as? String, "Loading")
        XCTAssertTrue(app.otherElements["map.loading"].exists, "Searching tile on the map during refresh")
        XCTAssertTrue(row(app, 1).exists, "rows stay on screen while refreshing")
        let idle = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "value == ''"), evaluatedWith: refresh)], timeout: wait)
        XCTAssertEqual(idle, .completed)
        XCTAssertTrue(row(app, 1).exists)
    }

    func testSearchFocusExpandsSheet() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        let sheet = app.otherElements["sheet"].firstMatch
        XCTAssertTrue(sheet.exists)
        let before = sheet.frame.minY
        app.textFields["search.field"].tap()
        let expanded = expectation(for: NSPredicate { _, _ in sheet.frame.minY < before - 100 }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [expanded], timeout: wait), .completed, "sheet expands when search is focused (minY \(sheet.frame.minY) vs \(before))")
    }

    func testSearchRelabelsHeaderAndReloads() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        search(app, "Union Square")
        waitLabel(app.staticTexts["header.title"], "Union Square")
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        let clear = app.buttons["search.clear"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertFalse(clear.exists)
        let value = app.textFields["search.field"].value as? String ?? ""
        XCTAssertFalse(value.contains("Union Square"), value)
    }

    func testSearchNoPlace() {
        let app = launch("-uitest-noplace")
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        search(app, "zzz")
        let msg = app.staticTexts["state.message"]
        XCTAssertTrue(msg.waitForExistence(timeout: wait))
        XCTAssertEqual(msg.label, "No place named “zzz”")
        XCTAssertTrue(app.buttons["state.retry"].exists)
    }

    func testOfflineShowsRetry() {
        let app = launch("-uitest-fail")
        let msg = app.staticTexts["state.message"]
        XCTAssertTrue(msg.waitForExistence(timeout: wait))
        XCTAssertEqual(msg.label, "You're offline")
        app.buttons["state.retry"].tap()
        XCTAssertTrue(msg.waitForExistence(timeout: wait))
        XCTAssertEqual(msg.label, "You're offline")
    }

    func testEmpty() {
        let app = launch("-uitest-empty")
        let note = app.staticTexts["state.note"]
        XCTAssertTrue(note.waitForExistence(timeout: wait))
        XCTAssertEqual(note.label, "No restrooms within range.")
    }

    func testLocationDenied() {
        let app = launch("-uitest-denied")
        let msg = app.staticTexts["state.message"]
        XCTAssertTrue(msg.waitForExistence(timeout: wait))
        XCTAssertTrue(msg.label.hasPrefix("Location is off"), msg.label)
        XCTAssertTrue(app.buttons["state.settings"].exists)
        search(app, "Union Square")
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        XCTAssertEqual(app.staticTexts["header.title"].label, "Union Square")
    }

    func testTapPinOpensDetail() {
        let app = launch()
        let pin = app.buttons["pin.3"]
        XCTAssertTrue(pin.waitForExistence(timeout: wait))
        pin.tap()
        let name = app.staticTexts["detail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: wait))
        XCTAssertEqual(name.label, "Library")
        app.buttons["pin.1"].tap()
        waitLabel(app.staticTexts["detail.name"], "Happy Lemon")
        XCTAssertTrue(app.buttons["pin.1"].isSelected)
        XCTAssertFalse(app.buttons["pin.3"].isSelected)
    }

    func testZoomButtonsChangeMapSpan() {
        let app = launch()
        let map = app.otherElements["map"].firstMatch
        XCTAssertTrue(app.buttons["pin.1"].waitForExistence(timeout: wait))
        let start = map.value as? String ?? ""
        XCTAssertTrue(start.hasSuffix("across"), "map exposes its span, got \"\(start)\"")
        app.buttons["map.zoomIn"].tap()
        let zoomedIn = expectation(for: NSPredicate(format: "value != %@", start), evaluatedWith: map)
        XCTAssertEqual(XCTWaiter().wait(for: [zoomedIn], timeout: wait), .completed, "zoom in changes span")
        let mid = map.value as? String ?? ""
        app.buttons["map.zoomOut"].tap()
        let zoomedOut = expectation(for: NSPredicate(format: "value != %@", mid), evaluatedWith: map)
        XCTAssertEqual(XCTWaiter().wait(for: [zoomedOut], timeout: wait), .completed, "zoom out changes span")
        XCTAssertTrue(app.buttons["pin.1"].isHittable, "pins survive zooming")
    }

    // MARK: - Accessibility audits

    func testAccessibilityAuditHome() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        audit(app)
    }

    func testAccessibilityAuditDetail() {
        let app = launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        row(app, 1).tap()
        XCTAssertTrue(app.staticTexts["detail.name"].waitForExistence(timeout: wait))
        audit(app)
    }

    func testAccessibilityAuditErrorAndDenied() {
        let failed = launch("-uitest-fail")
        XCTAssertTrue(failed.buttons["state.retry"].waitForExistence(timeout: wait))
        audit(failed)
        failed.terminate()

        let denied = launch("-uitest-denied")
        XCTAssertTrue(denied.buttons["state.settings"].waitForExistence(timeout: wait))
        audit(denied)
    }

    func testAccessibilityAuditLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"] + largeText
        app.launch()
        XCTAssertTrue(row(app, 1).waitForExistence(timeout: wait))
        XCTAssertTrue(row(app, 1).label.contains("0.2 mi"), row(app, 1).label)
        audit(app)
        row(app, 1).tap()
        XCTAssertTrue(app.staticTexts["detail.name"].waitForExistence(timeout: wait))
        audit(app)
    }
}
