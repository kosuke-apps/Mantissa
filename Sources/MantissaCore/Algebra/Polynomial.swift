/// A polynomial in one unknown whose coefficients are expressions that do not contain it.
struct Polynomial: Equatable {
  /// `coefficients[k]` multiplies `x^k`. The last one is not zero; the zero polynomial has none.
  var coefficients: [Expr]

  var degree: Int { coefficients.count - 1 }
  var isZero: Bool { coefficients.isEmpty }

  /// The coefficients as rationals, when every one is a plain number.
  var rationalCoefficients: [Rational]? {
    var result: [Rational] = []
    for coefficient in coefficients {
      guard let value = coefficient.rational else { return nil }
      result.append(value)
    }
    return result
  }
}

extension Expr {
  /// The expression as a polynomial in `variable`, or `nil` if it is not one (a power with the unknown in it that is not
  /// a whole positive power, a function of the unknown, a denominator with it).
  func polynomial(in variable: String, maxDegree: Int = 200) -> Polynomial? {
    let source = expanded()
    let terms: [Expr]
    if case .sum(let inner) = source { terms = inner } else { terms = [source] }

    var byDegree: [Int: [Expr]] = [:]
    for term in terms {
      guard let (degree, coefficient) = term.monomial(of: variable), degree <= maxDegree else { return nil }
      byDegree[degree, default: []].append(coefficient)
    }
    var coefficients = Array(repeating: Expr.zero, count: (byDegree.keys.max() ?? -1) + 1)
    for (degree, parts) in byDegree { coefficients[degree] = Expr.makeSum(parts) }
    while coefficients.last?.isZero == true { coefficients.removeLast() }
    return Polynomial(coefficients: coefficients)
  }

  /// `(k, c)` when the term is `c·x^k` for a coefficient `c` that does not contain `x`.
  private func monomial(of variable: String) -> (Int, Expr)? {
    if !freeSymbols.contains(variable) { return (0, self) }
    switch self {
    case .symbol:
      return (1, .one)
    case .power(let base, let exponent):
      guard base == .symbol(variable), let n = exponent.rational, n.isInteger, n.signum > 0,
        let degree = n.numerator.asInt
      else { return nil }
      return (degree, .one)
    case .product(let factors):
      var degree = 0
      var rest: [Expr] = []
      for factor in factors {
        if !factor.freeSymbols.contains(variable) {
          rest.append(factor)
          continue
        }
        guard let (k, coefficient) = factor.monomial(of: variable), coefficient == .one else { return nil }
        degree += k
      }
      return (degree, Expr.makeProduct(rest))
    default:
      return nil
    }
  }
}
