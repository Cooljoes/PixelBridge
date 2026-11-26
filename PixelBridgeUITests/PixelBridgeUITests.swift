import XCTest

final class PixelBridgeUITests: XCTestCase {
    @MainActor func testBrowsePreviewAndImportOriginal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        app.buttons["Open demo camera"].tap()
        XCTAssertTrue(app.staticTexts["Ready"].waitForExistence(timeout: 15))
        app.buttons["Gallery"].firstMatch.tap()
        app.buttons.containing(.staticText, identifier: "TestChart.jpg").firstMatch.tap()
        app.buttons["Load thumbnail"].tap()
        XCTAssertTrue(app.images["Camera thumbnail"].waitForExistence(timeout: 10))
        app.buttons["Download original"].tap()
        XCTAssertTrue(app.staticTexts["Saved TestChart.jpg"].waitForExistence(timeout: 12))
        app.buttons["Transfers"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save to Photos"].exists)
    }
}

extension PixelBridgeUITests {
    @MainActor func testPhysicalProfileAndInvalidAddress() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        let host = app.textFields["Camera IPv4 address"]
        host.tap()
        host.typeText("999")
        app.buttons["Connect over Wi-Fi"].tap()
        XCTAssertTrue(app.staticTexts["Enter the private IPv4 address shown by your camera."].waitForExistence(timeout: 5))
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["Camera compatibility"].tap()
        app.buttons["Nikon Z8"].tap()
        let offState = app.descendants(matching: .any)["profile.uploadWhileOff"].firstMatch
        XCTAssertTrue(offState.exists)
        XCTAssertEqual(offState.value as? String, "Untested")
    }
}
