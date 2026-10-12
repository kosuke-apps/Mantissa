// Multiplying out, substituting, and writing a sum of fractions as one fraction: the operations the solver needs that
// the canonical form deliberately does not do on its own.

extension Expr {
  /// The expression with products of sums, and whole-number powers of sums, multiplied out: `(x+1)(x-2)` is
  /// `x² - x - 2` and `(x+1)^3` is `x³ + 3x² + 3x + 1`. Negative powers (denominators) are left as they are, and
  /// powers too large to expand are kept as written.
  public func expanded() -> Expr {
    switch self {
    case .number, .constant, .symbol:
      return self
    case .sum(let terms):
      return Expr.makeSum(terms.map { $0.expanded() })
    case .product(let factors):
      let parts = factors.map { $0.expanded() }
      return parts.dropFirst().reduce(parts[0]) { Expr.multipliedOut($0, $1) }
    case .power(let base, let exponent):
      let expandedBase = base.expanded()
      if let n = exponent.rational, n.isInteger, let whole = n.numerator.asInt, whole > 1, case .sum = expandedBase,
        let result = Expr.expandedPower(expandedBase, whole)
      {
        return result
      }
      return Expr.makePower(expandedBase, exponent.expanded())
    case .function(let function, let arguments):
      return (try? Expr.apply(function, arguments.map { $0.expanded() })) ?? self
    }
  }

  /// `base^n` multiplied out, by repeated squaring; `nil` when the result would be too large.
  private static func expandedPower(_ base: Expr, _ n: Int) -> Expr? {
    guard n <= 64 else { return nil }
    var result: Expr = .one
    var square = base
    var remaining = n
    while remaining > 0 {
      if remaining & 1 == 1 { result = multipliedOut(result, square) }
      remaining >>= 1
      if remaining > 0 { square = multipliedOut(square, square) }
      if result.nodeCount > 20_000 || square.nodeCount > 20_000 { return nil }
    }
    return result
  }

  /// The expression with every occurrence of the unknown `name` replaced by `value`, or `nil` when that is undefined
  /// (a division by zero, a logarithm of zero).
  public func substituting(_ name: String, with value: Expr) -> Expr? {
    switch self {
    case .number, .constant: return self
    case .symbol(let symbol): return symbol == name ? value : self
    case .sum(let terms):
      var parts: [Expr] = []
      for term in terms {
        guard let part = term.substituting(name, with: value) else { return nil }
        parts.append(part)
      }
      return Expr.makeSum(parts)
    case .product(let factors):
      var parts: [Expr] = []
      for factor in factors {
        guard let part = factor.substituting(name, with: value) else { return nil }
        parts.append(part)
      }
      return Expr.makeProduct(parts)
    case .power(let base, let exponent):
      guard let newBase = base.substituting(name, with: value),
        let newExponent = exponent.substituting(name, with: value)
      else { return nil }
      return try? newBase.raised(to: newExponent)
    case .function(let function, let arguments):
      var parts: [Expr] = []
      for argument in arguments {
        guard let part = argument.substituting(name, with: value) else { return nil }
        parts.append(part)
      }
      return try? Expr.apply(function, parts)
    }
  }

  /// The sum written as one fraction: `numerator / denominator`, where the denominator is a product of powers of
  /// expressions that contain `variable` (each power listed once, with the largest exponent any term has). A term's
  /// denominator that does not contain the variable stays in the numerator as a coefficient. `numerator` is multiplied
  /// out. `nil` when a term has the variable in a denominator that is not a whole power (a square root, say).
  func together(variable: String) -> (numerator: Expr, denominators: [(base: Expr, power: Int)])? {
    let source = expanded()
    let terms: [Expr]
    if case .sum(let inner) = source { terms = inner } else { terms = [source] }

    var parts: [(numerator: Expr, denominators: [Expr: Int])] = []
    for term in terms {
      guard let part = term.fractionParts(variable: variable) else { return nil }
      parts.append(part)
    }
    var common: [Expr: Int] = [:]
    var order: [Expr] = []
    for part in parts {
      for (base, power) in part.denominators {
        if common[base] == nil { order.append(base) }
        common[base] = max(common[base] ?? 0, power)
      }
    }

    var numerators: [Expr] = []
    for part in parts {
      var factor = part.numerator
      for base in order {
        let missing = common[base]! - (part.denominators[base] ?? 0)
        if missing > 0 { factor = Expr.makeProduct([factor, Expr.makePower(base, .integer(missing))]) }
      }
      numerators.append(factor)
    }
    let numerator = Expr.makeSum(numerators.map { $0.expanded() })
    return (numerator, order.map { ($0, common[$0]!) })
  }

  /// A term split into a numerator and the denominators that contain `variable`.
  private func fractionParts(variable: String) -> (numerator: Expr, denominators: [Expr: Int])? {
    if !freeSymbols.contains(variable) { return (self, [:]) }
    var numerator: [Expr] = []
    var denominators: [Expr: Int] = [:]
    let factors: [Expr]
    if case .product(let inner) = self { factors = inner } else { factors = [self] }
    for factor in factors {
      guard factor.freeSymbols.contains(variable) else {
        numerator.append(factor)
        continue
      }
      if case .power(let base, let exponent) = factor, let n = exponent.rational, n.signum < 0 {
        // Only whole negative powers can be cleared.
        guard n.isInteger, let whole = n.numerator.asInt else { return nil }
        denominators[base, default: 0] += -whole
      } else {
        numerator.append(factor)
      }
    }
    return (Expr.makeProduct(numerator), denominators)
  }
}
