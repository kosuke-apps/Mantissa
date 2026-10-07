import Testing

@testable import MantissaCore

/// End-to-end checks: text in, exact answer out. Each expectation was worked out by hand from the mathematics, not
/// copied from the program's output.
@Suite("Calculator")
struct CalculatorTests {
  private func exact(_ text: String, unit: AngleUnit = .degrees) throws -> String {
    var settings = CalculatorSettings()
    settings.angleUnit = unit
    return try Calculator(settings: settings).evaluate(text).exact.description
  }

  @Test(
    "Arithmetic is exact",
    arguments: [
      ("1+2*3", "7"), ("(1+2)*3", "9"), ("2^10", "1024"), ("2^-2", "1/4"), ("-2^2", "-4"), ("2^3^2", "512"),
      ("1/3+1/6", "1/2"), ("0.1+0.2", "3/10"), ("12/8", "3/2"), ("(2/3)^2", "4/9"), ("(−2)^3", "-8"),
      ("10^-3", "1/1000"), ("1/(1+1/(1+1/2))", "3/5"), ("(2+3)(4+5)", "45"), ("3(4)", "12"), ("1.5E3", "1500"),
      ("0.1^2", "1/100"), ("-3-(-2)", "-1"), ("6/4/3", "1/2"), ("2^0", "1"), ("0^3", "0"), ("7-7", "0"),
    ])
  func arithmetic(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Roots are simplified to an integer part and prime radicals",
    arguments: [
      ("sqrt(12)", "2√3"), ("√12", "2√3"), ("√2*√3", "√6"), ("√2+√8", "3√2"), ("1/√2", "√2/2"),
      ("(1+√2)(1-√2)", "-1"), ("(√3)^2", "3"), ("∛8", "2"), ("root(27,3)", "3"), ("8^(1/3)", "2"), ("1/√3", "√3/3"),
      ("√(8/9)", "2√2/3"), ("√(1/2)", "√2/2"), ("2^(5/4)", "2·2^(1/4)"), ("(-8)^(1/3)", "-2"), ("(-8)^(2/3)", "4"),
      ("√(2+7)", "3"), ("sqrt(16)+sqrt(9)", "7"), ("√50", "5√2"), ("√(3)*√(12)", "6"), ("√0", "0"), ("∜16", "2"),
      ("√2√2", "2"), ("2√3+√3", "3√3"),
    ])
  func roots(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Denominators are rationalised and sums of radicals multiplied out",
    arguments: [
      ("1/(1+√2)", "-1 + √2"), ("(√2+1)/(√2-1)", "3 + 2√2"), ("(1+√3)^2", "4 + 2√3"), ("(√2+√3)^2", "5 + 2√6"),
      ("1/(√3-√2)", "√2 + √3"), ("(2+√3)(2-√3)", "1"), ("1/(2+2√2)", "-1/2 + √2/2"),
    ])
  func rationalising(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Trigonometry in degrees is exact at the usual angles",
    arguments: [
      ("sin(30)", "1/2"), ("cos(60)", "1/2"), ("tan(45)", "1"), ("sin(45)", "√2/2"), ("cos(30)", "√3/2"),
      ("sin(90)", "1"), ("cos(90)", "0"), ("cos(180)", "-1"), ("sin(210)", "-1/2"), ("sin(-30)", "-1/2"),
      ("tan(15)", "2 - √3"), ("tan(75)", "2 + √3"), ("tan(135)", "-1"), ("sin(15)", "√6/4 - √2/4"),
      ("cos(75)", "√6/4 - √2/4"), ("asin(0.5)", "30"), ("acos(-0.5)", "120"), ("atan(1)", "45"), ("atan(√3)", "60"),
      ("asin(-1)", "-90"), ("acos(1)", "0"), ("sin(30°)", "1/2"), ("sin(0)", "0"), ("cos(0)", "1"),
      ("sin(360)", "0"), ("sin(390)", "1/2"),
    ])
  func degrees(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Trigonometry in radians, and π in degree mode, is exact at the usual angles",
    arguments: [
      ("sin(π/6)", "1/2"), ("cos(π)", "-1"), ("sin(π)", "0"), ("tan(π/4)", "1"), ("cos(π/3)", "1/2"),
      ("sin(30°)", "1/2"), ("asin(1/2)", "π/6"), ("acos(-1/2)", "2π/3"), ("atan(1)", "π/4"), ("sin(2π)", "0"),
      ("cos(7π/6)", "-√3/2"),
    ])
  func radians(input: String, expected: String) throws {
    #expect(try exact(input, unit: .radians) == expected, "\(input) in radians")
  }

  @Test("A π in the argument is taken as radians even in degree mode")
  func piInDegreeMode() throws {
    #expect(try exact("sin(π/6)", unit: .degrees) == "1/2")
    #expect(try exact("cos(π)", unit: .degrees) == "-1")
    #expect(try exact("sin(1)", unit: .degrees) == "sin(π/180)")
  }

  @Test(
    "Logarithms, exponentials and constants",
    arguments: [
      ("ln(e)", "1"), ("log(1000)", "3"), ("log(8,2)", "3"), ("log(8,4)", "3/2"), ("log(1/8,2)", "-3"),
      ("ln(e^3)", "3"), ("e^(ln(5))", "5"), ("exp(1)", "e"), ("ln(1)", "0"), ("log(1)", "0"), ("ln(10)", "ln(10)"),
      ("log(5,3)", "log(5, 3)"), ("π/6", "π/6"), ("2π", "2π"), ("π*π", "π^2"), ("π/π", "1"), ("e^2*e^3", "e^5"),
      ("ln(√e)", "1/2"),
    ])
  func logarithms(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Integer functions",
    arguments: [
      ("5!", "120"), ("0!", "1"), ("10!", "3628800"), ("20!/18!", "380"), ("nCr(5,2)", "10"), ("nPr(5,2)", "20"),
      ("nCr(10,0)", "1"), ("gcd(12,18)", "6"), ("lcm(4,6)", "12"), ("floor(2.7)", "2"), ("ceil(2.1)", "3"),
      ("round(2.5)", "3"), ("round(-2.5)", "-3"), ("floor(-2.5)", "-3"), ("abs(-3)", "3"), ("|−5|", "5"),
      ("floor(√2)", "1"), ("ceil(π)", "4"), ("50%", "1/2"), ("200*10%", "20"),
    ])
  func integerFunctions(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Expressions with unknowns are simplified symbolically",
    arguments: [
      ("2x+3x", "5x"), ("x+x", "2x"), ("x*x", "x^2"), ("2x*3x", "6x^2"), ("(x+1)*2", "2x + 2"), ("x/x", "1"),
      ("x^2*x^3", "x^5"), ("x - x", "0"), ("2(x+3)", "2x + 6"), ("x^2 - 3x + 2", "x^2 - 3x + 2"),
      ("xy", "xy"), ("yx", "xy"), ("x²", "x^2"), ("(x+1)/(x+1)", "1"), ("√x*√x", "x"), ("x/2", "x/2"),
      ("x*2", "2x"), ("(2x)^2", "4x^2"), ("(x^2)^3", "x^6"), ("1/x*x", "1"), ("2^(x+1)", "2·2^x"),
      ("e^(ln(x))", "x"), ("x+y+x", "2x + y"), ("(2x+2)^2", "4(x + 1)^2"), ("sin 2x", "x sin(π/90)"),
    ])
  func symbolic(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("Equal expressions are equal whichever way they were written")
  func canonicalEquality() throws {
    let pairs = [
      ("x+y", "y+x"), ("2(x+1)", "2x+2"), ("x*y*z", "z*y*x"), ("(x+1)+(y+2)", "x+y+3"), ("2x/2", "x"),
      ("3/6", "1/2"), ("√8", "2√2"), ("x^2*x", "x*x^2"), ("(x*y)^2", "x^2*y^2"), ("x-y", "-y+x"),
      ("(a+b)*3", "3a+3b"), ("2/(4x)", "1/(2x)"),
    ]
    for (left, right) in pairs {
      #expect(try exact(left) == exact(right), "\(left) vs \(right)")
    }
  }

  @Test("Fullwidth and typeset characters are understood")
  func unicodeInput() throws {
    #expect(try exact("１２＋３×４") == "24")
    #expect(try exact("１÷３") == "1/3")
    #expect(try exact("2−1") == "1")
    #expect(try exact("８÷（２＋２）") == "2")
    #expect(try exact("√（１６）") == "4")
    #expect(try exact("[1+2]*{3}") == "9")
  }

  @Test("Decimal approximations are correct to the digits asked for")
  func approximations() throws {
    let calculator = Calculator()
    let root2 = try #require(calculator.evaluate("√2").approximation)
    #expect(root2 == BigDecimal("1.4142135623730950488016887242096980785696718753769"))
    let pi = try #require(calculator.evaluate("π").approximation)
    #expect(pi == BigDecimal.pi())
    let value = try #require(calculator.evaluate("sin(1)").approximation)
    // 1 degree in radians: sin(π/180).
    #expect(value.rounded(toSignificantDigits: 20) == BigDecimal("0.017452406437283512819"))
    #expect(
      try #require(calculator.evaluate("1/3").approximation).rounded(toSignificantDigits: 10)
        == BigDecimal("0.3333333333"))
    #expect(
      try #require(calculator.evaluate("100!").approximation).rounded(toSignificantDigits: 10)
        == BigDecimal("9.332621544e157"))
    #expect(try calculator.evaluate("2x+1").approximation == nil)

    var settings = CalculatorSettings()
    settings.precision = 8
    let short = try #require(Calculator(settings: settings).evaluate("√2").approximation)
    #expect(short == BigDecimal("1.4142136"))
  }

  @Test("sin²(1°) + cos²(1°) − 1 is not left as a rounding residue")
  func cancellationIsZero() throws {
    let result = try Calculator().evaluate("sin(1)^2+cos(1)^2-1")
    #expect(result.approximation == BigDecimal(0))
  }

  @Test("Errors say what went wrong")
  func errors() {
    func fails(_ text: String) -> CalculatorError? {
      do {
        _ = try Calculator().evaluate(text)
        return nil
      } catch {
        return error
      }
    }
    #expect(fails("1/0") == .math(.divisionByZero))
    #expect(fails("0^0") == .math(.domain))
    #expect(fails("0^-1") == .math(.divisionByZero))
    #expect(fails("ln(0)") == .math(.domain))
    #expect(fails("ln(-1)") == .math(.domain))
    #expect(fails("asin(2)") == .math(.domain))
    #expect(fails("acos(-1.5)") == .math(.domain))
    #expect(fails("tan(90)") == .math(.domain))
    #expect(fails("(-3)!") == .math(.domain))
    #expect(fails("2.5!") == .math(.domain))
    #expect(fails("nCr(3,5)") == .math(.domain))
    #expect(fails("x=3") == .unsupported(.equation))
    #expect(fails("x+1=2, x-1=0") == .unsupported(.system))
    #expect(fails("1<x") == .unsupported(.equation))
    #expect(fails("2 3") == .parse(ParseError(reason: .unexpectedToken("3"), offset: 2)))
    #expect(fails("(1+2") == .parse(ParseError(reason: .missingClosingParenthesis, offset: 4)))
    #expect(fails("1+") == .parse(ParseError(reason: .unexpectedEnd, offset: 2)))
    #expect(fails("") == .parse(ParseError(reason: .empty, offset: 0)))
    #expect(fails("1 + * 2") == .parse(ParseError(reason: .unexpectedToken("×"), offset: 4)))
    #expect(fails("1 $ 2") == .parse(ParseError(reason: .unexpectedCharacter("$"), offset: 2)))
    #expect(
      fails("log(1,2,3)")
        == .parse(ParseError(reason: .wrongArgumentCount(function: "log", expected: "1 or 2"), offset: 0)))
    #expect(
      fails("root(8)") == .parse(ParseError(reason: .wrongArgumentCount(function: "root", expected: "2"), offset: 0)))
    #expect(fails("|3") == .parse(ParseError(reason: .missingClosingBar, offset: 2)))
  }

  @Test("A real-valued exact expression with no real value keeps its exact form")
  func nonRealResult() throws {
    let result = try Calculator().evaluate("√(-4)")
    #expect(result.exact.description == "√(-4)")
    #expect(result.approximation == nil)
    #expect(result.approximationError == .domain)
  }

  @Test("Huge results are kept as written rather than expanded to millions of digits")
  func hugeNumbers() throws {
    #expect(try exact("2^100000") == "2^100000")
    #expect(try exact("2^100") == "1267650600228229401496703205376")
    let approximate = try #require(Calculator().evaluate("2^100000").approximation)
    #expect(approximate.rounded(toSignificantDigits: 10) == BigDecimal("9.990020930e30102"))
    #expect(throws: CalculatorError.math(.overflow)) { try Calculator().evaluate("100000!") }
  }
}
