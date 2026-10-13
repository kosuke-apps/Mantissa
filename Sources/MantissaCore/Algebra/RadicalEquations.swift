/// Equations with roots of expressions that contain the unknown (`√(x + 1) = x − 1`).
///
/// Each root `b^(1/L)` becomes a symbol `r` with `r^L = b`. The equation is then a polynomial in `r` whose degree is lowered
/// to below `L` by that relation, `c₀ + c₁r (+ c₂r²)`, and multiplying by its conjugate (`c₀ − c₁r`; for cube roots the
/// product over the three roots of unity) removes `r`. What is left is solved as an ordinary equation, and the candidates
/// are checked in the original, since squaring adds solutions.
enum RadicalEquations {
  /// The roots to remove: `b^(p/q)` with the unknown in `b` and `q > 1`.
  private static func isRadical(_ expression: Expr, _ variable: String) -> Bool {
    guard case .power(let base, let exponent) = expression, let n = exponent.rational, !n.isInteger,
      base.contains(variable)
    else { return false }
    return true
  }

  static func solve(_ expression: Expr, _ variable: String) -> [SolvedValue]? {
    let radicals = expression.collect(where: { isRadical($0, variable) })
    guard !radicals.isEmpty else { return nil }

    // One symbol for each base, standing for its root of the common order of the exponents' denominators.
    var bases: [Expr] = []
    for radical in radicals {
      if case .power(let base, _) = radical, !bases.contains(base) { bases.append(base) }
    }
    var order: [Int] = []
    for base in bases {
      var common = 1
      for radical in radicals {
        guard case .power(let b, let exponent) = radical, b == base else { continue }
        guard let n = exponent.rational, let q = n.denominator.asInt else { return nil }
        common = common / gcd(common, q) * q
      }
      guard common <= 3 else { return nil }  // square and cube roots only
      order.append(common)
    }
    let names = bases.indices.map { "r\($0)" }
    guard names.allSatisfy({ !expression.contains($0) }) else { return nil }

    // b^(p/q) = r^(p·L/q).
    guard
      var current = expression.replacing({ part in
        guard case .power(let base, let exponent) = part, let n = exponent.rational, !n.isInteger,
          let index = bases.firstIndex(of: base)
        else { return nil }
        let times = n * Rational(order[index])
        guard times.isInteger else { return nil }
        return try? Expr.symbol(names[index]).raised(to: .number(times))
      })
    else { return nil }

    for index in bases.indices {
      guard let eliminated = eliminate(names[index], order: order[index], base: bases[index], from: current) else {
        return nil
      }
      current = eliminated
    }
    return TranscendentalSolver.realSolutions(of: current, variable)
  }

  /// The equation with the root `name` (where `name^order = base`) removed.
  private static func eliminate(_ name: String, order: Int, base: Expr, from expression: Expr) -> Expr? {
    // A root in a denominator: multiply through by its largest negative power first.
    var scaled = expression
    let symbol = Expr.symbol(name)
    if let negative = lowestPower(of: name, in: expression), negative < 0 {
      guard let factor = try? symbol.raised(to: .integer(-negative)) else { return nil }
      scaled = (expression * factor).expanded()
    }
    guard let polynomial = scaled.polynomial(in: name) else { return nil }

    // Reduce with r^order = base.
    var reduced = Array(repeating: [Expr](), count: order)
    for (power, coefficient) in polynomial.coefficients.enumerated() {
      guard let times = try? base.raised(to: .integer(power / order)) else { return nil }
      reduced[power % order].append(coefficient * times)
    }
    let c = reduced.map { Expr.makeSum($0).expanded() }
    if order == 2 {
      return (c[0] * c[0] - c[1] * c[1] * base).expanded()
    }
    // The norm of c0 + c1 r + c2 r² for r³ = base.
    let (c0, c1, c2) = (c[0], c[1], c[2])
    let b2 = (base * base).expanded()
    let norm =
      c0 * c0 * c0 + c1 * c1 * c1 * base + c2 * c2 * c2 * b2 - Expr.integer(3) * c0 * c1 * c2 * base
    return norm.expanded()
  }

  /// The lowest exponent `name` is raised to in the expression (negative for a denominator).
  private static func lowestPower(of name: String, in expression: Expr) -> Int? {
    var lowest: Int?
    func visit(_ part: Expr) {
      switch part {
      case .power(.symbol(name), let exponent):
        if let n = exponent.rational, n.isInteger, let whole = n.numerator.asInt {
          lowest = min(lowest ?? whole, whole)
        }
      case .symbol(let symbol):
        if symbol == name { lowest = min(lowest ?? 1, 1) }
      case .sum(let parts), .product(let parts), .function(_, let parts): parts.forEach(visit)
      case .power(let base, let exponent):
        visit(base)
        visit(exponent)
      default: break
      }
    }
    visit(expression)
    return lowest
  }

  private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
