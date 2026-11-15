// The gamma function and the regularised incomplete gamma and beta functions, to any number of digits (`docs/statistics.md`).
//
// ln Γ(z) is Stirling's series, reached by moving the argument up until the series is as accurate as is asked (the Bernoulli
// numbers in it are exact). The incomplete functions are their series and continued fractions, each used on the side where it
// converges quickly and keeps its digits; the smaller of a function and its complement is always the one that is computed, so that a
// tail keeps all its digits. The inverses are Newton's method from a start found with machine numbers.

import Foundation

/// The even Bernoulli numbers B₂, B₄, …, exactly, for the Stirling series.
enum Bernoulli {
  /// The number of them: enough for Stirling's series to reach about 100 digits.
  static let count = 64

  static let even: [Rational] = {
    let last = 2 * count
    var numbers = [Rational](repeating: Rational(0), count: last + 1)
    numbers[0] = Rational(1)
    for m in 1...last {
      // B_m = −(1/(m + 1)) Σ_{k<m} C(m + 1, k) B_k; the odd ones other than B₁ are zero.
      var sum = Rational(0)
      for k in 0..<m where !numbers[k].isZero {
        guard let choose = NumberTheory.combinations(m + 1, k) else { continue }
        sum += Rational(choose) * numbers[k]
      }
      numbers[m] = -sum / Rational(m + 1)
    }
    return (1...count).map { numbers[2 * $0] }
  }()
}

extension BigDecimal {
  /// Beyond this size the gamma function is not worked out.
  private static let gammaLimit = BigDecimal(100_000)

  private static func order(of value: BigDecimal) -> Int { max(0, value.decimalOrder ?? 0) }

  // MARK: Gamma

  /// ln Γ(x) for x > 0.
  public func lgamma(precision p: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(p >= 1, "Precision must be at least 1")
    guard signum > 0 else { throw .domain }
    guard self <= Self.gammaLimit else { throw .overflow }
    let w = p + 25 + 2 * Self.order(of: self)
    let tolerance = BigDecimal(BigInt(1), exponent: -(w + 2))
    let threshold = BigDecimal(w / 2 + 12)
    var z = rounded(toSignificantDigits: w)
    var product = BigDecimal(1)
    while z < threshold {
      product = (product * z).rounded(toSignificantDigits: w)
      z = z + BigDecimal(1)
    }
    let half = BigDecimal(BigInt(5), exponent: -1)
    var result = (z - half) * (try z.ln(precision: w)) - z
    result = result + (try (BigDecimal(2) * BigDecimal.pi(precision: w)).ln(precision: w)) * half
    // Σ B₂ₖ / (2k(2k − 1) z^(2k−1)), which converges to the error of Stirling's formula until its terms start to grow.
    let squared = (z * z).rounded(toSignificantDigits: w)
    var power = z
    var previous: BigDecimal?
    for k in 1...Bernoulli.count {
      let coefficient = Bernoulli.even[k - 1] / Rational(2 * k * (2 * k - 1))
      let term = try BigDecimal(coefficient, precision: w).divided(by: power, precision: w)
      // The series has begun to diverge: there are not enough digits to be had.
      if let previous, term.magnitude > previous { throw .overflow }
      result = result + term
      if term.magnitude < tolerance { break }
      previous = term.magnitude
      power = (power * squared).rounded(toSignificantDigits: w)
    }
    return (result - (try product.ln(precision: w))).rounded(toSignificantDigits: p)
  }

  /// Γ(x), for every x that is not a whole number at or below zero.
  public func gamma(precision p: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(p >= 1, "Precision must be at least 1")
    if signum > 0 {
      guard self <= Self.gammaLimit else { throw .overflow }
      // ln Γ is as large as x ln x: carry the digits that it has before the point.
      let rough = SpecialDouble.logGamma(doubleValue)
      let extra = rough.isFinite ? max(0, Int(Foundation.log10(max(abs(rough), 1)))) : 6
      return try (try lgamma(precision: p + 10 + extra)).exp(precision: p)
    }
    guard !isInteger else { throw .domain }  // poles at 0, −1, −2, …
    // Γ(x) = π / (sin(πx) Γ(1 − x))
    let w = p + 25
    let one = BigDecimal(1)
    let pi = BigDecimal.pi(precision: w)
    let sine = try (pi * self).sin(precision: w)
    let reflected = try (one - self).gamma(precision: w)
    return try pi.divided(by: sine * reflected, precision: w).rounded(toSignificantDigits: p)
  }

  // MARK: Incomplete gamma

  /// The regularised lower incomplete gamma function P(a, x) = γ(a, x)/Γ(a), for a > 0 and x ≥ 0.
  public static func gammaP(
    _ a: BigDecimal, _ x: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  ) throws(MathError)
    -> BigDecimal
  {
    try incompleteGamma(a, x, precision: precision).lower
  }

  /// The regularised upper incomplete gamma function Q(a, x) = 1 − P(a, x), with all its digits where it is small.
  public static func gammaQ(
    _ a: BigDecimal, _ x: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  ) throws(MathError)
    -> BigDecimal
  {
    try incompleteGamma(a, x, precision: precision).upper
  }

  private static func incompleteGamma(
    _ a: BigDecimal, _ x: BigDecimal, precision p: Int, logGammaA: BigDecimal? = nil
  ) throws(MathError) -> (lower: BigDecimal, upper: BigDecimal) {
    precondition(p >= 1, "Precision must be at least 1")
    guard a.signum > 0, !x.isNegative else { throw .domain }
    if x.isZero { return (BigDecimal(0), BigDecimal(1)) }
    guard a <= gammaLimit, x <= gammaLimit else { throw .overflow }
    let w = p + 25 + 2 * max(order(of: a), order(of: x))
    let tolerance = BigDecimal(BigInt(1), exponent: -(w + 2))
    let one = BigDecimal(1)
    // x^a e^−x / Γ(a)
    let logGammaOfA: BigDecimal
    if let logGammaA { logGammaOfA = logGammaA } else { logGammaOfA = try a.lgamma(precision: w) }
    let logFactor = try a * x.ln(precision: w) - x - logGammaOfA
    let factor = try logFactor.exp(precision: w)

    // The series is much the cheaper of the two, and as good for P at any x; for Q it loses the digits that Q is below 1, so the
    // continued fraction is kept for where Q is small.
    let upperIsSmall = SpecialDouble.gamma(a.doubleValue, x.doubleValue).q < 1e-10
    if x < a + one || !upperIsSmall {
      // P = factor · Σ xⁿ / (a(a + 1)…(a + n)).
      var term = try one.divided(by: a, precision: w)
      var sum = term
      var n = 0
      while term.magnitude > sum.magnitude * tolerance {
        n += 1
        term = try (term * x).divided(by: a + BigDecimal(n), precision: w)
        sum = sum + term
        guard n < 1_000_000 else { throw .overflow }
      }
      let lower = (factor * sum).rounded(toSignificantDigits: w)
      return (lower.rounded(toSignificantDigits: p), (one - lower).rounded(toSignificantDigits: p))
    }
    // Q = factor / (x + 1 − a − 1(1 − a)/(x + 3 − a − 2(2 − a)/(x + 5 − a − …))), by Lentz's method.
    var f = x + one - a
    var c = f
    var d = BigDecimal(0)
    var n = 0
    while true {
      n += 1
      let numerator = -BigDecimal(n) * (BigDecimal(n) - a)
      let denominator = x + BigDecimal(2 * n + 1) - a
      d = denominator + numerator * d
      c = denominator + (try numerator.divided(by: c, precision: w))
      d = try one.divided(by: d, precision: w)
      let delta = (c * d).rounded(toSignificantDigits: w)
      f = (f * delta).rounded(toSignificantDigits: w)
      if (delta - one).magnitude < tolerance { break }
      guard n < 1_000_000 else { throw .overflow }
    }
    let upper = try factor.divided(by: f, precision: w)
    return ((one - upper).rounded(toSignificantDigits: p), upper.rounded(toSignificantDigits: p))
  }

  /// ln B(a, b) = ln Γ(a) + ln Γ(b) − ln Γ(a + b).
  private static func logBetaFunction(
    _ a: BigDecimal, _ b: BigDecimal, precision w: Int
  ) throws(MathError) -> BigDecimal {
    try a.lgamma(precision: w) + b.lgamma(precision: w) - (a + b).lgamma(precision: w)
  }

  // MARK: Incomplete beta

  /// The regularised incomplete beta function I_x(a, b), for a, b > 0 and 0 ≤ x ≤ 1.
  public static func betaI(
    _ x: BigDecimal, _ a: BigDecimal, _ b: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  )
    throws(MathError) -> BigDecimal
  { try incompleteBeta(x, a, b, precision: precision).lower }

  /// The complement 1 − I_x(a, b), with all its digits where it is small.
  public static func betaIComplement(
    _ x: BigDecimal, _ a: BigDecimal, _ b: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  ) throws(MathError) -> BigDecimal { try incompleteBeta(x, a, b, precision: precision).upper }

  private static func incompleteBeta(
    _ x: BigDecimal, _ a: BigDecimal, _ b: BigDecimal, precision p: Int, logBeta: BigDecimal? = nil
  ) throws(MathError) -> (lower: BigDecimal, upper: BigDecimal) {
    precondition(p >= 1, "Precision must be at least 1")
    let one = BigDecimal(1)
    guard a.signum > 0, b.signum > 0, !x.isNegative, x <= one else { throw .domain }
    if x.isZero { return (BigDecimal(0), one) }
    if x == one { return (one, BigDecimal(0)) }
    guard a <= gammaLimit, b <= gammaLimit else { throw .overflow }
    let w = p + 25 + 2 * max(order(of: a), order(of: b))
    // x^a (1 − x)^b / B(a, b)
    let logBetaOfAB: BigDecimal
    if let logBeta { logBetaOfAB = logBeta } else { logBetaOfAB = try logBetaFunction(a, b, precision: w) }
    let logFront = try a * x.ln(precision: w) + b * (one - x).ln(precision: w) - logBetaOfAB
    let front = try logFront.exp(precision: w)
    let switchPoint = try (a + one).divided(by: a + b + BigDecimal(2), precision: 20)
    if x < switchPoint {
      let lower = try front.divided(by: a, precision: w) * (try betaFraction(x, a, b, working: w))
      return (lower.rounded(toSignificantDigits: p), (one - lower).rounded(toSignificantDigits: p))
    }
    let upper = try front.divided(by: b, precision: w) * (try betaFraction(one - x, b, a, working: w))
    return ((one - upper).rounded(toSignificantDigits: p), upper.rounded(toSignificantDigits: p))
  }

  /// 1/(1 + d₁/(1 + d₂/(1 + …))) with d₂ₘ₊₁ = −(a + m)(a + b + m)x / ((a + 2m)(a + 2m + 1)) and
  /// d₂ₘ = m(b − m)x / ((a + 2m − 1)(a + 2m)), by Lentz's method.
  private static func betaFraction(
    _ x: BigDecimal, _ a: BigDecimal, _ b: BigDecimal, working w: Int
  ) throws(MathError)
    -> BigDecimal
  {
    let one = BigDecimal(1)
    let two = BigDecimal(2)
    let tolerance = BigDecimal(BigInt(1), exponent: -(w + 2))
    var c = one
    var d = try one.divided(by: one - ((a + b) * x).divided(by: a + one, precision: w), precision: w)
    var f = d
    var m = 0
    while true {
      m += 1
      let bigM = BigDecimal(m)
      let even = try (bigM * (b - bigM) * x).divided(by: (a + two * bigM - one) * (a + two * bigM), precision: w)
      d = try one.divided(by: one + even * d, precision: w)
      c = one + (try even.divided(by: c, precision: w))
      f = (f * d * c).rounded(toSignificantDigits: w)
      let odd = try (-(a + bigM) * (a + b + bigM) * x).divided(
        by: (a + two * bigM) * (a + two * bigM + one), precision: w)
      d = try one.divided(by: one + odd * d, precision: w)
      c = one + (try odd.divided(by: c, precision: w))
      let delta = (c * d).rounded(toSignificantDigits: w)
      f = (f * delta).rounded(toSignificantDigits: w)
      if (delta - one).magnitude < tolerance { break }
      guard m < 1_000_000 else { throw .overflow }
    }
    return f
  }

  // MARK: Inverses

  /// The working digits of Newton's iterations: the start is good to about 12 digits, and each step doubles them, so the early
  /// steps are made with few digits.
  private static func schedule(_ full: Int) -> [Int] {
    var steps: [Int] = []
    var digits = 14
    while digits < full {
      digits = min(2 * digits + 4, full)
      steps.append(digits + 8)
    }
    return steps.map { min($0, full) } + [full]
  }

  /// The x with P(a, x) = p, for 0 < p < 1.
  public static func inverseGammaP(
    _ a: BigDecimal, _ p: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  )
    throws(MathError) -> BigDecimal
  {
    let one = BigDecimal(1)
    guard a.signum > 0, p.signum > 0, p < one else { throw .domain }
    let w = precision + 25 + 2 * order(of: a)
    var x = BigDecimal("\(SpecialDouble.inverseGamma(a.doubleValue, p.doubleValue))") ?? one
    if x.signum <= 0 { x = BigDecimal(BigInt(1), exponent: -300) }
    // Work on the tail that is smaller, so that its digits are all kept.
    let useUpper = p > BigDecimal(BigInt(5), exponent: -1)
    let target = useUpper ? one - p : p
    let tolerance = BigDecimal(BigInt(1), exponent: -(precision + 4))
    let logGammaA = try a.lgamma(precision: w)
    for digits in schedule(w) + [w] {
      let (lower, upper) = try incompleteGamma(a, x, precision: digits, logGammaA: logGammaA)
      let residual = (useUpper ? upper : lower) - target
      // The density x^(a−1) e^−x / Γ(a), and the sign of the slope of what is being solved.
      let logDensity = try (a - one) * x.ln(precision: digits) - x - logGammaA
      let density = try logDensity.exp(precision: digits)
      var step = try residual.divided(by: density, precision: digits)
      if useUpper { step = -step }
      var next = x - step
      // A step past zero is halved towards it instead.
      while next.signum <= 0 {
        step = try step.divided(by: BigDecimal(2), precision: digits)
        next = x - step
      }
      x = next.rounded(toSignificantDigits: digits)
      if digits == w, step.magnitude <= x.magnitude * tolerance { break }
    }
    return x.rounded(toSignificantDigits: precision)
  }

  /// The x with I_x(a, b) = p, for 0 < p < 1.
  public static func inverseBetaI(
    _ p: BigDecimal, _ a: BigDecimal, _ b: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  ) throws(MathError) -> BigDecimal {
    let one = BigDecimal(1)
    guard a.signum > 0, b.signum > 0, p.signum > 0, p < one else { throw .domain }
    let w = precision + 25 + 2 * max(order(of: a), order(of: b))
    var x =
      BigDecimal("\(SpecialDouble.inverseBeta(p.doubleValue, a.doubleValue, b.doubleValue))")
      ?? BigDecimal(BigInt(5), exponent: -1)
    if x.signum <= 0 { x = BigDecimal(BigInt(1), exponent: -300) }
    if x >= one { x = one - BigDecimal(BigInt(1), exponent: -16) }
    let useUpper = p > BigDecimal(BigInt(5), exponent: -1)
    let target = useUpper ? one - p : p
    let tolerance = BigDecimal(BigInt(1), exponent: -(precision + 4))
    let logBeta = try logBetaFunction(a, b, precision: w)
    for digits in schedule(w) + [w] {
      let (lower, upper) = try incompleteBeta(x, a, b, precision: digits, logBeta: logBeta)
      let residual = (useUpper ? upper : lower) - target
      // The density x^(a−1) (1 − x)^(b−1) / B(a, b).
      let logDensity = try (a - one) * x.ln(precision: digits) + (b - one) * (one - x).ln(precision: digits) - logBeta
      let density = try logDensity.exp(precision: digits)
      var step = try residual.divided(by: density, precision: digits)
      if useUpper { step = -step }
      var next = x - step
      // A step out of (0, 1) is halved towards the end it went past.
      while next.signum <= 0 || next >= one {
        step = try step.divided(by: BigDecimal(2), precision: digits)
        next = x - step
      }
      x = next.rounded(toSignificantDigits: digits)
      if digits == w, step.magnitude <= x.magnitude * tolerance { break }
    }
    return x.rounded(toSignificantDigits: precision)
  }
}
