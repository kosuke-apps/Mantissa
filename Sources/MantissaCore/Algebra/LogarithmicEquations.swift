/// Equations that are a sum of logarithms and a constant (`ln x = 3`, `log(x) + log(x − 3) = 1`, `2·ln x − ln(x + 6) = 0`).
///
/// With natural logarithms throughout, the equation is `Σ kᵢ ln gᵢ + C = 0`. When the `kᵢ` are rational multiples of one
/// another the logarithms combine: `Π gᵢ^(rᵢ) = e^δ`, an algebraic equation. Its solutions are checked in the original
/// equation, which drops those where an argument is not positive.
enum LogarithmicEquations {
  static func solve(_ expression: Expr, _ variable: String) -> [SolvedValue]? {
    let logarithms = expression.collect(where: { part in
      switch part {
      case .function(.ln, let arguments): return arguments[0].contains(variable)
      case .function(.log, let arguments): return arguments[0].contains(variable) && !arguments[1].contains(variable)
      default: return false
      }
    })
    guard !logarithms.isEmpty else { return nil }

    // log(g, b) = ln g / ln b.
    let natural = expression.replacing { part in
      guard logarithms.contains(part), case .function(let function, let parts) = part else { return nil }
      guard function == .log else { return part }
      guard let ln = try? Expr.apply(.ln, [parts[0]]), let base = try? Expr.apply(.ln, [parts[1]]),
        let quotient = try? ln.divided(by: base)
      else { return nil }
      return quotient
    }
    guard let natural else { return nil }
    // The arguments of the natural logarithms, in the order they first occur.
    let atoms = natural.collect(where: {
      if case .function(.ln, let a) = $0 { return a[0].contains(variable) } else { return false }
    })
    guard !atoms.isEmpty else { return nil }

    // One placeholder for each logarithm; the equation must be linear in them with coefficients that are plain numbers.
    let names = atoms.indices.map { "l\($0)" }
    guard names.allSatisfy({ !natural.contains($0) }) else { return nil }
    guard
      let linear = natural.replacing({ part in
        atoms.firstIndex(of: part).map { Expr.symbol(names[$0]) }
      })?.expanded()
    else { return nil }

    var coefficients: [Expr] = []
    var rest = linear
    for name in names {
      guard let polynomial = rest.polynomial(in: name), polynomial.degree == 1 else { return nil }
      coefficients.append(polynomial.coefficients[1])
      rest = polynomial.coefficients[0]
    }
    // The coefficients and the constant must not depend on x or on each other's placeholders.
    guard rest.freeSymbols.isEmpty, coefficients.allSatisfy({ $0.freeSymbols.isEmpty }) else { return nil }

    var ratios: [Rational] = []
    for coefficient in coefficients {
      guard let ratio = try? coefficient.divided(by: coefficients[0]), let value = ratio.rational else { return nil }
      ratios.append(value)
    }
    var denominator = BigInt(1)
    for ratio in ratios { denominator = denominator / BigInt.gcd(denominator, ratio.denominator) * ratio.denominator }
    guard let multiple = denominator.asInt, multiple <= 6 else { return nil }

    // Σ rᵢ ln gᵢ = δ, so Π gᵢ^(rᵢ·m) = (e^δ)^m.
    guard let delta = try? (-rest).divided(by: coefficients[0]),
      let target = try? Expr.makePower(.e, delta).raised(to: .integer(multiple))
    else { return nil }
    var top: [Expr] = []
    var bottom: [Expr] = []
    for (argument, ratio) in zip(atoms, ratios) {
      guard case .function(_, let parts) = argument else { return nil }
      let n = (ratio * Rational(multiple)).numerator
      guard let whole = n.asInt else { return nil }
      guard let power = try? parts[0].raised(to: .integer(abs(whole))) else { return nil }
      if whole > 0 { top.append(power) } else { bottom.append(power) }
    }
    let equation = (Expr.makeProduct(top) - target * Expr.makeProduct(bottom)).expanded()
    return TranscendentalSolver.realSolutions(of: equation, variable)
  }
}
