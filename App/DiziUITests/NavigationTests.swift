import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testOpensAPieceFromTheList() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["茉莉花"].tap()

        XCTAssertTrue(app.navigationBars["茉莉花"].waitForExistence(timeout: 5))
    }
}
