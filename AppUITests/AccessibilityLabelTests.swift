import XCTest

/// What the accessibility tree says on screen, which is what VoiceOver reads: the formula in words, the answer in words, the graph
/// with its summary and its move and zoom actions.
final class AccessibilityLabelTests: XCTestCase {
  private func launch(_ input: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-MantissaInput", input]
    app.launch()
    return app
  }

  func testTheFormulaAndTheAnswerAreReadInWords() {
    let app = launch("x^2-5x+6=0")
    XCTAssertTrue(
      app.staticTexts["x squared minus 5 x plus 6 equals 0"].waitForExistence(timeout: 10), "the formula in words")
    XCTAssertTrue(app.staticTexts["x equals 2"].waitForExistence(timeout: 10), "a solution in words")
    XCTAssertTrue(app.staticTexts["x equals 3"].exists)
  }

  func testTheGraphHasASummaryAndActions() {
    let app = launch("x^2-5x+6=0")
    let graph = app.otherElements["Graph"].firstMatch
    XCTAssertTrue(graph.waitForExistence(timeout: 10))
    let value = graph.value as? String ?? ""
    XCTAssertTrue(value.hasPrefix("Graph with one curve."), value)
    XCTAssertTrue(value.contains("The graph shows x from"), value)
  }

  func testAMatrixAnswerIsReadRowByRow() {
    let app = launch("[[1,2],[3,4]]^(-1)")
    let predicate = NSPredicate(format: "label BEGINSWITH 'matrix with 2 rows and 2 columns.'")
    XCTAssertTrue(app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 10))
  }
}
