import XCTest

/// Runs Xcode's accessibility audit (contrast, labels, hit regions, text that does not scale, clipped text) on the screens of the
/// app. A debug build takes `-MantissaInput` on the launch line, which types a formula, so each state can be reached without
/// tapping keys.
final class AccessibilityAuditTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = true
  }

  private func launch(_ input: String? = nil, keyboardMode: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    if let input { app.launchArguments += ["-MantissaInput", input] }
    // The keyboard's mode is a setting kept in the defaults, which a launch argument overrides for this run.
    app.launchArguments += ["-keyboardMode", keyboardMode ?? "standard"]
    app.launch()
    return app
  }

  /// Audits the screen and writes what it found into the test log, one line per issue, so that all of them can be read at once.
  private func audit(_ app: XCUIApplication, _ name: String) throws {
    var found = 0
    try app.performAccessibilityAudit { issue in
      found += 1
      let element = issue.element.map { "\($0.elementType.rawValue) “\($0.label)” \($0.frame)" } ?? "no element"
      print(
        "AUDIT \(name): \(issue.auditType.rawValue) — \(issue.compactDescription) — \(issue.detailedDescription) — \(element)"
      )
      return true  // keep going: the point is the list
    }
    print("AUDIT \(name): \(found) issue(s)")
  }

  func testEmptyScreen() throws { try audit(launch(), "empty") }

  func testAnEquationWithItsGraph() throws { try audit(launch("x^2-5x+6=0"), "equation") }

  func testAMatrixAnswer() throws { try audit(launch("[[1,2],[3,4]]^(-1)"), "matrix") }

  func testASystemOfEquations() throws { try audit(launch("x+y=3\nx-y=1"), "system") }

  func testAnIntegral() throws { try audit(launch("int(x^2,x)"), "integral") }

  func testAStatisticsReport() throws { try audit(launch("stats(2,4,4,4,5,5,7,9)"), "statistics") }

  func testARegressionWithItsGraph() throws {
    try audit(launch("linreg([[1,2],[2,4],[3,5],[4,4],[5,5]])"), "regression")
  }

  func testTheStatisticsKeyboardPage() throws {
    let app = launch(keyboardMode: "statistics")
    app.buttons["Statistics"].tap()
    try audit(app, "stats-keys")
  }

  func testTheProbabilityKeyboardPage() throws {
    let app = launch(keyboardMode: "statistics")
    app.buttons["Probability"].tap()
    try audit(app, "prob-keys")
  }

  func testTheMatrixKeyboardPage() throws {
    let app = launch(keyboardMode: "matrix")
    app.buttons["Matrix"].tap()
    try audit(app, "matrix-keys")
  }

  func testTheHistorySheet() throws {
    let app = launch("x^2-5x+6=0")
    app.buttons["History"].tap()
    XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    try audit(app, "history")
  }

  func testTheSettingsSheet() throws {
    let app = launch()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    try audit(app, "settings")
  }
}
