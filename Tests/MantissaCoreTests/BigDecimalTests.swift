import Testing

@testable import MantissaCore

private struct ArithmeticCase: Decodable {
  let a: String
  let b: String
  let sum: String
  let difference: String
  let product: String
  let compare: Int
  let quotient50: String?
  let quotient7: String?
}

private struct RoundingCase: Decodable {
  let x: String
  let digits: Int
  let places: Int
  let toDigits: String
  let toPlaces: String
}

private struct RootCase: Decodable {
  let x: String
  let precision: Int
  let expected: String
}

private struct PowerCase: Decodable {
  let x: String
  let n: Int
  let precision: Int
  let expected: String
}

private struct DecimalVectors: Decodable {
  let arithmetic: [ArithmeticCase]
  let rounding: [RoundingCase]
  let roots: [RootCase]
  let powers: [PowerCase]
}

private func decimal(_ text: String) throws -> BigDecimal {
  try #require(BigDecimal(text), "cannot parse \(text)")
}

@Suite("BigDecimal arithmetic")
struct BigDecimalArithmeticTests {
  @Test("Addition, subtraction, multiplication, division and ordering agree with Python's decimal")
  func matchesReferenceVectors() throws {
    let vectors: DecimalVectors = try loadVectors("decimal-vectors")
    #expect(vectors.arithmetic.count >= 250)
    for item in vectors.arithmetic {
      let a = try decimal(item.a)
      let b = try decimal(item.b)
      #expect(a + b == (try decimal(item.sum)), "\(item.a) + \(item.b)")
      #expect(a - b == (try decimal(item.difference)), "\(item.a) - \(item.b)")
      #expect(a * b == (try decimal(item.product)), "\(item.a) * \(item.b)")
      #expect((a < b ? -1 : a > b ? 1 : 0) == item.compare, "compare \(item.a), \(item.b)")
      if let quotient = item.quotient50, let short = item.quotient7 {
        #expect(try a.divided(by: b, precision: 50) == decimal(quotient), "\(item.a) / \(item.b) to 50 digits")
        #expect(try a.divided(by: b, precision: 7) == decimal(short), "\(item.a) / \(item.b) to 7 digits")
      }
    }
  }

  @Test("Rounding to significant digits and to decimal places agrees with Python")
  func rounding() throws {
    let vectors: DecimalVectors = try loadVectors("decimal-vectors")
    for item in vectors.rounding {
      let x = try decimal(item.x)
      #expect(
        x.rounded(toSignificantDigits: item.digits) == (try decimal(item.toDigits)),
        "\(item.x) to \(item.digits) digits")
      #expect(x.rounded(toPlaces: item.places) == (try decimal(item.toPlaces)), "\(item.x) to \(item.places) places")
    }
  }

  @Test("Rounding a very small or very large number is immediate")
  func roundingExtremes() throws {
    #expect(try decimal("1e-1000000").rounded(toPlaces: 2) == BigDecimal(0))
    #expect(try decimal("-1e-1000000").rounded(toPlaces: 2) == BigDecimal(0))
    #expect(try decimal("1e1000000").rounded(toPlaces: 2) == decimal("1e1000000"))
    #expect(try decimal("0.4e-3").rounded(toPlaces: 3) == BigDecimal(0))
    #expect(try decimal("0.5e-3").rounded(toPlaces: 3) == decimal("0.001"))
    #expect(try decimal("-0.5e-3").rounded(toPlaces: 3) == decimal("-0.001"))
  }

  @Test("Square roots agree with Python at several precisions")
  func squareRoots() throws {
    let vectors: DecimalVectors = try loadVectors("decimal-vectors")
    for item in vectors.roots {
      let root = try decimal(item.x).squareRoot(precision: item.precision)
      #expect(root == (try decimal(item.expected)), "√\(item.x) to \(item.precision) digits")
    }
  }

  @Test("Integer powers agree with Python's exact power, rounded")
  func integerPowers() throws {
    let vectors: DecimalVectors = try loadVectors("decimal-vectors")
    for item in vectors.powers {
      let value = try decimal(item.x).power(item.n, precision: item.precision)
      #expect(value == (try decimal(item.expected)), "\(item.x)^\(item.n) to \(item.precision) digits")
    }
  }

  @Test("Decimal literals are parsed exactly and printed back losslessly")
  func parsingAndPrinting() throws {
    let cases: [(String, String)] = [
      ("0", "0"), ("-0", "0"), ("12", "12"), ("1.50", "1.5"), ("0.001", "0.001"), ("0.0000001", "1e-7"),
      ("1e-7", "1e-7"), ("123456789012345678901", "123456789012345678901"), ("1e20", "100000000000000000000"),
      ("1e21", "1e+21"), ("-2.5e-30", "-2.5e-30"), ("12345.678", "12345.678"), ("1.5E+3", "1500"),
      (".5", "0.5"), ("5.", "5"), ("100", "100"), ("-0.05", "-0.05"),
    ]
    for (input, printed) in cases {
      let value = try decimal(input)
      #expect(value.description == printed, "\(input)")
      #expect(try decimal(value.description) == value, "round trip of \(input)")
    }
    for bad in ["", ".", "-", "e5", "1e", "1.2.3", "1,5", "abc", "1e1000000001", "--1", "1 2", "0x10"] {
      #expect(BigDecimal(bad) == nil, "\(bad.debugDescription)")
    }
  }

  @Test("Equal values are equal whatever their spelling")
  func canonicalForm() throws {
    #expect(try decimal("1.50") == decimal("1.5"))
    #expect(try decimal("100") == BigDecimal(BigInt(1), exponent: 2))
    #expect(try decimal("0.0").hashValue == BigDecimal(0).hashValue)
    #expect(try decimal("-0") == BigDecimal(0))
    #expect(try decimal("1e3").hashValue == decimal("1000").hashValue)
    #expect(BigDecimal(0).decimalOrder == nil)
    #expect(try decimal("1234").decimalOrder == 4)
    #expect(try decimal("0.5").decimalOrder == 0)
    #expect(try decimal("0.05").decimalOrder == -1)
    #expect(try decimal("9.99").decimalOrder == 1)
  }

  @Test("Conversions: exact rational, floor, Int and Double")
  func conversions() throws {
    #expect(try decimal("0.125").rational == Rational(1, 8))
    #expect(try decimal("-2.5e2").rational == Rational(-250))
    #expect(BigDecimal(Rational(1, 3), precision: 10) == (try decimal("0.3333333333")))
    #expect(BigDecimal(Rational(2, 3), precision: 5) == (try decimal("0.66667")))
    #expect(BigDecimal(Rational(5, 4), precision: 20) == (try decimal("1.25")))
    #expect(try decimal("2.5").floor == BigInt(2))
    #expect(try decimal("-2.5").floor == BigInt(-3))
    #expect(try decimal("-2").floor == BigInt(-2))
    #expect(try decimal("1e30").floor == BigInt("1000000000000000000000000000000"))
    #expect(try decimal("42").asInt == 42)
    #expect(try decimal("4.2").asInt == nil)
    #expect(try decimal("1e30").asInt == nil)
    #expect(BigDecimal(0).asInt == 0)
    #expect(try decimal("0.1").doubleValue == 0.1)
    #expect(try decimal("1e-300").doubleValue == 1e-300)
  }

  @Test("Division by zero and the square root of a negative number are reported, not trapped")
  func errors() throws {
    #expect(throws: MathError.divisionByZero) { try BigDecimal(1).divided(by: BigDecimal(0)) }
    #expect(throws: MathError.domain) { try BigDecimal(-4).squareRoot() }
    #expect(throws: MathError.domain) { try BigDecimal(0).power(0) }
    #expect(throws: MathError.divisionByZero) { try BigDecimal(0).power(-1) }
    #expect(try BigDecimal(0).divided(by: BigDecimal(5)) == BigDecimal(0))
    #expect(try BigDecimal(0).squareRoot() == BigDecimal(0))
  }

  @Test("Exact results stay exact")
  func exactResults() throws {
    #expect(try BigDecimal(4).squareRoot() == BigDecimal(2))
    #expect(try decimal("0.0001").squareRoot() == decimal("0.01"))
    #expect(try decimal("2.25").squareRoot() == decimal("1.5"))
    #expect(try decimal("1.5").power(2) == decimal("2.25"))
    #expect(try BigDecimal(2).power(-2) == decimal("0.25"))
    #expect(try BigDecimal(10).power(30) == decimal("1e30"))
    #expect(try BigDecimal(1).divided(by: BigDecimal(8)) == decimal("0.125"))
    // 0.1 + 0.2 is exactly 0.3, unlike binary floating point.
    #expect(try decimal("0.1") + decimal("0.2") == decimal("0.3"))
  }

  @Test("√2 to 60 digits")
  func squareRootOfTwo() throws {
    let root = try BigDecimal(2).squareRoot(precision: 60)
    #expect(root == (try decimal("1.41421356237309504880168872420969807856967187537694807317668")))
  }
}
