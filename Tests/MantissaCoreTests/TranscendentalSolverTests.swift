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
