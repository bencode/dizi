import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testOpensAScoreFromTheList() {
        let app = XCUIApplication()
        app.launch()

        let firstPiece = app.collectionViews.buttons.firstMatch
        XCTAssertTrue(firstPiece.waitForExistence(timeout: 5))
        firstPiece.tap()

        XCTAssertTrue(app.descendants(matching: .any)["score"].waitForExistence(timeout: 5))
        // Only the stopped page: while 走谱 runs the page redraws every frame, so the app never goes idle
        // for XCUITest. The transport logic is covered by ScoreKit's unit tests.
        XCTAssertTrue(app.buttons["开始"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "score"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
