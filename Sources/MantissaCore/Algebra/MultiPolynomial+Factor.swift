// Factoring polynomials in several unknowns. The methods are the ones that textbook problems need: what every term shares,
// squares and repeated factors, quadratics whose discriminant is a perfect square (a² − b², a² + 2ab + b², x² + xy − 2y²),
// linear factors found from the divisors of the first and last coefficient, and homogeneous polynomials of two unknowns
// (a³ + b³, x⁴ + x²y² + y⁴). A polynomial none of them splits is left whole, which is still a correct factorization.

extension MultiPolynomial {
  /// `self = coefficient · Π baseᵖᵒʷᵉʳ`, each base with whole-number coefficients and a positive leading coefficient.
  func factored() -> (coefficient: Rational, factors: [(base: MultiPolynomial, power: Int)]) {
    let (coefficient, squarefree) = squarefreeDecomposition()
    var number = coefficient
    var result: [(base: MultiPolynomial, power: Int)] = []
    for (base, power) in squarefree {
      let (scale, pieces) = base.split()
      number *= scale.power(power)
      for piece in pieces {
        if let existing = result.firstIndex(where: { $0.base == piece }) {
          result[existing].power += power
        } else {
          result.append((piece, power))
        }
      }
    }
    return (number, result)
  }

  /// A squarefree polynomial as a number times irreducible factors, as far as the methods here go.
  func split() -> (coefficient: Rational, pieces: [MultiPolynomial]) {
    var work = [normalized]
    var done: [MultiPolynomial] = []
    var steps = 0
    while let piece = work.popLast() {
      steps += 1
      if steps > 200 || ring.isExhausted { return (Rational(1), [normalized]) }
      if let (first, second) = piece.findSplit() {
        work.append(second.normalized)
        work.append(first.normalized)
      } else {
        done.append(piece)
      }
    }
    var product = one
    for piece in done { product = product * piece }
    guard let ratio = dividedExactly(by: product), let number = ratio.constantValue, !number.isZero else {
      return (Rational(1), [normalized])
    }
    return (number, done)
  }

  private var variableIndices: [Int] { names.indices.filter { degree(in: $0) > 0 } }

  /// Two polynomials whose product is this one, both of lower degree; `nil` when no method here finds a split.
  private func findSplit() -> (MultiPolynomial, MultiPolynomial)? {
    guard totalDegree >= 2 else { return nil }
    func divided(by factor: MultiPolynomial) -> (MultiPolynomial, MultiPolynomial)? {
      guard let rest = dividedExactly(by: factor), !factor.isConstant, !rest.isConstant else { return nil }
      return (factor, rest)
    }

    // An unknown in every term.
    for index in names.indices where terms.keys.allSatisfy({ $0[index] > 0 }) {
      if let split = divided(by: .variable(index, ring: ring)) { return split }
    }
    let present = variableIndices
    // A polynomial in the other unknowns that every term shares.
    for index in present {
      let shared = content(in: index)
      if !shared.isConstant, let split = divided(by: shared) { return split }
    }

    if present.count == 1 { return univariateSplit(in: present[0]) }
    for index in present where degree(in: index) == 2 {
      if let split = quadraticSplit(in: index) { return split }
    }
    for index in present where degree(in: index) >= 3 {
      if let split = linearFactorSplit(in: index) { return split }
    }
    if present.count == 2, let split = homogeneousSplit(present[0], present[1]) { return split }
    return nil
  }

  private func univariateSplit(in index: Int) -> (MultiPolynomial, MultiPolynomial)? {
    let polynomial = RationalPolynomial(coefficients(in: index).map { $0.constantValue ?? Rational(0) })
    let factors = polynomial.irreducibleFactors()
    guard factors.count >= 2 else { return nil }
    let first = MultiPolynomial.assemble(
      factors[0].coefficients.map { .constant($0, ring: ring) }, in: index, ring: ring)
    guard let rest = dividedExactly(by: first) else { return nil }
    return (first, rest)
  }

  /// `a·x² + b·x + c` in the unknown at `index`, with a, b and c polynomials in the others, is a product of two linear
  /// factors when `b² − 4ac` is the square of a polynomial `s`: the roots are `(−b ± s)/(2a)`.
  private func quadraticSplit(in index: Int) -> (MultiPolynomial, MultiPolynomial)? {
    let parts = coefficients(in: index)
    guard parts.count == 3 else { return nil }
    let (c, b, a) = (parts[0], parts[1], parts[2])
    let discriminant = b * b - a * c.scaled(by: Rational(4))
    guard let root = discriminant.exactSquareRoot() else { return nil }
    let twiceA = a.scaled(by: Rational(2))
    let variable = MultiPolynomial.variable(index, ring: ring)
    let first = (twiceA * variable + b + root).primitivePart(in: index).normalized
    guard !first.isConstant, let rest = dividedExactly(by: first), !rest.isConstant else { return nil }
    return (first, rest)
  }

  /// A linear factor `p·x − q`, where `p` divides the coefficient of the highest power of the unknown at `index` and `q` the
  /// one of the lowest: the rational root theorem, with polynomials in the other unknowns in place of whole numbers.
  private func linearFactorSplit(in index: Int) -> (MultiPolynomial, MultiPolynomial)? {
    let parts = coefficients(in: index)
    guard let lead = parts.last, !parts[0].isZero else { return nil }
    guard let leadDivisors = lead.divisorsForSearch(), let constantDivisors = parts[0].divisorsForSearch(),
      leadDivisors.count * constantDivisors.count <= 3000
    else { return nil }
    let variable = MultiPolynomial.variable(index, ring: ring)
    for p in leadDivisors {
      for q in constantDivisors {
        for sign in [1, -1] {
          let candidate = (p * variable + q.scaled(by: Rational(sign))).normalized
          if let rest = dividedExactly(by: candidate), !rest.isConstant { return (candidate, rest) }
        }
      }
    }
    return nil
  }

  /// Every positive divisor of a polynomial's content times any product of its irreducible factors; `nil` when there would be
  /// too many or the content cannot be factored.
  private func divisorsForSearch() -> [MultiPolynomial]? {
    let (coefficient, factors) = factored()
    guard let numbers = RationalPolynomial.divisors(of: coefficient.numerator.magnitude) else { return nil }
    var divisors = numbers.map { MultiPolynomial.constant(Rational($0), ring: ring) }
    for (base, power) in factors {
      var next: [MultiPolynomial] = []
      var multiple = one
      for _ in 0...power {
        for divisor in divisors { next.append(divisor * multiple) }
        multiple = multiple * base
      }
      divisors = next
      if divisors.count > 400 { return nil }
    }
    return divisors
  }

  /// A polynomial of two unknowns whose terms all have the same degree is `yⁿ · h(x/y)`, and the factors of the polynomial `h`
  /// in one unknown give the factors of this one.
  private func homogeneousSplit(_ first: Int, _ second: Int) -> (MultiPolynomial, MultiPolynomial)? {
    let degree = totalDegree
    guard terms.keys.allSatisfy({ $0.reduce(0, +) == degree }) else { return nil }
    var coefficients = Array(repeating: Rational(0), count: degree + 1)
    for (monomial, coefficient) in terms { coefficients[monomial[first]] = coefficient }
    let factors = RationalPolynomial(coefficients).irreducibleFactors()
    guard factors.count >= 2 else { return nil }
    let factor = factors[0]
    var homogeneous: [Monomial: Rational] = [:]
    for power in 0...factor.degree {
      var monomial = Array(repeating: 0, count: names.count)
      monomial[first] = power
      monomial[second] = factor.degree - power
      homogeneous[monomial] = factor[power]
    }
    let candidate = MultiPolynomial(ring: ring, terms: homogeneous).normalized
    guard let rest = dividedExactly(by: candidate), !rest.isConstant else { return nil }
    return (candidate, rest)
  }
}
