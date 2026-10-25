// Vectors: a matrix with a single column or a single row.

extension Matrix {
  /// The dot product `a₁b₁ + a₂b₂ + …` of two vectors with the same number of entries, whichever way each is written.
  public func dot(_ other: Matrix) throws(MathError) -> Expr {
    guard isVector, other.isVector, entries.count == other.entries.count else { throw .dimensionMismatch }
    var terms: [Expr] = []
    for (a, b) in zip(entries, other.entries) { terms.append(a * b) }
    return Expr.makeSum(terms).expanded()
  }

  /// The cross product of two vectors of three entries, written the way the first is.
  public func cross(_ other: Matrix) throws(MathError) -> Matrix {
    guard isVector, other.isVector, entries.count == 3, other.entries.count == 3 else { throw .dimensionMismatch }
    let a = entries
    let b = other.entries
    let result = [
      (a[1] * b[2] - a[2] * b[1]).expanded(),
      (a[2] * b[0] - a[0] * b[2]).expanded(),
      (a[0] * b[1] - a[1] * b[0]).expanded(),
    ]
    return Matrix(rowCount: rowCount, columnCount: columnCount, entries: result)
  }

  /// The length of a vector, `√(|a₁|² + |a₂|² + …)`.
  public func norm() throws(MathError) -> Expr {
    guard isVector else { throw .dimensionMismatch }
    var terms: [Expr] = []
    for entry in entries {
      let size = try Expr.apply(.abs, [entry])
      terms.append(try size.raised(to: .integer(2)))
    }
    return try Expr.makeSum(terms).expanded().raised(to: .fraction(1, 2))
  }
}
