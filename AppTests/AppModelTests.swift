import MantissaCore
import XCTest

@testable import Mantissa

@MainActor
final class AppModelTests: XCTestCase {
  /// Waits for the answer, which is computed off the main thread.
  private func makeModel() -> AppModel { AppModel(history: HistoryStore(fileURL: nil)) }

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
    let model = makeModel()
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

  func testAFunctionOfXIsDrawn() async throws {
    let model = makeModel()
    for key in ["x", "+", "1"] { model.press(.symbol(key)) }
    _ = await answer(model)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(model.graph?.functions.count, 1)
    XCTAssertEqual(model.graph?.viewport.xMin.isFinite, true)

    model.clearAll()
    XCTAssertNil(model.graph)
  }

  func testAnEquationIsSolvedAndItsSidesAreDrawn() async throws {
    let model = makeModel()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["−", "4", "="] { model.press(.symbol(key)) }
    model.press(.symbol("0"))
    let outcome = await answer(model)
    guard case .solutions(let solutions) = outcome else { return XCTFail("expected solutions, got \(outcome)") }
    XCTAssertEqual(solutions.kind, .values)
    XCTAssertEqual(solutions.lines.map { $0.exact.parserText }, ["x=−2", "x=2"])
    XCTAssertNil(solutions.lines[0].decimal)
    XCTAssertEqual(solutions.summary.parserText, "x=−2, x=2")
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertEqual(model.graph?.functions.count, 1)  // x² − 4, whose roots are the solutions
  }

  func testSolutionsWithRootsAndComplexNumbers() async {
    let model = makeModel()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["−", "2", "="] { model.press(.symbol(key)) }
    model.press(.symbol("0"))
    guard case .solutions(let roots) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(roots.lines.map { $0.exact.parserText }, ["x=−√(2)", "x=√(2)"])
    XCTAssertEqual(roots.lines[1].decimal?.parserText, "1.41421356237")

    model.clearAll()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["+", "1", "="] { model.press(.symbol(key)) }
    model.press(.symbol("0"))
    guard case .solutions(let complex) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(complex.lines.map { $0.exact.parserText }, ["x=−i", "x=i"])
  }

  func testAnEquationWithNoSolutionAndAnIdentity() async {
    let model = makeModel()
    for key in ["x", "+", "1", "=", "x"] { model.press(.symbol(key)) }
    guard case .solutions(let none) = await answer(model) else { return XCTFail("expected a solution") }
    XCTAssertEqual(none.kind, .none)

    model.clearAll()
    for key in ["x", "=", "x"] { model.press(.symbol(key)) }
    guard case .solutions(let all) = await answer(model) else { return XCTFail("expected a solution") }
    XCTAssertEqual(all.kind, .everything)
  }

  func testTheGraphKeepsItsWindowWhileTheFunctionIsTheSame() async throws {
    let model = makeModel()
    for key in ["x", "+", "1"] { model.press(.symbol(key)) }
    try await Task.sleep(for: .milliseconds(300))
    let graph = try XCTUnwrap(model.graph)
    graph.viewport = graph.viewport.panned(dx: 5, dy: 0)
    // A key that changes nothing about the function leaves the graph, and where the user moved it, alone.
    model.press(.left)
    try await Task.sleep(for: .milliseconds(300))
    XCTAssertTrue(model.graph === graph)
  }

  func testASquareRootOfANegativeNumberIsImaginaryWithADecimal() async {
    let model = makeModel()
    model.press(.squareRoot)
    for key in ["−", "7"] { model.press(.symbol(key)) }
    model.press(.right)
    let outcome = await answer(model)
    guard case .answer(let answer) = outcome else { return XCTFail("expected an answer, got \(outcome)") }
    XCTAssertEqual(answer.exact.parserText, "√(7)i")
    XCTAssertEqual(answer.decimal?.parserText, "2.64575131106i")
    XCTAssertFalse(answer.hasNoRealValue)
  }

  func testAWholeImaginaryAnswerNeedsNoDecimal() async {
    let model = makeModel()
    model.press(.squareRoot)
    for key in ["−", "4"] { model.press(.symbol(key)) }
    model.press(.right)
    let outcome = await answer(model)
    guard case .answer(let answer) = outcome else { return XCTFail("expected an answer, got \(outcome)") }
    XCTAssertEqual(answer.exact.parserText, "2i")
    XCTAssertNil(answer.decimal)
  }

  func testAnUnfinishedFormulaIsIncomplete() async {
    let model = makeModel()
    model.press(.symbol("5"))
    model.press(.symbol("+"))
    let outcome = await answer(model)
    XCTAssertEqual(outcome, .incomplete)
  }

  func testClearingEmptiesTheAnswer() async {
    let model = makeModel()
    model.press(.symbol("2"))
    model.press(.symbol("+"))
    model.press(.symbol("2"))
    _ = await answer(model)
    model.clearAll()
    XCTAssertEqual(model.outcome, .empty)
    XCTAssertTrue(model.editor.isEmpty)
  }

  func testDivisionByZeroIsReported() async {
    let model = makeModel()
    for key in ["1", "÷", "0"] { model.press(.symbol(key)) }
    let outcome = await answer(model)
    XCTAssertEqual(outcome, .failure(.divisionByZero))
  }
}
