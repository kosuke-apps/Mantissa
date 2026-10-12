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

  /// A sum of numbers written as one fraction, `(1 + √5)/2` for `1/2 + √5/2`: `(denominator, numerator)` when at least two
  /// terms have a fractional coefficient and no term has anything but a number or radical, `π` or `i` besides it. The
  /// denominator is the least common multiple of the coefficients' denominators. Sums with unknowns are left alone.
  static func commonDenominator(_ terms: [Expr]) -> (denominator: BigInt, numerator: Expr)? {
    guard terms.count >= 2, terms.allSatisfy({ $0.freeSymbols.isEmpty }) else { return nil }
    var denominator = BigInt(1)
    var fractional = 0
    for term in terms {
      var coefficient = Rational(1)
      switch term {
      case .number(let value): coefficient = value
      case .product(let factors):
        if case .number(let value) = factors[0] { coefficient = value }
        // A factor to a negative power is itself a fraction; stacking it inside this one would be hard to read.
        for factor in factors {
          if case .power(_, let exponent) = factor, exponent.rational?.isNegative == true { return nil }
        }
      case .power(_, let exponent):
        if exponent.rational?.isNegative == true { return nil }
      default: break
      }
      if !coefficient.denominator.isOne { fractional += 1 }
      denominator = denominator / BigInt.gcd(denominator, coefficient.denominator) * coefficient.denominator
    }
    guard fractional >= 2, !denominator.isOne, denominator.bitWidth < 62 else { return nil }
    let numerator = Expr.makeSum(terms.map { Expr.makeProduct([.number(Rational(denominator)), $0]) })
    return (denominator, numerator)
  }

  /// How the terms of a sum are ordered for reading. With unknowns: highest degree first, plain numbers last
  /// (`x^2 - 3x + 2`). Without: a plain number first, then the rest with positive terms before negative ones
  /// (`2 - √3`, `√6/4 - √2/4`). Terms with the imaginary unit come after the real ones (`1 + √2 + 3i`).
  static func displayOrder(_ terms: [Expr]) -> [Expr] {
    let hasUnknowns = terms.contains { !$0.freeSymbols.isEmpty }
    func group(_ term: Expr) -> Int {
      if case .number = term { return hasUnknowns ? 2 : 0 }
      if term.freeSymbols.isEmpty { return term.containsImaginaryUnit ? 3 : 1 }
      return 0
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

extension Expr {
  /// Whether the value is `a + bi` for whole numbers `a` and `b`, which a decimal would only repeat.
  public var isGaussianInteger: Bool {
    guard let (real, imaginary) = complexParts() else { return false }
    return real.isInteger && imaginary.isInteger
  }
}
