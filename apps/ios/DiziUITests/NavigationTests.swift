import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testOpensAChartAndAScoreFromTheTabs() {
        let app = XCUIApplication()
        app.launch()

        let firstPiece = app.collectionViews.buttons.matching(identifier: "piece").firstMatch
        XCTAssertTrue(firstPiece.waitForExistence(timeout: 5))
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "list"
        list.lifetime = .keepAlways
        add(list)

        // The 词典 opens a chart; a dictionary lost between the tools and the app would list no entry.
        app.tabBars.buttons["词典"].tap()
        let entry = app.collectionViews.buttons.matching(identifier: "entry").firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let chartRow = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '缓吹'"))
        XCTAssertTrue(chartRow.firstMatch.waitForExistence(timeout: 5))
        let chart = XCTAttachment(screenshot: app.screenshot())
        chart.name = "chart"
        chart.lifetime = .keepAlways
        add(chart)

        // The 乐曲 tab lists its own pieces; a section kind lost on the way would leave it empty.
        app.tabBars.buttons["乐曲"].tap()
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
