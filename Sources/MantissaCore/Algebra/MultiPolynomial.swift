// A polynomial in several unknowns with rational coefficients, for the operations that need more than one unknown at a time:
// cancelling a fraction, factoring, and recognising a perfect square.

/// The unknowns of a family of polynomials, and how much work may still be spent on them. Cancelling and factoring are run
/// while a person types, so they give up, rather than go on for long, on a polynomial that turns out to be hard: every
/// operation is charged, and once the budget is gone the operations stop working and `isExhausted` tells the caller to
/// discard whatever came out.
final class PolynomialRing: @unchecked Sendable {
  let names: [String]
  private let budget: Int
  private var remaining: Int

  init(names: [String], budget: Int) {
    self.names = names
    self.budget = budget
    remaining = budget
  }

  var isExhausted: Bool { remaining < 0 }
  /// How much of the budget has been spent.
  var spent: Int { budget - remaining }

  func charge(_ cost: Int) { remaining -= cost }
}

struct MultiPolynomial: Equatable, Sendable {
  /// The exponent of each unknown, in the order of `ring.names`.
  typealias Monomial = [Int]

  let ring: PolynomialRing
  var names: [String] { ring.names }
  /// Only the terms whose coefficient is not zero.
  private(set) var terms: [Monomial: Rational]

  init(ring: PolynomialRing, terms: [Monomial: Rational] = [:]) {
    self.ring = ring
    self.terms = terms.filter { !$0.value.isZero }
  }

  static func == (lhs: MultiPolynomial, rhs: MultiPolynomial) -> Bool {
    lhs.ring.names == rhs.ring.names && lhs.terms == rhs.terms
  }

  static func constant(_ value: Rational, ring: PolynomialRing) -> MultiPolynomial {
    MultiPolynomial(ring: ring, terms: [Array(repeating: 0, count: ring.names.count): value])
  }

  static func variable(_ index: Int, ring: PolynomialRing) -> MultiPolynomial {
    var monomial = Array(repeating: 0, count: ring.names.count)
    monomial[index] = 1
    return MultiPolynomial(ring: ring, terms: [monomial: Rational(1)])
  }

  var one: MultiPolynomial { .constant(Rational(1), ring: ring) }
  var zero: MultiPolynomial { MultiPolynomial(ring: ring) }

  var isZero: Bool { terms.isEmpty }
  var isConstant: Bool { terms.keys.allSatisfy { $0.allSatisfy { $0 == 0 } } }
  var constantValue: Rational? {
    guard isConstant else { return nil }
    return terms.values.first ?? Rational(0)
  }

  /// The highest power of the unknown at `index`.
  func degree(in index: Int) -> Int { terms.keys.map { $0[index] }.max() ?? 0 }
  var totalDegree: Int { terms.keys.map { $0.reduce(0, +) }.max() ?? 0 }

  /// The first monomial in lexicographic order of the exponents (the first unknown counts most).
  var leadingMonomial: Monomial? { terms.keys.max { $0.lexicographicallyPrecedes($1) } }
  var leadingCoefficient: Rational { leadingMonomial.flatMap { terms[$0] } ?? Rational(0) }

  /// The terms, leading one first.
  var sortedTerms: [(monomial: Monomial, coefficient: Rational)] {
    terms.sorted { $1.key.lexicographicallyPrecedes($0.key) }.map { ($0.key, $0.value) }
  }

  // MARK: Arithmetic

  /// The size of the largest coefficient in bits, which is what makes an operation on a polynomial slow once its coefficients
  /// have grown.
  private var coefficientBits: Int {
    terms.values.reduce(0) { max($0, $1.numerator.bitWidth + $1.denominator.bitWidth) }
  }

  /// What it costs to go through the terms of this polynomial and `other` once.
  private func cost(with other: MultiPolynomial, perPair: Bool) -> Int {
    let size = perPair ? terms.count * other.terms.count : terms.count + other.terms.count
    return size * (1 + (coefficientBits + other.coefficientBits) / 64)
  }

  static func + (a: MultiPolynomial, b: MultiPolynomial) -> MultiPolynomial {
    a.ring.charge(a.cost(with: b, perPair: false))
    if a.ring.isExhausted { return a.zero }
    var sum = a.terms
    for (monomial, coefficient) in b.terms { sum[monomial, default: Rational(0)] += coefficient }
    return MultiPolynomial(ring: a.ring, terms: sum)
  }

  static prefix func - (a: MultiPolynomial) -> MultiPolynomial {
    MultiPolynomial(ring: a.ring, terms: a.terms.mapValues { -$0 })
  }

  static func - (a: MultiPolynomial, b: MultiPolynomial) -> MultiPolynomial { a + (-b) }

  static func * (a: MultiPolynomial, b: MultiPolynomial) -> MultiPolynomial {
    a.ring.charge(a.cost(with: b, perPair: true))
    if a.ring.isExhausted { return a.zero }
    var product: [Monomial: Rational] = [:]
    for (left, leftCoefficient) in a.terms {
      for (right, rightCoefficient) in b.terms {
        var monomial = left
        for index in monomial.indices { monomial[index] += right[index] }
        product[monomial, default: Rational(0)] += leftCoefficient * rightCoefficient
      }
    }
    return MultiPolynomial(ring: a.ring, terms: product)
  }

  func scaled(by factor: Rational) -> MultiPolynomial {
    MultiPolynomial(ring: ring, terms: terms.mapValues { $0 * factor })
  }

  func multiplied(byVariable index: Int, power: Int) -> MultiPolynomial {
    var shifted: [Monomial: Rational] = [:]
    for (monomial, coefficient) in terms {
      var next = monomial
      next[index] += power
      shifted[next] = coefficient
    }
    return MultiPolynomial(ring: ring, terms: shifted)
  }

  func power(_ exponent: Int) -> MultiPolynomial {
    var result = one
    for _ in 0..<exponent { result = result * self }
    return result
  }

  /// `self / divisor` when it divides exactly; `nil` otherwise.
  func dividedExactly(by divisor: MultiPolynomial) -> MultiPolynomial? {
    guard let lead = divisor.leadingMonomial else { return nil }
    let leadCoefficient = divisor.terms[lead]!
    var remainder = self
    var quotient: [Monomial: Rational] = [:]
    var steps = 0
    while let top = remainder.leadingMonomial {
      steps += 1
      ring.charge(divisor.cost(with: remainder, perPair: false))
      if steps > 20_000 || ring.isExhausted { return nil }
      var shift = top
      for index in shift.indices {
        shift[index] -= lead[index]
        if shift[index] < 0 { return nil }
      }
      let factor = remainder.terms[top]! / leadCoefficient
      quotient[shift] = factor
      var step: [Monomial: Rational] = [:]
      for (monomial, coefficient) in divisor.terms {
        var next = monomial
        for index in next.indices { next[index] += shift[index] }
        step[next] = coefficient * factor
      }
      remainder = remainder - MultiPolynomial(ring: ring, terms: step)
    }
    return MultiPolynomial(ring: ring, terms: quotient)
  }

  func derivative(in index: Int) -> MultiPolynomial {
    var result: [Monomial: Rational] = [:]
    for (monomial, coefficient) in terms where monomial[index] > 0 {
      var next = monomial
      next[index] -= 1
      result[next] = coefficient * Rational(monomial[index])
    }
    return MultiPolynomial(ring: ring, terms: result)
  }

  // MARK: As a polynomial in one unknown

  /// The polynomial written in powers of the unknown at `index`: element `k` multiplies `x^k` and does not contain it.
  func coefficients(in index: Int) -> [MultiPolynomial] {
    guard !isZero else { return [] }
    ring.charge(terms.count)
    var parts = Array(repeating: [Monomial: Rational](), count: degree(in: index) + 1)
    for (monomial, coefficient) in terms {
      var rest = monomial
      let power = rest[index]
      rest[index] = 0
      parts[power][rest] = coefficient
    }
    return parts.map { MultiPolynomial(ring: ring, terms: $0) }
  }

  /// The coefficients in `x^k` put back together.
  static func assemble(_ coefficients: [MultiPolynomial], in index: Int, ring: PolynomialRing) -> MultiPolynomial {
    var result = MultiPolynomial(ring: ring)
    for (power, coefficient) in coefficients.enumerated() {
      result = result + coefficient.multiplied(byVariable: index, power: power)
    }
    return result
  }

  /// The polynomial with the unknown at `index` set to a number.
  func substituting(_ index: Int, with value: Rational) -> MultiPolynomial {
    var result: [Monomial: Rational] = [:]
    for (monomial, coefficient) in terms {
      var next = monomial
      let power = next[index]
      next[index] = 0
      result[next, default: Rational(0)] += coefficient * value.power(power)
    }
    return MultiPolynomial(ring: ring, terms: result)
  }

  // MARK: Scaling

  /// Whole-number coefficients with no common factor and a positive leading coefficient, and the number it was scaled by:
  /// `self = content × normalized`.
  var normalizedWithContent: (normalized: MultiPolynomial, content: Rational) {
    guard !isZero else { return (self, Rational(1)) }
    var multiple = BigInt(1)
    for coefficient in terms.values {
      multiple = multiple / BigInt.gcd(multiple, coefficient.denominator) * coefficient.denominator
    }
    var divisor = BigInt(0)
    for coefficient in terms.values {
      divisor = BigInt.gcd(divisor, (coefficient.numerator * (multiple / coefficient.denominator)).magnitude)
    }
    var scale = Rational(multiple, divisor)
    if leadingCoefficient.isNegative { scale = -scale }
    return (scaled(by: scale), scale.reciprocal)
  }

  var normalized: MultiPolynomial { normalizedWithContent.normalized }

  // MARK: Expressions

  /// The polynomial an expression is, or `nil` when it has anything but the unknowns of `ring`, whole non-negative powers of them
  /// and rational numbers in it.
  init?(_ expression: Expr, ring: PolynomialRing) {
    let names = ring.names
    let source = expression.expanded()
    let list: [Expr]
    if case .sum(let inner) = source { list = inner } else { list = [source] }
    var terms: [Monomial: Rational] = [:]
    for term in list {
      var coefficient = Rational(1)
      var exponents = Array(repeating: 0, count: names.count)
      let factors: [Expr]
      if case .product(let inner) = term { factors = inner } else { factors = [term] }
      for factor in factors {
        switch factor {
        case .number(let value): coefficient *= value
        case .symbol(let name):
          guard let index = names.firstIndex(of: name) else { return nil }
          exponents[index] += 1
        case .power(.symbol(let name), let exponent):
          guard let index = names.firstIndex(of: name), let n = exponent.rational, n.isInteger, n.signum > 0,
            let whole = n.numerator.asInt
          else { return nil }
          exponents[index] += whole
        default: return nil
        }
      }
      terms[exponents, default: Rational(0)] += coefficient
    }
    self.init(ring: ring, terms: terms)
  }

  /// The polynomial as an expression, highest term first.
  var expression: Expr {
    Expr.makeSum(
      sortedTerms.map { monomial, coefficient in
        var factors: [Expr] = [.number(coefficient)]
        for (index, exponent) in monomial.enumerated() where exponent > 0 {
          factors.append(Expr.makePower(.symbol(names[index]), .integer(exponent)))
        }
        return Expr.makeProduct(factors)
      })
  }
}
