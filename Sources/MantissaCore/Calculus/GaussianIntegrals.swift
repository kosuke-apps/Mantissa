// Definite integrals of `x^m · e^(−a x² + b x + c)` over the whole line or a half line: the Gaussian integrals, whose
// antiderivatives are not elementary (they involve erf), so the antiderivative route cannot give them.

extension Expr {
  /// ∫ f dx from `lower` to `upper` when `f` is a constant times `x^m e^(q(x))` with `q` a quadratic whose x² coefficient is
  /// negative, and the ends are (−∞, ∞), or (0, ∞) or (−∞, 0) with no x term in `q`. Otherwise `nil`.
  func gaussianIntegral(_ variable: String, from lower: LimitPoint, to upper: LimitPoint) -> Expr? {
    // The shape: a constant, a power of x, and one exponential e^(quadratic).
    let factors: [Expr]
    if case .product(let parts) = self { factors = parts } else { factors = [self] }
    var constants: [Expr] = []
    var power = 0
    var exponent: Expr?
    for factor in factors {
      if !factor.contains(variable) {
        constants.append(factor)
      } else if factor == .symbol(variable) {
        power += 1
      } else if case .power(let base, let exponentOfBase) = factor {
        if base == .symbol(variable), let n = exponentOfBase.rational, n.isInteger, n.signum > 0,
          let whole = n.numerator.asInt
        {
          power += whole
        } else if base == .e, exponent == nil {
          exponent = exponentOfBase
        } else {
          return nil
        }
      } else {
        return nil
      }
    }
    guard let exponent, power <= 20, let q = exponent.polynomial(in: variable), q.degree == 2,
      !q.coefficients[0].contains(variable), !q.coefficients[1].contains(variable)
    else { return nil }
    let c0 = q.coefficients[0]
    let c1 = q.coefficients[1]
    let a = -q.coefficients[2]
    guard a.freeSymbols.isEmpty, a.numericSign == 1 else { return nil }
    let constant = Expr.makeProduct(constants)
    guard !constant.contains(variable) else { return nil }

    let sqrtPi = Expr.makePower(.pi, .fraction(1, 2))
    // ∫ t^j e^(−a t²) dt over the whole line: (j−1)!!/(2a)^(j/2) · √(π/a) for even j, 0 for odd j.
    func moment(_ j: Int) -> Expr {
      guard j % 2 == 0 else { return .zero }
      var doubleFactorial = 1
      var k = j - 1
      while k > 1 {
        doubleFactorial *= k
        k -= 2
      }
      let scale = Expr.makePower(Expr.integer(2) * a, .integer(-(j / 2)))
      let root = Expr.makePower(a, .fraction(-1, 2))
      return Expr.makeProduct([.integer(doubleFactorial), scale, sqrtPi, root])
    }

    func isZero(_ point: LimitPoint) -> Bool {
      if case .finite(let value) = point { return value.isZero }
      return false
    }

    var value: Expr
    switch (lower, upper) {
    case (.minusInfinity, .plusInfinity):
      // Complete the square: −a x² + c1 x + c0 = −a (x − h)² + c0 + c1²/(4a) with h = c1/(2a).
      let h = Expr.makeProduct([c1, Expr.makePower(Expr.integer(2) * a, .minusOne)])
      let shift = c0 + Expr.makeProduct([c1, c1, Expr.makePower(Expr.integer(4) * a, .minusOne)])
      var total: Expr = .zero
      for j in 0...power {
        let binomial = Expr.integer(NumberTheory.combinations(power, j).flatMap { $0.asInt } ?? 0)
        total = total + Expr.makeProduct([binomial, Expr.makePower(h, .integer(power - j)), moment(j)])
      }
      guard let growth = try? Expr.e.raised(to: shift) else { return nil }
      value = Expr.makeProduct([growth, total])

    case (.plusInfinity, _), (_, .minusInfinity):
      return nil

    case (let start, .plusInfinity) where isZero(start), (.minusInfinity, let start) where isZero(start):
      guard c1.isZero else { return nil }
      // On a half line: half of the whole line for an even power; for an odd one ((m−1)/2)!/(2a^((m+1)/2)).
      let growth = Expr.makePower(.e, c0)
      if power % 2 == 0 {
        value = Expr.makeProduct([growth, .fraction(1, 2), moment(power)])
      } else {
        var factorial = 1
        if power >= 3 { for k in 2...((power - 1) / 2) { factorial *= k } }
        let scale = Expr.makePower(a, .integer(-(power + 1) / 2))
        value = Expr.makeProduct([growth, .integer(factorial), .fraction(1, 2), scale])
        if case .minusInfinity = lower { value = -value }
      }

    default:
      return nil
    }
    return Expr.makeProduct([constant, value])
  }
}
