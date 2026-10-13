// Writing a result of calculus as one fraction when that is simpler.

extension Expr {
  /// The expression as one fraction, `N / (b₁ⁿ b₂ᵐ …)`, with a denominator that divides the numerator cancelled, when that
  /// has fewer parts than the expression as it is (`1/(x+1) − x/(x+1)²` is `1/(x+1)²`, `cos(x)/x − sin(x)/x²` is
  /// `(x cos(x) − sin(x))/x²`). Otherwise the expression itself.
  func combinedOverCommonDenominator(variable: String) -> Expr {
    guard freeSymbols == [variable] || (freeSymbols.contains(variable)), containsNegativePower(),
      let (numerator, denominators) = together(variable: variable)
    else { return self }

    var numerator2 = numerator
    var kept: [(base: Expr, power: Int)] = []
    for (base, power) in denominators {
      var remaining = power
      // Cancel a factor of the denominator that the numerator has (polynomials with rational coefficients only).
      while remaining > 0, let quotient = Expr.divide(numerator2, by: base, variable: variable) {
        numerator2 = quotient
        remaining -= 1
      }
      if remaining > 0 { kept.append((base, remaining)) }
    }
    var factors = [numerator2]
    for (base, power) in kept { factors.append(Expr.makePower(base, .integer(-power))) }
    let combined = Expr.makeProduct(factors)
    return combined.nodeCount < nodeCount ? combined : self
  }

  private func containsNegativePower() -> Bool {
    !collectAll(where: { part in
      if case .power(_, let exponent) = part, exponent.rational?.isNegative == true { return true }
      return false
    }).isEmpty
  }

  /// `numerator / divisor` when both are polynomials in `variable` with rational coefficients and the division is exact.
  private static func divide(_ numerator: Expr, by divisor: Expr, variable: String) -> Expr? {
    guard let top = numerator.polynomial(in: variable)?.rationalCoefficients,
      let bottom = divisor.polynomial(in: variable)?.rationalCoefficients, !bottom.isEmpty, !top.isEmpty
    else { return nil }
    let (quotient, remainder) = RationalPolynomial(top).quotientAndRemainder(dividingBy: RationalPolynomial(bottom))
    guard remainder.isZero else { return nil }
    let terms = quotient.coefficients.enumerated().map { power, coefficient in
      Expr.makeProduct([.number(coefficient), Expr.makePower(.symbol(variable), .integer(power))])
    }
    return Expr.makeSum(terms)
  }
}
