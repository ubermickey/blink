import XCTest

final class BlinkUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @discardableResult
  private func launchApp(entry: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["BLINK_UI_TEST_MODE"] = "1"
    if let entry {
      app.launchEnvironment["BLINK_UI_TEST_ENTRY"] = entry
    }
    app.launch()
    XCTAssertTrue(app.waitForExistence(timeout: 10))
    app.activate()
    return app
  }

  func testLaunchesToShell() throws {
    _ = launchApp()
  }

  func testCanOpenConfigFromKeyboardShortcut() throws {
    let app = launchApp(entry: "config")
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
  }

  func testCanOpenSnippetsFromKeyboardShortcut() throws {
    let app = launchApp(entry: "snippets")
    XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10))
  }
}
