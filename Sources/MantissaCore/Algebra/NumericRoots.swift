import Foundation

/// The complex roots of a polynomial with rational coefficients, as decimals: found in `Double` by the Aberth–Ehrlich
/// method, which finds all of them at once, then refined by Newton's method in extended precision.
enum NumericRoots {
  private struct Complex {
    var re: Double
    var im: Double

    static func + (a: Complex, b: Complex) -> Complex { Complex(re: a.re + b.re, im: a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(re: a.re - b.re, im: a.im - b.im) }
    static func * (a: Complex, b: Complex) -> Complex {
      Complex(re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re)
    }
    static func / (a: Complex, b: Complex) -> Complex {
      let norm = b.re * b.re + b.im * b.im
      return Complex(re: (a.re * b.re + a.im * b.im) / norm, im: (a.im * b.re - a.re * b.im) / norm)
    }
    var magnitude: Double { hypot(re, im) }
  }

  /// The roots of `polynomial` (which should have no repeated roots), each to `precision` significant digits, or `nil`
  /// when the polynomial is too large or too badly scaled for this method. A root whose imaginary part is only rounding
  /// error is returned as real.
  static func roots(of polynomial: RationalPolynomial, precision: Int = 50) -> [ComplexDecimal]? {
    let degree = polynomial.degree
    guard degree >= 1, degree <= 40 else { return nil }
    let coefficients = polynomial.coefficients.map { BigDecimal($0, precision: 30).doubleValue }
    guard coefficients.allSatisfy({ $0.isFinite && abs($0) < 1e100 }) else { return nil }

    guard var guesses = aberth(coefficients) else { return nil }
    var roots: [ComplexDecimal] = []
    let working = precision + 15
    let exact = polynomial.coefficients.map { BigDecimal($0, precision: working) }
    for index in guesses.indices {
      guard let start = ComplexDecimal(guesses[index].re, guesses[index].im) else { return nil }
      roots.append(start)
    }
    // Newton's method doubles the number of correct digits at each step, from about 15.
    var steps = 0
    var digits = 12
    while digits < working {
      digits *= 2
      steps += 1
    }
    for index in roots.indices {
      var z = roots[index]
      for _ in 0..<(steps + 2) {
        guard let next = newton(exact, z, precision: working) else { break }
        z = next
      }
      roots[index] = z
    }
    guesses.removeAll()

    return roots.map { root in
      var cleaned = root
      // A real root of a real polynomial has an imaginary part that is only noise.
      if let imaginary = cleaned.imaginary.decimalOrder {
        let size = cleaned.real.decimalOrder ?? imaginary
        if imaginary < max(size, 0) - precision + 5 || imaginary < -(precision - 5) {
          cleaned.imaginary = BigDecimal(0)
        }
      }
      return cleaned.rounded(toSignificantDigits: precision)
    }
  }

  /// One step of Newton's method for the polynomial given by `coefficients` (lowest power first).
  private static func newton(_ coefficients: [BigDecimal], _ z: ComplexDecimal, precision p: Int) -> ComplexDecimal? {
    var value = ComplexDecimal(real: BigDecimal(0))
    var slope = ComplexDecimal(real: BigDecimal(0))
    for coefficient in coefficients.reversed() {
      slope = slope.multiplied(by: z, precision: p).adding(value, precision: p)
      value = value.multiplied(by: z, precision: p).adding(ComplexDecimal(real: coefficient), precision: p)
    }
    if value.isZero { return z }
    guard let step = try? value.divided(by: slope, precision: p) else { return nil }
    return z.adding(-step, precision: p)
  }

  /// Aberth–Ehrlich iteration in `Double`.
  private static func aberth(_ coefficients: [Double]) -> [Complex]? {
    let n = coefficients.count - 1
    // Start on a circle of the size of the roots' geometric mean, at angles that no symmetry of the polynomial shares.
    let radius = pow(abs(coefficients[0] / coefficients[n]), 1 / Double(n))
    let scale = radius.isFinite && radius > 0 ? radius : 1
    var z = (0..<n).map { k -> Complex in
      let angle = 2 * Double.pi * Double(k) / Double(n) + 0.4
      return Complex(re: scale * cos(angle), im: scale * sin(angle))
    }

    for _ in 0..<500 {
      var largest = 0.0
      for k in 0..<n {
        var value = Complex(re: 0, im: 0)
        var slope = Complex(re: 0, im: 0)
        for coefficient in coefficients.reversed() {
          slope = slope * z[k] + value
          value = value * z[k] + Complex(re: coefficient, im: 0)
        }
        if value.magnitude == 0 { continue }
        let ratio = value / slope
        var sum = Complex(re: 0, im: 0)
        for j in 0..<n where j != k {
          let difference = z[k] - z[j]
          if difference.magnitude == 0 { continue }
          sum = sum + Complex(re: 1, im: 0) / difference
        }
        let denominator = Complex(re: 1, im: 0) - ratio * sum
        let correction = ratio / denominator
        guard correction.re.isFinite, correction.im.isFinite else { return nil }
        z[k] = z[k] - correction
        largest = max(largest, correction.magnitude / max(z[k].magnitude, 1e-300))
      }
      if largest < 1e-15 { return z }
    }
    return z
  }
}

extension ComplexDecimal {
  /// A complex decimal from two doubles, or `nil` for an infinity or NaN.
  fileprivate init?(_ re: Double, _ im: Double) {
    guard let real = BigDecimal("\(re)"), let imaginary = BigDecimal("\(im)") else { return nil }
    self.init(real: real, imaginary: imaginary)
  }
}
