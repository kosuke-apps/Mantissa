import Testing

@testable import MantissaCore

@Suite("Number theory")
struct NumberTheoryTests {
  private func factors(_ text: String) -> [String] {
    let result = NumberTheory.factor(BigInt(text)!)
    var parts = result.primes.map { $0.exponent == 1 ? "\($0.prime)" : "\($0.prime)^\($0.exponent)" }
    if !result.cofactor.isOne { parts.append("[\(result.cofactor)]") }
    return parts
  }

  @Test("Small numbers are factored completely")
  func smallFactorizations() {
    #expect(factors("1") == [])
    #expect(factors("2") == ["2"])
    #expect(factors("12") == ["2^2", "3"])
    #expect(factors("360") == ["2^3", "3^2", "5"])
    #expect(factors("97") == ["97"])
    #expect(factors("1000000007") == ["1000000007"])
    #expect(factors("600851475143") == ["71", "839", "1471", "6857"])
    #expect(factors("999999000001") == ["999999000001"])
    #expect(factors("9223372036854775807") == ["7^2", "73", "127", "337", "92737", "649657"])
  }

  @Test("Numbers beyond 63 bits are factored by small primes; what is left is reported as a cofactor")
  func bigFactorizations() {
    // 2^70 · 3 · 5^2: all small primes.
    #expect(factors("88544371553805847756800") == ["2^70", "3", "5^2"])
    // 2^64 + 1 = 274177 × 67280421310721, whose smaller factor exceeds the trial limit for big numbers.
    let result = NumberTheory.factor(BigInt("18446744073709551617")!)
    #expect(result.primes.isEmpty || result.primes.map(\.prime) == [BigInt(274177)])
    var product = result.cofactor
    for entry in result.primes { product *= entry.prime.power(entry.exponent) }
    #expect(product == BigInt("18446744073709551617"))
  }

  @Test("Factors multiply back to the number")
  func factorizationsMultiplyBack() {
    var generator = SplitMix64(seed: 7)
    for _ in 0..<200 {
      let value = BigInt(Int(generator.next() % 1_000_000_000_000) + 1)
      let result = NumberTheory.factor(value)
      var product = result.cofactor
      for entry in result.primes { product *= entry.prime.power(entry.exponent) }
      #expect(product == value, "\(value)")
      #expect(result.cofactor.isOne, "\(value) should factor completely")
    }
  }

  @Test("Factorials and counting")
  func counting() {
    #expect(NumberTheory.factorial(0) == BigInt(1))
    #expect(NumberTheory.factorial(5) == BigInt(120))
    #expect(NumberTheory.factorial(20) == BigInt("2432902008176640000"))
    #expect(NumberTheory.factorial(-1) == nil)
    #expect(NumberTheory.factorial(100_000) == nil)
    // The edge the quick refusal uses is the real one: the last factorial within the limit, and the next one beyond it.
    let edge = NumberTheory.largestFactorialArgument
    let last = NumberTheory.factorial(edge)
    #expect(last != nil)
    #expect((last?.bitWidth ?? Int.max) <= NumberTheory.maxExactBits)
    #expect(((last ?? BigInt(1)) * BigInt(edge + 1)).bitWidth > NumberTheory.maxExactBits)
    #expect(NumberTheory.factorial(edge + 1) == nil)
    // A factorial of a factorial is refused as soon as it is seen, whatever the first one is.
    #expect(NumberTheory.factorial(Int.max) == nil)
    #expect(NumberTheory.combinations(5, 2) == BigInt(10))
    #expect(NumberTheory.combinations(52, 5) == BigInt(2_598_960))
    #expect(NumberTheory.combinations(10, 0) == BigInt(1))
    #expect(NumberTheory.combinations(10, 10) == BigInt(1))
    #expect(NumberTheory.combinations(3, 5) == nil)
    #expect(NumberTheory.permutations(5, 2) == BigInt(20))
    #expect(NumberTheory.permutations(5, 0) == BigInt(1))
    #expect(NumberTheory.permutations(5, 5) == BigInt(120))
    #expect(NumberTheory.permutations(-1, 0) == nil)
  }

  @Test("Exact logarithms of rationals")
  func exactLogarithms() {
    func log(_ value: Rational, _ base: Rational) -> Rational? { NumberTheory.exactLogarithm(of: value, base: base) }
    #expect(log(Rational(8), Rational(2)) == Rational(3))
    #expect(log(Rational(8), Rational(4)) == Rational(3, 2))
    #expect(log(Rational(1, 8), Rational(2)) == Rational(-3))
    #expect(log(Rational(1000), Rational(10)) == Rational(3))
    #expect(log(Rational(1), Rational(7)) == Rational(0))
    #expect(log(Rational(9, 4), Rational(3, 2)) == Rational(2))
    #expect(log(Rational(2, 3), Rational(3, 2)) == Rational(-1))
    #expect(log(Rational(5), Rational(3)) == nil)
    #expect(log(Rational(6), Rational(2)) == nil)
    #expect(log(Rational(0), Rational(2)) == nil)
    #expect(log(Rational(4), Rational(1)) == nil)
    #expect(log(Rational(-4), Rational(2)) == nil)
    #expect(log(Rational(2), Rational(8)) == Rational(1, 3))
  }
}
