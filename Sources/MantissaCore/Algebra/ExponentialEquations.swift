/// Equations with powers of a constant whose exponent contains the unknown (`2^x = 8`, `4^x − 3·2^x + 2 = 0`, `e^(2x) = 5`).
///
/// The powers are written with one base `g` (`4 = 2²`, so `4^x = (2^x)²`) and then `g^(x/V)` is a new unknown `t` that the
/// powers are whole powers of. The equation in `t` is solved as a polynomial, and each positive solution `t₀` gives
/// `x = V·log_g t₀`.
enum ExponentialEquations {
  static func solve(_ expression: Expr, _ variable: String) -> [SolvedValue]? {
    let atoms = expression.collect(where: { part in
      guard case .power(let base, let exponent) = part else { return false }
      return !base.contains(variable) && exponent.contains(variable)
    })
    guard !atoms.isEmpty else { return nil }

    struct Power {
      var atom: Expr
      var base: Expr
      var coefficient: Rational
      var constant: Expr
    }
    var powers: [Power] = []
    for atom in atoms {
      guard case .power(let base, let exponent) = atom, let (c, d) = exponent.linear(in: variable),
        let value = base.realValue, value.signum > 0, value != BigDecimal(1)
      else { return nil }
      powers.append(Power(atom: atom, base: base, coefficient: c, constant: d))
    }

    // Every base as a rational power of the first.
    let common = powers[0].base
    var exponents: [Rational] = []
    for power in powers {
      if power.base == common {
        exponents.append(Rational(1))
      } else if case .number(let a) = power.base, case .number(let g) = common,
        let k = NumberTheory.exactLogarithm(of: a, base: g)
      {
        exponents.append(k)
      } else {
        return nil
      }
    }

    // g^(k(cx + d)) = g^(kd) · t^(V·k·c), with t = g^(x/V).
    var denominator = BigInt(1)
    for (power, k) in zip(powers, exponents) {
      let u = k * power.coefficient
      denominator = denominator / BigInt.gcd(denominator, u.denominator) * u.denominator
    }
    guard let scale = denominator.asInt, scale <= 12 else { return nil }
    let t = "t"
    guard !expression.contains(t) else { return nil }

    let replaced = expression.replacing { part in
      guard let index = powers.firstIndex(where: { $0.atom == part }) else { return nil }
      let power = powers[index]
      let times = exponents[index] * power.coefficient * Rational(scale)
      guard let offset = try? common.raised(to: power.constant * Expr.number(exponents[index])),
        let unknown = try? Expr.symbol(t).raised(to: .number(times))
      else { return nil }
      return offset * unknown
    }
    guard var equation = replaced, !equation.contains(variable) else { return nil }
    // Negative powers of t (a power with a negative exponent) are cleared by a power of t.
    if let lowest = lowestPower(of: t, in: equation), lowest < 0,
      let factor = try? Expr.symbol(t).raised(to: .integer(-lowest))
    {
      equation = (equation * factor).expanded()
    }
    guard let solved = TranscendentalSolver.realSolutions(of: equation, t) else { return nil }

    var results: [SolvedValue] = []
    for root in solved {
      guard let exact = root.exact, let value = root.realValue, value.signum > 0 else { continue }
      let logarithm: Expr
      if common == .e {
        guard let log = try? Expr.apply(.ln, [exact]) else { continue }
        logarithm = log
      } else {
        guard let log = try? Expr.apply(.log, [exact, common]) else { continue }
        logarithm = log
      }
      if let solution = SolvedValue.exact(Expr.number(Rational(scale)) * logarithm) { results.append(solution) }
    }
    return results
  }

  private static func lowestPower(of name: String, in expression: Expr) -> Int? {
    var lowest: Int?
    func visit(_ part: Expr) {
      switch part {
      case .symbol(let symbol):
        if symbol == name { lowest = min(lowest ?? 1, 1) }
      case .power(.symbol(let symbol), let exponent):
        if symbol == name, let n = exponent.rational, n.isInteger, let whole = n.numerator.asInt {
          lowest = min(lowest ?? whole, whole)
        }
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
}
