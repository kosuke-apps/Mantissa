import Testing

@testable import MantissaCore

/// Derivatives, integrals, limits and sums. Each expectation was worked out by hand.
@Suite("Derivatives")
struct DerivativeTests {
  private func exact(_ text: String) throws -> String {
    try Calculator().evaluate(text).exact.description
  }

  @Test(
    "Derivatives of the usual functions",
    arguments: [
      ("diff(x^2)", "2x"), ("diff(x^3+2x)", "3x^2 + 2"), ("diff(5)", "0"), ("diff(sin(x))", "cos(x)"),
      ("diff(cos(x))", "-sin(x)"), ("diff(e^x)", "e^x"), ("diff(ln(x))", "1/x"), ("diff(1/x)", "-1/x^2"),
      ("diff(√x)", "1/(2√x)"), ("diff((x^2+1)^3)", "6x(x^2 + 1)^2"), ("diff(x^x)", "x^x(ln(x) + 1)"),
      ("diff(tan(x))", "tan(x)^2 + 1"), ("diff(atan(x))", "1/(x^2 + 1)"), ("diff(asin(x))", "1/√(1 - x^2)"),
      ("diff(sin(2x))", "2cos(2x)"), ("diff(e^(x^2))", "2xe^(x^2)"), ("diff(2^x)", "2^x ln(2)"),
      ("diff(x*e^x)", "xe^x + e^x"), ("diff(ln(x^2+1))", "2x/(x^2 + 1)"), ("diff(x^(1/3))", "1/(3x^(2/3))"),
      ("diff(log(x,2))", "1/(x ln(2))"), ("diff(sinh(x))", "cosh(x)"), ("diff(cosh(2x))", "2sinh(2x)"),
      ("diff(x/(x+1))", "1/(x + 1)^2"), ("diff(sin(x)/x)", "(x cos(x) - sin(x))/x^2"), ("diff(a*x^2,x)", "2ax"),
      ("diff(a*x^2,a)", "x^2"), ("diff(√(1-x^2))", "-x/√(1 - x^2)"), ("diff(abs(x))", "x/abs(x)"),
    ])
  func derivatives(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("Higher derivatives, and the unknown chosen when not named")
  func higher() throws {
    #expect(try exact("diff(x^2,x,2)") == "2")
    #expect(try exact("diff(x^4,x,2)") == "12x^2")
    #expect(try exact("diff(sin(x),x,4)") == "sin(x)")
    #expect(try exact("diff(y^3)") == "3y^2")
    #expect(try exact("diff(x*y)") == "y")  // x is the unknown when there is one
    #expect(try exact("diff(7,x)") == "0")
  }

  /// For random expressions in x, the derivative agrees with the slope measured by a central difference at 50 digits.
  @Test("Derivatives agree with numerical differentiation")
  func numericalCheck() throws {
    var generator = SyntaxGenerator(seed: 777)
    generator.includesUnknown = true
    let builder = Builder(angleUnit: .radians)
    var checked = 0
    for _ in 0..<600 {
      let syntax = generator.make(depth: 3)
      guard let expression = try? builder.build(syntax), expression.contains("x"),
        let slope = try? expression.derivative("x")
      else { continue }
      for point in ["0.7", "1.3", "-0.4", "2.1"] {
        let x = BigDecimal(point)!
        let h = BigDecimal(BigInt(1), exponent: -20)
        guard let above = try? expression.approximation(precision: 60, values: ["x": x + h]),
          let below = try? expression.approximation(precision: 60, values: ["x": x - h]),
          let measured = try? (above - below).divided(by: h.doubled, precision: 40),
          let computed = try? slope.approximation(precision: 40, values: ["x": x])
        else { continue }
        let scale = max(BigDecimal(1), computed.magnitude, measured.magnitude)
        #expect(
          (computed - measured).magnitude <= scale * BigDecimal(BigInt(1), exponent: -25),
          "d/dx \(expression) at \(point)")
        checked += 1
      }
    }
    #expect(checked > 300)
  }
}

@Suite("Integrals")
struct IntegralTests {
  private func exact(_ text: String) throws -> String {
    try Calculator().evaluate(text).exact.description
  }

  @Test(
    "Basic integrals",
    arguments: [
      ("int(x^2)", "x^3/3"), ("int(x^3-2x+1)", "x^4/4 - x^2 + x"), ("int(1/x)", "ln(abs(x))"), ("int(1/x^2)", "-1/x"),
      ("int(√x)", "2x^(3/2)/3"), ("int(e^x)", "e^x"), ("int(e^(2x))", "e^(2x)/2"), ("int(2^x)", "2^x/ln(2)"),
      ("int(sin(x))", "-cos(x)"), ("int(cos(x))", "sin(x)"), ("int(sin(2x))", "-cos(2x)/2"),
      ("int(tan(x))", "-ln(abs(cos(x)))"), ("int(ln(x))", "x ln(x) - x"), ("int(atan(x))", "x atan(x) - ln(x^2 + 1)/2"),
      ("int(asin(x))", "√(1 - x^2) + x asin(x)"), ("int((x+1)^5)", "(x + 1)^6/6"),
      ("int(1/(2x+1))", "ln(abs(2x + 1))/2"),
      ("int(sin(3x+1))", "-cos(3x + 1)/3"), ("int(e^(-x))", "-e^(-x)"), ("int(5)", "5x"), ("int(a*x)", "ax^2/2"),
    ])
  func basic(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Substitution, by parts, partial fractions and powers of sines and cosines",
    arguments: [
      ("int(x*e^x)", "xe^x - e^x"), ("int(x*sin(x))", "sin(x) - x cos(x)"),
      ("int(x^2*sin(x))", "-x^2cos(x) + 2x sin(x) + 2cos(x)"),
      ("int(x*ln(x))", "x^2ln(x)/2 - x^2/4"), ("int(e^x*sin(x))", "e^x(sin(x) - cos(x))/2"),
      ("int(2x*e^(x^2))", "e^(x^2)"), ("int(ln(x)/x)", "ln(x)^2/2"), ("int(x/(x^2+1))", "ln(x^2 + 1)/2"),
      ("int(1/(x^2+1))", "atan(x)"), ("int(1/(x^2+4))", "atan(x/2)/2"),
      ("int(1/(x^2-1))", "ln(abs(x - 1))/2 - ln(abs(x + 1))/2"),
      ("int(1/(x*(x+1)))", "ln(abs(x)) - ln(abs(x + 1))"),
      ("int((x+1)/(x^2+x-2))", "ln(abs(x + 2))/3 + 2ln(abs(x - 1))/3"),
      ("int((2x+1)/(x^2+x+1))", "ln(x^2 + x + 1)"), ("int(x^3/(x^2+1))", "x^2/2 - ln(x^2 + 1)/2"),
      ("int(sin(x)^2)", "x/2 - sin(2x)/4"), ("int(cos(x)^2)", "x/2 + sin(2x)/4"),
      ("int(sin(x)^3)", "cos(3x)/12 - 3cos(x)/4"),
      ("int(tan(x)^2)", "tan(x) - x"), ("int(1/(1+e^x))", "x - ln(e^x + 1)"),
      ("int(ln(x)^2)", "-2x ln(x) + 2x + x ln(x)^2"),
      ("int(1/√(1-x^2))", "asin(x)"), ("int(x/√(x^2+1))", "√(x^2 + 1)"),
    ])
  func techniques(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  /// Whatever the engine returns is differentiated and compared with the integrand before it is returned, so for a list of
  /// integrands the antiderivative's derivative agrees with the integrand at fresh points, too.
  @Test("Antiderivatives differentiate back to the integrand")
  func roundTrip() throws {
    let integrands = [
      "x^4-3x^2+7", "1/x^3", "x^(2/3)", "e^(3x+1)", "3^x", "cos(4x)", "tan(2x)", "x*cos(x)", "x^3*e^(2x)",
      "e^(2x)*cos(3x)",
      "x^2*atan(x)", "1/(x^2+2x+5)", "(3x+2)/(x^2-4)", "1/(x^3+x)", "(x^2+3)/(x^3-x)", "x^2/(x^2+1)",
      "sin(x)^4", "sin(x)^2*cos(x)", "sin(x)*cos(x)^3", "cos(2x)*sin(3x)", "e^x/(1+e^x)", "cos(x)/(1+sin(x)^2)",
      "x*√(1-x^2)",
      "(2x+1)^(1/3)", "√(x+1)/x", "1/(x*(x+1)^2)", "ln(3x+2)", "x*ln(x+1)", "sinh(2x)*cosh(2x)", "2^x*3^x",
      "x^2*e^(-x)",
    ]
    for text in integrands {
      let integrand = try Calculator().evaluate(text).exact
      guard let antiderivative = integrand.antiderivative("x") else {
        Issue.record("no antiderivative found for \(text)")
        continue
      }
      let slope = try antiderivative.derivative("x")
      var compared = 0
      for point in ["0.21", "1.37", "2.55", "-0.66", "3.4"] {
        let x = BigDecimal(point)!
        guard let wanted = try? integrand.approximation(precision: 40, values: ["x": x]),
          let got = try? slope.approximation(precision: 40, values: ["x": x])
        else { continue }
        let scale = max(BigDecimal(1), wanted.magnitude)
        #expect((wanted - got).magnitude <= scale * BigDecimal(BigInt(1), exponent: -25), "\(text) at \(point)")
        compared += 1
      }
      #expect(compared >= 2, "\(text) was compared at too few points")
    }
  }

  @Test("An integral with no elementary antiderivative is not answered")
  func nonElementary() {
    #expect(throws: CalculatorError.math(.unsupported)) { try Calculator().evaluate("int(e^(x^2))") }
    #expect(throws: CalculatorError.math(.unsupported)) { try Calculator().evaluate("int(sin(x)/x)") }
  }
}

@Suite("Definite integrals, limits and sums")
struct LimitsAndSumsTests {
  private func exact(_ text: String) throws -> String {
    try Calculator().evaluate(text).exact.description
  }

  @Test(
    "Definite and improper integrals",
    arguments: [
      ("int(x^2,x,0,1)", "1/3"), ("int(sin(x),x,0,π)", "2"), ("int(1/x,x,1,e)", "1"), ("int(e^x,x,0,1)", "-1 + e"),
      ("int(1/(1+x^2),x,0,1)", "π/4"), ("int(x*e^x,x,0,1)", "1"), ("int(1/√x,x,0,1)", "2"), ("int(1/x^2,x,1,∞)", "1"),
      ("int(e^(-x),x,0,∞)", "1"), ("int(1/(1+x^2),x,-∞,∞)", "π"), ("int(ln(x),x,0,1)", "-1"),
      ("int(x^2,x,1,3)", "26/3"),
      ("int(cos(x)^2,x,0,2π)", "π"), ("int(abs(x),x,-1,1)", "1"), ("int(x,x,a,b)", "b^2/2 - a^2/2"),
      ("int(x*e^(-x^2),x,0,∞)", "1/2"), ("int(1/(x^2+1),x,0,∞)", "π/2"),
    ])
  func definite(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("An integral that diverges has no value")
  func divergent() {
    for text in ["int(1/x,x,1,∞)", "int(1/x,x,-1,1)", "int(1/x^2,x,-1,1)", "int(x,x,0,∞)"] {
      #expect(throws: CalculatorError.math(.undefined), "\(text)") { try Calculator().evaluate(text) }
    }
  }

  @Test(
    "Limits",
    arguments: [
      ("lim(sin(x)/x,x,0)", "1"), ("lim((1-cos(x))/x^2,x,0)", "1/2"), ("lim((e^x-1)/x,x,0)", "1"),
      ("lim((x^2-1)/(x-1),x,1)", "2"), ("lim(x*ln(x),x,0,1)", "0"), ("lim(1/x,x,0,1)", "∞"), ("lim(1/x,x,0,-1)", "-∞"),
      ("lim(1/x^2,x,0)", "∞"), ("lim((1+1/x)^x,x,∞)", "e"), ("lim(x*sin(1/x),x,∞)", "1"),
      ("lim((3x^2+1)/(x^2-5),x,∞)", "3"), ("lim(e^x/x^2,x,∞)", "∞"), ("lim(e^(-x),x,∞)", "0"), ("lim(ln(x),x,∞)", "∞"),
      ("lim(atan(x),x,∞)", "π/2"), ("lim(√(x^2+x)-x,x,∞)", "1/2"), ("lim(sin(x)/x,x,∞)", "0"), ("lim(x^2,x,3)", "9"),
      ("lim((1+x)^(1/x),x,0)", "e"), ("lim(tan(x),x,π/2,-1)", "∞"), ("lim(x^x,x,0,1)", "1"),
      ("lim((x^3-8)/(x-2),x,2)", "12"),
      ("lim(√x,x,0)", "0"), ("lim((sin(x)-x)/x^3,x,0)", "-1/6"), ("lim(x^2,x,-∞)", "∞"), ("lim(x^3,x,-∞)", "-∞"),
      ("lim(1/x,x,-∞)", "0"), ("lim((2x+1)/(x-3),x,∞)", "2"), ("lim(ln(x)/x,x,∞)", "0"), ("lim(x*e^(-x),x,∞)", "0"),
      ("lim((x^2-4)/(x^2-x-2),x,2)", "4/3"), ("lim(2^x,x,-∞)", "0"), ("lim(x^(1/x),x,∞)", "1"),
      ("lim((1-1/x)^x,x,∞)", "1/e"),
      ("lim(tan(x)/x,x,0)", "1"), ("lim((√(1+x)-1)/x,x,0)", "1/2"), ("lim(x^2*sin(1/x),x,0)", "0"),
    ])
  func limits(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("A limit that does not exist")
  func noLimit() {
    for text in ["lim(1/x,x,0)", "lim(sin(1/x),x,0)", "lim(abs(x)/x,x,0)", "lim(sin(x),x,∞)"] {
      #expect(throws: CalculatorError.math(.undefined), "\(text)") { try Calculator().evaluate(text) }
    }
  }

  @Test(
    "Finite sums",
    arguments: [
      ("sum(k,k,1,100)", "5050"), ("sum(k,k,1,1000)", "500500"), ("sum(k^3,k,1,10)", "3025"),
      ("sum(2^k,k,0,10)", "2047"),
      ("sum(k,k,1,n)", "n^2/2 + n/2"), ("sum(k^2,k,1,n)", "n^3/3 + n^2/2 + n/6"), ("sum(2k+1,k,0,n)", "n^2 + 2n + 1"),
      ("sum(1/k,k,1,4)", "25/12"), ("sum(k^2,k,1,10000)", "333383335000"), ("sum(3,k,1,n)", "3n"),
      ("sum(k,k,5,3)", "0"),
    ])
  func finite(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test(
    "Infinite sums",
    arguments: [
      ("sum(1/2^k,k,0,∞)", "2"), ("sum((1/2)^k,k,1,∞)", "1"), ("sum(3*(2/3)^k,k,0,∞)", "9"),
      ("sum(k*(1/2)^k,k,1,∞)", "2"),
      ("sum(k^2*(1/3)^k,k,1,∞)", "3/2"), ("sum(1/(k*(k+1)),k,1,∞)", "1"), ("sum(1/(k^2-1),k,2,∞)", "3/4"),
      ("sum(1/(k*(k+2)),k,1,∞)", "3/4"), ("sum(1/k^2,k,1,∞)", "π^2/6"), ("sum(1/k^4,k,1,∞)", "π^4/90"),
      ("sum(1/k^2,k,2,∞)", "-1 + π^2/6"), ("sum((-1)^k/k,k,1,∞)", "-ln(2)"), ("sum((-1)^k/k^2,k,1,∞)", "-π^2/12"),
      ("sum(1/k!,k,0,∞)", "e"), ("sum(2^k/k!,k,0,∞)", "e^2"), ("sum(1/k!,k,1,∞)", "-1 + e"),
    ])
  func infinite(input: String, expected: String) throws {
    #expect(try exact(input) == expected, "\(input)")
  }

  @Test("A series that diverges has no sum")
  func divergentSeries() {
    for text in ["sum(1/k,k,1,∞)", "sum(2^k,k,0,∞)", "sum(k,k,1,∞)", "sum((-1)^k,k,0,∞)"] {
      #expect(throws: CalculatorError.math(.undefined), "\(text)") { try Calculator().evaluate(text) }
    }
  }
}

@Suite("Secant, cosecant and Gaussian integrals")
struct GaussianAndSecantTests {
  private func value(_ text: String) throws -> Evaluation { try Calculator().evaluate(text) }

  @Test(
    "Gaussian integrals have exact values",
    arguments: [
      ("int(e^(-x^2),x,-∞,∞)", "√π"), ("int(e^(-x^2),x,0,∞)", "√π/2"), ("int(e^(-x^2),x,-∞,0)", "√π/2"),
      ("int(e^(-2x^2),x,-∞,∞)", "√π√2/2"), ("int(x^2*e^(-x^2),x,-∞,∞)", "√π/2"),
      ("int(x^4*e^(-x^2),x,-∞,∞)", "3√π/4"), ("int(x*e^(-x^2),x,-∞,∞)", "0"), ("int(x*e^(-x^2),x,0,∞)", "1/2"),
      ("int(3e^(-x^2),x,-∞,∞)", "3√π"), ("int(e^(-x^2-1),x,-∞,∞)", "√π/e"),
      ("int(x^2*e^(-x^2),x,0,∞)", "√π/4"), ("int(e^(-x^2/2),x,-∞,∞)", "√π√2"),
    ])
  func gaussian(input: String, expected: String) throws {
    #expect(try value(input).exact.description == expected, "\(input)")
  }

  @Test("A shifted Gaussian, and the value agrees with a numerical integral")
  func shiftedGaussian() throws {
    // ∫ e^(−x² + 2x) dx = e·√π (the peak is at x = 1 and its height is e).
    let shifted = try value("int(e^(-x^2+2x),x,-∞,∞)")
    let approximate = try #require(shifted.approximation)
    let reference = try #require(try value("e*sqrt(π)").approximation)
    #expect((approximate - reference).magnitude < BigDecimal(BigInt(1), exponent: -40))
    // ∫ x e^(−x² + 2x) dx = e·√π (the mean is 1).
    let mean = try #require(try value("int(x*e^(-x^2+2x),x,-∞,∞)").approximation)
    #expect((mean - reference).magnitude < BigDecimal(BigInt(1), exponent: -40))
  }

  @Test("Not Gaussian: the positive x² is not integrable, and a finite range has no closed form here")
  func notGaussian() {
    #expect(throws: CalculatorError.self) { try Calculator().evaluate("int(e^(x^2),x,-∞,∞)") }
    #expect(throws: CalculatorError.self) { try Calculator().evaluate("int(e^(-x^2),x,0,1)") }
  }

  @Test(
    "Secant and cosecant",
    arguments: [
      "int(1/cos(x),x)", "int(1/sin(x),x)", "int(sec(x),x)", "int(csc(x),x)", "int(1/cos(2x),x)", "int(1/sin(3x+1),x)",
    ])
  func secants(input: String) throws {
    let answer = try value(input)
    #expect(answer.isAntiderivative)
    // The answer differentiates back to the integrand: the integrator checks this itself, and here it is checked again.
    let integrand = input.replacingOccurrences(of: "int(", with: "").replacingOccurrences(of: ",x)", with: "")
    let derivative = try value("diff(" + answer.exact.description + ",x)")
    for point in ["0.3", "0.9", "-0.4"] {
      let values = ["x": BigDecimal(point)!]
      let a = try #require(try? derivative.exact.approximation(precision: 40, values: values))
      let b = try #require(try? value(integrand).exact.approximation(precision: 40, values: values))
      #expect((a - b).magnitude < BigDecimal(BigInt(1), exponent: -25), "\(input) at \(point)")
    }
  }

  @Test("Definite secant integral")
  func definiteSecant() throws {
    // ∫ from 0 to π/4 of sec x dx is ln(1 + √2).
    let answer = try #require(try value("int(sec(x),x,0,π/4)").approximation)
    let expected = try #require(try value("ln(1+sqrt(2))").approximation)
    #expect((answer - expected).magnitude < BigDecimal(BigInt(1), exponent: -40))
  }
}

@Suite("Integrals with the square root of a quadratic")
struct QuadraticRadicalIntegralTests {
  private func value(_ text: String) throws -> Evaluation { try Calculator().evaluate(text) }

  @Test(
    "Exact antiderivatives",
    arguments: [
      ("int(sqrt(x^2+1),x)", "x√(x^2 + 1)/2 + asinh(x)/2"), ("int(x^2/sqrt(1-x^2),x)", "asin(x)/2 − x√(1 − x^2)/2"),
      ("int(1/(x^2+1)^(3/2),x)", "x/√(x^2 + 1)"), ("int(1/(x^2*sqrt(x^2+1)),x)", "−√(x^2 + 1)/x"),
      ("int(x*sqrt(x^2+1),x)", "√(x^2 + 1)·(x^2/3 + 1/3)"), ("int(1/sqrt(3-2x-x^2),x)", "asin(x/2 + 1/2)"),
      ("int(sinh(x)^2,x)", "sinh(2x)/4 − x/2"), ("int(cosh(x)^2,x)", "x/2 + sinh(2x)/4"),
      ("int(acosh(x),x)", "xacosh(x) − √(x^2 − 1)"),
    ])
  func antiderivatives(input: String, expected: String) throws {
    #expect(Typesetter.nodes(for: try value(input).exact).plainText == expected, "\(input)")
  }

  @Test(
    "These all have an antiderivative, which the integrator has already checked against the integrand",
    arguments: [
      "int(sqrt(x^2-1),x)", "int(x*asin(x),x)", "int(x*acos(x),x)", "int(x*asinh(x),x)", "int(x^2*sqrt(1-x^2),x)",
      "int(sqrt(x^2+4x+5),x)", "int(sqrt(x^2-4x),x)", "int(x^3/sqrt(x^2+1),x)", "int(x^2/(x^2+1)^(3/2),x)",
      "int(1/(x*sqrt(x^2-1)),x)", "int(1/(x*sqrt(1-x^2)),x)", "int(1/(x*sqrt(x^2+x+1)),x)", "int(sqrt(x^2+1)/x,x)",
      "int(sqrt(4-x^2)/x^2,x)", "int(sqrt(4-x^2)/x,x)", "int((x+1)/(x*sqrt(x^2+1)),x)", "int(atanh(x),x)",
      "int(x*atanh(x),x)", "int(acot(x),x)",
    ])
  func exists(input: String) throws {
    #expect(try value(input).isAntiderivative)
  }

  @Test(
    "Definite integrals with exact values",
    arguments: [
      ("int(sqrt(1-x^2),x,0,1)", "π/4"), ("int(x^2*sqrt(1-x^2),x,0,1)", "π/16"), ("int(sqrt(4-x^2),x,0,2)", "π"),
      ("int(1/(x^2*sqrt(x^2-1)),x,1,2)", "√3/2"),
    ])
  func definite(input: String, expected: String) throws {
    #expect(Typesetter.nodes(for: try value(input).exact).plainText == expected, "\(input)")
  }
}
