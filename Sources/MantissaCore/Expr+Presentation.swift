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
    let sorted = indexed.sorted { a, b in
      let (ga, gb) = (group(a.term), group(b.term))
      if ga != gb { return ga < gb }
      if hasUnknowns {
        let (da, db) = (degree(a.term), degree(b.term))
        if da != db { return da > db }
        // Same degree: a plain monomial before a term with a root in it (−b + √(b² − 4ac)), then by the powers of the
        // unknowns in alphabetical order, so that x comes before y and a²b before ab².
        let (ma, mb) = (monomialPowers(a.term) != nil, monomialPowers(b.term) != nil)
        if ma != mb, (ma ? b.term : a.term).hasRoot { return ma }
        if let (ea, eb) = monomialPowers(a.term).flatMap({ left in monomialPowers(b.term).map { (left, $0) } }) {
          for name in Set(ea.keys).union(eb.keys).sorted() where ea[name, default: 0] != eb[name, default: 0] {
            return ea[name, default: 0] > eb[name, default: 0]
          }
        } else {
          let (ka, kb) = (a.term.freeSymbols.sorted().joined(), b.term.freeSymbols.sorted().joined())
          if ka != kb { return ka < kb }
        }
      } else {
        let (na, nb) = (splitSign(a.term).0, splitSign(b.term).0)
        if na != nb { return !na }
      }
      return a.index < b.index
    }.map(\.term)
    // Two terms with a minus sign first read better the other way round: 1 − x², not −x² + 1.
    // The exception is the quadratic formula's −b + √(b² − 4ac).
    if hasUnknowns, sorted.count == 2, splitSign(sorted[0]).0, !splitSign(sorted[1]).0, !sorted[1].hasRoot {
      return sorted.reversed()
    }
    return sorted
  }

  /// The powers of the unknowns in a term that is a product of unknowns to whole powers and a number (`3a²b`); `nil` for any
  /// other term.
  static func monomialPowers(_ term: Expr) -> [String: Int]? {
    var powers: [String: Int] = [:]
    let factors: [Expr]
    if case .product(let inner) = term { factors = inner } else { factors = [term] }
    for factor in factors {
      switch factor {
      case .number: continue
      case .symbol(let name): powers[name, default: 0] += 1
      case .power(.symbol(let name), let exponent):
        guard let n = exponent.rational, n.isInteger, let whole = n.numerator.asInt, whole > 0 else { return nil }
        powers[name, default: 0] += whole
      default: return nil
      }
    }
    return powers.isEmpty ? nil : powers
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
  /// Whether the term is, or has as a factor, a power with a fractional exponent: a square root.
  var hasRoot: Bool {
    func isRoot(_ expression: Expr) -> Bool {
      if case .power(_, let exponent) = expression, let n = exponent.rational, !n.isInteger { return true }
      return false
    }
    if case .product(let factors) = self { return factors.contains(where: isRoot) }
    return isRoot(self)
  }

  /// Whether the value is `a + bi` for whole numbers `a` and `b`, which a decimal would only repeat.
  public var isGaussianInteger: Bool {
    guard let (real, imaginary) = complexParts() else { return false }
    return real.isInteger && imaginary.isInteger
  }
}
