import Foundation
import Testing

@testable import MantissaCore

/// Equations in one unknown. Each expectation was worked out by hand.
@Suite("Equation solving")
struct SolverTests {
  /// The solutions as text: the exact form, or `≈` and six digits when there is none.
  private func solutions(_ text: String) throws -> [String] {
    guard case .values(_, let values) = try Calculator().solve(text) else {
      Issue.record("\(text) did not give values")
      return []
    }
    return values.map { value in
      if let exact = value.exact { return exact.description }
      let z = value.approximation!
      return "≈" + (z.isReal ? "\(z.real.rounded(toSignificantDigits: 6))" : "\(z.rounded(toSignificantDigits: 6))")
    }
  }

  @Test(
    "Linear equations",
    arguments: [
      ("x+3=5", ["2"]), ("2x-4=0", ["2"]), ("3x+1=x-5", ["-3"]), ("x/2=3", ["6"]), ("0.5x=1", ["2"]),
      ("5=x", ["5"]), ("2(x+1)=10", ["4"]), ("3-x=x", ["3/2"]), ("1/x=4", ["1/4"]), ("(x+1)/(x-1)=2", ["3"]),
      ("√2x=2", ["√2"]), ("πx=3", ["3/π"]), ("x/3+x/4=7", ["12"]),
    ])
  func linear(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }

  @Test(
    "Quadratic equations",
    arguments: [
      ("x²-4=0", ["-2", "2"]), ("x²=4", ["-2", "2"]), ("x²-5x+6=0", ["2", "3"]), ("2x²-3x-2=0", ["-1/2", "2"]),
      ("x²+2x+1=0", ["-1"]), ("x²=0", ["0"]), ("x(x-3)=0", ["0", "3"]), ("x²-2=0", ["-√2", "√2"]),
      ("x²-2x-1=0", ["1 - √2", "1 + √2"]), ("x²-x-1=0", ["(1 - √5)/2", "(1 + √5)/2"]),
      ("3x²-2=0", ["-√6/3", "√6/3"]), ("x²+1=0", ["-i", "i"]), ("x²+4=0", ["-2i", "2i"]),
      ("x²-2x+5=0", ["1 - 2i", "1 + 2i"]), ("x²+x+1=0", ["(-1 - √3i)/2", "(-1 + √3i)/2"]),
      ("(x-1)^2=9", ["-2", "4"]), ("x²+x=0", ["-1", "0"]),
    ])
  func quadratic(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }

  @Test(
    "Higher degrees: rational roots, then the rest",
    arguments: [
      ("(x-1)(x+2)(x-3)=0", ["-2", "1", "3"]), ("x³=8", ["2", "-1 - √3i", "-1 + √3i"]),
      ("x⁴=16", ["-2", "2", "-2i", "2i"]), ("x⁴-5x²+4=0", ["-2", "-1", "1", "2"]),
      ("x⁴+4=0", ["-1 - i", "-1 + i", "1 - i", "1 + i"]), ("x³-x=0", ["-1", "0", "1"]),
      ("x³+x²-2x=0", ["-2", "0", "1"]), ("2x³-3x²-3x+2=0", ["-1", "1/2", "2"]),
      ("x³=-8", ["-2", "1 - √3i", "1 + √3i"]),
      ("x⁶=1", ["-1", "1", "(-1 - √3i)/2", "(-1 + √3i)/2", "(1 - √3i)/2", "(1 + √3i)/2"]),
    ])
  func higher(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }

  @Test("A root of an irreducible polynomial is given as a decimal")
  func numeric() throws {
    // Wallis's number, the real root of x³ − 2x − 5.
    let wallis = try solutions("x³-2x-5=0")
    #expect(wallis.count == 3)
    #expect(wallis[0] == "≈2.09455")
    #expect(wallis[1] == "≈-1.04728 - 1.13594i")
    // The real root of x⁵ − x − 1.
    #expect(try solutions("x⁵-x-1=0").first == "≈1.1673")
    #expect(try solutions("x³+x+1=0").first == "≈-0.682328")
  }

  @Test("Numeric roots satisfy the equation to many digits")
  func residuals() throws {
    guard case .values(_, let values) = try Calculator().solve("x⁵-x-1=0") else {
      Issue.record("no values")
      return
    }
    #expect(values.count == 5)
    for value in values {
      let z = try #require(value.approximation)
      var total = ComplexDecimal(real: BigDecimal(0))
      for coefficient in [-1, -1, 0, 0, 0, 1].reversed() {
        total = total.multiplied(by: z, precision: 60).adding(
          ComplexDecimal(real: BigDecimal(coefficient)), precision: 60)
      }
      #expect((total.magnitudeSquared.decimalOrder ?? -999) < -80, "residual of \(z)")
    }
  }

  @Test("Equations with other letters are solved for x")
  func parameters() throws {
    #expect(try solutions("ax+b=0") == ["-b/a"])
    #expect(try solutions("2x+y=10") == ["5 - y/2"])
    #expect(try solutions("x²=a") == ["√a", "-√a"])
    #expect(try solutions("z=3x+1") == ["z/3 - 1/3"])
  }

  @Test("The unknown is x if there is one, then y, then the first letter")
  func choosingTheUnknown() throws {
    func variable(_ text: String) throws -> String? {
      switch try Calculator().solve(text) {
      case .values(let name, _), .none(let name), .everything(let name, _), .intervals(let name, _): return name
      case .truth, .tuples, .dependent, .periodic: return nil
      }
    }
    #expect(try variable("y+x=3") == "x")
    #expect(try variable("y+1=3") == "y")
    #expect(try variable("b+a=3") == "a")
    #expect(try variable("z-1=0") == "z")
  }

  @Test("No solution, every number, and statements with no unknown")
  func specialCases() throws {
    #expect(try Calculator().solve("x+1=x") == .none(variable: "x"))
    #expect(try Calculator().solve("2x=2x+3") == .none(variable: "x"))
    #expect(try Calculator().solve("x=x") == .everything(variable: "x", excluding: []))
    #expect(try Calculator().solve("2(x+1)=2x+2") == .everything(variable: "x", excluding: []))
    #expect(try Calculator().solve("1+1=2") == .truth(true))
    #expect(try Calculator().solve("1+1=3") == .truth(false))
    #expect(try Calculator().solve("√2*√3=√6") == .truth(true))
    #expect(try Calculator().solve("sin(1)^2+cos(1)^2=1") == .truth(true))
    // (x² − 1)/(x − 1) − (x + 1) is 0 wherever it is defined, which is everywhere except 1.
    guard case .everything(_, let excluded) = try Calculator().solve("(x²-1)/(x-1)=x+1") else {
      Issue.record("not an identity")
      return
    }
    #expect(excluded.map { $0.exact?.description } == ["1"])
  }

  @Test("A value that makes a denominator zero is not a solution")
  func extraneous() throws {
    #expect(try solutions("(x²-1)/(x-1)=0") == ["-1"])
    #expect(try solutions("x+1/x=2") == ["1"])
    #expect(try solutions("1/x+1/(x+1)=1") == ["(1 - √5)/2", "(1 + √5)/2"])
    #expect(try Calculator().solve("1/(x-2)=1/(x-2)+1") == .none(variable: "x"))
    #expect(try Calculator().solve("x/(x-1)=1/(x-1)") == .none(variable: "x"))
  }

  @Test("Exact answers have a decimal value alongside")
  func decimals() throws {
    guard case .values(_, let values) = try Calculator().solve("x²-2=0") else {
      Issue.record("no values")
      return
    }
    #expect(values[1].approximation?.real.rounded(toSignificantDigits: 10) == BigDecimal("1.414213562"))
    guard case .values(_, let complex) = try Calculator().solve("x²+4=0") else {
      Issue.record("no values")
      return
    }
    #expect(complex[1].approximation == ComplexDecimal(real: BigDecimal(0), imaginary: BigDecimal(2)))
  }

  /// Random polynomials with small whole coefficients (some built from chosen rational roots): the solver returns as many
  /// distinct roots as the polynomial has, and every one satisfies the equation to many digits.
  @Test("Random polynomials: every root is found and satisfies the equation")
  func randomPolynomials() throws {
    var random = SplitMix64(seed: 90210)
    func int(_ range: ClosedRange<Int>) -> Int { Int(random.next() % UInt64(range.count)) + range.lowerBound }
    var checked = 0
    let rounds = max(60, (Int(ProcessInfo.processInfo.environment["MANTISSA_SAMPLES"] ?? "") ?? 400) / 3)

    for round in 0..<rounds {
      var coefficients: [Int]  // lowest power first
      if round % 3 == 0 {
        // Multiply out (x − r₁)(x − r₂)… with small whole roots, so the rational root search has work to do.
        coefficients = [int(1...3)]
        for _ in 0..<int(1...4) {
          let root = int(-4...4)
          var next = Array(repeating: 0, count: coefficients.count + 1)
          for (power, coefficient) in coefficients.enumerated() {
            next[power + 1] += coefficient
            next[power] -= root * coefficient
          }
          coefficients = next
        }
      } else {
        coefficients = (0...int(1...6)).map { _ in int(-9...9) }
        if coefficients.last == 0 { coefficients[coefficients.count - 1] = int(1...9) }
      }
      let polynomial = RationalPolynomial(coefficients.map { Rational($0) })
      guard polynomial.degree >= 1 else { continue }

      var text = ""
      for (power, coefficient) in coefficients.enumerated() where coefficient != 0 {
        text += "\(coefficient < 0 ? "-" : "+")\(abs(coefficient))*x^\(power)"
      }
      guard case .values(_, let values) = try Calculator().solve(text + "=0") else {
        Issue.record("no values for \(text)")
        continue
      }
      #expect(values.count == polynomial.squarefree.degree, "\(text): \(values.count) roots")

      for value in values {
        let z = try #require(value.approximation, "\(text)")
        var total = ComplexDecimal(real: BigDecimal(0))
        var scale = BigDecimal(0)
        for (power, coefficient) in coefficients.enumerated().reversed() {
          total = total.multiplied(by: z, precision: 60).adding(
            ComplexDecimal(real: BigDecimal(coefficient)), precision: 60)
          let size = try z.magnitude(precision: 20)
          scale =
            scale + BigDecimal(abs(coefficient)) * (power == 0 ? BigDecimal(1) : try size.power(power, precision: 20))
        }
        // |p(z)|² against (30 digits of the sum of |aₖ||z|ᵏ)².
        let limit = scale * scale * BigDecimal(BigInt(1), exponent: -50)
        #expect(total.magnitudeSquared <= limit, "\(text) at \(z): residual \(total)")
      }
      checked += 1
    }
    #expect(checked > rounds * 4 / 5)
  }
}
