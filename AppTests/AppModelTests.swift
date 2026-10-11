import MantissaCore
import XCTest

@testable import Mantissa

@MainActor
final class AppModelTests: XCTestCase {
  /// Waits for the answer, which is computed off the main thread.
  private func answer(_ model: AppModel, timeout: TimeInterval = 5) async -> AppModel.Outcome {
    let deadline = Date().addingTimeInterval(timeout)
    var last = model.outcome
    while Date() < deadline {
      try? await Task.sleep(nanoseconds: 20_000_000)
      last = model.outcome
      if last != .empty { break }
    }
    return last
  }

  func testTypingAFractionGivesAnAnswer() async {
    let model = AppModel()
    model.press(.symbol("1"))
    model.press(.fraction)
    model.press(.symbol("4"))
    model.press(.right)
    model.press(.symbol("+"))
    model.press(.symbol("1"))
    let outcome = await answer(model)
    guard case .answer(let answer) = outcome else { return XCTFail("expected an answer, got \(outcome)") }
    XCTAssertEqual(answer.exact.parserText, "((5)/(4))")
    XCTAssertEqual(answer.decimal?.parserText, "1.25")
  }

  func testAnUnfinishedFormulaIsIncomplete() async {
    let model = AppModel()
    model.press(.symbol("5"))
    model.press(.symbol("+"))
    let outcome = await answer(model)
    XCTAssertEqual(outcome, .incomplete)
  }

  func testClearingEmptiesTheAnswer() async {
    let model = AppModel()
    model.press(.symbol("2"))
    model.press(.symbol("+"))
    model.press(.symbol("2"))
    _ = await answer(model)
    model.clearAll()
    XCTAssertEqual(model.outcome, .empty)
    XCTAssertTrue(model.editor.isEmpty)
  }

  func testDivisionByZeroIsReported() async {
    let model = AppModel()
    for key in ["1", "÷", "0"] { model.press(.symbol(key)) }
    let outcome = await answer(model)
    XCTAssertEqual(outcome, .failure(.divisionByZero))
  }
}
