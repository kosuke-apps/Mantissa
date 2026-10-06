// Constants and elementary functions on BigDecimal.
//
// Every function takes `precision`, a number of significant digits, and returns the correctly rounded result in
// all but vanishingly rare cases (the working precision is `precision` plus guard digits, so a misrounding needs the
// true value to lie within about 10^-15 of a half-way point). Cancellation is handled by raising the working
// precision where the answer is small compared with the intermediate values: near multiples of π/2 for the
// trigonometric functions, near 1 for ln and near 0 for the hyperbolic functions.

/// Digits carried beyond the requested precision while computing.
private let guardDigits = 15

extension BigDecimal {
  private static let eightTenths = BigDecimal(BigInt(8), exponent: -1)
  private static let sixteenTenths = BigDecimal(BigInt(16), exponent: -1)

  /// True when x² is so small that `f(x) = x (1 + c x² + …)` with |c| ≤ 1/2 equals x to `precision` digits.
  private func isNegligibleSquare(precision: Int) -> Bool {
    guard let order = decimalOrder else { return true }
    return 2 * order <= -(precision + 2)
  }

  // MARK: Constants

  /// π.
  public static func pi(precision: Int = defaultPrecision) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let fixed = FixedPoint(digits: precision + guardDigits)
    return fixed.decimal(fixed.pi).rounded(toSignificantDigits: precision)
  }

  /// Euler's number, the base of natural logarithms.
  public static func e(precision: Int = defaultPrecision) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let fixed = FixedPoint(digits: precision + guardDigits)
    return fixed.decimal(fixed.exponential(fixed.one)).rounded(toSignificantDigits: precision)
  }

  // MARK: Exponential and logarithm

  /// e^self. The argument must be below 10^9 in magnitude.
  public func exp(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    guard let order = decimalOrder else { return BigDecimal(1) }
    guard order <= 9 else { throw .overflow }

    // e^x = 10^k × e^r with r in [0, ln 10), and e^r converges fast. The error in ln 10 is multiplied by k, so carry
    // as many extra digits as k has.
    let fixed = FixedPoint(digits: precision + guardDigits + max(order, 0))
    let ln10 = fixed.ln10
    let x = fixed.scaled(self)
    let decades = x.floorDivided(by: ln10)
    let value = fixed.exponential(x - decades * ln10)
    guard let decadeCount = decades.asInt else { throw .overflow }
    return BigDecimal(value, exponent: decadeCount - fixed.digits).rounded(toSignificantDigits: precision)
  }

  /// The natural logarithm. The value must be positive.
  public func ln(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    guard signum > 0, let order = decimalOrder else { throw .domain }
    if self == BigDecimal(1) { return BigDecimal(0) }

    // self = 10^decades × y × 2^-doublings with y in [0.8, 1.6). Numbers in [0.1, 10) skip the power of ten so that
    // values near 1 are not computed as a difference of two nearly equal terms.
    let decades = (order == 0 || order == 1) ? 0 : order - 1
    var y = BigDecimal(significand, exponent: exponent - decades)
    var doublings = 0
    while y >= Self.sixteenTenths {
      y = y.halved
      doublings -= 1
    }
    while y < Self.eightTenths {
      y = y.doubled
      doublings += 1
    }

    // For x close to 1 the answer is small, so the working precision must grow by the number of leading zeros.
    var extra = 0
    if doublings == 0 && decades == 0 {
      let deviation = y - BigDecimal(1)
      guard let deviationOrder = deviation.decimalOrder else { return BigDecimal(0) }
      // ln(1 + d) = d (1 − d/2 + …), so a tiny d is its own logarithm.
      if -deviationOrder > precision + 5 { return deviation.rounded(toSignificantDigits: precision) }
      extra = max(0, -deviationOrder)
    }

    // ln y = 2 atanh((y − 1) / (y + 1)), and |(y − 1) / (y + 1)| < 0.23 on [0.8, 1.6).
    let fixed = FixedPoint(digits: precision + guardDigits + extra)
    let z = fixed.scaled(y)
    var result = BigInt(2) * fixed.arctanh(fixed.divide(z - fixed.one, z + fixed.one))
    if doublings != 0 { result -= BigInt(doublings) * fixed.ln2 }
    if decades != 0 { result += BigInt(decades) * fixed.ln10 }
    return fixed.decimal(result).rounded(toSignificantDigits: precision)
  }

  /// The logarithm to `base`. Both must be positive and the base must not be 1.
  public func log(base: BigDecimal, precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    let working = precision + guardDigits
    let numerator = try ln(precision: working)
    let denominator = try base.ln(precision: working)
    if denominator.isZero { throw .domain }
    return try numerator.divided(by: denominator, precision: precision)
  }

  /// The base-10 logarithm.
  public func log10(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    try log(base: BigDecimal(10), precision: precision)
  }

  /// `self` to a real power. A negative base is a domain error here (the layers above handle odd roots and complex
  /// results); a whole-number power is computed exactly by repeated multiplication.
  public func power(
    _ exponent: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  ) throws(MathError)
    -> BigDecimal
  {
    if let whole = exponent.asInt { return try power(whole, precision: precision) }
    if isZero {
      if exponent.isNegative { throw .divisionByZero }
      return self
    }
    if isNegative { throw .domain }

    // x^y = e^(y ln x). An error ε in the logarithm becomes y ε in the exponent, so add the digits of the product.
    let rough = try ln(precision: 20)
    let productOrder = max((exponent * rough).decimalOrder ?? 0, 0)
    let product = try exponent * ln(precision: precision + guardDigits + productOrder)
    return try product.exp(precision: precision)
  }

  // MARK: Trigonometry (angles in radians)

  public func sin(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    try sineAndCosine(precision: precision).sine
  }

  public func cos(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    try sineAndCosine(precision: precision).cosine
  }

  /// The tangent. Near its poles the result is large but finite, because no decimal is exactly π/2 + kπ.
  public func tan(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    let working = precision + guardDigits
    let (sine, cosine) = try sineAndCosine(precision: working)
    return try sine.divided(by: cosine, precision: precision)
  }

  /// Sine and cosine together, from one reduction modulo π/2.
  private func sineAndCosine(precision: Int) throws(MathError) -> (sine: BigDecimal, cosine: BigDecimal) {
    precondition(precision >= 1, "Precision must be at least 1")
    guard let order = decimalOrder else { return (self, BigDecimal(1)) }
    if isNegligibleSquare(precision: precision) { return (rounded(toSignificantDigits: precision), BigDecimal(1)) }
    guard order <= 1000 else { throw .overflow }

    // x = n π/2 + r with |r| <= π/4. The reduction subtracts n π/2, so π needs as many extra digits as n has, and
    // r itself must keep `precision + 10` significant digits even when x is very close to a multiple of π/2.
    let integerDigits = max(order, 0)
    let needed = precision + 10 + integerDigits
    var extra = 0
    while true {
      let fixed = FixedPoint(digits: precision + guardDigits + integerDigits + extra)
      let halfPi = fixed.pi / BigInt(2)
      let x = fixed.scaled(self)
      let quarterTurns = (x + halfPi / BigInt(2)).floorDivided(by: halfPi)
      let r = x - quarterTurns * halfPi
      let significant = r.isZero ? 0 : r.magnitude.decimalDigitCount
      if significant < needed {
        extra += needed - significant + 1
        continue
      }

      let sine = fixed.sine(r)
      let cosine = fixed.cosine(r)
      var turn = (quarterTurns % BigInt(4)).asInt ?? 0
      if turn < 0 { turn += 4 }
      let (sinValue, cosValue): (BigInt, BigInt) =
        switch turn {
        case 0: (sine, cosine)
        case 1: (cosine, -sine)
        case 2: (-sine, -cosine)
        default: (-cosine, sine)
        }
      return (
        fixed.decimal(sinValue).rounded(toSignificantDigits: precision),
        fixed.decimal(cosValue).rounded(toSignificantDigits: precision)
      )
    }
  }

  // MARK: Inverse trigonometry (results in radians)

  /// The arctangent, in (−π/2, π/2).
  public func arctangent(precision: Int = BigDecimal.defaultPrecision) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    guard let order = decimalOrder else { return self }
    if isNegligibleSquare(precision: precision) { return rounded(toSignificantDigits: precision) }

    // atan(a) = π/2 − atan(1/a) brings a into [0, 1]; atan(t) = 2 atan(t / (1 + √(1 + t²))) then shrinks it to
    // about 0.05, where the Taylor series gains two digits per term.
    let fixed = FixedPoint(digits: precision + guardDigits + max(0, -order))
    let invert = magnitude > BigDecimal(1)
    let a = fixed.scaled(magnitude)
    var t = invert ? fixed.divide(fixed.one, a) : a
    let halvings = 4
    for _ in 0..<halvings {
      let root = fixed.squareRoot(fixed.one + fixed.multiply(t, t))
      t = fixed.divide(t, fixed.one + root)
    }
    var result = fixed.arctan(t) * BigInt(1 << halvings)
    if invert { result = fixed.pi / BigInt(2) - result }
    return fixed.decimal(isNegative ? -result : result).rounded(toSignificantDigits: precision)
  }

  /// The arcsine, in [−π/2, π/2]. The value must lie in [−1, 1].
  public func arcsine(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let one = BigDecimal(1)
    if magnitude > one { throw .domain }
    if isNegligibleSquare(precision: precision) { return rounded(toSignificantDigits: precision) }
    if magnitude == one {
      let halfPi = BigDecimal.pi(precision: precision + 2).halved.rounded(toSignificantDigits: precision)
      return isNegative ? -halfPi : halfPi
    }
    // asin(x) = atan(x / √(1 − x²)); 1 − x² is exact, so there is no cancellation near ±1.
    let working = precision + guardDigits
    let root = try (one - self * self).squareRoot(precision: working)
    return try divided(by: root, precision: working).arctangent(precision: precision)
  }

  /// The arccosine, in [0, π]. The value must lie in [−1, 1].
  public func arccosine(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let one = BigDecimal(1)
    if magnitude > one { throw .domain }
    // Zero, and arguments below about 10^-(precision + 5), leave the rounded π/2 unchanged.
    if decimalOrder.map({ -$0 > precision + 5 }) ?? true {
      return BigDecimal.pi(precision: precision + 2).halved.rounded(toSignificantDigits: precision)
    }
    if self == one { return BigDecimal(0) }
    if self == -one { return BigDecimal.pi(precision: precision) }

    // acos(x) = atan(√(1 − x²) / x) for x > 0, which stays accurate when the result is small (x near 1), and
    // acos(−x) = π − acos(x).
    let working = precision + guardDigits
    let root = try (one - self * self).squareRoot(precision: working)
    let positive = try root.divided(by: magnitude, precision: working).arctangent(precision: working)
    if !isNegative { return positive.rounded(toSignificantDigits: precision) }
    return (BigDecimal.pi(precision: working) - positive).rounded(toSignificantDigits: precision)
  }

  // MARK: Hyperbolic functions

  public func sinh(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    guard let order = decimalOrder else { return self }
    if isNegligibleSquare(precision: precision) { return rounded(toSignificantDigits: precision) }
    let (up, down) = try hyperbolicParts(working: precision + guardDigits + max(0, -order))
    let half = down.map { (up - $0).halved } ?? up.halved
    return (isNegative ? -half : half).rounded(toSignificantDigits: precision)
  }

  public func cosh(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    guard decimalOrder != nil else { return BigDecimal(1) }
    let (up, down) = try hyperbolicParts(working: precision + guardDigits)
    return (down.map { (up + $0).halved } ?? up.halved).rounded(toSignificantDigits: precision)
  }

  public func tanh(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    guard let order = decimalOrder else { return self }
    if isNegligibleSquare(precision: precision) { return rounded(toSignificantDigits: precision) }
    let working = precision + guardDigits + max(0, -order)
    // 1 − tanh|x| is about 2 e^(−2|x|), which is below the last digit once |x| exceeds 1.16 × (working + 5).
    if magnitude.doubleValue > 1.16 * Double(working + 5) { return BigDecimal(isNegative ? -1 : 1) }
    let (up, down) = try hyperbolicParts(working: working)
    guard let down else { return BigDecimal(isNegative ? -1 : 1) }
    let ratio = try (up - down).divided(by: up + down, precision: precision)
    return isNegative ? -ratio : ratio
  }

  /// e^|x| and e^−|x|, with the second `nil` when it is too small to affect a sum with the first at `working`
  /// digits (which also keeps the exact addition of the two within a few hundred digits of each other).
  private func hyperbolicParts(working: Int) throws(MathError) -> (up: BigDecimal, down: BigDecimal?) {
    let up = try magnitude.exp(precision: working)
    if magnitude.doubleValue > 2.31 * Double(working + 5) { return (up, nil) }
    return (up, try BigDecimal(1).divided(by: up, precision: working))
  }

  /// The inverse hyperbolic sine.
  public func asinh(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    guard let order = decimalOrder else { return self }
    if isNegligibleSquare(precision: precision) { return rounded(toSignificantDigits: precision) }
    let working = precision + guardDigits + max(0, -order)
    let value: BigDecimal
    if order > working + 5 {
      value = try magnitude.doubled.ln(precision: working)  // asinh(a) = ln(2a) + O(1/a²)
    } else {
      let root = try (magnitude * magnitude + BigDecimal(1)).squareRoot(precision: working)
      value = try (magnitude + root).ln(precision: working)
    }
    return (isNegative ? -value : value).rounded(toSignificantDigits: precision)
  }

  /// The inverse hyperbolic cosine. The value must be at least 1.
  public func acosh(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let one = BigDecimal(1)
    if self < one { throw .domain }
    if self == one { return BigDecimal(0) }
    let deviation = self - one
    let deviationOrder = deviation.decimalOrder ?? 0
    // acosh(1 + d) = √(2d) (1 − d/12 + …).
    if -deviationOrder > precision + 5 { return try deviation.doubled.squareRoot(precision: precision) }

    let working = precision + guardDigits + max(0, -deviationOrder)
    if let order = decimalOrder, order > working + 5 { return try doubled.ln(precision: precision) }
    let root = try (self * self - one).squareRoot(precision: working)
    return try (self + root).ln(precision: precision)
  }

  /// The inverse hyperbolic tangent. The value must lie strictly between −1 and 1.
  public func atanh(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    let one = BigDecimal(1)
    if magnitude >= one { throw .domain }
    guard let order = decimalOrder else { return self }
    if isNegligibleSquare(precision: precision) { return rounded(toSignificantDigits: precision) }
    let working = precision + guardDigits + max(0, -order)
    let ratio = try (one + self).divided(by: one - self, precision: working)
    return try ratio.ln(precision: working).halved.rounded(toSignificantDigits: precision)
  }
}
