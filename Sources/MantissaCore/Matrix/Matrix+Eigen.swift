// Eigenvalues and eigenvectors of a matrix of numbers, as exact values.
//
// The eigenvalues are the roots of the characteristic polynomial `det(A − λI)`, which the equation solver finds in closed form
// when there is one (every root of a quadratic, whole or fractional roots of higher degree, `x³ = 2`). A matrix whose
// characteristic polynomial has roots that are only known as decimals has no exact eigenvalues here.

extension Matrix {
  /// The letter standing for λ while the characteristic polynomial is worked out. It cannot be typed.
  private static let lambda = "λ#"

  /// The largest matrix whose eigenvalues are looked for: the characteristic polynomial is a determinant with a letter in it.
  private static let eigenLimit = 5

  /// The eigenvalues, each as many times as it is a root of the characteristic polynomial; the real ones first, smallest first,
  /// and then the others.
  public func eigenvalues() throws(MathError) -> [Expr] {
    guard isSquare else { throw .dimensionMismatch }
    guard freeSymbols.isEmpty, rowCount <= Matrix.eigenLimit else { throw .unsupported }
    let size = rowCount
    if size == 1 { return [entries[0]] }

    let shifted = try Matrix.generated(rows: size, columns: size) { row, column throws(MathError) in
      row == column ? self[row, column] - .symbol(Matrix.lambda) : self[row, column]
    }
    let polynomial = try shifted.determinant()
    guard let solved = EquationSolver.solve(polynomial, for: Matrix.lambda), case .values(_, let roots) = solved
    else { throw .unsupported }

    var values: [Expr] = []
    for root in roots {
      guard let exact = root.exact else { throw .unsupported }  // a root known only as a decimal
      // How many times it is a root: as long as the polynomial and its derivatives vanish there.
      var multiplicity = 0
      var derivative = polynomial
      while multiplicity < size, let value = derivative.substituting(Matrix.lambda, with: exact)?.expanded(),
        value.isZeroEntry
      {
        multiplicity += 1
        derivative = try derivative.derivative(Matrix.lambda)
      }
      values += Array(repeating: exact, count: max(multiplicity, 1))
    }
    guard values.count == size else { throw .unsupported }
    return values.sorted { Matrix.order($0) < Matrix.order($1) }
  }

  /// Where an eigenvalue sorts: real numbers by size, then the rest by real part and imaginary part.
  private static func order(_ value: Expr) -> (Double, Double, Double) {
    if let real = try? value.approximation(precision: 20) { return (0, real.doubleValue, 0) }
    if let complex = try? value.complexApproximation(precision: 20) {
      return (1, complex.real.doubleValue, complex.imaginary.doubleValue)
    }
    return (2, 0, 0)
  }

  /// A matrix whose columns are independent eigenvectors, in the order of `eigenvalues()`: the same number of columns as the
  /// matrix has rows. A matrix that has too few (a defective one) is not worked out.
  public func eigenvectors() throws(MathError) -> Matrix {
    let values = try eigenvalues()
    let size = rowCount
    var columns: [[Expr]] = []
    var index = 0
    while index < values.count {
      let value = values[index]
      var multiplicity = 1
      while index + multiplicity < values.count, values[index + multiplicity] == value { multiplicity += 1 }
      let shifted = try Matrix.generated(rows: size, columns: size) { row, column throws(MathError) in
        row == column ? self[row, column] - value : self[row, column]
      }
      let basis = shifted.nullSpace()
      guard basis.count == multiplicity else { throw .unsupported }
      columns += basis.map { Matrix.cleared($0) }
      index += multiplicity
    }
    return try Matrix.generated(rows: size, columns: size) { row, column throws(MathError) in columns[column][row] }
  }

  /// A basis of the vectors `v` with `A·v = 0`, one for each column that has no pivot.
  func nullSpace() -> [[Expr]] {
    guard let (reduced, pivots) = try? Matrix.reduce(rows, pivotColumns: columnCount) else { return [] }
    var basis: [[Expr]] = []
    for free in 0..<columnCount where !pivots.contains(free) {
      var vector = [Expr](repeating: .zero, count: columnCount)
      vector[free] = .one
      for (row, pivot) in pivots.enumerated() { vector[pivot] = -reduced[row][free] }
      basis.append(vector)
    }
    return basis
  }

  /// A vector of fractions scaled to whole numbers with no common factor and a positive first entry (`(1/2, 1)` is `(1, 2)`);
  /// a vector with anything else in it is left as it is.
  private static func cleared(_ vector: [Expr]) -> [Expr] {
    let numbers = vector.compactMap(\.rational)
    guard numbers.count == vector.count else { return vector }
    var scale = BigInt(1)
    for number in numbers { scale = scale / BigInt.gcd(scale, number.denominator) * number.denominator }
    var whole = numbers.map { $0.numerator * (scale / $0.denominator) }
    var divisor = BigInt(0)
    for entry in whole { divisor = BigInt.gcd(divisor, entry) }
    if divisor.isZero { return vector }
    whole = whole.map { $0 / divisor }
    if let first = whole.first(where: { !$0.isZero }), first.isNegative { whole = whole.map { -$0 } }
    return whole.map { .number(Rational($0)) }
  }
}
