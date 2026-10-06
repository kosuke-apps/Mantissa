import Testing

@testable import MantissaCore

private struct IntegerCase: Decodable {
  let a: String
  let b: String
  let sum: String
  let difference: String
  let product: String
  let gcd: String
  let compare: Int
  let digits: Int
  let isqrt: String?
  let quotient: String?
  let remainder: String?
  let floorQuotient: String?
}

private struct PowerCase: Decodable {
  let base: String
  let exponent: Int
  let result: String
}

private struct IntegerVectors: Decodable {
  let integers: [IntegerCase]
  let powers: [PowerCase]
}

@Suite("BigInt")
struct BigIntTests {
  @Test("Arithmetic agrees with Python on every reference vector")
  func matchesReferenceVectors() throws {
    let vectors: IntegerVectors = try loadVectors("integer-vectors")
    #expect(vectors.integers.count > 400)
    for item in vectors.integers {
      let a = try #require(BigInt(item.a))
      let b = try #require(BigInt(item.b))
      #expect((a + b).description == item.sum, "\(item.a) + \(item.b)")
      #expect((a - b).description == item.difference, "\(item.a) - \(item.b)")
      #expect((a * b).description == item.product, "\(item.a) * \(item.b)")
      #expect(BigInt.gcd(a, b).description == item.gcd, "gcd(\(item.a), \(item.b))")
      #expect((a < b ? -1 : a > b ? 1 : 0) == item.compare, "compare \(item.a), \(item.b)")
      if let quotient = item.quotient, let remainder = item.remainder {
        let result = a.quotientAndRemainder(dividingBy: b)
        #expect(result.quotient.description == quotient, "\(item.a) / \(item.b)")
        #expect(result.remainder.description == remainder, "\(item.a) % \(item.b)")
      }
      if let floorQuotient = item.floorQuotient {
        #expect(a.floorDivided(by: b).description == floorQuotient, "floor(\(item.a) / \(item.b))")
      }
      #expect(a.decimalDigitCount == item.digits, "digits of \(item.a)")
      if let root = item.isqrt {
        #expect(a.integerSquareRoot().description == root, "isqrt(\(item.a))")
      }
    }
  }

  @Test("Powers agree with Python")
  func powers() throws {
    let vectors: IntegerVectors = try loadVectors("integer-vectors")
    for item in vectors.powers {
      let base = try #require(BigInt(item.base))
      #expect(base.power(item.exponent).description == item.result, "\(item.base)^\(item.exponent)")
    }
  }

  @Test("Division satisfies q*b + r == a with |r| < |b| for operands that provoke the rare paths")
  func divisionIdentity() {
    var generator = SplitMix64(seed: 42)
    for _ in 0..<3000 {
      let a = BigInt.random(limbCount: Int(generator.next() % 12) + 1, using: &generator)
      let b = BigInt.random(limbCount: Int(generator.next() % 6) + 1, using: &generator)
      guard !b.isZero else { continue }
      let (q, r) = a.quotientAndRemainder(dividingBy: b)
      #expect(q * b + r == a, "\(a) / \(b)")
      #expect(r.magnitude < b.magnitude, "\(a) % \(b)")
    }
  }

  @Test("Signs follow Int: the quotient truncates and the remainder takes the dividend's sign")
  func signedDivision() {
    for (a, b) in [(7, 2), (-7, 2), (7, -2), (-7, -2), (0, 5), (6, 3), (-6, 3), (1, 1_000_000)] {
      let result = BigInt(a).quotientAndRemainder(dividingBy: BigInt(b))
      #expect(result.quotient == BigInt(a / b), "\(a) / \(b)")
      #expect(result.remainder == BigInt(a % b), "\(a) % \(b)")
    }
  }

  @Test("Zero is never negative")
  func zeroHasNoSign() {
    #expect(BigInt(0) == -BigInt(0))
    #expect(!(-BigInt(0)).isNegative)
    #expect((BigInt(5) - BigInt(5)).signum == 0)
    #expect(!BigInt("-0")!.isNegative)
    #expect(BigInt(0).hashValue == (-BigInt(0)).hashValue)
    #expect(BigInt(-5) * BigInt(0) == BigInt(0))
    #expect(!(BigInt(-5) * BigInt(0)).isNegative)
  }

  @Test("Conversion to and from Int, including the extremes")
  func intConversion() {
    for value in [0, 1, -1, 42, Int(Int32.max), Int(Int32.min), 1 << 32, -(1 << 32), Int.max, Int.min, Int.max - 1] {
      #expect(BigInt(value).asInt == value, "\(value)")
      #expect(BigInt(value).description == String(value), "\(value)")
    }
    #expect((BigInt(Int.max) + BigInt(1)).asInt == nil)
    #expect((BigInt(Int.min) - BigInt(1)).asInt == nil)
    #expect(BigInt("18446744073709551616")!.asInt == nil)
  }

  @Test("Parsing accepts signed decimal digits and nothing else")
  func parsing() {
    #expect(BigInt("007") == BigInt(7))
    #expect(BigInt("+12") == BigInt(12))
    #expect(BigInt("-12") == BigInt(-12))
    for bad in ["", "-", "+", "1_000", "1.5", " 1", "1 ", "0x1F", "١٢", "--1", "1-"] {
      #expect(BigInt(bad) == nil, "\(bad.debugDescription)")
    }
  }

  @Test("Printing round-trips, including numbers whose limbs print with inner zeros")
  func printing() {
    let texts = [
      "0", "1", "999999999", "1000000000", "1000000001", "100000000000000000000", "-4294967296",
      "340282366920938463463374607431768211456",
    ]
    for text in texts {
      #expect(BigInt(text)!.description == text)
    }
  }

  @Test("Bit width, parity and powers of small numbers")
  func smallFacts() {
    #expect(BigInt(0).bitWidth == 0)
    #expect(BigInt(1).bitWidth == 1)
    #expect(BigInt(255).bitWidth == 8)
    #expect(BigInt(256).bitWidth == 9)
    #expect(BigInt(1 << 32).bitWidth == 33)
    #expect(BigInt(10).isEven && !BigInt(-7).isEven && BigInt(0).isEven)
    #expect(BigInt(2).power(100).description == "1267650600228229401496703205376")
    #expect(BigInt(-3).power(3) == BigInt(-27))
    #expect(BigInt(0).power(0) == BigInt(1))
    #expect(BigInt(7).power(0) == BigInt(1))
  }

  @Test("Ordering across signs and sizes")
  func ordering() {
    let texts = [
      "-100000000000000000000", "-4294967296", "-1", "0", "1", "4294967295", "4294967296", "99999999999999999999",
    ]
    let values = texts.map { BigInt($0)! }
    for i in values.indices {
      for j in values.indices {
        #expect((values[i] < values[j]) == (i < j), "\(values[i]) < \(values[j])")
        #expect((values[i] == values[j]) == (i == j))
      }
    }
  }
}
