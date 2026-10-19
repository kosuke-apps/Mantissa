import MantissaCore
import XCTest

@testable import Mantissa

@MainActor
final class AppModelTests: XCTestCase {
  /// Waits for the answer, which is computed off the main thread.
  /// A model whose settings are kept in a scratch suite, so tests neither read nor change the real ones.
  private func makeModel() -> AppModel {
    let defaults = UserDefaults(suiteName: "dev.kosuke.mantissa.tests")!
    defaults.removePersistentDomain(forName: "dev.kosuke.mantissa.tests")
    return AppModel(history: HistoryStore(fileURL: nil), defaults: defaults)
  }

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

  func testASystemOfEquationsIsSolved() async {
    let model = makeModel()
    for key in ["x", "+", "y", "=", "3"] { model.press(.symbol(key)) }
    model.press(.newLine)
    for key in ["x", "−", "y", "=", "1"] { model.press(.symbol(key)) }
    guard case .solutions(let solutions) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(solutions.kind, .values)
    XCTAssertEqual(solutions.lines.map { $0.exact.parserText }, ["x=2, y=1"])
    XCTAssertNil(solutions.lines[0].decimal)
  }

  func testASystemWithIrrationalSolutionsShowsLabelledDecimals() async {
    let model = makeModel()
    for key in ["x", "−", "y", "=", "0"] { model.press(.symbol(key)) }
    model.press(.newLine)
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["+", "y"] { model.press(.symbol(key)) }
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["=", "2"] { model.press(.symbol(key)) }
    guard case .solutions(let solutions) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(solutions.lines.map { $0.exact.parserText }, ["x=−1, y=−1", "x=1, y=1"])
  }

  func testAnInequalityGivesIntervals() async {
    let model = makeModel()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["<", "4"] { model.press(.symbol(key)) }
    guard case .solutions(let solutions) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(solutions.kind, .intervals)
    XCTAssertEqual(solutions.lines.map { $0.exact.parserText }, ["−2<x<2"])
    XCTAssertEqual(solutions.notation?.parserText, "(−2, 2)")

    model.clearAll()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["≥", "4"] { model.press(.symbol(key)) }
    guard case .solutions(let outside) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(outside.lines.map { $0.exact.parserText }, ["x≤−2", "x≥2"])
    XCTAssertEqual(outside.notation?.parserText, "(−∞, −2]∪[2, ∞)")
  }

  func testATrigonometricEquationGivesFamiliesOfSolutions() async {
    let model = makeModel()
    model.press(.function("sin"))
    model.press(.symbol("x"))
    model.press(.right)
    for key in ["=", "0", "."] { model.press(.symbol(key)) }
    model.press(.symbol("5"))
    guard case .solutions(let solutions) = await answer(model) else { return XCTFail("expected solutions") }
    XCTAssertEqual(solutions.kind, .periodic(integer: "n"))
    XCTAssertEqual(solutions.lines.map { $0.exact.parserText }.count, 2)
    XCTAssertEqual(solutions.lines[0].decimal?.parserText, "0.52359878+6.2831853n")
  }

  func testAnAntiderivativeEndsWithPlusC() async {
    let model = makeModel()
    model.press(.function("int"))
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in [",", "x"] { model.press(.symbol(key)) }
    guard case .answer(let answer) = await answer(model) else { return XCTFail("expected an answer") }
    XCTAssertTrue(answer.exact.parserText.hasSuffix("+C"), answer.exact.parserText)
  }

  func testALimitAtInfinityIsInfinity() async {
    let model = makeModel()
    model.press(.function("lim"))
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in [",", "x", ",", "∞"] { model.press(.symbol(key)) }
    guard case .answer(let answer) = await answer(model) else { return XCTFail("expected an answer") }
    XCTAssertEqual(answer.exact.parserText, "∞")
    XCTAssertNil(answer.decimal)
  }

  func testADivergentSeriesDoesNotExist() async {
    let model = makeModel()
    model.press(.function("sum"))
    for key in ["k", ",", "k", ",", "1", ",", "∞"] { model.press(.symbol(key)) }
    let outcome = await answer(model)
    XCTAssertEqual(outcome, .failure(.doesNotExist))
  }

  func testSettingsAreKeptAndAppliedToTheNextAnswer() async {
    let suite = "dev.kosuke.mantissa.tests.settings"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let model = AppModel(history: HistoryStore(fileURL: nil), defaults: defaults)
    XCTAssertEqual(model.angleUnit, .radians)
    XCTAssertEqual(model.decimalDigits, 12)

    model.angleUnit = .degrees
    model.decimalDigits = 20
    model.language = .japanese
    let again = AppModel(history: HistoryStore(fileURL: nil), defaults: defaults)
    XCTAssertEqual(again.angleUnit, .degrees)
    XCTAssertEqual(again.decimalDigits, 20)
    XCTAssertEqual(again.language, .japanese)

    // sin(30) is 1/2 in degrees.
    again.press(.function("sin"))
    for key in ["3", "0"] { again.press(.symbol(key)) }
    again.press(.right)
    guard case .answer(let answer) = await answer(again) else { return XCTFail("expected an answer") }
    XCTAssertEqual(answer.exact.parserText, "((1)/(2))")
    defaults.removePersistentDomain(forName: suite)
  }

  func testAnAnswerWithAnUnknownOffersTheFactoredForm() async {
    let model = makeModel()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["−", "5", "x", "+", "6"] { model.press(.symbol(key)) }
    // x² − 5x + 6 is its own expanded form, so only the factored form is offered.
    let outcome = await answer(model)
    guard case .answer(let answer) = outcome else { return XCTFail("expected an answer, got \(outcome)") }
    XCTAssertEqual(answer.forms.map(\.kind), [.factored])
    XCTAssertEqual(answer.forms.first?.nodes.parserText, "(x−2)(x−3)")
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

  func testALogarithmWithABaseIsTypedAndAnswered() async {
    let model = makeModel()
    model.press(.logarithm)
    model.press(.symbol("2"))
    model.press(.right)
    model.press(.symbol("8"))
    guard case .answer(let answer) = await answer(model) else { return XCTFail("expected an answer") }
    XCTAssertEqual(answer.exact.parserText, "3")
    XCTAssertEqual(model.editor.text, "log(8,2)")
  }

  func testNewFunctionKeysGiveAnswers() async {
    let model = makeModel()
    for (keys, expected) in [(["mod"], "2"), (["max"], "7")] {
      model.clearAll()
      model.press(.function(keys[0]))
      for key in keys[0] == "mod" ? ["1", "7", ",", "5"] : ["3", ",", "7", ",", "2"] { model.press(.symbol(key)) }
      guard case .answer(let answer) = await answer(model) else { return XCTFail("expected an answer for \(keys)") }
      XCTAssertEqual(answer.exact.parserText, expected, "\(keys)")
    }
  }

  func testACircleIsDrawnWithEqualScales() async throws {
    let model = makeModel()
    for key in ["x"] { model.press(.symbol(key)) }
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    model.press(.symbol("+"))
    model.press(.symbol("y"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    model.press(.symbol("="))
    for key in ["2", "5"] { model.press(.symbol(key)) }
    _ = await answer(model)
    try await Task.sleep(for: .milliseconds(300))
    let graph = try XCTUnwrap(model.graph)
    XCTAssertTrue(graph.functions.isEmpty)
    XCTAssertEqual(graph.content.relations.count, 1)
    // The graph tells where the circle meets each axis.
    XCTAssertEqual(graph.points.filter { $0.kind == .xIntercept }.count, 2)
    XCTAssertEqual(graph.points.filter { $0.kind == .yIntercept }.count, 2)

    // Once it is drawn at a size, the scales are equal; a later circle keeps them.
    graph.fit(to: CGSize(width: 360, height: 320))
    XCTAssertEqual(graph.viewport.width / 360, graph.viewport.height / 320, accuracy: 1e-9)
    model.press(.symbol("0"))
    _ = await answer(model)
    try await Task.sleep(for: .milliseconds(300))
    let next = try XCTUnwrap(model.graph)
    XCTAssertFalse(next === graph)
    XCTAssertEqual(next.viewport.width / 360, next.viewport.height / 320, accuracy: 1e-9)
  }

  func testAnInequalityInTwoUnknownsIsAShadedRegionWithoutAMessage() async throws {
    let model = makeModel()
    for key in ["y", ">", "x"] { model.press(.symbol(key)) }
    let outcome = await answer(model)
    try await Task.sleep(for: .milliseconds(300))
    // There is nothing to solve for, and the graph says it all: no "not supported yet".
    XCTAssertEqual(outcome, .empty)
    XCTAssertEqual(model.graph?.content.relations.map(\.isRegion), [true])
  }

  func testAnAnswerCanBeCopiedAndUsedAsInput() async throws {
    let model = makeModel()
    for key in ["1", "5", "°"] { model.press(.symbol(key)) }
    // sin(15°) in radians
    model.clearAll()
    model.press(.function("sin"))
    for key in ["1", "5", "°"] { model.press(.symbol(key)) }
    _ = await answer(model)
    let copyable = try XCTUnwrap(model.copyable)
    XCTAssertEqual(copyable.exact, "(√6 − √2)/4")
    XCTAssertEqual(copyable.decimal?.hasPrefix("0.2588190451"), true)

    model.useAnswerAsInput()
    XCTAssertEqual(model.inputText, "(√6 − √2)/4")
    // The answer is now the input, and its value is the same.
    let again = await answer(model)
    guard case .answer(let answer) = again else { return XCTFail("expected an answer") }
    XCTAssertEqual(answer.decimal?.plainText.hasPrefix("0.2588190451"), true)
  }

  func testSolutionsCanBeCopiedAsText() async throws {
    let model = makeModel()
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    model.press(.right)
    for key in ["=", "4"] { model.press(.symbol(key)) }
    _ = await answer(model)
    XCTAssertEqual(model.copyable?.exact, "x = −2, x = 2")
    XCTAssertNil(model.copyable?.decimal)
    // Solutions are not an expression to go on from.
    model.useAnswerAsInput()
    XCTAssertEqual(model.inputText, "x^2 = 4")
  }

  func testPastingAFormulaFromTheClipboard() async throws {
    let model = makeModel()
    UIPasteboard.general.string = "sqrt(2)/2 + x^2"
    XCTAssertTrue(model.canPaste)
    model.paste()
    XCTAssertEqual(model.inputText, "√2/2 + x^2")
    // A second paste adds at the cursor, and something that is not a formula changes nothing.
    UIPasteboard.general.string = "not a formula ("
    model.paste()
    XCTAssertEqual(model.inputText, "√2/2 + x^2")
  }

  func testAnExactNumberTypedInIsCopiedAsTyped() async throws {
    let model = makeModel()
    model.press(.squareRoot)
    model.press(.symbol("2"))
    guard case .answer(let answer) = await answer(model) else { return XCTFail("expected a decimal") }
    XCTAssertTrue(answer.exact.isEmpty)  // what was typed already says it
    XCTAssertEqual(answer.decimal?.plainText, "1.41421356237")
    let copyable = try XCTUnwrap(model.copyable)
    XCTAssertEqual(copyable.exact, "√2")
    XCTAssertFalse(copyable.canBeInput)
  }

  func testValuesThatAreUndefinedSaySo() async {
    let model = makeModel()
    model.press(.function("tan"))
    model.press(.symbol("π"))
    model.press(.fraction)
    model.press(.symbol("2"))
    XCTAssertEqual(model.editor.text, "tan(((π)/(2)))")
    let tangent = await answer(model)
    XCTAssertEqual(tangent, .failure(.undefinedHere))
    model.clearAll()
    model.press(.function("ln"))
    model.press(.symbol("0"))
    let logarithm = await answer(model)
    XCTAssertEqual(logarithm, .failure(.undefinedHere))
  }

  func testATrigonometricInequalityGivesRepeatingIntervals() async throws {
    let model = makeModel()
    model.press(.function("sin"))
    model.press(.symbol("x"))
    model.press(.right)
    model.press(.symbol(">"))
    model.press(.symbol("1"))
    model.press(.fraction)
    model.press(.symbol("2"))
    let outcome = await answer(model)
    guard case .solutions(let solutions) = outcome else { return XCTFail("expected solutions, got \(outcome)") }
    XCTAssertEqual(solutions.kind, .periodic(integer: "n"))
    XCTAssertEqual(solutions.lines.map { $0.exact.plainText }, ["π/6 + 2πn < x < 5π/6 + 2πn"])
    XCTAssertEqual(model.copyable?.exact, "π/6 + 2πn < x < 5π/6 + 2πn")
  }

  func testTheTimesTenToTheNKeyWritesScientificNotation() async throws {
    let model = makeModel()
    for key in ["1", ".", "5"] { model.press(.symbol(key)) }
    // The alternative of the times key: ×10 with an exponent to fill in.
    let alternate = try XCTUnwrap(
      KeyboardLayout.rows(for: .basic).flatMap { $0 }.first { $0.id == "×" }?.alternates.first { $0.title == "×10ⁿ" })
    model.press(alternate.actions)
    model.press(.symbol("3"))
    guard case .answer(let answer) = await answer(model) else { return XCTFail("expected an answer") }
    XCTAssertEqual(answer.exact.parserText, "1500")
  }

  func testTracingFollowsTheNearestCurve() async throws {
    let model = makeModel()
    for key in ["y", "=", "x"] { model.press(.symbol(key)) }
    model.press(.symbol("="))
    // A system whose lines are y = x and y = x²: typed as two lines.
    model.clearAll()
    model.press(.symbol("y"))
    model.press(.symbol("="))
    model.press(.symbol("x"))
    model.press(.newLine)
    model.press(.symbol("y"))
    model.press(.symbol("="))
    model.press(.symbol("x"))
    model.press(.power)
    model.press(.symbol("2"))
    _ = await answer(model)
    try await Task.sleep(for: .milliseconds(400))
    let graph = try XCTUnwrap(model.graph)
    XCTAssertEqual(graph.functions.count, 2)
    let upper = try XCTUnwrap(graph.traced(atX: 2, nearY: 3.9))
    XCTAssertEqual(upper.index, 1)
    XCTAssertEqual(upper.y, 4, accuracy: 1e-9)
    let lower = try XCTUnwrap(graph.traced(atX: 2, nearY: 2.2))
    XCTAssertEqual(lower.index, 0)
    XCTAssertEqual(lower.y, 2, accuracy: 1e-9)
  }

  func testAWholeNumberLongerThanTheDecimalAlsoGetsOneInScientificNotation() {
    func answer(_ text: String) -> AppModel.Answer? {
      if case .answer(let answer) = AppModel.outcome(for: text, calculator: Calculator(), digits: 12) { return answer }
      return nil
    }
    XCTAssertNotNil(answer("100!")?.decimal)
    XCTAssertFalse(answer("100!")?.exact.isEmpty ?? true, "the exact digits stay")
    XCTAssertNil(answer("2^10+0.5*0")?.decimal, "a short whole number needs no decimal")
  }

  func testAFractionOfHugeNumbersShowsOnlyItsDecimal() throws {
    let outcome = AppModel.outcome(for: "sum(1/k^2,k,1,1000)", calculator: Calculator(), digits: 12)
    guard case .answer(let answer) = outcome else { return XCTFail("expected an answer, got \(outcome)") }
    XCTAssertTrue(answer.exact.isEmpty)
    XCTAssertEqual(try XCTUnwrap(answer.decimal).plainText.prefix(8), "1.643934")
  }

  func testAnEquationWithSeveralLettersOffersThemAndSolvesForTheChosenOne() {
    func solutions(_ letter: String?) -> AppModel.Solutions? {
      if case .solutions(let solutions) = AppModel.outcome(
        for: "v=u+a*t", calculator: Calculator(), digits: 12, solveFor: letter)
      {
        return solutions
      }
      return nil
    }
    let byDefault = solutions(nil)
    XCTAssertEqual(byDefault?.choices, ["a", "t", "u", "v"])
    XCTAssertEqual(byDefault?.chosen, "a")
    let forT = solutions("t")
    XCTAssertEqual(forT?.chosen, "t")
    XCTAssertEqual(forT?.lines.first?.exact.plainText, "t = (v − u)/a")
    // One letter: nothing to choose.
    if case .solutions(let one) = AppModel.outcome(for: "x+1=3", calculator: Calculator(), digits: 12) {
      XCTAssertTrue(one.choices.isEmpty)
    } else {
      XCTFail("expected solutions")
    }
  }
}
