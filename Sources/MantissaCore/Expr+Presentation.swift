// Choices about how an expression is laid out for reading that the text rendering and the typesetter share.

enum Presentation {
  /// `(true, |term|)` for a negative number or a product with a negative coefficient, else `(false, term)`.
  static func splitSign(_ term: Expr) -> (Bool, Expr) {
    switch term {
    case .number(let value): return value.isNegative ? (true, .number(-value)) : (false, term)
    case .product(let factors):
      if case .number(let coefficient) = factors[0], coefficient.isNegative { return (true, -term) }
      return (false, term)
    default: return (false, term)
    }
  }

  /// How the terms of a sum are ordered for reading. With unknowns: highest degree first, plain numbers last
  /// (`x^2 - 3x + 2`). Without: a plain number first, then the rest with positive terms before negative ones
  /// (`2 - √3`, `√6/4 - √2/4`).
  static func displayOrder(_ terms: [Expr]) -> [Expr] {
    let hasUnknowns = terms.contains { !$0.freeSymbols.isEmpty }
    func group(_ term: Expr) -> Int {
      if case .number = term { return hasUnknowns ? 2 : 0 }
      return term.freeSymbols.isEmpty ? 1 : 0
    }
    let indexed = terms.enumerated().map { (index: $0.offset, term: $0.element) }
    return indexed.sorted { a, b in
      let (ga, gb) = (group(a.term), group(b.term))
      if ga != gb { return ga < gb }
      if hasUnknowns {
        let (da, db) = (degree(a.term), degree(b.term))
        if da != db { return da > db }
        // Same degree: by the names of the unknowns, so that x comes before y.
        let (ka, kb) = (a.term.freeSymbols.sorted().joined(), b.term.freeSymbols.sorted().joined())
        if ka != kb { return ka < kb }
      } else {
        let (na, nb) = (splitSign(a.term).0, splitSign(b.term).0)
        if na != nb { return !na }
      }
      return a.index < b.index
    }.map(\.term)
  }

  /// A polynomial-style degree, used only to order terms for reading.
  static func degree(_ term: Expr) -> Double {
    switch term {
    case .symbol: return 1
    case .power(let base, let exponent):
      guard let number = exponent.rational else { return degree(base) }
      return degree(base) * (Double(number.numerator.description) ?? 1) / (Double(number.denominator.description) ?? 1)
    case .product(let factors): return factors.reduce(0) { $0 + degree($1) }
    case .sum(let terms): return terms.map(degree).max() ?? 0
    default: return 0
    }
  }
}
