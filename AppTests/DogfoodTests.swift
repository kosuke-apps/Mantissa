import MantissaCore
import XCTest

@testable import Mantissa

/// Prints what the app would show for a list of everyday inputs, to be read by a person. Set `MANTISSA_DOGFOOD` to a file
/// of inputs, one per line, to run it; without it the test does nothing.
@MainActor
final class DogfoodTests: XCTestCase {
  func testPrintWhatTheAppShows() throws {
    guard
      let path = ProcessInfo.processInfo.environment["MANTISSA_DOGFOOD"]
        ?? UserDefaults.standard.string(forKey: "MANTISSA_DOGFOOD")
    else { return }
    let inputs = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
    var report = ""
    for input in inputs where !input.isEmpty && !input.hasPrefix("#") {
      let outcome = AppModel.outcome(for: input, calculator: Calculator(), digits: 12)
      var line = input + "\n    → "
      switch outcome {
      case .empty: line += "(nothing)"
      case .incomplete: line += "(incomplete)"
      case .failure(let failure): line += "failure: \(failure)"
      case .answer(let answer):
        line += answer.exact.plainText
        if let decimal = answer.decimal { line += "  ≈ " + decimal.plainText }
        for form in answer.forms { line += "  [\(form.kind): \(form.nodes.plainText)]" }
      case .solutions(let solutions):
        line +=
          "\(solutions.kind): "
          + solutions.lines.map { $0.exact.plainText + ($0.decimal.map { " ≈ " + $0.plainText } ?? "") }.joined(
            separator: " | ")
        if let notation = solutions.notation { line += "   " + notation.plainText }
      }
      let content = Calculator().plotContent(input)
      if !content.isEmpty {
        line += "   [graph: \(content.functions.count) functions, \(content.relations.count) relations]"
      }
      report += line + "\n"
    }
    try report.write(toFile: path + ".out", atomically: true, encoding: .utf8)
  }
}
