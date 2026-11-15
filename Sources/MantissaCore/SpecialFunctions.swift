// The error function and the normal quantile, to any number of digits (`docs/statistics.md`).
//
// erf(x) for small |x| is the series with no alternating signs, erf(x) = 2/√π e^(−x²) Σ 2ⁿ x^(2n+1) / (1·3·…·(2n+1)), which has no cancellation to
// lose digits to. erfc(x) for large x is a continued fraction, which keeps the digits of a number that is nearly zero. The quantile
// is found by Newton's method on erfc, from a start that is worked out with machine numbers.

import Foundation

extension BigDecimal {
  /// Beyond this magnitude the error function is not worked out: erfc(300) is about 10^−39 000.
  private static let erfLimit = 300

  /// The point where erf and erfc change from the series to the continued fraction.
  private static let erfSwitch = BigDecimal(3)

  // MARK: Error function

  /// The error function, 2/√π ∫₀ˣ e^(−t²) dt.
  public func erf(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    if isZero { return self }
    guard magnitude <= BigDecimal(Self.erfLimit) else { return isNegative ? BigDecimal(-1) : BigDecimal(1) }
    let working = precision + 20
    let x = magnitude
    let value: BigDecimal
    if x < Self.erfSwitch {
      value = try Self.erfSeries(x, working: working)
    } else {
      value = BigDecimal(1) - (try Self.erfcFraction(x, working: working))
    }
    return (isNegative ? -value : value).rounded(toSignificantDigits: precision)
  }

  /// The complementary error function, 1 − erf(x), with all its digits right however small it is.
  public func erfc(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let working = precision + 20
    if magnitude > BigDecimal(Self.erfLimit) {
      if isNegative { return BigDecimal(2) }
      throw .overflow  // smaller than 10^−39 000
    }
    let x = magnitude
    let positive: BigDecimal
    if x < Self.erfSwitch {
      positive = BigDecimal(1) - (try Self.erfSeries(x, working: working))
    } else {
      positive = try Self.erfcFraction(x, working: working)
    }
    // erfc(−x) = 2 − erfc(x)
    return (isNegative ? BigDecimal(2) - positive : positive).rounded(toSignificantDigits: precision)
  }

  /// erf(x) for 0 ≤ x < 3.
  private static func erfSeries(_ x: BigDecimal, working w: Int) throws(MathError) -> BigDecimal {
    if x.isZero { return x }
    let x2 = (x * x).rounded(toSignificantDigits: w)
    let twoX2 = x2 + x2
    var term = x
    var sum = x
    var n = 0
    let tolerance = BigDecimal(BigInt(1), exponent: -(w + 2))
    while true {
      n += 1
      term = try (term * twoX2).divided(by: BigDecimal(2 * n + 1), precision: w)
      sum = sum + term
      if term.magnitude < sum.magnitude * tolerance { break }
      guard n < 200_000 else { throw .overflow }
    }
    let root = try BigDecimal.pi(precision: w).squareRoot(precision: w)
    let prefactor = try BigDecimal(2).divided(by: root, precision: w)
    return (prefactor * (try (-x2).exp(precision: w)) * sum).rounded(toSignificantDigits: w)
  }

  /// erfc(x) for x ≥ 3: e^(−x²)/√π divided by the continued fraction x + (1/2)/(x + 1/(x + (3/2)/(x + 2/(x + …)))), summed by Lentz's
  /// method until the terms no longer change the value.
  private static func erfcFraction(_ x: BigDecimal, working w: Int) throws(MathError) -> BigDecimal {
    let x2 = (x * x).rounded(toSignificantDigits: w)
    let tolerance = BigDecimal(BigInt(1), exponent: -(w + 2))
    var f = x
    var c = x
    var d = BigDecimal(0)
    var k = 0
    while true {
      k += 1
      let a = try BigDecimal(k).divided(by: BigDecimal(2), precision: w)
      d = x + a * d
      c = x + (try a.divided(by: c, precision: w))
      d = try BigDecimal(1).divided(by: d, precision: w)
      let delta = (c * d).rounded(toSignificantDigits: w)
      f = (f * delta).rounded(toSignificantDigits: w)
      if (delta - BigDecimal(1)).magnitude < tolerance { break }
      guard k < 200_000 else { throw .overflow }
    }
    let root = try BigDecimal.pi(precision: w).squareRoot(precision: w)
    let prefactor = try (try (-x2).exp(precision: w)).divided(by: root, precision: w)
    return try prefactor.divided(by: f, precision: w)
  }

  // MARK: Normal quantile

  /// The value z with Φ(z) = self, where Φ is the standard normal distribution function (the quantile function, or probit). The
  /// value must be strictly between 0 and 1.
  public func probit(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let one = BigDecimal(1)
    guard signum > 0, self < one else { throw .domain }
    let half = try BigDecimal(1).divided(by: BigDecimal(2), precision: 5)
    if self == half { return BigDecimal(0) }
    // The lower tail has the digits; the upper tail is its mirror image.
    let upper = self > half
    let tail = upper ? one - self : self
    let z = try Self.lowerQuantile(tail, precision: precision)
    return upper ? -z : z
  }

  /// z ≤ 0 with Φ(z) = q for 0 < q < 1/2, to `precision` digits.
  private static func lowerQuantile(_ q: BigDecimal, precision: Int) throws(MathError) -> BigDecimal {
    let working = precision + 20
    var z = try startingQuantile(q)
    let root2 = try BigDecimal(2).squareRoot(precision: working)
    let tau = try (BigDecimal(2) * BigDecimal.pi(precision: working)).squareRoot(precision: working)
    let tolerance = BigDecimal(BigInt(1), exponent: -(precision + 4))
    for _ in 0..<12 {
      // Newton's step for Φ(z) − q, with Φ(z) = erfc(−z/√2)/2 and the density e^(−z²/2)/√(2π).
      let argument = try (-z).divided(by: root2, precision: working)
      let cdf = try argument.erfc(precision: working).halved
      let density = try (try (-(z * z).halved).exp(precision: working)).divided(by: tau, precision: working)
      let step = try (cdf - q).divided(by: density, precision: working)
      z = (z - step).rounded(toSignificantDigits: working)
      if step.magnitude <= z.magnitude * tolerance { break }
    }
    return z.rounded(toSignificantDigits: precision)
  }

  /// A start for Newton's method, good to about nine digits: the root of Φ(z) = q found by bisection on machine numbers (and, for a
  /// q below what a machine number holds, the first terms of the tail's expansion).
  private static func startingQuantile(_ q: BigDecimal) throws(MathError) -> BigDecimal {
    let value = q.doubleValue
    if value < 1e-300 {
      // Φ(z) ≈ e^(−z²/2) / (|z|√(2π)), so z² ≈ −2 ln q − ln(−2 ln q) − ln 2π.
      let l = try q.ln(precision: 30)
      let a = -(l + l)
      let z2 = a - (try a.ln(precision: 30)) - (try (BigDecimal(2) * BigDecimal.pi(precision: 30)).ln(precision: 30))
      return -(try z2.squareRoot(precision: 30))
    }
    var low = -40.0
    var high = 0.0
    for _ in 0..<80 {
      let middle = (low + high) / 2
      if 0.5 * Foundation.erfc(-middle / 2.0.squareRoot()) < value { low = middle } else { high = middle }
    }
    return BigDecimal("\(low)") ?? BigDecimal(0)
  }
}

/// The standard normal functions on machine numbers, for plotting.
enum NormalDouble {
  /// The quantile: z with Φ(z) = p, or NaN outside (0, 1).
  static func quantile(_ p: Double) -> Double {
    guard p > 0, p < 1 else { return .nan }
    if p == 0.5 { return 0 }
    let upper = p > 0.5
    let q = upper ? 1 - p : p
    var low = -40.0
    var high = 0.0
    for _ in 0..<80 {
      let middle = (low + high) / 2
      if 0.5 * Foundation.erfc(-middle / 2.0.squareRoot()) < q { low = middle } else { high = middle }
    }
    let z = (low + high) / 2
    return upper ? -z : z
  }
}
