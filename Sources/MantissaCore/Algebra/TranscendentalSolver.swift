/// Equations that are not polynomials: absolute values, roots, exponentials and logarithms, trigonometric functions.
///
/// Each kind has a strategy that rewrites the equation into polynomial ones (or into the closed form of an inverse function)
/// and solves those. A strategy only proposes candidates: every one is checked against the original equation, so a root
/// brought in by squaring, or a logarithm of a negative number, is dropped. Solutions of these equations are the real ones.
/// What no strategy can solve exactly is located numerically, as decimals.
enum TranscendentalSolver {
  static func solve(_ expression: Expr, for variable: String) -> Solved? {
    guard expression.freeSymbols == [variable] else { return nil }

    let strategies: [(Expr, String) -> [SolvedValue]?] = [
      AbsoluteValueEquations.solve, ExponentialEquations.solve, LogarithmicEquations.solve, RadicalEquations.solve,
    ]
    for strategy in strategies {
      guard let candidates = strategy(expression, variable) else { continue }
      let verified = EquationSolver.sortedAndDistinct(candidates.filter { verifies($0, expression, variable) })
      return verified.isEmpty ? .none(variable: variable) : .values(variable: variable, verified)
    }
    return nil
  }

  /// Whether the value is a real solution of `expression = 0`.
  static func verifies(_ value: SolvedValue, _ expression: Expr, _ variable: String) -> Bool {
    guard let approximation = value.approximation, approximation.isReal else { return false }
    if let exact = value.exact {
      guard let substituted = expression.substituting(variable, with: exact) else { return false }
      if substituted.isZero { return true }
      guard let result = try? substituted.approximation(precision: 40) else { return false }
      return result.isZero || (result.decimalOrder ?? Int.min) < -30
    }
    guard let result = try? expression.approximation(precision: 40, values: [variable: approximation.real]) else {
      return false
    }
    return result.isZero || (result.decimalOrder ?? Int.min) < -20
  }

  /// The real solutions of an equation found by the polynomial or transcendental solvers, or `nil` if it is beyond them.
  static func realSolutions(of expression: Expr, _ variable: String) -> [SolvedValue]? {
    guard let solved = EquationSolver.solve(expression, for: variable) else { return nil }
    switch solved {
    case .values(_, let values): return values.filter(\.isReal)
    case .none: return []
    default: return nil
    }
  }
}
