/// A polynomial with rational coefficients in one unknown, `coefficients[k]` multiplying `x^k`.
struct RationalPolynomial: Equatable {
  private(set) var coefficients: [Rational]

  /// The last coefficient is not zero; the zero polynomial has none.
  init(_ coefficients: [Rational]) {
    var trimmed = coefficients
    while trimmed.last?.isZero == true { trimmed.removeLast() }
    self.coefficients = trimmed
  }

  subscript(index: Int) -> Rational { index < coefficients.count ? coefficients[index] : Rational(0) }

  var degree: Int { coefficients.count - 1 }
  var isZero: Bool { coefficients.isEmpty }
  var leading: Rational { coefficients.last ?? Rational(0) }

  func evaluate(_ x: Rational) -> Rational {
    var result = Rational(0)
    for coefficient in coefficients.reversed() { result = result * x + coefficient }
    return result
  }

  var derivative: RationalPolynomial {
    guard coefficients.count > 1 else { return RationalPolynomial([]) }
    return RationalPolynomial((1..<coefficients.count).map { coefficients[$0] * Rational($0) })
  }

  /// `self / divisor` and the remainder, by long division.
  func quotientAndRemainder(
    dividingBy divisor: RationalPolynomial
  ) -> (quotient: RationalPolynomial, remainder: RationalPolynomial) {
    precondition(!divisor.isZero, "Division by the zero polynomial")
    var remainder = coefficients
    if degree < divisor.degree { return (RationalPolynomial([]), self) }
    var quotient = Array(repeating: Rational(0), count: degree - divisor.degree + 1)
    while remainder.count >= divisor.coefficients.count {
      let factor = remainder.last! / divisor.leading
      let shift = remainder.count - divisor.coefficients.count
      quotient[shift] = factor
      for (index, coefficient) in divisor.coefficients.enumerated() {
        remainder[index + shift] -= factor * coefficient
      }
      remainder.removeLast()
      while remainder.last?.isZero == true { remainder.removeLast() }
    }
    return (RationalPolynomial(quotient), RationalPolynomial(remainder))
  }

  /// The greatest common divisor, scaled to have leading coefficient 1.
  static func gcd(_ a: RationalPolynomial, _ b: RationalPolynomial) -> RationalPolynomial {
    var (x, y) = (a, b)
    while !y.isZero { (x, y) = (y, x.quotientAndRemainder(dividingBy: y).remainder) }
    guard !x.isZero else { return x }
    return RationalPolynomial(x.coefficients.map { $0 / x.leading })
  }

  /// The same roots, each once: `p / gcd(p, p′)`.
  var squarefree: RationalPolynomial {
    guard degree >= 2 else { return self }
    let common = RationalPolynomial.gcd(self, derivative)
    return common.degree >= 1 ? quotientAndRemainder(dividingBy: common).quotient : self
  }

  /// The quotient by `x − root`, for a root of the polynomial.
  func deflated(byRoot root: Rational) -> RationalPolynomial {
    guard degree >= 1 else { return self }
    var quotient = Array(repeating: Rational(0), count: degree)
    var carry = Rational(0)
    for index in stride(from: degree, to: 0, by: -1) {
      carry = coefficients[index] + carry * root
      quotient[index - 1] = carry
    }
    return RationalPolynomial(quotient)
  }

  /// Whole-number coefficients with no common factor, found by clearing denominators.
  var primitiveIntegerCoefficients: [BigInt] {
    var multiple = BigInt(1)
    for coefficient in coefficients {
      multiple = multiple / BigInt.gcd(multiple, coefficient.denominator) * coefficient.denominator
    }
    let integers = coefficients.map { $0.numerator * (multiple / $0.denominator) }
    var divisor = BigInt(0)
    for integer in integers { divisor = BigInt.gcd(divisor, integer) }
    return divisor.isZero ? integers : integers.map { $0 / divisor }
  }

  /// If `p(x) = q(x^k)` for the largest `k > 1` that works, `(k, q)`.
  var substitution: (exponent: Int, polynomial: RationalPolynomial)? {
    var common = 0
    for (index, coefficient) in coefficients.enumerated() where index > 0 && !coefficient.isZero {
      common = common == 0 ? index : Int(BigInt.gcd(BigInt(common), BigInt(index)).asInt ?? 1)
    }
    guard common > 1 else { return nil }
    return (common, RationalPolynomial(stride(from: 0, to: coefficients.count, by: common).map { coefficients[$0] }))
  }

  // MARK: Rational roots

  /// Every rational root, by the rational root theorem, and what is left after dividing them out. The polynomial must
  /// not have zero as a root. When the constant or leading coefficient is too large to factor completely, or has too
  /// many divisors, no root is looked for.
  func rationalRoots() -> (roots: [Rational], remainder: RationalPolynomial) {
    guard degree >= 1, !self[0].isZero else { return ([], self) }
    let integers = primitiveIntegerCoefficients
    guard let constants = RationalPolynomial.divisors(of: integers.first!.magnitude),
      let leadings = RationalPolynomial.divisors(of: integers.last!.magnitude),
      constants.count * leadings.count <= 200_000
    else { return ([], self) }

    var polynomial = self
    var roots: [Rational] = []
    for numerator in constants {
      for denominator in leadings where BigInt.gcd(numerator, denominator).isOne {
        for sign in [1, -1] {
          let candidate = Rational(sign < 0 ? -numerator : numerator, denominator)
          while polynomial.degree >= 1, polynomial.evaluate(candidate).isZero {
            roots.append(candidate)
            polynomial = polynomial.deflated(byRoot: candidate)
          }
        }
      }
    }
    return (roots, polynomial)
  }

  /// All the positive divisors of a positive integer, or `nil` when it cannot be factored completely.
  static func divisors(of value: BigInt) -> [BigInt]? {
    if value.isOne { return [value] }
    let factorization = NumberTheory.factor(value)
    guard factorization.cofactor.isOne else { return nil }
    var divisors = [BigInt(1)]
    for entry in factorization.primes {
      var next: [BigInt] = []
      var power = BigInt(1)
      for _ in 0...entry.exponent {
        for divisor in divisors { next.append(divisor * power) }
        power *= entry.prime
      }
      divisors = next
    }
    return divisors
  }
}
