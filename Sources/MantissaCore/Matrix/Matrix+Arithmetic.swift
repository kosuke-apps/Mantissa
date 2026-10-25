// Adding, scaling, multiplying and raising to a power. Every entry is multiplied out, so that equal matrices compare equal.

extension Matrix {
  public func adding(_ other: Matrix) throws(MathError) -> Matrix {
    guard rowCount == other.rowCount, columnCount == other.columnCount else { throw .dimensionMismatch }
    var result: [Expr] = []
    result.reserveCapacity(entries.count)
    for (a, b) in zip(entries, other.entries) { result.append((a + b).expanded()) }
    return Matrix(rowCount: rowCount, columnCount: columnCount, entries: result)
  }

  public func subtracting(_ other: Matrix) throws(MathError) -> Matrix {
    guard rowCount == other.rowCount, columnCount == other.columnCount else { throw .dimensionMismatch }
    var result: [Expr] = []
    result.reserveCapacity(entries.count)
    for (a, b) in zip(entries, other.entries) { result.append((a - b).expanded()) }
    return Matrix(rowCount: rowCount, columnCount: columnCount, entries: result)
  }

  public func negated() -> Matrix {
    Matrix(rowCount: rowCount, columnCount: columnCount, entries: entries.map { -$0 })
  }

  /// Every entry times `factor`.
  public func scaled(by factor: Expr) throws(MathError) -> Matrix {
    let result = Matrix(
      rowCount: rowCount, columnCount: columnCount, entries: entries.map { ($0 * factor).expanded() })
    guard result.weight <= Matrix.weightLimit else { throw .overflow }
    return result
  }

  /// Every entry divided by `divisor`.
  public func divided(by divisor: Expr) throws(MathError) -> Matrix {
    if divisor.isZeroEntry { throw .divisionByZero }
    return try scaled(by: Expr.one.divided(by: divisor))
  }

  /// The matrix product: an m×n times an n×p is an m×p.
  public func multiplied(by other: Matrix) throws(MathError) -> Matrix {
    guard columnCount == other.rowCount else { throw .dimensionMismatch }
    let result = try Matrix.generated(rows: rowCount, columns: other.columnCount) { row, column throws(MathError) in
      var terms: [Expr] = []
      terms.reserveCapacity(columnCount)
      for k in 0..<columnCount { terms.append(self[row, k] * other[k, column]) }
      return Expr.makeSum(terms).expanded()
    }
    guard result.weight <= Matrix.weightLimit else { throw .overflow }
    return result
  }

  public func transposed() -> Matrix {
    // Building from known sizes cannot fail.
    (try? Matrix.generated(rows: columnCount, columns: rowCount) { row, column in self[column, row] })!
  }

  /// The sum of the diagonal.
  public func trace() throws(MathError) -> Expr {
    guard isSquare else { throw .dimensionMismatch }
    return Expr.makeSum((0..<rowCount).map { self[$0, $0] }).expanded()
  }

  /// This matrix to a whole-number power. A negative one is a power of the inverse; the zeroth is the identity.
  public func raised(to exponent: Int) throws(MathError) -> Matrix {
    guard isSquare else { throw .dimensionMismatch }
    // Repeated squaring takes a handful of products, but the entries of a symbolic matrix grow with each, so those are
    // held to a modest power.
    guard abs(exponent) <= (freeSymbols.isEmpty ? 1000 : 16) else { throw .overflow }
    var base = exponent < 0 ? try inverse() : self
    var remaining = abs(exponent)
    var result = Matrix.identity(rowCount)
    var isIdentity = true
    while remaining > 0 {
      if remaining & 1 == 1 {
        result = isIdentity ? base : try result.multiplied(by: base)
        isIdentity = false
      }
      remaining >>= 1
      if remaining > 0 { base = try base.multiplied(by: base) }
    }
    return result
  }
}

extension Expr {
  /// Whether an entry is zero: exactly, for a number, and for a value with no letters in it also when its decimal value is zero
  /// to many digits (a root that cancels in a way the canonical form has not seen).
  var isZeroEntry: Bool {
    if case .number(let value) = self { return value.isZero }
    return isZeroValue
  }
}
