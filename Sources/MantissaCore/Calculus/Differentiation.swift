// Derivatives of exact expressions.

extension Expr {
  /// The derivative with respect to `variable`; any other symbol is a constant. The rules are applied term by term and the
  /// result is in canonical form, which is as simple as the canonical form gets: `(x² + 1)³` gives `6x(x² + 1)²`, and `x^x`
  /// gives `x^x (ln x + 1)`.
  ///
  /// Functions with no derivative to speak of (the factorial, binomial coefficients) are `MathError.unsupported`.
  public func derivative(_ variable: String) throws(MathError) -> Expr {
    switch self {
    case .number, .constant:
      return .zero

    case .symbol(let name):
      return name == variable ? .one : .zero

    case .sum(let terms):
      var parts: [Expr] = []
      for term in terms { parts.append(try term.derivative(variable)) }
      return Expr.makeSum(parts)

    case .product(let factors):
      // (f₁ f₂ … fₙ)′ = Σ fᵢ′ · Π_{j≠i} fⱼ
      var parts: [Expr] = []
      for (index, factor) in factors.enumerated() where factor.contains(variable) {
        var others = factors
        others.remove(at: index)
        parts.append(Expr.makeProduct([try factor.derivative(variable)] + others))
      }
      return Expr.makeSum(parts)

    case .power(let base, let exponent):
      return try Expr.derivativeOfPower(base, exponent, variable)

    case .function(let function, let arguments):
      return try Expr.derivativeOfFunction(function, arguments, variable)
    }
  }

  /// The `n`-th derivative.
  public func derivative(_ variable: String, order: Int) throws(MathError) -> Expr {
    var result = self
    for _ in 0..<max(order, 0) { result = try result.derivative(variable) }
    return result
  }

  private static func derivativeOfPower(_ base: Expr, _ exponent: Expr, _ variable: String) throws(MathError) -> Expr {
    let baseMoves = base.contains(variable)
    let exponentMoves = exponent.contains(variable)
    if !baseMoves && !exponentMoves { return .zero }

    if !exponentMoves {
      // (b^n)′ = n b^(n−1) b′
      let slope = try base.derivative(variable)
      return Expr.makeProduct([exponent, Expr.makePower(base, exponent - .one), slope])
    }

    // (b^e)′ = b^e (e′ ln b + e b′/b), which is b^e ln b · e′ when the base is constant.
    let slope = try exponent.derivative(variable)
    let logarithm = try Expr.apply(.ln, [base])
    var inner = Expr.makeProduct([slope, logarithm])
    if baseMoves {
      let ratio = try base.derivative(variable).divided(by: base)
      inner = inner + exponent * ratio
    }
    return Expr.makeProduct([Expr.makePower(base, exponent), inner])
  }

  private static func derivativeOfFunction(
    _ function: MathFunction, _ arguments: [Expr], _ variable: String
  ) throws(MathError) -> Expr {
    guard arguments.contains(where: { $0.contains(variable) }) else { return .zero }
    let g = arguments[0]
    let slope = try g.derivative(variable)

    func call(_ function: MathFunction, _ argument: Expr) throws(MathError) -> Expr {
      try Expr.apply(function, [argument])
    }
    /// 1/√(1 − g²) and its relatives.
    func rootOf(_ expression: Expr) -> Expr { Expr.makePower(expression, .fraction(-1, 2)) }
    let square = Expr.makePower(g, .integer(2))

    switch function {
    case .sin: return Expr.makeProduct([try call(.cos, g), slope])
    case .cos: return Expr.makeProduct([.minusOne, try call(.sin, g), slope])
    case .tan: return Expr.makeProduct([Expr.one + Expr.makePower(try call(.tan, g), .integer(2)), slope])
    case .asin: return Expr.makeProduct([rootOf(Expr.one - square), slope])
    case .acos: return Expr.makeProduct([.minusOne, rootOf(Expr.one - square), slope])
    case .atan: return Expr.makeProduct([Expr.makePower(Expr.one + square, .minusOne), slope])
    case .sinh: return Expr.makeProduct([try call(.cosh, g), slope])
    case .cosh: return Expr.makeProduct([try call(.sinh, g), slope])
    case .tanh: return Expr.makeProduct([Expr.one - Expr.makePower(try call(.tanh, g), .integer(2)), slope])
    case .asinh: return Expr.makeProduct([rootOf(square + .one), slope])
    case .acosh: return Expr.makeProduct([rootOf(square - .one), slope])
    case .atanh: return Expr.makeProduct([Expr.makePower(Expr.one - square, .minusOne), slope])
    case .ln: return try slope.divided(by: g)
    case .log:
      guard !arguments[1].contains(variable) else { throw .unsupported }
      return try slope.divided(by: g * (try call(.ln, arguments[1])))
    case .abs: return Expr.makeProduct([g, Expr.makePower(try call(.abs, g), .minusOne), slope])
    case .floor, .ceil, .round: return .zero
    case .factorial, .combinations, .permutations, .gcd, .lcm: throw .unsupported
    }
  }
}
