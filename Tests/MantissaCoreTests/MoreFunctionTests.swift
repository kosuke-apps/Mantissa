import Testing

@testable import MantissaCore

/// `mod`, `min`, `max`, `sign`, the two-argument `atan`, the parts of a complex number, and the reciprocal and inverse
/// reciprocal trigonometric and hyperbolic functions. Each expectation was worked out by hand.
@Suite("More functions")
struct MoreFunctionTests {
  private func exact(_ text: String, unit: AngleUnit = .radians) throws -> String {
    var settings = CalculatorSettings()
    settings.angleUnit = unit
    return try Calculator(settings: settings).evaluate(text).exact.description
  }

  @Test(
    "Modulo has the sign of the divisor",
    arguments: [
      ("mod(17,5)", "2"), ("mod(-7,3)", "2"), ("mod(7,-3)", "-2"), ("mod(5.5,2)", "3/2"), ("mod(10,5)", "0"),
      ("mod(0,4)", "0"), ("mod(-1,5)", "4"), ("mod(1/2,1/3)", "1/6"), ("mod(2π,π)", "0"), ("mod(2^100,7)", "2"),
    ])
  func modulo(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("Modulo of something irrational, and by zero")
  func moduloEdges() throws {
    let value = try Calculator().evaluate("mod(π,1)").approximation
    #expect(value?.rounded(toSignificantDigits: 10).description == "0.1415926536")
    #expect(throws: CalculatorError.math(.divisionByZero)) { try Calculator().evaluate("mod(5,0)") }
  }

  @Test(
    "The larger and the smaller of some numbers",
    arguments: [
      ("max(1,2)", "2"), ("min(1,2)", "1"), ("max(3,1,2)", "3"), ("min(-1,-5,0)", "-5"), ("max(√2,3/2)", "3/2"),
      ("min(√2,3/2)", "√2"), ("max(π,3)", "π"), ("min(1/3,0.3)", "3/10"), ("max(2,2)", "2"), ("max(-1,-2)", "-1"),
      ("min(e,2.7)", "27/10"), ("max(√3,√2,1)", "√3"),
    ])
  func extremes(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("max and min with an unknown are |a − b| formulas that take the right value")
  func symbolicExtremes() throws {
    let larger = try Calculator().evaluate("max(x,3)").exact
    #expect(try larger.approximation(values: ["x": BigDecimal(5)]).description == "5")
    #expect(try larger.approximation(values: ["x": BigDecimal(1)]).description == "3")
    let smaller = try Calculator().evaluate("min(x,y)").exact
    #expect(try smaller.approximation(values: ["x": BigDecimal(-4), "y": BigDecimal(2)]).description == "-4")
  }

  @Test(
    "The sign of a number",
    arguments: [
      ("sign(-5)", "-1"), ("sign(0)", "0"), ("sign(7/2)", "1"), ("sign(√2-1)", "1"), ("sign(1-√2)", "-1"),
      ("sign(-π)", "-1"), ("sign(x)", "x/abs(x)"), ("sign(3+4i)", "(3 + 4i)/5"),
    ])
  func sign(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "atan with two arguments is the angle of the point",
    arguments: [
      ("atan(1,1)", "π/4"), ("atan(1,-1)", "3π/4"), ("atan(-1,-1)", "-3π/4"), ("atan(-1,1)", "-π/4"),
      ("atan(0,-1)", "π"), ("atan(0,5)", "0"), ("atan(1,0)", "π/2"), ("atan(-1,0)", "-π/2"), ("atan(√3,1)", "π/3"),
      ("atan(1,-√3)", "5π/6"),
    ])
  func twoArgumentArctangent(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("atan(y, x) in degrees, at the origin and with unknowns")
  func twoArgumentArctangentEdges() throws {
    #expect(try exact("atan(1,-1)", unit: .degrees) == "135")
    #expect(try exact("atan(-1,-1)", unit: .degrees) == "-135")
    #expect(throws: CalculatorError.math(.noValue)) { try Calculator().evaluate("atan(0,0)") }
    #expect(throws: CalculatorError.math(.unsupported)) { try Calculator().evaluate("atan(y,x)") }
  }

  @Test(
    "Real part, imaginary part, conjugate and argument",
    arguments: [
      ("re(2+3i)", "2"), ("im(2+3i)", "3"), ("conj(2+3i)", "2 - 3i"), ("conj(i)", "-i"), ("re(5)", "5"), ("im(5)", "0"),
      ("arg(1+i)", "π/4"), ("arg(-1)", "π"), ("arg(i)", "π/2"), ("arg(-i)", "-π/2"), ("arg(1)", "0"),
      ("arg(-1-i)", "-3π/4"), ("arg(√3+i)", "π/6"), ("re(x+yi)", "x"), ("im(x+yi)", "y"), ("conj(1-2i)", "1 + 2i"),
      ("re((1+i)^2)", "0"), ("im((1+i)^2)", "2"), ("conj(2)", "2"),
    ])
  func complexParts(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("arg in degrees and at zero")
  func argumentEdges() throws {
    #expect(try exact("arg(1+i)", unit: .degrees) == "45")
    #expect(try exact("arg(-1)", unit: .degrees) == "180")
    #expect(throws: CalculatorError.math(.noValue)) { try Calculator().evaluate("arg(0)") }
  }

  @Test(
    "Inverse cotangent, secant and cosecant",
    arguments: [
      ("acot(1)", "π/4"), ("acot(-1)", "3π/4"), ("acot(0)", "π/2"), ("acot(√3)", "π/6"), ("asec(2)", "π/3"),
      ("asec(1)", "0"), ("asec(-2)", "2π/3"), ("acsc(2)", "π/6"), ("acsc(-1)", "-π/2"), ("acsc(√2)", "π/4"),
    ])
  func inverseReciprocals(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("The inverse reciprocals in degrees and outside their domain")
  func inverseReciprocalEdges() throws {
    #expect(try exact("acot(1)", unit: .degrees) == "45")
    #expect(try exact("asec(2)", unit: .degrees) == "60")
    #expect(try exact("acsc(2)", unit: .degrees) == "30")
    #expect(throws: CalculatorError.math(.domain)) { try Calculator().evaluate("asec(1/2)") }
    #expect(throws: CalculatorError.math(.domain)) { try Calculator().evaluate("acsc(0.3)") }
    #expect(throws: CalculatorError.math(.divisionByZero)) { try Calculator().evaluate("asec(0)") }
  }

  @Test(
    "Hyperbolic cotangent, secant and cosecant, and their inverses",
    arguments: [
      ("coth(x)", "cosh(x)/sinh(x)"), ("sech(x)", "1/cosh(x)"), ("csch(x)", "1/sinh(x)"), ("sech(0)", "1"),
      ("acoth(2)", "atanh(1/2)"), ("asech(1)", "0"), ("acsch(1)", "asinh(1)"), ("acsch(-1)", "-asinh(1)"),
    ])
  func hyperbolicReciprocals(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("The hyperbolic reciprocals where they are not defined")
  func hyperbolicReciprocalEdges() throws {
    #expect(throws: CalculatorError.math(.divisionByZero)) { try Calculator().evaluate("coth(0)") }
    #expect(throws: CalculatorError.math(.divisionByZero)) { try Calculator().evaluate("csch(0)") }
    #expect(throws: CalculatorError.math(.domain)) { try Calculator().evaluate("asech(2)") }
    #expect(throws: CalculatorError.math(.domain)) { try Calculator().evaluate("acoth(1/2)") }
  }

  @Test("Numerically they agree with the functions they are made of")
  func numericAgreement() throws {
    let checks: [(String, String)] = [
      ("coth(1.5)", "cosh(1.5)/sinh(1.5)"), ("sech(2)", "1/cosh(2)"), ("csch(0.7)", "1/sinh(0.7)"),
      ("acoth(3)", "atanh(1/3)"), ("asech(0.25)", "acosh(4)"), ("acsch(2.5)", "asinh(0.4)"),
      ("acot(-2)", "π/2 - atan(-2)"),
    ]
    for (left, right) in checks {
      let a = try #require(try Calculator().evaluate(left).approximation)
      let b = try #require(try Calculator().evaluate(right).approximation)
      #expect(a == b, "\(left) against \(right)")
    }
  }

  @Test("Names that are letters people multiply stay letters unless a parenthesis follows")
  func lettersAreNotFunctions() throws {
    #expect(try exact("re") == exact("r*e"))
    #expect(try exact("im") == exact("i*m"))
    #expect(try exact("max") == exact("m*a*x"))
    #expect(try exact("2mod") == exact("2*m*o*d"))
    #expect(try exact("xmax(1,2)") == exact("x*max(1,2)"))
    #expect(try exact("arg+1") == exact("a*r*g+1"))
  }

  @Test("A function with the wrong number of arguments is refused")
  func argumentCounts() {
    for text in ["mod(1)", "mod(1,2,3)", "max(1)", "sign(1,2)", "re(1,2)", "atan(1,2,3)", "coth(1,2)"] {
      #expect(throws: CalculatorError.self, "\(text)") { try Calculator().evaluate(text) }
    }
  }
}

/// Quarter turns and whole turns taken out of the argument of a trigonometric function, and even powers of |x|.
@Suite("Turns in trigonometric arguments and powers of bars")
struct TurnTests {
  private func exact(_ text: String, unit: AngleUnit = .radians) throws -> String {
    var settings = CalculatorSettings()
    settings.angleUnit = unit
    return try Calculator(settings: settings).evaluate(text).exact.description
  }

  @Test(
    "Multiples of π/2 swap sine and cosine, and other multiples are brought within a turn",
    arguments: [
      ("sin(x+π)", "-sin(x)"), ("sin(x+π/2)", "cos(x)"), ("cos(x+π/2)", "-sin(x)"), ("cos(x+π)", "-cos(x)"),
      ("sin(x+3π/2)", "-cos(x)"), ("cos(x+3π/2)", "sin(x)"), ("sin(π-x)", "sin(x)"), ("cos(π-x)", "-cos(x)"),
      ("sin(π/2-x)", "cos(x)"), ("cos(π/2-x)", "sin(x)"), ("sin(x+2π)", "sin(x)"), ("cos(x-2π)", "cos(x)"),
      ("sin(x+7π/3)", "sin(x + π/3)"), ("sin(x-7π/3)", "sin(x - π/3)"), ("sin(x+5π/3)", "sin(x - π/3)"),
      ("tan(x+π)", "tan(x)"), ("tan(x+3π/4)", "tan(x - π/4)"), ("sin(2x+π)", "-sin(2x)"),
      ("sin(-x-π/2)", "-cos(x)"), ("sin(x+π/3)", "sin(x + π/3)"), ("sin(x+π/4)", "sin(x + π/4)"),
      ("sin(x+11π/2)", "-cos(x)"), ("cos(x-π/2)", "sin(x)"),
    ])
  func shifts(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("tan(x + π/2) is −cot x, written with sine and cosine")
  func tangentQuarterTurn() throws {
    #expect(try exact("tan(x+π/2)") == "-cos(x)/sin(x)")
    #expect(try exact("tan(x-π/2)") == "-cos(x)/sin(x)")
  }

  @Test("In degrees the same shifts happen, since the argument is written with π")
  func degreeShifts() throws {
    #expect(try exact("sin(x+90)", unit: .degrees) == exact("cos(x)", unit: .degrees))
    #expect(try exact("cos(x+180)", unit: .degrees) == exact("-cos(x)", unit: .degrees))
    #expect(try exact("sin(x+360)", unit: .degrees) == exact("sin(x)", unit: .degrees))
  }

  @Test("The square root of an even power is the absolute value")
  func evenPowers() throws {
    #expect(try exact("sqrt(x^2)") == "abs(x)")
    #expect(try exact("(x^4)^(1/2)") == "x^2")
    #expect(try exact("(x^2)^(3/2)") == "abs(x)^3")
    #expect(try exact("(x^2)^(1/3)") == "abs(x)^(2/3)")
    #expect(try exact("sqrt((x-1)^2)") == "abs(x - 1)")
    #expect(try exact("abs(x)^2") == "x^2")
    #expect(try exact("abs(x)^4") == "x^4")
    #expect(try exact("abs(x)^3") == "abs(x)^3")
    #expect(try exact("abs(x)^(-2)") == "1/x^2")
    // An odd power may be negative, so its root is not simplified; a positive base needs no bars.
    #expect(try exact("sqrt(x^3)") == "√(x^3)")
    #expect(try exact("sqrt(e^2)") == "e")
  }
}

/// Identities that make an answer smaller.
@Suite("Trigonometric simplification")
struct TrigonometricSimplificationTests {
  private func exact(_ text: String) throws -> String {
    try Calculator().evaluate(text).exact.description
  }

  /// The expression as the canonical form has it, before any identity is applied.
  private func canonical(_ text: String) throws -> Expr {
    guard case .expression(let syntax) = try Parser.parse(text) else { throw MathError.unsupported }
    return try Builder(angleUnit: .radians).build(syntax)
  }

  @Test(
    "Sums of squares and double angles",
    arguments: [
      ("sin(x)^2+cos(x)^2", "1"), ("2sin(x)^2+2cos(x)^2", "2"), ("1-sin(x)^2", "cos(x)^2"), ("1-cos(x)^2", "sin(x)^2"),
      ("cos(x)^2-sin(x)^2", "cos(2x)"), ("sin(x)^2-cos(x)^2", "-cos(2x)"), ("1-2sin(x)^2", "cos(2x)"),
      ("2cos(x)^2-1", "cos(2x)"), ("2sin(x)cos(x)", "sin(2x)"), ("4sin(x)cos(x)", "2sin(2x)"),
      ("x*sin(x)^2+x*cos(x)^2", "x"), ("sin(2x)^2+cos(2x)^2", "1"), ("sin(x)^2+cos(x)^2+x", "x + 1"),
      ("e^(sin(x)^2+cos(x)^2)", "e"), ("3-3cos(x)^2", "3sin(x)^2"), ("sin(x+1)^2+cos(x+1)^2", "1"),
      ("(sin(x)^2+cos(x)^2)^3+x", "x + 1"),
    ])
  func identities(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Left alone: different angles, different coefficients, nothing smaller",
    arguments: [
      "sin(x)^2+cos(y)^2", "3sin(x)^2+2cos(x)^2", "sin(x)cos(y)", "sin(x)^2", "3sin(x)cos(x)", "sin(x)^2+x*cos(x)^2",
      "(sin(x)+cos(x))^2", "tan(x)^2+1",
    ])
  func unchanged(input: String) throws {
    let value = try Calculator().evaluate(input).exact
    #expect(value == (try canonical(input)))
    #expect(
      value.trigonometricallySimplified() == nil,
      "\(input) became \(String(describing: value.trigonometricallySimplified()))")
  }

  @Test("Random sums of sine and cosine squares keep their value, and never get bigger")
  func randomSums() throws {
    var random = SplitMix64(seed: 1729 &+ propertySeedOffset)
    func pick<T>(_ items: [T]) -> T { items[Int(random.next() % UInt64(items.count))] }
    let angles = ["x", "2x", "x+1", "3x-2"]
    let rests = ["1", "x", "y", "x*y", "e^x"]
    let coefficients = ["1", "2", "-1", "-2", "3", "1/2", "4"]
    var changed = 0
    for _ in 0..<120 {
      var terms: [String] = []
      for _ in 0..<Int(random.next() % 4 + 2) {
        let angle = pick(angles)
        let rest = pick(rests)
        let coefficient = pick(coefficients)
        switch random.next() % 5 {
        case 0: terms.append("(\(coefficient))*(\(rest))*sin(\(angle))^2")
        case 1, 2: terms.append("(\(coefficient))*(\(rest))*cos(\(angle))^2")
        case 3: terms.append("(\(coefficient))*(\(rest))*sin(\(angle))*cos(\(angle))")
        default: terms.append("(\(coefficient))*(\(rest))")
        }
      }
      let text = terms.joined(separator: "+")
      let typed = try canonical(text)
      let answer = try Calculator().evaluate(text).exact
      #expect(answer.nodeCount <= typed.nodeCount, "\(text)")
      if answer != typed { changed += 1 }
      for (x, y) in [(Rational(13, 10), Rational(3, 7)), (Rational(-7, 10), Rational(5, 3))] {
        let values = ["x": BigDecimal(x, precision: 40), "y": BigDecimal(y, precision: 40)]
        let a = try typed.approximation(precision: 40, values: values)
        let b = try answer.approximation(precision: 40, values: values)
        #expect((a - b).magnitude <= BigDecimal(BigInt(1), exponent: -30) * max(BigDecimal(1), a.magnitude), "\(text)")
      }
    }
    #expect(changed > 8, "only \(changed) sums were simplified")
  }
}
