import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testOpensAScoreFromTheList() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["茉莉花"].tap()

        XCTAssertTrue(app.navigationBars["茉莉花"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["score"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "score"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
