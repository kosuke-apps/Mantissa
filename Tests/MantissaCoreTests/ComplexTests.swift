import Testing

@testable import MantissaCore

/// The imaginary unit: exact arithmetic with it, and its numerical values. Each expectation was worked out by hand.
@Suite("Complex numbers")
struct ComplexTests {
  private func exact(_ text: String) throws -> String {
    try Calculator().evaluate(text).exact.description
  }

  @Test(
    "Powers of i cycle through four values",
    arguments: [
      ("i", "i"), ("i*i", "-1"), ("i^2", "-1"), ("i^3", "-i"), ("i^4", "1"), ("i^5", "i"), ("i^-1", "-i"),
      ("i^-2", "-1"), ("i^-3", "i"), ("i^101", "i"), ("i^100", "1"), ("1/i", "-i"), ("i^0", "1"), ("i³", "-i"),
    ])
  func powers(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Square roots of negative numbers",
    arguments: [
      ("√(-1)", "i"), ("√(-4)", "2i"), ("√(-12)", "2√3i"), ("√(-2)*√(-2)", "-2"), ("√(-4)*√(-9)", "-6"),
      ("(-4)^(1/2)", "2i"), ("(-1)^(1/2)", "i"), ("(-9)^(3/2)", "-27i"), ("(-4)^(-1/2)", "-i/2"),
      ("√(-1/4)", "i/2"), ("(√(-3))^2", "-3"),
    ])
  func roots(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Arithmetic with complex numbers",
    arguments: [
      ("1+i", "1 + i"), ("(1+i)+(1-i)", "2"), ("(1+i)(1-i)", "2"), ("(1+i)^2", "2i"), ("(1+i)^4", "-4"),
      ("(2+3i)(4-5i)", "23 + 2i"), ("(3+4i)(3-4i)", "25"), ("i(1+i)", "-1 + i"), ("2i+3i", "5i"), ("3-i-i", "3 - 2i"),
      ("(1+2i)^2", "-3 + 4i"), ("(1+i)^3", "-2 + 2i"), ("(1-i)^2", "-2i"), ("i^2+1", "0"),
    ])
  func arithmetic(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Division by a complex number is rationalised",
    arguments: [
      ("1/(1+i)", "(1 - i)/2"), ("1/(1-i)", "(1 + i)/2"), ("(1+i)/(1-i)", "i"), ("1/(3+4i)", "(3 - 4i)/25"),
      ("(2+i)/(1+2i)", "(4 - 3i)/5"), ("1/(2i)", "-i/2"), ("i/(1+i)", "(1 + i)/2"), ("(1+i)/(1+i)", "1"),
      ("1/(1+√2+i)", "(√2 + √2i - 2i)/4"),
    ])
  func division(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Absolute values of complex numbers",
    arguments: [("|3+4i|", "5"), ("|i|", "1"), ("|-2i|", "2"), ("|1+i|", "√2"), ("|5-12i|", "13"), ("|3|", "3")])
  func absoluteValue(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Euler's formula is exact at the angles the trigonometric tables cover",
    arguments: [
      ("e^(iπ)", "-1"), ("e^(2iπ)", "1"), ("e^(iπ/2)", "i"), ("e^(-iπ/2)", "-i"), ("e^(iπ/6)", "(√3 + i)/2"),
      ("e^(3iπ)", "-1"), ("e^(iπ/4)", "(√2 + √2i)/2"),
    ])
  func euler(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Square roots of complex numbers are simplified when that gives a simpler expression",
    arguments: [
      ("√(3+4i)", "2 + i"), ("√(3-4i)", "2 - i"), ("√(2i)", "1 + i"), ("√(-2i)", "1 - i"), ("√(-3+4i)", "1 + 2i"),
      ("√(-1/2+√3i/2)", "(1 + √3i)/2"), ("√(5+12i)", "3 + 2i"), ("√(-5+12i)", "2 + 3i"), ("(3+4i)^(1/2)", "2 + i"),
      ("√(i)", "(√2 + √2i)/2"),
    ])
  func complexRoots(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("i^(1/2) and other roots of i are the principal values")
  func rootsOfI() throws {
    #expect(try exact("i^(1/2)") == "(√2 + √2i)/2")
    #expect(try exact("(-1)^(1/4)") == "(√2 + √2i)/2")
    #expect(try exact("(-1)^(1/6)") == "(√3 + i)/2")
  }

  @Test("Complex values are given as decimals")
  func approximations() throws {
    func complex(_ text: String, digits: Int = 30) throws -> ComplexDecimal {
      var settings = CalculatorSettings()
      settings.precision = digits
      return try #require(Calculator(settings: settings).evaluate(text).complexApproximation)
    }
    let root = try complex("(1+i)/√2", digits: 20)
    #expect(root.real == BigDecimal("0.70710678118654752440"))
    #expect(root.imaginary == BigDecimal("0.70710678118654752440"))
    let unit = try complex("e^(i)", digits: 20)  // cos 1 + i sin 1
    #expect(unit.real == BigDecimal("0.54030230586813971740"))
    #expect(unit.imaginary == BigDecimal("0.84147098480789650665"))
    // A real number with a hidden imaginary part of exactly zero is reported as real.
    let evaluation = try Calculator().evaluate("e^(i*π)+1")
    #expect(evaluation.exact.description == "0")
    #expect(try Calculator().evaluate("(-4)^(1/4)").exact.description == "1 + i")
  }

  @Test("Typeset complex decimals")
  func typesetting() {
    func text(_ re: String, _ im: String) -> String {
      Typesetter.nodes(
        for: ComplexDecimal(real: BigDecimal(re)!, imaginary: BigDecimal(im)!), significantDigits: 6
      ).parserText
    }
    #expect(text("0.5", "0.25") == "0.5+0.25i")
    #expect(text("0.5", "-1") == "0.5−i")
    #expect(text("0", "2") == "2i")
    #expect(text("0", "-1") == "−i")
    #expect(text("3", "0") == "3")
  }

  @Test("i cannot be drawn")
  func notPlotted() {
    #expect(Calculator().plotFunctions("x+i").isEmpty)
  }

  /// Values from Python's `cmath` (double precision, so compared to 12 digits).
  @Test(
    "Complex functions agree with an independent implementation",
    arguments: [
      ("exp", 1, 2, -1.1312043837568135, 2.4717266720048188),
      ("exp", -3, 0.5, 0.04369226300728118, 0.02386919206778745),
      ("exp", 10, -10, -18481.78033459865, 11982.862390657456), ("ln", -3, 4, 1.6094379124341003, 2.214297435588181),
      ("ln", 1, 1, 0.34657359027997264, 0.7853981633974483), ("ln", -1, 0, 0.0, 3.141592653589793),
      ("ln", 0, -2, 0.6931471805599453, -1.5707963267948966), ("ln", 5, -12, 2.5649493574615367, -1.176005207095135),
      ("sin", 1, 2, 3.165778513216168, 1.959601041421606), ("sin", -3, 0.5, -0.15913058529843999, -0.5158804424525267),
      ("sin", 0, 1, 0.0, 1.1752011936438014), ("cos", 1, 2, 2.0327230070196656, -3.0518977991517997),
      ("cos", -3, 0.5, -1.1163412445261518, 0.0735369737112366), ("cos", 0, 1, 1.5430806348152437, 0.0),
      ("sinh", 1, 2, -0.4890562590412937, 1.4031192506220405), ("sinh", -3, 0.5, -8.791512343493714, 4.82669427481082),
      ("cosh", 1, 2, -0.64214812471552, 1.0686074213827783), ("cosh", -3, 0.5, 8.835204606500994, -4.802825082743033),
    ] as [(String, Double, Double, Double, Double)])
  func functions(name: String, re: Double, im: Double, expectedRe: Double, expectedIm: Double) throws {
    let z = ComplexDecimal(real: BigDecimal("\(re)")!, imaginary: BigDecimal("\(im)")!)
    let result: ComplexDecimal
    switch name {
    case "exp": result = try z.exp(precision: 30)
    case "ln": result = try z.ln(precision: 30)
    case "sin": result = try z.sin(precision: 30)
    case "cos": result = try z.cos(precision: 30)
    case "sinh": result = try z.sinh(precision: 30)
    default: result = try z.cosh(precision: 30)
    }
    func close(_ value: BigDecimal, _ expected: Double) -> Bool {
      abs(value.doubleValue - expected) <= 1e-12 * max(1, abs(expected))
    }
    #expect(close(result.real, expectedRe) && close(result.imaginary, expectedIm), "\(name)(\(re), \(im)) = \(result)")
  }

  @Test("Powers with fractional and complex exponents are the principal values")
  func principalPowers() throws {
    func value(_ text: String) throws -> ComplexDecimal {
      try #require(Calculator().evaluate(text).complexApproximation)
    }
    // (1 + i)^(1/2) = 2^(1/4) e^(iπ/8)
    let root = try value("(1+i)^(1/2)")
    #expect(abs(root.real.doubleValue - 1.09868411346781) < 1e-13)
    #expect(abs(root.imaginary.doubleValue - 0.45508986056222733) < 1e-13)
    // i^i = e^(−π/2) is real
    let power = try Calculator().evaluate("i^i")
    #expect(power.complexApproximation == nil)
    #expect(abs(try #require(power.approximation).doubleValue - 0.20787957635076193) < 1e-15)
    // The real cube root convention holds inside a complex calculation.
    #expect(try Calculator().evaluate("(-8)^(1/3)+i").exact.description == "-2 + i")
  }
}
