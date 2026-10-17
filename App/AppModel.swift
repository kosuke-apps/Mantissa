import MantissaCore
import Observation
import SwiftUI
import UIKit

/// What a key does.
enum KeyAction: Hashable {
  case symbol(String)
  /// An exponent that is already filled in, as on the x² and x³ keys.
  case exponent(String)
  case fraction, power, squareRoot, nthRoot, group, absolute
  case function(String)
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
      enum Kind: String, Codable { case expanded, factored, simplified }
      var kind: Kind
      var nodes: [MathNode]
    }
  }

  typealias Solutions = SolutionsDisplay

  enum Failure: Equatable {
    case divisionByZero
    case noRealAnswer
    case tooLarge
    case notSupportedYet
    /// A limit whose sides disagree, an integral or a series that diverges.
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
  }

  /// Puts an earlier problem back into the calculator.
  func open(_ entry: HistoryEntry) {
    editor = MathEditor(lines: entry.lines)
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

  func clearAll() {
    editor.clear()
    refresh()
  }

  private func perform(_ action: KeyAction) {
    switch action {
    case .symbol(let text): editor.insert(text)
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
    case .function(let name): editor.insertFunction(name)
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
    evaluation = Task {
      let result = await Task.detached(priority: .userInitiated) {
        (AppModel.outcome(for: text, calculator: calculator, digits: digits), calculator.plotFunctions(text))
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

  /// Keeps the graph (and the window the user has moved it to) while the functions are the same.
  private func updateGraph(_ functions: [PlotFunction]) {
    if functions.isEmpty {
      graph = nil
    } else if graph?.functions.map(\.expression) != functions.map(\.expression) {
      graph = GraphModel(functions: functions)
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

  nonisolated private static func outcome(for text: String, calculator: Calculator, digits: Int) -> Outcome {
    do {
      let evaluation = try calculator.evaluate(text)
      var exact = Typesetter.nodes(for: evaluation.exact)
      // An answer that says what was typed (a lone number, `x²`) adds nothing, unless it has other forms to show.
      let saysWhatWasTyped = exact.parserText == text
      // An antiderivative is one of many.
      if evaluation.isAntiderivative { exact += [.symbol("+"), .symbol("C")] }
      var decimal: [MathNode]?
      if saysWhatWasTyped {
        decimal = nil
      } else if let value = evaluation.approximation, evaluation.exact.rational?.isInteger != true {
        decimal = Typesetter.nodes(for: value, significantDigits: digits)
      } else if let value = evaluation.complexApproximation, !evaluation.exact.isGaussianInteger {
        decimal = Typesetter.nodes(for: value, significantDigits: digits)
      }
      let forms: [Answer.Form] = evaluation.otherForms.map { form in
        switch form {
        case .expanded(let expression): return .init(kind: .expanded, nodes: Typesetter.nodes(for: expression))
        case .factored(let factorization):
          return .init(
            kind: factorization.cancelled ? .simplified : .factored, nodes: Typesetter.nodes(for: factorization))
        }
      }
      if saysWhatWasTyped && forms.isEmpty { return .empty }
      return .answer(
        Answer(
          exact: saysWhatWasTyped ? [] : exact, decimal: decimal, hasNoRealValue: evaluation.approximationError != nil,
          forms: forms))
    } catch {
      switch error {
      case .parse: return .incomplete
      case .unsupported: return solution(for: text, calculator: calculator, digits: digits)
      case .math(let math): return failure(math)
      }
    }
  }

  nonisolated private static func failure(_ error: MathError) -> Outcome {
    switch error {
    case .divisionByZero: return .failure(.divisionByZero)
    case .domain, .notNumeric: return .failure(.noRealAnswer)
    case .overflow: return .failure(.tooLarge)
    case .unsupported: return .failure(.notSupportedYet)
    case .undefined: return .failure(.doesNotExist)
    }
  }

  /// An equation, system or inequality: its solutions, or "not supported yet" for the kinds that are not solved.
  nonisolated private static func solution(for text: String, calculator: Calculator, digits: Int) -> Outcome {
    do {
      return .solutions(SolutionsDisplay(try calculator.solve(text), digits: digits))
    } catch {
      switch error {
      case .parse: return .incomplete
      case .unsupported: return .failure(.notSupportedYet)
      case .math(let math): return failure(math)
      }
    }
  }
}
