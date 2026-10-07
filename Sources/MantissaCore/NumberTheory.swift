/// Integer helpers the exact layer needs: factoring (for radicals and logarithms), factorials and counting.
enum NumberTheory {
  struct PrimePower: Equatable {
    var prime: BigInt
    var exponent: Int
  }

  /// A factorization found by trial division. `cofactor` is 1 when the number was factored completely; otherwise it
  /// is what is left after removing every prime up to the trial limit (it may be prime or composite).
  struct Factorization: Equatable {
    var primes: [PrimePower]
    var cofactor: BigInt
  }

  /// Numbers below 2^63 are trial-divided up to this bound, so anything below 10^12 is factored completely.
  private static let nativeLimit: UInt64 = 1_000_000
  /// Larger numbers are divided only up to this bound, which keeps a single factoring under a second.
  private static let bigLimit = 50_000

  /// Factors a positive integer.
  static func factor(_ value: BigInt) -> Factorization {
    precondition(value.signum > 0, "Only positive integers can be factored")
    if let small = value.asInt { return factorNative(UInt64(small)) }
    return factorBig(value)
  }

  private static func factorNative(_ value: UInt64) -> Factorization {
    var remaining = value
    var primes: [PrimePower] = []
    func divideOut(_ divisor: UInt64) {
      var count = 0
      while remaining % divisor == 0 {
        remaining /= divisor
        count += 1
      }
      if count > 0 { primes.append(PrimePower(prime: BigInt(Int(divisor)), exponent: count)) }
    }
    divideOut(2)
    var divisor: UInt64 = 3
    while divisor <= nativeLimit && divisor * divisor <= remaining {
      divideOut(divisor)
      divisor += 2
    }
    if remaining == 1 { return Factorization(primes: primes, cofactor: BigInt(1)) }
    if divisor * divisor > remaining {
      primes.append(PrimePower(prime: BigInt(Int(remaining)), exponent: 1))
      return Factorization(primes: primes, cofactor: BigInt(1))
    }
    return Factorization(primes: primes, cofactor: BigInt(Int(remaining)))
  }

  private static func factorBig(_ value: BigInt) -> Factorization {
    var remaining = value
    var primes: [PrimePower] = []
    func divideOut(_ divisor: Int) {
      let factor = BigInt(divisor)
      var count = 0
      while true {
        let (quotient, remainder) = remaining.quotientAndRemainder(dividingBy: factor)
        if !remainder.isZero { break }
        remaining = quotient
        count += 1
      }
      if count > 0 { primes.append(PrimePower(prime: factor, exponent: count)) }
    }
    divideOut(2)
    var divisor = 3
    while divisor <= bigLimit {
      divideOut(divisor)
      divisor += 2
    }
    if remaining.isOne { return Factorization(primes: primes, cofactor: BigInt(1)) }
    let bound = BigInt(divisor)
    if bound * bound > remaining {
      primes.append(PrimePower(prime: remaining, exponent: 1))
      return Factorization(primes: primes, cofactor: BigInt(1))
    }
    return Factorization(primes: primes, cofactor: remaining)
  }

  /// Results beyond this many bits (about 21 000 digits) are refused: nobody can read them and they cost real time.
  static let maxExactBits = 70_000

  /// `n!`, or `nil` when `n` is negative or the result would be larger than `maxExactBits`.
  static func factorial(_ n: Int) -> BigInt? {
    guard n >= 0 else { return nil }
    var result = BigInt(1)
    if n >= 2 {
      for factor in 2...n {
        result *= BigInt(factor)
        if result.bitWidth > maxExactBits { return nil }
      }
    }
    return result
  }

  /// The number of ways to choose `r` of `n` things, or `nil` when the arguments are out of range or too large.
  static func combinations(_ n: Int, _ r: Int) -> BigInt? {
    guard n >= 0, r >= 0, r <= n else { return nil }
    let k = min(r, n - r)
    var result = BigInt(1)
    if k >= 1 {
      for index in 1...k {
        result = result * BigInt(n - k + index) / BigInt(index)
        if result.bitWidth > maxExactBits { return nil }
      }
    }
    return result
  }

  /// The number of ordered arrangements of `r` of `n` things, or `nil` when out of range or too large.
  static func permutations(_ n: Int, _ r: Int) -> BigInt? {
    guard n >= 0, r >= 0, r <= n else { return nil }
    var result = BigInt(1)
    if r >= 1 {
      for index in 0..<r {
        result *= BigInt(n - index)
        if result.bitWidth > maxExactBits { return nil }
      }
    }
    return result
  }

  /// `t` such that `base^t == value`, for positive rationals with `base != 1`; `nil` when there is no rational `t`
  /// or the factoring was too incomplete to tell. For example `log_4(8) = 3/2` and `log_2(1/8) = -3`.
  static func exactLogarithm(of value: Rational, base: Rational) -> Rational? {
    guard value.signum > 0, base.signum > 0, base != Rational(1) else { return nil }
    guard let valueVector = primeVector(value), let baseVector = primeVector(base) else { return nil }
    guard let pivot = baseVector.first(where: { $0.value != 0 }) else { return nil }
    let ratio = Rational(valueVector[pivot.key] ?? 0) / Rational(pivot.value)
    for key in Set(valueVector.keys).union(baseVector.keys) {
      let expected = ratio * Rational(baseVector[key] ?? 0)
      if expected != Rational(valueVector[key] ?? 0) { return nil }
    }
    return ratio
  }

  /// Prime exponents of a positive rational (denominator primes count negatively). An unresolved cofactor is used
  /// as if it were a prime of its own; two numbers sharing one cofactor still compare correctly.
  private static func primeVector(_ value: Rational) -> [BigInt: Int]? {
    var vector: [BigInt: Int] = [:]
    for (part, sign) in [(value.numerator, 1), (value.denominator, -1)] {
      let factorization = factor(part)
      for entry in factorization.primes { vector[entry.prime, default: 0] += sign * entry.exponent }
      if !factorization.cofactor.isOne { vector[factorization.cofactor, default: 0] += sign }
    }
    return vector
  }
}
