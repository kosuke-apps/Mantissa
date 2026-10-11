/// A complex number as two decimals, for the numerical value of an answer such as `0.5 + 0.866025…i`.
///
/// Every operation takes the number of significant digits to keep and rounds its components to it, the way `BigDecimal`
/// does. The functions are the principal values: `ln` has its imaginary part in (−π, π], and a power is `e^(w ln z)`.
public struct ComplexDecimal: Sendable, Hashable {
  public var real: BigDecimal
  public var imaginary: BigDecimal

  public init(real: BigDecimal, imaginary: BigDecimal = BigDecimal(0)) {
    self.real = real
    self.imaginary = imaginary
  }

  public var isReal: Bool { imaginary.isZero }
  public var isZero: Bool { real.isZero && imaginary.isZero }

  public func rounded(toSignificantDigits digits: Int) -> ComplexDecimal {
    ComplexDecimal(
      real: real.rounded(toSignificantDigits: digits), imaginary: imaginary.rounded(toSignificantDigits: digits))
  }

  // MARK: Arithmetic

  public static prefix func - (value: ComplexDecimal) -> ComplexDecimal {
    ComplexDecimal(real: -value.real, imaginary: -value.imaginary)
  }

  func adding(_ other: ComplexDecimal, precision p: Int) -> ComplexDecimal {
    ComplexDecimal(
      real: real.adding(other.real, precision: p), imaginary: imaginary.adding(other.imaginary, precision: p))
  }

  func multiplied(by other: ComplexDecimal, precision p: Int) -> ComplexDecimal {
    // (a + bi)(c + di) = (ac − bd) + (ad + bc)i, each product exact and rounded once.
    ComplexDecimal(
      real: (real * other.real - imaginary * other.imaginary).rounded(toSignificantDigits: p),
      imaginary: (real * other.imaginary + imaginary * other.real).rounded(toSignificantDigits: p))
  }

  func multiplied(by factor: BigDecimal, precision p: Int) -> ComplexDecimal {
    ComplexDecimal(
      real: (real * factor).rounded(toSignificantDigits: p),
      imaginary: (imaginary * factor).rounded(toSignificantDigits: p))
  }

  func divided(by other: ComplexDecimal, precision p: Int) throws(MathError) -> ComplexDecimal {
    let norm = other.real * other.real + other.imaginary * other.imaginary
    if norm.isZero { throw .divisionByZero }
    // (a + bi)/(c + di) = ((ac + bd) + (bc − ad)i)/(c² + d²).
    let top = ComplexDecimal(
      real: real * other.real + imaginary * other.imaginary, imaginary: imaginary * other.real - real * other.imaginary)
    return ComplexDecimal(
      real: try top.real.divided(by: norm, precision: p), imaginary: try top.imaginary.divided(by: norm, precision: p))
  }

  /// |z|² without rounding.
  var magnitudeSquared: BigDecimal { real * real + imaginary * imaginary }

  func magnitude(precision p: Int) throws(MathError) -> BigDecimal {
    if isReal { return real.magnitude }
    if real.isZero { return imaginary.magnitude }
    return try magnitudeSquared.squareRoot(precision: p)
  }

  /// The angle in (−π, π]. Zero has none.
  func argument(precision p: Int) throws(MathError) -> BigDecimal {
    if isZero { throw .domain }
    let working = p + 5
    if real.isZero {
      let quarter = try BigDecimal.pi(precision: working).divided(by: BigDecimal(2), precision: working)
      return imaginary.isNegative ? -quarter : quarter
    }
    let slope = try imaginary.divided(by: real, precision: working)
    let base = slope.arctangent(precision: working)
    if !real.isNegative { return base.rounded(toSignificantDigits: p) }
    let pi = BigDecimal.pi(precision: working)
    return (imaginary.isNegative ? base - pi : base + pi).rounded(toSignificantDigits: p)
  }

  /// A whole power by repeated squaring.
  func power(_ exponent: Int, precision p: Int) throws(MathError) -> ComplexDecimal {
    if exponent < 0 {
      let positive = try power(-exponent, precision: p + 5)
      return try ComplexDecimal(real: BigDecimal(1)).divided(by: positive, precision: p)
    }
    var result = ComplexDecimal(real: BigDecimal(1))
    var square = self
    var remaining = exponent
    while remaining > 0 {
      if remaining & 1 == 1 { result = result.multiplied(by: square, precision: p + 5) }
      remaining >>= 1
      if remaining > 0 { square = square.multiplied(by: square, precision: p + 5) }
    }
    return result.rounded(toSignificantDigits: p)
  }

  // MARK: Exponential, logarithm

  func exp(precision p: Int) throws(MathError) -> ComplexDecimal {
    let scale = try real.exp(precision: p + 5)
    if imaginary.isZero { return ComplexDecimal(real: scale.rounded(toSignificantDigits: p)) }
    let cosine = try imaginary.cos(precision: p + 5)
    let sine = try imaginary.sin(precision: p + 5)
    return ComplexDecimal(real: scale * cosine, imaginary: scale * sine).rounded(toSignificantDigits: p)
  }

  /// The principal logarithm.
  func ln(precision p: Int) throws(MathError) -> ComplexDecimal {
    if isZero { throw .domain }
    let working = p + 5
    let squared = isReal ? real * real : magnitudeSquared
    let half = try squared.ln(precision: working).divided(by: BigDecimal(2), precision: working)
    let angle = isReal && !real.isNegative ? BigDecimal(0) : try argument(precision: working)
    return ComplexDecimal(real: half, imaginary: angle).rounded(toSignificantDigits: p)
  }

  // MARK: Trigonometric and hyperbolic functions

  func sin(precision p: Int) throws(MathError) -> ComplexDecimal {
    // sin(a + bi) = sin a cosh b + i cos a sinh b
    let w = p + 5
    return ComplexDecimal(
      real: try real.sin(precision: w) * imaginary.cosh(precision: w),
      imaginary: try real.cos(precision: w) * imaginary.sinh(precision: w)
    ).rounded(toSignificantDigits: p)
  }

  func cos(precision p: Int) throws(MathError) -> ComplexDecimal {
    // cos(a + bi) = cos a cosh b − i sin a sinh b
    let w = p + 5
    return ComplexDecimal(
      real: try real.cos(precision: w) * imaginary.cosh(precision: w),
      imaginary: -(try real.sin(precision: w) * imaginary.sinh(precision: w))
    ).rounded(toSignificantDigits: p)
  }

  func sinh(precision p: Int) throws(MathError) -> ComplexDecimal {
    // sinh(a + bi) = sinh a cos b + i cosh a sin b
    let w = p + 5
    return ComplexDecimal(
      real: try real.sinh(precision: w) * imaginary.cos(precision: w),
      imaginary: try real.cosh(precision: w) * imaginary.sin(precision: w)
    ).rounded(toSignificantDigits: p)
  }

  func cosh(precision p: Int) throws(MathError) -> ComplexDecimal {
    // cosh(a + bi) = cosh a cos b + i sinh a sin b
    let w = p + 5
    return ComplexDecimal(
      real: try real.cosh(precision: w) * imaginary.cos(precision: w),
      imaginary: try real.sinh(precision: w) * imaginary.sin(precision: w)
    ).rounded(toSignificantDigits: p)
  }
}

extension ComplexDecimal: CustomStringConvertible {
  public var description: String {
    imaginary.isNegative ? "\(real) - \(imaginary.magnitude)i" : "\(real) + \(imaginary)i"
  }
}
