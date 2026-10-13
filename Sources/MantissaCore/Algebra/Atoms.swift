// Finding and replacing parts of an expression, for the solvers that rewrite an equation before solving it.

extension Expr {
  /// Every distinct subexpression for which `predicate` holds, outermost first.
  func collect(where predicate: (Expr) -> Bool) -> [Expr] {
    var found: [Expr] = []
    func visit(_ expression: Expr) {
      if predicate(expression) {
        if !found.contains(expression) { found.append(expression) }
        return
      }
      switch expression {
      case .number, .constant, .symbol: break
      case .sum(let parts), .product(let parts), .function(_, let parts): parts.forEach(visit)
      case .power(let base, let exponent):
        visit(base)
        visit(exponent)
      }
    }
    visit(self)
    return found
  }

  /// Every distinct subexpression for which `predicate` holds, at any depth (so a match inside a match is found too).
  func collectAll(where predicate: (Expr) -> Bool) -> [Expr] {
    var found: [Expr] = []
    func visit(_ expression: Expr) {
      if predicate(expression), !found.contains(expression) { found.append(expression) }
      switch expression {
      case .number, .constant, .symbol: break
      case .sum(let parts), .product(let parts), .function(_, let parts): parts.forEach(visit)
      case .power(let base, let exponent):
        visit(base)
        visit(exponent)
      }
    }
    visit(self)
    return found
  }

  /// The expression with every subexpression for which `choose` gives a replacement replaced by it (the replacement is not
  /// searched again), or `nil` when the result is undefined.
  func replacing(_ choose: (Expr) -> Expr?) -> Expr? {
    if let replacement = choose(self) { return replacement }
    switch self {
    case .number, .constant, .symbol:
      return self
    case .sum(let terms):
      var parts: [Expr] = []
      for term in terms {
        guard let part = term.replacing(choose) else { return nil }
        parts.append(part)
      }
      return Expr.makeSum(parts)
    case .product(let factors):
      var parts: [Expr] = []
      for factor in factors {
        guard let part = factor.replacing(choose) else { return nil }
        parts.append(part)
      }
      return Expr.makeProduct(parts)
    case .power(let base, let exponent):
      guard let newBase = base.replacing(choose), let newExponent = exponent.replacing(choose) else { return nil }
      return try? newBase.raised(to: newExponent)
    case .function(let function, let arguments):
      var parts: [Expr] = []
      for argument in arguments {
        guard let part = argument.replacing(choose) else { return nil }
        parts.append(part)
      }
      return try? Expr.apply(function, parts)
    }
  }

  /// Whether the unknown occurs in the expression.
  func contains(_ variable: String) -> Bool { freeSymbols.contains(variable) }

  /// The coefficient `c` and constant `d` when the expression is `c·variable + d` with `c` a nonzero rational and `d` free of the
  /// variable.
  func linear(in variable: String) -> (coefficient: Rational, constant: Expr)? {
    guard let polynomial = polynomial(in: variable), polynomial.degree == 1, let c = polynomial.coefficients[1].rational
    else { return nil }
    return (c, polynomial.coefficients[0])
  }

  /// Whether the number is a real, finite value to within rounding: its imaginary part is negligible.
  var realValue: BigDecimal? {
    guard freeSymbols.isEmpty else { return nil }
    if let real = try? approximation(precision: 50) { return real }
    if let complex = try? complexApproximation(precision: 50), complex.isReal { return complex.real }
    return nil
  }
}

extension SolvedValue {
  /// The real value as a decimal, or `nil` for a value that is not a real number.
  var realValue: BigDecimal? {
    guard let approximation, approximation.isReal else { return nil }
    return approximation.real
  }
}
