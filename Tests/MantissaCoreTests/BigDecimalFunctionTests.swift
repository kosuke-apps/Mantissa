import Testing

@testable import MantissaCore

private struct FunctionCase: Decodable {
  let fn: String
  let x: String?
  let y: String?
  let expected: String
}

private struct FunctionVectors: Decodable {
  let functions: [FunctionCase]
}

private func decimal(_ text: String) -> BigDecimal {
  guard let value = BigDecimal(text) else { fatalError("cannot parse \(text)") }
  return value
}

private func evaluate(_ item: FunctionCase, precision p: Int) throws(MathError) -> BigDecimal {
  switch item.fn {
  case "pi": return BigDecimal.pi(precision: p)
  case "e": return BigDecimal.e(precision: p)
  default: break
  }
  let x = decimal(item.x ?? "0")
  switch item.fn {
  case "exp": return try x.exp(precision: p)
  case "ln": return try x.ln(precision: p)
  case "sqrt": return try x.squareRoot(precision: p)
  case "sin": return try x.sin(precision: p)
  case "cos": return try x.cos(precision: p)
  case "tan": return try x.tan(precision: p)
  case "atan": return x.arctangent(precision: p)
  case "asin": return try x.arcsine(precision: p)
  case "acos": return try x.arccosine(precision: p)
  case "sinh": return try x.sinh(precision: p)
  case "cosh": return try x.cosh(precision: p)
  case "tanh": return try x.tanh(precision: p)
  case "asinh": return try x.asinh(precision: p)
  case "acosh": return try x.acosh(precision: p)
  case "atanh": return try x.atanh(precision: p)
  case "pow": return try x.power(decimal(item.y ?? "0"), precision: p)
  case "log": return try x.log(base: decimal(item.y ?? "10"), precision: p)
  default: fatalError("unknown function \(item.fn)")
  }
}

@Suite("BigDecimal functions")
struct BigDecimalFunctionTests {
  /// The Swift result must equal Python's 110-digit value rounded to the same number of digits. Anything else is
  /// reported with the input, so a failure says which function and argument went wrong.
  @Test(
    "Every function matches the Python oracle to the last digit at 15, 50 and 100 digits", arguments: [15, 50, 100])
  func matchesOracle(precision: Int) throws {
    let vectors: FunctionVectors = try loadVectors("decimal-vectors")
    #expect(vectors.functions.count >= 450)
    var mismatches: [String] = []
    for item in vectors.functions {
      let expected = decimal(item.expected).rounded(toSignificantDigits: precision)
      do {
        let actual = try evaluate(item, precision: precision)
        if actual != expected {
          mismatches.append(
            "\(item.fn)(\(item.x ?? "")\(item.y.map { ", " + $0 } ?? "")) = \(actual), expected \(expected)")
        }
      } catch {
        mismatches.append("\(item.fn)(\(item.x ?? "")) threw \(error)")
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(8))")
  }

  @Test("π and e to 50 digits")
  func constants() {
    #expect(BigDecimal.pi() == decimal("3.1415926535897932384626433832795028841971693993751"))
    #expect(BigDecimal.e() == decimal("2.7182818284590452353602874713526624977572470937"))
  }

  @Test("Thousand-digit π and e are quick and consistent with the shorter ones")
  func manyDigits() {
    let pi = BigDecimal.pi(precision: 1000)
    #expect(pi.significand.decimalDigitCount == 1000)
    #expect(pi.rounded(toSignificantDigits: 50) == BigDecimal.pi())
    #expect(BigDecimal.e(precision: 1000).rounded(toSignificantDigits: 50) == BigDecimal.e())
  }

  @Test("Exact answers come out exact, so the layer above can trust them")
  func exactAnswers() throws {
    #expect(try BigDecimal(1000).log10() == BigDecimal(3))
    #expect(try BigDecimal(1024).log(base: BigDecimal(2)) == BigDecimal(10))
    #expect(try decimal("0.001").log10() == BigDecimal(-3))
    #expect(try BigDecimal(1).ln() == BigDecimal(0))
    #expect(try BigDecimal(0).exp() == BigDecimal(1))
    #expect(try BigDecimal(9).power(decimal("0.5")) == BigDecimal(3))
    #expect(
      try BigDecimal(8).power(decimal("0.3333333333333333333333333333333333333333333333333333")).rounded(
        toSignificantDigits: 20) == BigDecimal(2))
    #expect(try BigDecimal(0).sin() == BigDecimal(0))
    #expect(try BigDecimal(0).cos() == BigDecimal(1))
    #expect(BigDecimal(0).arctangent() == BigDecimal(0))
    #expect(try BigDecimal(1).arcsine() == BigDecimal.pi(precision: 52).halved.rounded(toSignificantDigits: 50))
    #expect(try BigDecimal(1).arccosine() == BigDecimal(0))
    #expect(try BigDecimal(-1).arccosine() == BigDecimal.pi())
    #expect(BigDecimal(1).arctangent() == BigDecimal.pi(precision: 52).halved.halved.rounded(toSignificantDigits: 50))
  }

  @Test("sin(π) and cos(π/2) are tiny at the precision of π, not exactly zero (the exact layer handles those)")
  func trigonometricCancellation() throws {
    // sin(π − δ) = sin δ ≈ δ, so sin(π₅₀) is the distance from π₅₀ to the true π. Check it against a 100-digit π.
    let pi = BigDecimal.pi(precision: 50)
    let sine = try pi.sin(precision: 20)
    let distance = BigDecimal.pi(precision: 100) - pi
    #expect(sine.decimalOrder.map { $0 < -48 && $0 > -52 } == true, "\(sine)")
    #expect(sine == distance.rounded(toSignificantDigits: 20), "\(sine) vs \(distance)")
  }

  @Test("sin² + cos² = 1 and tan = sin / cos across many magnitudes")
  func pythagoreanIdentity() throws {
    for text in ["0.3", "1", "2.5", "-4", "17", "123.456", "1e6", "1e15", "-1e25", "1e-8"] {
      let x = decimal(text)
      let (s, c) = (try x.sin(precision: 60), try x.cos(precision: 60))
      let error = (s * s + c * c - BigDecimal(1)).magnitude
      #expect(error < decimal("1e-58"), "sin²+cos² for \(text): off by \(error)")
      let t = try x.tan(precision: 40)
      let ratio = try s.divided(by: c, precision: 40)
      #expect(t == ratio, "tan for \(text)")
    }
  }

  @Test("exp and ln are inverses, and ln(a·b) = ln a + ln b")
  func logarithmIdentities() throws {
    for text in ["0.001", "0.5", "1.0000001", "3", "123456.789", "1e40", "1e-40"] {
      let x = decimal(text)
      let roundTrip = try x.ln(precision: 70).exp(precision: 50)
      #expect(roundTrip == x.rounded(toSignificantDigits: 50), "exp(ln \(text))")
    }
    let a = decimal("12.5")
    let b = decimal("0.003")
    let sum = try a.ln(precision: 60) + b.ln(precision: 60)
    let product = try (a * b).ln(precision: 50)
    #expect(sum.rounded(toSignificantDigits: 50) == product)
  }

  @Test("Inverse functions undo the forward ones")
  func inverses() throws {
    for text in ["0.3", "-0.7", "1.2", "-1.4"] {
      let x = decimal(text)
      #expect(
        try x.sin(precision: 70).arcsine(precision: 50) == x.rounded(toSignificantDigits: 50), "asin(sin \(text))")
      #expect(
        try x.tan(precision: 70).arctangent(precision: 50) == x.rounded(toSignificantDigits: 50), "atan(tan \(text))")
    }
    for text in ["0.3", "1", "2.5", "3.1"] {
      let x = decimal(text)
      #expect(
        try x.cos(precision: 70).arccosine(precision: 50) == x.rounded(toSignificantDigits: 50), "acos(cos \(text))")
    }
    for text in ["0.3", "-2", "10", "1e-9"] {
      let x = decimal(text)
      #expect(
        try x.sinh(precision: 70).asinh(precision: 50) == x.rounded(toSignificantDigits: 50), "asinh(sinh \(text))")
      #expect(
        try x.tanh(precision: 70).atanh(precision: 50) == x.rounded(toSignificantDigits: 50), "atanh(tanh \(text))")
    }
    #expect(try decimal("2.5").cosh(precision: 70).acosh(precision: 50) == decimal("2.5"))
  }

  @Test("Arguments of absurd size are handled without huge computations")
  func extremeArguments() throws {
    // Tiny arguments: f(x) = x to the precision asked for.
    let tiny = decimal("1e-1000000")
    for result in [
      try tiny.sin(), try tiny.tan(), tiny.arctangent(), try tiny.sinh(), try tiny.tanh(), try tiny.asinh(),
      try tiny.atanh(), try tiny.arcsine(),
    ] {
      #expect(result == tiny)
    }
    #expect(try tiny.cos() == BigDecimal(1))
    #expect(try tiny.exp() == BigDecimal(1))
    let nearlyOne = BigDecimal(1) + decimal("1e-1000")
    #expect(try nearlyOne.ln() == decimal("1e-1000"))
    #expect(try nearlyOne.acosh() == (decimal("2e-1000").squareRoot(precision: 50)))
    #expect(try tiny.arccosine() == BigDecimal.pi(precision: 52).halved.rounded(toSignificantDigits: 50))
    // Huge arguments: asymptotes.
    #expect(try decimal("1e500").tanh() == BigDecimal(1))
    #expect(try decimal("1e50").tanh() == BigDecimal(1))
    #expect(try decimal("-1e50").tanh() == BigDecimal(-1))
    #expect(decimal("1e300").arctangent() == BigDecimal.pi(precision: 52).halved.rounded(toSignificantDigits: 50))
    #expect(
      try decimal("1e1000").ln()
        == (try BigDecimal(10).ln(precision: 60) * BigDecimal(1000)).rounded(toSignificantDigits: 50))
  }

  @Test("Domain and range errors")
  func errors() {
    #expect(throws: MathError.domain) { try BigDecimal(0).ln() }
    #expect(throws: MathError.domain) { try BigDecimal(-1).ln() }
    #expect(throws: MathError.domain) { try BigDecimal(2).arcsine() }
    #expect(throws: MathError.domain) { try decimal("-1.0001").arccosine() }
    #expect(throws: MathError.domain) { try decimal("0.5").acosh() }
    #expect(throws: MathError.domain) { try BigDecimal(1).atanh() }
    #expect(throws: MathError.domain) { try BigDecimal(-1).atanh() }
    #expect(throws: MathError.domain) { try BigDecimal(-2).power(decimal("0.5")) }
    #expect(throws: MathError.domain) { try BigDecimal(5).log(base: BigDecimal(1)) }
    #expect(throws: MathError.domain) { try BigDecimal(5).log(base: BigDecimal(-2)) }
    #expect(throws: MathError.divisionByZero) { try BigDecimal(0).power(decimal("-0.5")) }
    #expect(throws: MathError.overflow) { try decimal("1e10").exp() }
    #expect(throws: MathError.overflow) { try decimal("-1e10").exp() }
    #expect(throws: MathError.overflow) { try decimal("1e2000").sin() }
    #expect(throws: MathError.overflow) { try BigDecimal(10).power(2_000_000_000) }
  }
}
