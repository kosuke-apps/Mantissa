/// Fixed-point arithmetic on `BigInt`: a value `v` stands for `v / 10^digits`.
///
/// This is the workhorse behind the transcendental functions. Every operation truncates toward zero, so each one
/// is off by less than one unit in the last place; the functions in `BigDecimal+Functions.swift` add guard digits
/// to absorb the accumulated error and round once at the end.
struct FixedPoint {
  let digits: Int
  let one: BigInt

  init(digits: Int) {
    self.digits = digits
    one = BigInt.power10(digits)
  }

  func multiply(_ a: BigInt, _ b: BigInt) -> BigInt { (a * b) / one }

  /// `b` must not be zero.
  func divide(_ a: BigInt, _ b: BigInt) -> BigInt { (a * one) / b }

  /// `a` must not be negative.
  func squareRoot(_ a: BigInt) -> BigInt { (a * one).integerSquareRoot() }

  /// The fixed-point value nearest `x` toward zero.
  func scaled(_ x: BigDecimal) -> BigInt {
    let shift = x.exponent + digits
    if shift >= 0 { return x.significand * BigInt.power10(shift) }
    // Everything lies below the last digit; do not build a huge power of ten just to divide by it.
    if -shift > x.significand.decimalDigitCount { return BigInt() }
    return x.significand / BigInt.power10(-shift)
  }

  func decimal(_ a: BigInt) -> BigDecimal { BigDecimal(a, exponent: -digits) }

  // MARK: Constants

  /// π by Machin's formula, π = 16 atan(1/5) − 4 atan(1/239).
  var pi: BigInt { BigInt(16) * arctanOfReciprocal(5) - BigInt(4) * arctanOfReciprocal(239) }

  /// ln 2 = 2 atanh(1/3), because (1 + 1/3) / (1 − 1/3) = 2.
  var ln2: BigInt { BigInt(2) * arctanhOfReciprocal(3) }

  /// ln 10 = 3 ln 2 + ln(5/4), and ln(5/4) = 2 atanh(1/9).
  var ln10: BigInt { BigInt(6) * arctanhOfReciprocal(3) + BigInt(2) * arctanhOfReciprocal(9) }

  // MARK: Series

  /// atan(1/n) = Σ (−1)^k / ((2k + 1) n^(2k+1)) for an integer n > 1.
  private func arctanOfReciprocal(_ n: Int) -> BigInt {
    let nSquared = BigInt(n * n)
    var power = one / BigInt(n)
    var sum = power
    var k = 1
    while true {
      power = power / nSquared
      if power.isZero { return sum }
      let term = power / BigInt(2 * k + 1)
      sum = k & 1 == 1 ? sum - term : sum + term
      k += 1
    }
  }

  /// atanh(1/n) = Σ 1 / ((2k + 1) n^(2k+1)) for an integer n > 1.
  private func arctanhOfReciprocal(_ n: Int) -> BigInt {
    let nSquared = BigInt(n * n)
    var power = one / BigInt(n)
    var sum = power
    var k = 1
    while true {
      power = power / nSquared
      if power.isZero { return sum }
      sum += power / BigInt(2 * k + 1)
      k += 1
    }
  }

  /// atanh(t) = t + t³/3 + t⁵/5 + …, for |t| well below 1.
  func arctanh(_ t: BigInt) -> BigInt {
    let tSquared = multiply(t, t)
    var power = t
    var sum = t
    var k = 1
    while true {
      power = multiply(power, tSquared)
      if power.isZero { return sum }
      sum += power / BigInt(2 * k + 1)
      k += 1
    }
  }

  /// atan(t) = t − t³/3 + t⁵/5 − …, for |t| well below 1.
  func arctan(_ t: BigInt) -> BigInt {
    let tSquared = multiply(t, t)
    var power = t
    var sum = t
    var k = 1
    while true {
      power = multiply(power, tSquared)
      if power.isZero { return sum }
      let term = power / BigInt(2 * k + 1)
      sum = k & 1 == 1 ? sum - term : sum + term
      k += 1
    }
  }

  /// sin(r) for |r| up to about 0.8.
  func sine(_ r: BigInt) -> BigInt {
    let rSquared = multiply(r, r)
    var term = r
    var sum = r
    var k = 1
    while true {
      term = -multiply(term, rSquared) / BigInt((2 * k) * (2 * k + 1))
      if term.isZero { return sum }
      sum += term
      k += 1
    }
  }

  /// cos(r) for |r| up to about 0.8.
  func cosine(_ r: BigInt) -> BigInt {
    let rSquared = multiply(r, r)
    var term = one
    var sum = one
    var k = 1
    while true {
      term = -multiply(term, rSquared) / BigInt((2 * k - 1) * (2 * k))
      if term.isZero { return sum }
      sum += term
      k += 1
    }
  }

  /// e^r for 0 <= r <= ln 10. The argument is halved ten times so the Taylor series converges quickly, and the
  /// result is squared ten times to undo that; the squarings magnify the error about a thousandfold, which the
  /// guard digits cover.
  func exponential(_ r: BigInt) -> BigInt {
    let halvings = 10
    let reduced = r / BigInt(1 << halvings)
    var term = one
    var sum = one
    var k = 1
    while true {
      term = multiply(term, reduced) / BigInt(k)
      if term.isZero { break }
      sum += term
      k += 1
    }
    for _ in 0..<halvings { sum = multiply(sum, sum) }
    return sum
  }
}
