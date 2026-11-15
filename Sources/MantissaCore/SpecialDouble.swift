// The gamma, incomplete gamma and incomplete beta functions on machine numbers (about 13 digits), for plotting and as the start of the
// decimal ones' Newton iterations (`SpecialFunctions+Gamma.swift`).

import Foundation

enum SpecialDouble {
  /// ln Γ(x) for x > 0, by the system's function.
  static func logGamma(_ x: Double) -> Double { Foundation.lgamma(x) }

  // MARK: Incomplete gamma

  /// The regularised lower and upper incomplete gamma functions P(a, x) and Q(a, x) = 1 − P(a, x), for a > 0 and x ≥ 0.
  static func gamma(_ a: Double, _ x: Double) -> (p: Double, q: Double) {
    guard a > 0, x >= 0, a.isFinite, !x.isNaN else { return (.nan, .nan) }
    if x == 0 { return (0, 1) }
    if x.isInfinite { return (1, 0) }
    let logFactor = a * log(x) - x - logGamma(a)
    if x < a + 1 {
      var term = 1 / a
      var sum = term
      var n = 0.0
      while abs(term) > abs(sum) * 1e-17, n < 100_000 {
        n += 1
        term *= x / (a + n)
        sum += term
      }
      let p = exp(logFactor) * sum
      return (min(p, 1), max(1 - p, 0))
    }
    // The continued fraction for Q, by Lentz's method.
    let tiny = 1e-300
    var b = x + 1 - a
    var c = 1 / tiny
    var d = 1 / b
    var f = d
    var n = 0.0
    while n < 100_000 {
      n += 1
      let an = -n * (n - a)
      b += 2
      d = an * d + b
      if abs(d) < tiny { d = tiny }
      c = b + an / c
      if abs(c) < tiny { c = tiny }
      d = 1 / d
      let delta = d * c
      f *= delta
      if abs(delta - 1) < 1e-16 { break }
    }
    let q = exp(logFactor) * f
    return (max(1 - q, 0), min(q, 1))
  }

  // MARK: Incomplete beta

  /// The regularised incomplete beta function I_x(a, b) and its complement, for a, b > 0 and 0 ≤ x ≤ 1. `y` is 1 − x (given, so that
  /// an x close to 1 keeps its digits).
  static func beta(_ x: Double, _ y: Double, _ a: Double, _ b: Double) -> (lower: Double, upper: Double) {
    guard a > 0, b > 0, x >= 0, y >= 0 else { return (.nan, .nan) }
    if x == 0 { return (0, 1) }
    if y == 0 { return (1, 0) }
    let logFront = a * log(x) + b * log(y) - (logGamma(a) + logGamma(b) - logGamma(a + b))
    if x < (a + 1) / (a + b + 2) {
      let lower = exp(logFront) / a * betaFraction(x, a, b)
      return (lower, 1 - lower)
    }
    let upper = exp(logFront) / b * betaFraction(y, b, a)
    return (1 - upper, upper)
  }

  /// The continued fraction 1/(1 + d₁/(1 + d₂/(1 + …))) of the incomplete beta function, by Lentz's method.
  private static func betaFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
    let tiny = 1e-300
    var c = 1.0
    var d = 1 - (a + b) * x / (a + 1)
    if abs(d) < tiny { d = tiny }
    d = 1 / d
    var f = d
    var m = 0.0
    while m < 100_000 {
      m += 1
      let even = m * (b - m) * x / ((a + 2 * m - 1) * (a + 2 * m))
      d = 1 + even * d
      if abs(d) < tiny { d = tiny }
      c = 1 + even / c
      if abs(c) < tiny { c = tiny }
      d = 1 / d
      f *= d * c
      let odd = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 2 * m + 1))
      d = 1 + odd * d
      if abs(d) < tiny { d = tiny }
      c = 1 + odd / c
      if abs(c) < tiny { c = tiny }
      d = 1 / d
      let delta = d * c
      f *= delta
      if abs(delta - 1) < 1e-16 { break }
    }
    return f
  }

  // MARK: Inverses

  /// The x with P(a, x) = p, by bisection on ln x; good to about 13 digits.
  static func inverseGamma(_ a: Double, _ p: Double) -> Double {
    guard a > 0, p > 0, p < 1 else { return .nan }
    var low = -700.0
    var high = log(max(a, 1) + 40 * (max(a, 1)).squareRoot() + 100)
    // P is increasing: widen the top until it is above p.
    while gamma(a, exp(high)).p < p, high < 700 { high += 1 }
    for _ in 0..<200 {
      let middle = (low + high) / 2
      if gamma(a, exp(middle)).p < p { low = middle } else { high = middle }
    }
    return exp((low + high) / 2)
  }

  /// The x with I_x(a, b) = p, by bisection on the logit of x; good to about 13 digits.
  static func inverseBeta(_ p: Double, _ a: Double, _ b: Double) -> Double {
    guard a > 0, b > 0, p > 0, p < 1 else { return .nan }
    var low = -700.0
    var high = 700.0
    for _ in 0..<200 {
      let u = (low + high) / 2
      // x = 1/(1 + e^−u), and 1 − x = 1/(1 + e^u)
      let x = 1 / (1 + exp(-u))
      let y = 1 / (1 + exp(u))
      if beta(x, y, a, b).lower < p { low = u } else { high = u }
    }
    return 1 / (1 + exp(-(low + high) / 2))
  }
}
