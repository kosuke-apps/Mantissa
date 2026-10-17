import Foundation
import Testing

@testable import MantissaCore

/// `MANTISSA_SEED` and `MANTISSA_SAMPLES` widen the random search, as for the expression tests.
private let seedOffset = UInt64(ProcessInfo.processInfo.environment["MANTISSA_SEED"] ?? "") ?? 0
private let sampleCount = Int(ProcessInfo.processInfo.environment["MANTISSA_SAMPLES"] ?? "") ?? 800

private func exact(_ text: String) throws -> Expr {
  try Calculator().evaluate(text).exact
}

private func digits(_ text: String) -> [MathNode] { text.map { .symbol(String($0)) } }

@Suite("Typesetter")
struct TypesetterTests {
  @Test("Answers are laid out with stacked fractions, radicals and raised exponents")
  func layout() throws {
    #expect(Typesetter.nodes(for: try exact("7")) == digits("7"))
    #expect(Typesetter.nodes(for: try exact("-7")) == [.symbol("−")] + digits("7"))
    #expect(Typesetter.nodes(for: try exact("3/4")) == [.fraction(numerator: digits("3"), denominator: digits("4"))])
    #expect(
      Typesetter.nodes(for: try exact("-3/4"))
        == [.symbol("−"), .fraction(numerator: digits("3"), denominator: digits("4"))])
    #expect(Typesetter.nodes(for: try exact("√12")) == digits("2") + [.radical(index: nil, radicand: digits("3"))])
    #expect(
      Typesetter.nodes(for: try exact("√2*√3")) == [.radical(index: nil, radicand: digits("6"))])
    #expect(
      Typesetter.nodes(for: try exact("x^2"))
        == [.symbol("x"), .superscript(digits("2"))])
    #expect(
      Typesetter.nodes(for: try exact("1/x"))
        == [.fraction(numerator: digits("1"), denominator: [.symbol("x")])])
    #expect(
      Typesetter.nodes(for: try exact("π/6"))
        == [.fraction(numerator: [.symbol("π")], denominator: digits("6"))])
    #expect(
      Typesetter.nodes(for: try exact("√2/2"))
        == [.fraction(numerator: [.radical(index: nil, radicand: digits("2"))], denominator: digits("2"))])
    #expect(
      Typesetter.nodes(for: try exact("2x+3"))
        == digits("2") + [.symbol("x"), .symbol("+")] + digits("3"))
    #expect(
      Typesetter.nodes(for: try exact("x^2-3x+2"))
        == [.symbol("x"), .superscript(digits("2")), .symbol("−")] + digits("3") + [.symbol("x"), .symbol("+")]
        + digits("2"))
    #expect(
      Typesetter.nodes(for: try exact("2-√3")) == digits("2") + [
        .symbol("−"), .radical(index: nil, radicand: digits("3")),
      ])
    #expect(Typesetter.nodes(for: try exact("sin(x)")) == [.function(name: "sin", argument: [.symbol("x")])])
  }

  @Test("A fraction or a sum used as a base is put in parentheses")
  func parenthesesWhereNeeded() throws {
    let sumSquared = try (Expr.symbol("x") + 1).raised(to: 2)
    #expect(
      Typesetter.nodes(for: sumSquared)
        == [.group([.symbol("x"), .symbol("+"), .symbol("1")]), .superscript(digits("2"))])
    let negativeBase = try (Expr.integer(-2)).raised(to: Expr.symbol("x"))
    #expect(
      Typesetter.nodes(for: negativeBase) == [.group([.symbol("−"), .symbol("2")]), .superscript([.symbol("x")])])
  }

  @Test("Factorials, absolute values and logarithms with a base")
  func functions() throws {
    #expect(Typesetter.nodes(for: try exact("x!")) == [.symbol("x"), .symbol("!")])
    #expect(Typesetter.nodes(for: try exact("|x|")) == [.absolute([.symbol("x")])])
    // The base is written small below `log`.
    #expect(Typesetter.nodes(for: try exact("log(5,3)")) == [.logarithm(base: digits("3"), argument: digits("5"))])
    #expect(
      Typesetter.nodes(for: try exact("log(x,2)")) == [.logarithm(base: digits("2"), argument: [.symbol("x")])])
    // Base 10 is the plain `log`, and base e is `ln`.
    #expect(Typesetter.nodes(for: try exact("log(x)")) == [.function(name: "log", argument: [.symbol("x")])])
    #expect(Typesetter.nodes(for: try exact("log(x,e)")) == [.function(name: "ln", argument: [.symbol("x")])])
  }

  @Test(
    "Decimals: plain, rounded, and scientific for the very large and very small",
    arguments: [
      ("0.5", 10, "0.5"), ("3.14159265358979323846", 10, "3.141592654"), ("-2.5", 10, "−2.5"), ("100", 10, "100"),
      ("0.000123", 10, "0.000123"), ("123456789012345", 10, "123456789000000"), ("0", 10, "0"),
      ("0.1", 3, "0.1"), ("1234.5678", 6, "1234.57"), ("0.0000001", 10, "1×10^−7"), ("1e30", 10, "1×10^30"),
      ("1.5e30", 10, "1.5×10^30"), ("-6.02214076e23", 10, "−6.02214076×10^23"), ("1e16", 10, "1×10^16"),
      ("9.99999", 3, "10"), ("1e15", 10, "1000000000000000"), ("0.000001", 10, "0.000001"),
    ])
  func decimals(input: String, digits: Int, expected: String) throws {
    let value = try #require(BigDecimal(input))
    let nodes = Typesetter.nodes(for: value, significantDigits: digits)
    #expect(flat(nodes) == expected, "\(input) to \(digits) digits")
  }

  /// A one-line reading of a node list, with ^ for an exponent, to compare decimals compactly.
  private func flat(_ nodes: [MathNode]) -> String {
    nodes.map { node -> String in
      switch node {
      case .symbol(let text): return text
      case .superscript(let inner): return "^" + flat(inner)
      default: return "?"
      }
    }.joined()
  }

  @Test(
    "Typeset text reads back as the same expression, for many random expressions",
    arguments: [AngleUnit.radians, .degrees])
  func roundTrip(angleUnit: AngleUnit) throws {
    var generator = SyntaxGenerator(seed: (angleUnit == .radians ? 31 : 62) &+ seedOffset &* 7919)
    let builder = Builder(angleUnit: angleUnit)
    var checked = 0
    var failures: [String] = []
    for _ in 0..<sampleCount {
      guard let built = try? builder.build(generator.make(depth: 3)) else { continue }
      let text = Typesetter.nodes(for: built).parserText
      do {
        guard case .expression(let syntax) = try Parser.parse(text) else {
          failures.append("\(text) is not an expression")
          continue
        }
        let again = try Builder(angleUnit: .radians).build(syntax)
        if again != built { failures.append("\(built) came back as \(again) via \(text)") }
      } catch {
        failures.append("\(built) typeset as \(text), which failed with \(error)")
      }
      checked += 1
    }
    #expect(checked > sampleCount / 2)
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(5))")
  }
}
