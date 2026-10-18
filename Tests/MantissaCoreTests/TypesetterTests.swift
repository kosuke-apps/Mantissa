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

@Suite("Plain text of a formula")
struct PlainTextTests {
  private func plain(_ text: String) throws -> String {
    Typesetter.nodes(for: try Calculator().evaluate(text).exact).plainText
  }

  @Test(
    "An answer copied as text reads as it is written",
    arguments: [
      ("sin(15°)", "(√6 − √2)/4"), ("1/2", "1/2"), ("π/6", "π/6"), ("x^2-5x+6", "x^2 − 5x + 6"), ("3√3", "3√3"),
      ("1/(1+√2)", "−1 + √2"), ("e^(2x)", "e^(2x)"), ("e^(x+3)", "e^3·e^x"), ("x^(y+1)", "x^(y + 1)"),
      ("x/(2y)", "x/(2y)"), ("√(2x)", "√x·√2"), ("√(x+1)", "√(x + 1)"), ("x^(a)", "x^a"),
      ("sin(x)^2", "sin(x)^2"), ("x^3*e^x", "x^3·e^x"), ("2^x*x^2", "x^2 × 2^x"), ("sin(x)*x^2*e^x", "x^2·e^x·sin(x)"),
      ("1/sin(x)", "1/sin(x)"), ("log(5,3)", "log₃(5)"), ("log(x,10)", "log(x)"),
      ("2/3", "2/3"), ("-5/4", "−5/4"), ("x/(x+1)", "x/(x + 1)"), ("2^(1/3)", "2^(1/3)"), ("|x|", "|x|"),
      ("1/√2", "√2/2"), ("(1+2i)*(3-i)", "5 + 5i"), ("x^3/3", "x^3/3"), ("3x^2", "3x^2"),
    ])
  func answers(input: String, expected: String) throws {
    #expect(try plain(input) == expected, "\(input)")
  }

  @Test("Equations: spaces around the signs, a comma and a space between the solutions")
  func equations() {
    let nodes: [MathNode] = [
      .symbol("x"), .symbol("="), .symbol("−"), .symbol("2"), .symbol(","), .symbol("x"), .symbol("="), .symbol("2"),
    ]
    #expect(nodes.plainText == "x = −2, x = 2")
    let interval: [MathNode] = [.symbol("x"), .symbol("<"), .symbol("−"), .symbol("2"), .symbol("≤"), .symbol("3")]
    #expect(interval.plainText == "x < −2 ≤ 3")
    #expect(([] as [MathNode]).plainText == "")
    // Spacing already in the nodes (after the comma of an interval) does not split a sign from its number.
    let pair: [MathNode] = [
      .symbol("("), .symbol("−"), .symbol("∞"), .symbol(","), .symbol(" "), .symbol("−"), .symbol("2"), .symbol(")"),
    ]
    #expect(pair.plainText == "(−∞, −2)")
  }

  @Test("A root with an index and a calculus node")
  func structures() {
    let root = MathNode.radical(index: [.symbol("3")], radicand: [.symbol("x"), .symbol("+"), .symbol("1")])
    #expect([root].plainText == "root(x + 1, 3)")
    let integral = MathNode.calculus(.integral, [[.symbol("x")], [.symbol("x")], [.symbol("0")], [.symbol("1")]])
    #expect([integral].plainText == "int(x, x, 0, 1)")
  }

  @Test("Random answers copied as text read back as the same value", arguments: [AngleUnit.radians, AngleUnit.degrees])
  func randomAnswersReadBack(angleUnit: AngleUnit) throws {
    var generator = SyntaxGenerator(seed: (angleUnit == .radians ? 7919 : 104_729) &+ propertySeedOffset &* 7919)
    generator.includesUnknown = true
    generator.includesDerivedFunctions = true
    let builder = Builder(angleUnit: angleUnit)
    var compared = 0
    var failures: [String] = []
    for _ in 0..<350 {
      guard let exact = try? builder.build(generator.make(depth: 4)) else { continue }
      let text = Typesetter.nodes(for: exact).plainText
      guard case .expression(let syntax)? = try? Parser.parse(text),
        let again = try? Builder(angleUnit: .radians).build(syntax)
      else {
        failures.append("did not read back: \(text) from \(exact)")
        continue
      }
      compared += 1
      for point in [BigDecimal(BigInt(13), exponent: -1), BigDecimal(BigInt(-7), exponent: -1)] {
        let a = try? exact.approximation(precision: 40, values: ["x": point])
        let b = try? again.approximation(precision: 40, values: ["x": point])
        switch (a, b) {
        case (let a?, let b?):
          let scale = max(BigDecimal(1), a.magnitude)
          if (a - b).magnitude > scale * BigDecimal(BigInt(1), exponent: -30) {
            failures.append("\(text): \(a) became \(b)")
          }
        case (nil, nil): break
        default: failures.append("\(text): \(String(describing: a)) became \(String(describing: b))")
        }
      }
    }
    #expect(compared > 120, "only \(compared) compared")
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(4))")
  }
}
