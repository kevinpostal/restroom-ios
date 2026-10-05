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
    /// Only MapKit's own internals (attribution, compass, user dot) are ignored; app pins/rows on the map are not.
    private func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let map = app.otherElements["map"].firstMatch
        let mapFrame = map.exists ? map.frame : .zero
        let resume = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = resume }
        try? app.performAccessibilityAudit(for: .all) { issue in
            let el = issue.element
            let ownedByApp = el.map { $0.identifier.hasPrefix("pin.") || $0.identifier.hasPrefix("row.") } ?? true
            let insideMap = el.map { $0.identifier == "map" || mapFrame.contains($0.frame) } ?? false
            let ignore = insideMap && !ownedByApp
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
        let ys = (1...3).map { row(app, $0) }.map { r -> CGFloat in
            XCTAssertTrue(r.exists, r.identifier)
            return r.frame.minY
        }
        XCTAssertEqual(ys, ys.sorted(), "rows must be in distance order")
        XCTAssertEqual(app.staticTexts["header.title"].label, "Near you")
        let label = row(app, 1).label
        XCTAssertTrue(label.contains("Happy Lemon"), label)
        XCTAssertTrue(label.contains("0.4 mi"), label)
        XCTAssertTrue(label.contains("Accessible"), label)
        app.collectionViews["list"].swipeUp()
        XCTAssertTrue(row(app, 4).waitForExistence(timeout: wait), "farthest row reachable by scrolling")
        XCTAssertTrue(row(app, 4).label.contains("1.3 mi"), row(app, 4).label)
    }

    func testTapRowOpensDetailAndSelectsPin() {
        let app = launch()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: wait))
        row(app, 2).tap()
        let name = app.staticTexts["detail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: wait))
        XCTAssertEqual(name.label, "Kaiser Hospital")
        XCTAssertTrue(app.buttons["detail.directions"].isHittable)
        XCTAssertTrue(app.staticTexts["Unisex"].exists)
        XCTAssertTrue(app.buttons["pin.2"].isSelected)
        XCTAssertTrue(app.otherElements["map"].firstMatch.isHittable, "map stays visible with detail open")
        XCTAssertTrue(app.buttons["pin.2"].isHittable)
        app.buttons["detail.close"].tap()
        XCTAssertTrue(row(app, 2).waitForExistence(timeout: wait))
        XCTAssertFalse(app.staticTexts["detail.name"].exists)
        XCTAssertFalse(app.buttons["pin.2"].isSelected)
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
        XCTAssertTrue(row(app, 1).label.contains("0.4 mi"), row(app, 1).label)
        audit(app)
        row(app, 1).tap()
        XCTAssertTrue(app.staticTexts["detail.name"].waitForExistence(timeout: wait))
        audit(app)
    }
}
