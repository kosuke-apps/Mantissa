import Foundation
import Testing

@testable import MantissaCore

/// Equations with roots, absolute values, exponentials, logarithms and trigonometric functions: real solutions.
@Suite("Equations beyond polynomials")
struct TranscendentalSolverTests {
  private func solutions(_ text: String) throws -> [String] {
    switch try Calculator().solve(text) {
    case .values(_, let values):
      return values.map { value in
        if let exact = value.exact { return exact.description }
        return "≈" + "\(value.approximation!.real.rounded(toSignificantDigits: 6))"
      }
    case .none: return []
    default:
      Issue.record("\(text) did not give values")
      return []
    }
  }

  @Test(
    "Roots",
    arguments: [
      ("√x=2", ["4"]), ("√(x+1)=x-1", ["3"]), ("√x=-2", []), ("√(2x+3)=x", ["3"]), ("√(x+3)+√(x-2)=5", ["6"]),
      ("∛x=2", ["8"]), ("∛(x-1)=-2", ["-7"]), ("√x+√(x+7)=7", ["9"]), ("x^(3/2)=8", ["4"]), ("1/√x=2", ["1/4"]),
      ("x-√x=2", ["4"]), ("√x=x", ["0", "1"]), ("√(x²-4)=0", ["-2", "2"]), ("√x=√(x-1)", []), ("√x+1=0", []),
      ("√(x+5)=x+3", ["-1"]), ("2√x=x", ["0", "4"]), ("√(3x+1)-√(x-1)=2", ["1", "5"]),
    ])
  func radicals(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }

  @Test(
    "Absolute values",
    arguments: [
      ("|x|=3", ["-3", "3"]), ("|x-1|=3", ["-2", "4"]), ("|2x+1|=5", ["-3", "2"]), ("|x|=-1", []), ("|x|=x-2", []),
      ("|x-1|+|x+2|=5", ["-3", "2"]), ("|x²-4|=3", ["-√7", "-1", "1", "√7"]), ("||x|-1|=2", ["-3", "3"]),
      ("|x-2|=|x+2|", ["0"]), ("|x|=2x-3", ["3"]), ("|3x-2|=x", ["1/2", "1"]), ("|x+1|-|x-1|=1", ["1/2"]),
    ])
  func absoluteValues(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }

  @Test(
    "Exponential equations",
    arguments: [
      ("2^x=8", ["3"]), ("2^x=5", ["log(5, 2)"]), ("3^x=1/9", ["-2"]), ("e^x=5", ["ln(5)"]), ("e^(2x)=5", ["ln(5)/2"]),
      ("4^x-3*2^x+2=0", ["0", "1"]), ("2^(x+1)=8", ["2"]), ("2^x=-1", []), ("9^x=3", ["1/2"]), ("5^(2x-1)=125", ["2"]),
      ("2^x+2^(-x)=5/2", ["-1", "1"]), ("10^x=1000", ["3"]), ("2^(3x)=4", ["2/3"]), ("e^x=1", ["0"]),
      ("3*2^x=12", ["2"]), ("2^x=3^2", ["log(9, 2)"]),
    ])
  func exponentials(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }

  @Test(
    "Logarithmic equations",
    arguments: [
      ("ln(x)=3", ["e^3"]), ("log(x)=2", ["100"]), ("log(x,2)=3", ["8"]), ("ln(x)+ln(x-2)=ln(3)", ["3"]),
      ("log(x)+log(x-3)=1", ["5"]), ("2ln(x)=ln(x+6)", ["3"]), ("ln(x²)=4", ["-e^2", "e^2"]), ("ln(x)=0", ["1"]),
      ("ln(x+1)=-1", ["-1 + 1/e"]), ("log(x,5)=-1", ["1/5"]), ("ln(x)-ln(x-1)=ln(2)", ["2"]),
      ("log(2x+1)=1", ["9/2"]), ("ln(x)=-5", ["1/e^5"]),
    ])
  func logarithms(input: String, expected: [String]) throws {
    #expect(try solutions(input) == expected, "\(input)")
  }
}

@Suite("Trigonometric equations")
struct TrigonometricEquationTests {
  private func families(_ text: String, unit: AngleUnit = .radians) throws -> [String] {
    var settings = CalculatorSettings()
    settings.angleUnit = unit
    switch try Calculator(settings: settings).solve(text) {
    case .periodic(_, let found): return found.map { "\($0.offset) + \($0.period)n" }
    case .none: return []
    default:
      Issue.record("\(text) did not give families")
      return []
    }
  }

  @Test(
    "Radians",
    arguments: [
      ("sin(x)=1/2", ["π/6 + 2πn", "5π/6 + 2πn"]), ("sin(x)=0", ["0 + πn"]), ("cos(x)=0", ["π/2 + πn"]),
      ("cos(x)=1/2", ["π/3 + 2πn", "5π/3 + 2πn"]), ("sin(x)=-1/2", ["7π/6 + 2πn", "11π/6 + 2πn"]),
      ("sin(x)=1", ["π/2 + 2πn"]), ("cos(x)=-1", ["π + 2πn"]), ("tan(x)=1", ["π/4 + πn"]), ("tan(x)=√3", ["π/3 + πn"]),
      ("sin(x)=cos(x)", ["π/4 + πn"]), ("2sin(x)²-sin(x)-1=0", ["π/2 + 2πn", "7π/6 + 2πn", "11π/6 + 2πn"]),
      ("sin(2x)=1/2", ["π/12 + πn", "5π/12 + πn"]), ("sin(x)=2", []), ("cos(x)=-2", []),
      ("sin(x)+cos(x)=1", ["0 + 2πn", "π/2 + 2πn"]), ("sin(x)+cos(x)=√2", ["π/4 + 2πn"]),
      ("sin(2x)=sin(x)", ["0 + πn", "π/3 + 2πn", "5π/3 + 2πn"]), ("cos(2x)=0", ["π/4 + π/2n"]),
      ("2cos(x)²=1", ["π/4 + π/2n"]), ("sin(x)²=1", ["π/2 + πn"]), ("tan(x)²=3", ["π/3 + πn", "2π/3 + πn"]),
    ])
  func radians(input: String, expected: [String]) throws {
    #expect(try families(input) == expected, "\(input)")
  }

  @Test(
    "Degrees",
    arguments: [
      ("sin(x)=1/2", ["30 + 360n", "150 + 360n"]), ("tan(x)=1", ["45 + 180n"]), ("cos(2x)=0", ["45 + 90n"]),
      ("cos(x)=-1/2", ["120 + 360n", "240 + 360n"]), ("sin(x)=0", ["0 + 180n"]),
    ])
  func degrees(input: String, expected: [String]) throws {
    #expect(try families(input, unit: .degrees) == expected, "\(input)")
  }

  @Test("A value with no closed-form angle keeps the inverse function")
  func inverseFunctions() throws {
    guard case .periodic(_, let found) = try Calculator().solve("sin(x)=1/3") else {
      Issue.record("expected families")
      return
    }
    #expect(found.map { $0.offset.description } == ["asin(1/3)", "π - asin(1/3)"])
    #expect(found[0].offsetApproximation?.rounded(toSignificantDigits: 8) == BigDecimal("0.33983691"))
    #expect(found[1].periodApproximation?.rounded(toSignificantDigits: 8) == BigDecimal("6.2831853"))
  }
}

@Suite("Numerical solutions")
struct NumericalEquationTests {
  private func decimals(_ text: String) throws -> [String] {
    guard case .values(_, let values) = try Calculator().solve(text) else {
      Issue.record("\(text) did not give values")
      return []
    }
    return values.map { value in
      if let exact = value.exact { return exact.description }
      return "≈" + "\(value.approximation!.real.rounded(toSignificantDigits: 8))"
    }
  }

  @Test(
    "Equations with no closed form",
    arguments: [
      ("e^x=x+2", ["≈-1.8414057", "≈1.1461932"]), ("x=cos(x)", ["≈0.73908513"]),
      ("ln(x)=x-2", ["≈0.15859434", "≈3.1461932"]),
      ("2^x=x²", ["≈-0.7666647", "2", "4"]), ("sin(x)=x/2", ["≈-1.8954943", "0", "≈1.8954943"]),
      ("x^x=2", ["≈1.5596105"]), ("x+ln(x)=0", ["≈0.56714329"]),
    ])
  func numeric(input: String, expected: [String]) throws {
    #expect(try decimals(input) == expected, "\(input)")
  }

  @Test("An equation with no solution in the window is not claimed to have none")
  func notClaimed() {
    #expect(throws: CalculatorError.unsupported(.equation)) { try Calculator().solve("e^x=-x²-1") }
  }
}

/// Inputs found by feeding random text to the solver, which once sent it round in circles or out of memory.
@Suite("Solving what has no value or a huge one")
struct SolverRobustnessTests {
  @Test(
    "Absolute values of something undefined are given up on, not looped over",
    arguments: ["abs(i!)+ln(y)=0", "abs(i!)+ln(y)>=0", "abs(y+e!)=6", "sign(y+e!)=6", "abs(i!)+y!>=0"])
  func undefinedInsideBars(input: String) {
    // Any answer will do; the test is that there is one.
    _ = try? Calculator().solve(input)
  }

  @Test("An inequality with a bound as large as e^1000000 reads the right side of it")
  func hugeBounds() throws {
    guard case .intervals(_, let intervals) = try Calculator().solve("x<e^1000000") else {
      Issue.record("expected intervals")
      return
    }
    #expect(intervals.count == 1 && intervals[0].lower == nil && intervals[0].upper?.isClosed == false)
  }

  @Test("A bound too large to compute is not reported as having no solution")
  func boundTooLarge() {
    #expect(throws: CalculatorError.self) { try Calculator().solve("x>2^(10^2000)") }
  }

  @Test(
    "Equations whose values are astronomically large are given up on quickly",
    arguments: [
      "exp(3628800*(y-e))=y/7", "exp(((y-e)*10!))<=(y/7)",
    ])
  func astronomicalValues(input: String) {
    let started = Date()
    _ = try? Calculator().solve(input)
    #expect(Date().timeIntervalSince(started) < 15)
  }

  @Test("A power whose exponent has tens of thousands of digits is too large, not slow")
  func hugeExponent() {
    let started = Date()
    #expect(throws: Never.self) { _ = try? Calculator().evaluate("0^(ln(10)^(π^10))") }
    #expect(Date().timeIntervalSince(started) < 10)
  }

  @Test("The floor of a number with millions of digits is left as it is, not built digit by digit")
  func floorOfAHugeNumber() throws {
    let started = Date()
    let result = try Calculator().evaluate("floor(2^3628800)")
    #expect(Date().timeIntervalSince(started) < 10)
    #expect(result.exact.description == "floor(2^3628800)")
  }

  @Test(
    "An equation with a huge number in it is solved without listing its divisors",
    arguments: ["n=100!", "n>100!", "x^2=100!", "n≠floor(7^e)!"])
  func hugeConstants(input: String) throws {
    #expect(throws: Never.self) { _ = try? Calculator().solve(input) }
  }
}
