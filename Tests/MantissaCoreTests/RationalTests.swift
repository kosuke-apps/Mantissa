import Testing

@testable import MantissaCore

private struct FractionCase: Decodable {
  let a: String
  let b: String
  let sum: String
  let difference: String
  let product: String
  let compare: Int
  let quotient: String?
}

private struct DecimalCase: Decodable {
  let text: String
  let value: String
}

private struct RationalVectors: Decodable {
  let fractions: [FractionCase]
  let decimals: [DecimalCase]
  let invalidDecimals: [String]
}

/// Reads `n/d` or `n`, as `Rational.description` prints it.
private func fraction(_ text: String) throws -> Rational {
  let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
  let numerator = try #require(BigInt(parts[0]))
  let denominator = try parts.count == 2 ? #require(BigInt(parts[1])) : BigInt(1)
  return Rational(numerator, denominator)
}

@Suite("Rational")
struct RationalTests {
  @Test("Arithmetic agrees with Python's Fraction on every reference vector")
  func matchesReferenceVectors() throws {
    let vectors: RationalVectors = try loadVectors("rational-vectors")
    #expect(vectors.fractions.count >= 300)
    for item in vectors.fractions {
      let a = try fraction(item.a)
      let b = try fraction(item.b)
      #expect((a + b).description == item.sum, "\(item.a) + \(item.b)")
      #expect((a - b).description == item.difference, "\(item.a) - \(item.b)")
      #expect((a * b).description == item.product, "\(item.a) * \(item.b)")
      #expect((a < b ? -1 : a > b ? 1 : 0) == item.compare, "compare \(item.a), \(item.b)")
      if let quotient = item.quotient {
        #expect((a / b).description == quotient, "\(item.a) / \(item.b)")
      }
    }
  }

  @Test("Fractions are stored in lowest terms with a positive denominator")
  func canonicalForm() {
    #expect(Rational(2, 4) == Rational(1, 2))
    #expect(Rational(2, -4) == Rational(-1, 2))
    #expect(Rational(-2, -4) == Rational(1, 2))
    #expect(Rational(0, 7) == Rational(0))
    #expect(Rational(0, -7).denominator == BigInt(1))
    #expect(Rational(6, 3).isInteger)
    #expect(!Rational(1, 3).isInteger)
    #expect(Rational(2, 4).hashValue == Rational(1, 2).hashValue)
    #expect(Rational(-3, 6).description == "-1/2")
    #expect(Rational(8, 4).description == "2")
  }

  @Test("Powers, including negative exponents")
  func powers() {
    #expect(Rational(2, 3).power(3) == Rational(8, 27))
    #expect(Rational(2, 3).power(-2) == Rational(9, 4))
    #expect(Rational(-2, 3).power(3) == Rational(-8, 27))
    #expect(Rational(5, 7).power(0) == Rational(1))
    #expect(Rational(0).power(5) == Rational(0))
  }

  @Test("Decimal literals parse exactly")
  func decimalLiterals() throws {
    let vectors: RationalVectors = try loadVectors("rational-vectors")
    for item in vectors.decimals {
      let parsed = try #require(Rational(decimal: item.text), "\(item.text)")
      #expect(parsed == (try fraction(item.value)), "\(item.text)")
    }
    for text in vectors.invalidDecimals {
      #expect(Rational(decimal: text) == nil, "\(text.debugDescription)")
    }
  }

  @Test("0.1 + 0.2 is exactly 0.3, unlike binary floating point")
  func decimalAddition() throws {
    let sum = try #require(Rational(decimal: "0.1")) + #require(Rational(decimal: "0.2"))
    #expect(sum == Rational(decimal: "0.3"))
  }

  @Test("Ordering, sign and reciprocal")
  func ordering() {
    #expect(Rational(1, 3) < Rational(1, 2))
    #expect(Rational(-1, 2) < Rational(-1, 3))
    #expect(Rational(-1, 2) < Rational(1, 1000))
    #expect(Rational(-3, 4).signum == -1)
    #expect(Rational(0).signum == 0)
    #expect(Rational(-3, 4).magnitude == Rational(3, 4))
    #expect(Rational(-3, 4).reciprocal == Rational(-4, 3))
  }
}
