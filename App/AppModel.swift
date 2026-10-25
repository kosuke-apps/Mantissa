import MantissaCore
import Observation
import SwiftUI
import UIKit

/// What a key does.
enum KeyAction: Hashable {
  case symbol(String)
  /// A symbol put in as it is, a lone bracket for instance (`symbol("(")` would make a pair).
  case literal(String)
  /// An exponent that is already filled in, as on the x² and x³ keys.
  case exponent(String)
  case fraction, power, squareRoot, nthRoot, group, absolute
  /// `log` with a base written small below it.
  case logarithm
  case function(String)
  /// ∫, Σ, lim or d/dx with its slots.
  case calculus(CalculusKind)
  /// A matrix of this size with empty cells; a vector has one column.
  case matrix(rows: Int, columns: Int)
  /// A row or column added to, or removed from, the matrix the cursor is in.
  case matrixChange(MathEditor.MatrixChange)
  case left, right, newLine, backspace
}

/// The state of the calculator screen: what has been typed, and what it comes to.
@MainActor @Observable
final class AppModel {
  struct Answer: Equatable, Codable {
    /// The exact value, typeset.
    var exact: [MathNode]
    /// The value as a decimal, when that says something more than the exact form does.
    var decimal: [MathNode]?
    /// The exact form is not a real number (the root of a negative number, for now).
    var hasNoRealValue: Bool
    /// Other ways of writing the answer when it has an unknown in it.
    var forms: [Form] = []

    struct Form: Equatable, Codable {
      enum Kind: String, Codable { case expanded, factored, simplified, combined }
      var kind: Kind
      var nodes: [MathNode]
    }
  }

  typealias Solutions = SolutionsDisplay

  enum Failure: Equatable {
    case divisionByZero
    case noRealAnswer
    /// The matrices are of sizes that do not fit the operation.
    case sizesDoNotFit
    /// A matrix whose determinant is zero.
    case noInverse
    case tooLarge
    case notSupportedYet
    /// A limit whose sides disagree, an integral or a series that diverges.
    /// A value that is undefined, such as `tan(π/2)` or `ln(0)`.
    case undefinedHere
    case doesNotExist
  }

  enum Outcome: Equatable {
    case empty
    /// The formula is not finished, or not something that can be read.
    case incomplete
    case answer(Answer)
    case solutions(Solutions)
    case failure(Failure)
  }

  private(set) var editor = MathEditor()
  private(set) var outcome = Outcome.empty
  let history: HistoryStore
  var showsHistory = false
  var showsSettings = false
  /// The graph of what is typed, when it is a function of x.
  private(set) var graph: GraphModel?
  var settings = CalculatorSettings() {
    didSet {
      storage.angleUnit = settings.angleUnit
      refresh()
    }
  }
  /// Significant digits shown for decimals.
  var decimalDigits: Int {
    didSet {
      storage.decimalDigits = decimalDigits
      refresh()
    }
  }
  /// The language the app shows itself in.
  var language: AppLanguage {
    didSet {
      storage.language = language
      Localizer.bundle = language.bundle
      refresh()
    }
  }

  /// Radians or degrees, the unit of `sin(30)`.
  var angleUnit: AngleUnit {
    get { settings.angleUnit }
    set { settings.angleUnit = newValue }
  }

  private let storage: SettingsStorage

  /// The letter an equation with several is solved for, when the user has chosen one; `nil` for the one picked by default.
  private(set) var solveFor: String?

  private var evaluation: Task<Void, Never>?
  private var recording: Task<Void, Never>?
  private let feedback = UIImpactFeedbackGenerator(style: .light)

  init(history: HistoryStore, defaults: UserDefaults = .standard) {
    self.history = history
    let storage = SettingsStorage(defaults: defaults)
    self.storage = storage
    decimalDigits = storage.decimalDigits
    language = storage.language
    var calculator = CalculatorSettings()
    calculator.angleUnit = storage.angleUnit
    settings = calculator
    Localizer.bundle = storage.language.bundle
  }

  convenience init() {
    self.init(history: HistoryStore())
    #if DEBUG
      // `-MantissaInput "x^2-4"` on the launch command line types a formula, for checking a screen without tapping keys.
      let arguments = ProcessInfo.processInfo.arguments
      if let index = arguments.firstIndex(of: "-MantissaInput"), index + 1 < arguments.count {
        let text = arguments[index + 1]
        _ = editor.paste(text.replacingOccurrences(of: "\\n", with: "\n"))
        refresh()
      }
    #endif
  }

  /// Puts an earlier problem back into the calculator.
  func open(_ entry: HistoryEntry) {
    editor = MathEditor(lines: entry.lines)
    solveFor = nil
    refresh()
  }

  func press(_ action: KeyAction) {
    feedback.impactOccurred()
    perform(action)
    refresh()
  }

  func press(_ actions: [KeyAction]) {
    feedback.impactOccurred()
    for action in actions { perform(action) }
    refresh()
  }

  /// Puts the cursor where the user tapped the formula.
  func moveCursor(to cursor: MathCursor) {
    if editor.moveCursor(to: cursor) { refresh() }
  }

  func clearAll() {
    editor.clear()
    solveFor = nil
    refresh()
  }

  /// Solves the equation for another of its letters.
  func solve(for letter: String) {
    feedback.impactOccurred()
    solveFor = letter
    refresh()
  }

  // MARK: Pasteboard and answers

  /// Whether the pasteboard holds text (asking does not show the system's paste prompt; reading it does).
  var canPaste: Bool { UIPasteboard.general.hasStrings }

  /// Puts the formula on the pasteboard at the cursor, typeset, when it reads as one.
  func paste() {
    guard let text = UIPasteboard.general.string, editor.paste(text) else { return }
    feedback.impactOccurred()
    refresh()
  }

  /// What is typed, as text, one line for each equation.
  var inputText: String { editor.lines.map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n") }

  func copyInput() { UIPasteboard.general.string = inputText }

  /// The texts the answer can be copied as: the exact one, and the decimal when there is one.
  struct Copyable: Equatable {
    var exact: String
    var decimal: String?
    /// Whether the answer is a formula that can replace the input.
    var canBeInput = false
  }

  var copyable: Copyable? {
    switch outcome {
    case .answer(let answer):
      let nodes = answer.exact.isEmpty ? (answer.forms.first?.nodes ?? []) : answer.exact
      // When what was typed is already the exact answer (√2), that is what there is to copy.
      return Copyable(
        exact: nodes.isEmpty ? inputText : nodes.plainText, decimal: answer.decimal?.plainText,
        canBeInput: !nodes.isEmpty)
    case .solutions(let solutions):
      return Copyable(exact: solutions.summary.plainText)
    default:
      return nil
    }
  }

  func copy(_ text: String) {
    UIPasteboard.general.string = text
    feedback.impactOccurred()
  }

  /// Replaces what is typed with the answer, to go on from it.
  func useAnswerAsInput() {
    guard case .answer(let answer) = outcome else { return }
    let nodes = answer.exact.isEmpty ? (answer.forms.first?.nodes ?? []) : answer.exact
    guard !nodes.isEmpty else { return }
    editor = MathEditor(lines: [nodes])
    feedback.impactOccurred()
    refresh()
  }

  private func perform(_ action: KeyAction) {
    switch action {
    case .symbol(let text): editor.insert(text)
    case .literal(let text): editor.insertLiteral(text)
    case .exponent(let digit):
      editor.insertPower()
      editor.insert(digit)
      editor.moveRight()
    case .fraction: editor.insertFraction()
    case .power: editor.insertPower()
    case .squareRoot: editor.insertRadical()
    case .nthRoot: editor.insertRadical(withIndex: true)
    case .group: editor.insertGroup()
    case .absolute: editor.insertAbsolute()
    case .logarithm: editor.insertLogarithm()
    case .function(let name): editor.insertFunction(name)
    case .calculus(let kind): editor.insertCalculus(kind)
    case .matrix(let rows, let columns): editor.insertMatrix(rows: rows, columns: columns)
    case .matrixChange(let change): editor.change(matrix: change)
    case .left: editor.moveLeft()
    case .right: editor.moveRight()
    case .newLine: editor.newLine()
    case .backspace: editor.backspace()
    }
  }

  /// Works out the answer for the current input, off the main thread, and keeps only the latest.
  private func refresh() {
    evaluation?.cancel()
    recording?.cancel()
    let text = editor.text
    guard !text.isEmpty else {
      outcome = .empty
      graph = nil
      return
    }
    let calculator = Calculator(settings: settings)
    let digits = decimalDigits
    let letter = solveFor
    evaluation = Task {
      let result = await Task.detached(priority: .userInitiated) {
        (
          AppModel.outcome(for: text, calculator: calculator, digits: digits, solveFor: letter),
          calculator.plotContent(text)
        )
      }.value
      if !Task.isCancelled {
        var answer = result.0
        // `y = x²` is drawn, not solved, so the "not supported yet" for equations would only mislead.
        if !result.1.isEmpty && answer == .failure(.notSupportedYet) { answer = .empty }
        updateGraph(result.1)
        if answer == .incomplete {
          // Typing passes through unfinished formulas all the time. Clear the old answer at once, but say that the
          // formula is not complete only once the typing has paused.
          outcome = .empty
          try? await Task.sleep(for: .milliseconds(700))
          if !Task.isCancelled { outcome = .incomplete }
          return
        }
        outcome = answer
        scheduleRecording()
      }
    }
  }

  /// Keeps the graph (and the window the user has moved it to) while what it draws is the same.
  private func updateGraph(_ content: PlotContent) {
    if content.isEmpty {
      graph = nil
    } else if !(graph?.content.draws(sameAs: content) ?? false) {
      graph = GraphModel(content: content, size: graph?.drawingSize)
    }
  }

  /// A problem goes into the history once its answer has stood for a moment without being edited, so that typing a
  /// formula key by key leaves one entry and not one per key.
  private func scheduleRecording() {
    let exact: [MathNode]
    let decimal: [MathNode]?
    switch outcome {
    case .answer(let answer):
      exact = answer.exact.isEmpty ? (answer.forms.first?.nodes ?? []) : answer.exact
      decimal = answer.decimal
    case .solutions(let solutions):
      exact = solutions.summary
      decimal = nil
    case .empty where graph != nil:
      (exact, decimal) = ([], nil)  // a function that is only drawn has no answer to keep
    default:
      return
    }
    let lines = editor.lines
    recording = Task {
      try? await Task.sleep(for: .seconds(1.2))
      if !Task.isCancelled { history.record(lines: lines, exact: exact, decimal: decimal) }
    }
  }

  nonisolated static func outcome(
    for text: String, calculator: Calculator, digits: Int, solveFor: String? = nil
  ) -> Outcome {
    do {
      let evaluation: Evaluation
      switch try calculator.compute(text) {
      case .matrix(let matrix): return answer(for: matrix, text: text, digits: digits)
      case .lines(let lines): return worksheetAnswer(lines, text: text, digits: digits)
      case .number(let number): evaluation = number
      }
      var exact = Typesetter.nodes(for: evaluation.exact)
      // An answer that says what was typed (a lone number, `x²`) adds nothing, unless it has other forms to show.
      let saysWhatWasTyped = exact.parserText == text
      // An antiderivative is one of many.
      if evaluation.isAntiderivative { exact += [.symbol("+"), .symbol("C")] }
      // The decimal is shown even when the exact form is what was typed: √2 and 1/3 still have a value to read.
      var decimal: [MathNode]?
      // A whole number with more digits than the decimal has is shown in scientific notation too (1000! ≈ 4.0238…×10²⁵⁶⁷).
      let isLongInteger =
        evaluation.exact.rational.map { $0.isInteger && $0.numerator.magnitude.description.count > digits } ?? false
      if let value = evaluation.approximation, evaluation.exact.rational?.isInteger != true || isLongInteger {
        decimal = Typesetter.nodes(for: value, significantDigits: digits)
      } else if let value = evaluation.complexApproximation, !evaluation.exact.isGaussianInteger {
        decimal = Typesetter.nodes(for: value, significantDigits: digits)
      }
      let forms: [Answer.Form] = evaluation.otherForms.map { form in
        switch form {
        case .expanded(let expression): return .init(kind: .expanded, nodes: Typesetter.nodes(for: expression))
        case .combined(let expression): return .init(kind: .combined, nodes: Typesetter.nodes(for: expression))
        case .factored(let factorization):
          return .init(
            kind: factorization.cancelled ? .simplified : factorization.combinesFractions ? .combined : .factored,
            nodes: Typesetter.nodes(for: factorization))
        }
      }
      // A fraction of two huge numbers (Σ 1/k² to 1000) is no use to read; its decimal is.
      if decimal != nil, let value = evaluation.exact.rational, !value.isInteger,
        value.numerator.magnitude.description.count + value.denominator.description.count > 60
      {
        exact = []
      }
      if saysWhatWasTyped && forms.isEmpty && decimal == nil { return .empty }
      return .answer(
        Answer(
          exact: saysWhatWasTyped ? [] : exact, decimal: decimal, hasNoRealValue: evaluation.approximationError != nil,
          forms: forms))
    } catch {
      switch error {
      case .parse: return .incomplete
      case .unsupported: return solution(for: text, calculator: calculator, digits: digits, solveFor: solveFor)
      case .math(let math): return failure(math)
      }
    }
  }

  /// Lines that give letters their values: an answer line for each letter that was worked out and each expression, and none for
  /// a letter that was only given its value in numbers.
  nonisolated private static func worksheetAnswer(_ lines: [WorkedLine], text: String, digits: Int) -> Outcome {
    let display = SolutionsDisplay(lines, digits: digits)
    return display.lines.isEmpty ? .empty : .solutions(display)
  }

  /// A matrix, with its decimals beneath it when some entry is not a whole number.
  nonisolated private static func answer(for matrix: Matrix, text: String, digits: Int) -> Outcome {
    let exact = Typesetter.nodes(for: matrix)
    var decimal: [MathNode]?
    if let values = matrix.approximations(precision: digits),
      matrix.entries.contains(where: { $0.rational?.isInteger != true })
    {
      decimal = Typesetter.nodes(for: matrix, decimals: values, significantDigits: digits)
    }
    // A matrix that is just what was typed says nothing new.
    let saysWhatWasTyped = exact.parserText == text
    if saysWhatWasTyped && decimal == nil { return .empty }
    return .answer(Answer(exact: saysWhatWasTyped ? [] : exact, decimal: decimal, hasNoRealValue: false))
  }

  nonisolated private static func failure(_ error: MathError) -> Outcome {
    switch error {
    case .divisionByZero: return .failure(.divisionByZero)
    case .domain, .notNumeric: return .failure(.noRealAnswer)
    case .noValue: return .failure(.undefinedHere)
    case .overflow: return .failure(.tooLarge)
    case .dimensionMismatch: return .failure(.sizesDoNotFit)
    case .singular: return .failure(.noInverse)
    case .unsupported: return .failure(.notSupportedYet)
    case .undefined: return .failure(.doesNotExist)
    }
  }

  /// An equation, system or inequality: its solutions, or "not supported yet" for the kinds that are not solved.
  nonisolated private static func solution(
    for text: String, calculator: Calculator, digits: Int, solveFor: String?
  ) -> Outcome {
    do {
      var display = SolutionsDisplay(try calculator.solve(text, for: solveFor), digits: digits)
      // An equation with several letters can be solved for any of them.
      let letters = calculator.unknowns(in: text)
      if letters.count >= 2 {
        display.choices = letters
        display.chosen = solveFor.flatMap { letters.contains($0) ? $0 : nil } ?? letters[0]
      }
      return .solutions(display)
    } catch {
      switch error {
      case .parse: return .incomplete
      case .unsupported: return .failure(.notSupportedYet)
      case .math(let math): return failure(math)
      }
    }
  }
}
