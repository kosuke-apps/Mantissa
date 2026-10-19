// Factoring a polynomial in one unknown into irreducible factors over the rationals: rational roots first, then Kronecker's
// method for what is left. It is meant for the small polynomials of everyday problems (x⁴ + 4, x⁶ − 1).

extension RationalPolynomial {
  /// The irreducible factors over the rationals, each with whole-number coefficients and a positive leading coefficient, so that
  /// the polynomial is a number times their product. A factor may be missing from the list of linear ones only when it would
  /// take too long to find.
  func irreducibleFactors() -> [RationalPolynomial] {
    guard degree >= 1 else { return [] }
    var rest = RationalPolynomial(RationalPolynomial.positiveIntegers(self))
    var factors: [RationalPolynomial] = []
    let x = RationalPolynomial([Rational(0), Rational(1)])

    while rest.degree >= 1, rest[0].isZero {
      rest = RationalPolynomial(Array(rest.coefficients.dropFirst()))
      factors.append(x)
    }
    if rest.degree >= 1 {
      let (roots, remaining) = rest.rationalRoots()
      for root in roots {
        factors.append(RationalPolynomial([Rational(-root.numerator), Rational(root.denominator)]))
      }
      rest = remaining
    }
    factors += rest.factorsWithoutRoots()
    return factors
  }

  /// The factors of a polynomial known to have no rational root: none of degree 1, and any of degree 2 or 3 irreducible.
  func factorsWithoutRoots() -> [RationalPolynomial] {
    guard degree >= 1 else { return [] }
    var rest = RationalPolynomial(RationalPolynomial.positiveIntegers(self))
    var factors: [RationalPolynomial] = []
    while rest.degree >= 4, let factor = rest.kroneckerFactor() {
      factors.append(factor)
      rest = RationalPolynomial(
        RationalPolynomial.positiveIntegers(rest.quotientAndRemainder(dividingBy: factor).quotient))
    }
    if rest.degree >= 1 { factors.append(rest) }
    func key(_ polynomial: RationalPolynomial) -> (Int, String) {
      (polynomial.degree, polynomial.coefficients.map(\.description).joined(separator: ","))
    }
    return factors.sorted { key($0) < key($1) }
  }

  /// The coefficients scaled to whole numbers with no common factor and a positive leading one.
  static func positiveIntegers(_ polynomial: RationalPolynomial) -> [Rational] {
    var integers = polynomial.primitiveIntegerCoefficients
    if let leading = integers.last, leading.isNegative { integers = integers.map { -$0 } }
    return integers.map { Rational($0) }
  }

  /// A factor with a degree from 2 to half of the polynomial's, found by Kronecker's method: a factor of degree `d` takes a
  /// value at each of `d + 1` whole numbers that divides the polynomial's value there, so those can be tried. The polynomial
  /// must have whole-number coefficients and no rational root. `nil` when there is none or the search would be long.
  func kroneckerFactor() -> RationalPolynomial? {
    // A polynomial of high degree is not searched: the values at the points are too large to factor, and a search takes long.
    guard degree >= 4, degree <= 24 else { return nil }
    let candidatesLimit = 6_000
    let order = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]

    for factorDegree in 2...min(degree / 2, 5) {
      let points = Array(order.prefix(factorDegree + 1))
      var divisorLists: [[Rational]] = []
      var count = 1
      var feasible = true
      for (index, point) in points.enumerated() {
        let value = evaluate(Rational(point))
        guard !value.isZero, let divisors = RationalPolynomial.divisors(of: value.numerator.magnitude) else {
          feasible = false
          break
        }
        // A factor and its negative are the same factor, so the first value is taken positive.
        var signed = divisors.map { Rational($0) }
        if index > 0 { signed += divisors.map { Rational(-$0) } }
        divisorLists.append(signed)
        count *= signed.count
        if count > candidatesLimit {
          feasible = false
          break
        }
      }
      guard feasible else { continue }

      // The polynomial of degree `factorDegree` through the points is a sum of the basis polynomials, one per point.
      var basis: [RationalPolynomial] = []
      for (index, point) in points.enumerated() {
        var term = RationalPolynomial([Rational(1)])
        var denominator = Rational(1)
        for (other, otherPoint) in points.enumerated() where other != index {
          term = RationalPolynomial.product(term, RationalPolynomial([Rational(-otherPoint), Rational(1)]))
          denominator *= Rational(point - otherPoint)
        }
        basis.append(RationalPolynomial(term.coefficients.map { $0 / denominator }))
      }

      var choice = Array(repeating: 0, count: points.count)
      search: while true {
        var coefficients = Array(repeating: Rational(0), count: factorDegree + 1)
        for (index, selected) in choice.enumerated() {
          let value = divisorLists[index][selected]
          for power in 0...factorDegree { coefficients[power] += value * basis[index][power] }
        }
        let candidate = RationalPolynomial(coefficients)
        if candidate.degree == factorDegree, coefficients.allSatisfy(\.isInteger) {
          let (quotient, remainder) = quotientAndRemainder(dividingBy: candidate)
          if remainder.isZero, quotient.degree >= 1 {
            return RationalPolynomial(RationalPolynomial.positiveIntegers(candidate))
          }
        }
        // The next combination of choices.
        var position = choice.count - 1
        while position >= 0 {
          choice[position] += 1
          if choice[position] < divisorLists[position].count { continue search }
          choice[position] = 0
          position -= 1
        }
        break
      }
    }
    return nil
  }

  static func product(_ a: RationalPolynomial, _ b: RationalPolynomial) -> RationalPolynomial {
    guard !a.isZero, !b.isZero else { return RationalPolynomial([]) }
    var result = Array(repeating: Rational(0), count: a.degree + b.degree + 1)
    for i in 0...a.degree { for j in 0...b.degree { result[i + j] += a[i] * b[j] } }
    return RationalPolynomial(result)
  }
}
