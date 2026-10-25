// Determinant, inverse, rank and the reduced row echelon form.
//
// A matrix of numbers (fractions, roots, π, i) is reduced by Gauss–Jordan elimination, where an entry counts as zero when
// it is zero exactly or to many digits. A matrix with letters in it has no way to say which pivot might be zero, so its
// determinant is written out by cofactors, which divides by nothing, and its inverse is the adjugate over the determinant;
// its rank and echelon form are not worked out.

extension Matrix {
  /// The largest size whose determinant is written out by cofactors when it has letters in it (6! = 720 products).
  private static let cofactorLimit = 6
  /// The largest size whose inverse is written out through the adjugate when it has letters in it.
  private static let adjugateLimit = 4

  // MARK: Determinant

  public func determinant() throws(MathError) -> Expr {
    guard isSquare else { throw .dimensionMismatch }
    let size = rowCount
    if size <= 3 || !freeSymbols.isEmpty {
      guard size <= Matrix.cofactorLimit else { throw .unsupported }
      return Matrix.cofactors(rows)
    }
    // Elimination without back-substitution: the determinant is the product of the pivots, up to the sign of the swaps.
    var rows = self.rows
    var result = Expr.one
    var sign = 1
    for column in 0..<size {
      guard let found = (column..<size).first(where: { !rows[$0][column].isZeroEntry }) else { return .zero }
      if found != column {
        rows.swapAt(found, column)
        sign = -sign
      }
      let pivot = rows[column][column]
      result = (result * pivot).expanded()
      for other in (column + 1)..<size where !rows[other][column].isZeroEntry {
        let factor = try rows[other][column].divided(by: pivot)
        for k in column..<size { rows[other][k] = (rows[other][k] - factor * rows[column][k]).expanded() }
      }
      guard result.nodeCount <= Matrix.weightLimit else { throw .overflow }
    }
    return sign == 1 ? result : (-result).expanded()
  }

  /// The determinant written out by expanding along the row with the most zeros, which divides by nothing.
  private static func cofactors(_ rows: [[Expr]]) -> Expr {
    let size = rows.count
    if size == 1 { return rows[0][0] }
    if size == 2 { return (rows[0][0] * rows[1][1] - rows[0][1] * rows[1][0]).expanded() }
    let along = rows.indices.max { rows[$0].filter(\.isZero).count < rows[$1].filter(\.isZero).count }!
    var terms: [Expr] = []
    for column in 0..<size where !rows[along][column].isZero {
      let term = rows[along][column] * cofactors(minor(rows, removingRow: along, column: column))
      terms.append((along + column) % 2 == 0 ? term : -term)
    }
    return Expr.makeSum(terms).expanded()
  }

  private static func minor(_ rows: [[Expr]], removingRow row: Int, column: Int) -> [[Expr]] {
    rows.enumerated().filter { $0.offset != row }.map { line in
      line.element.enumerated().filter { $0.offset != column }.map(\.element)
    }
  }

  // MARK: Inverse

  public func inverse() throws(MathError) -> Matrix {
    guard isSquare else { throw .dimensionMismatch }
    let size = rowCount
    if freeSymbols.isEmpty {
      // Reduce the matrix with the identity beside it: what the matrix becomes the identity, the identity becomes the inverse.
      let augmented = rows.enumerated().map { $0.element + Matrix.identity(size).row($0.offset) }
      let (reduced, pivots) = try Matrix.reduce(augmented, pivotColumns: size)
      guard pivots.count == size else { throw .singular }
      return Matrix(rowCount: size, columnCount: size, entries: reduced.flatMap { Array($0[size...]) })
    }
    guard size <= Matrix.adjugateLimit else { throw .unsupported }
    if size == 1 { return Matrix(scalar: try Expr.one.divided(by: entries[0])) }
    let determinant = try self.determinant()
    if determinant.isZero { throw .singular }
    let rows = self.rows
    // Entry (i, j) of the inverse is the cofactor of entry (j, i) over the determinant.
    return try Matrix.generated(rows: size, columns: size) { i, j throws(MathError) in
      let cofactor = Matrix.cofactors(Matrix.minor(rows, removingRow: j, column: i))
      return try ((i + j) % 2 == 0 ? cofactor : -cofactor).divided(by: determinant)
    }
  }

  // MARK: Rank and echelon form

  /// The reduced row echelon form: each row starts with a 1 that is the only nonzero entry of its column.
  public func reducedRowEchelonForm() throws(MathError) -> Matrix {
    guard freeSymbols.isEmpty else { throw .unsupported }
    let (reduced, _) = try Matrix.reduce(rows, pivotColumns: columnCount)
    return Matrix(rowCount: rowCount, columnCount: columnCount, entries: reduced.flatMap { $0 })
  }

  public func rank() throws(MathError) -> Int {
    guard freeSymbols.isEmpty else { throw .unsupported }
    return try Matrix.reduce(rows, pivotColumns: columnCount).pivots.count
  }

  /// Gauss–Jordan elimination of `rows`, looking for pivots in the first `pivotColumns` columns only (the others are carried
  /// along, as the identity is when finding an inverse). Returns the reduced rows and the columns the pivots are in.
  static func reduce(
    _ input: [[Expr]], pivotColumns: Int
  ) throws(MathError) -> (rows: [[Expr]], pivots: [Int]) {
    var rows = input
    let width = rows[0].count
    var pivots: [Int] = []
    var row = 0
    for column in 0..<pivotColumns where row < rows.count {
      guard let found = (row..<rows.count).first(where: { !rows[$0][column].isZeroEntry }) else { continue }
      rows.swapAt(row, found)
      let pivot = rows[row][column]
      for k in 0..<width { rows[row][k] = try rows[row][k].divided(by: pivot).expanded() }
      for other in rows.indices where other != row && !rows[other][column].isZeroEntry {
        let factor = rows[other][column]
        for k in 0..<width { rows[other][k] = (rows[other][k] - factor * rows[row][k]).expanded() }
      }
      pivots.append(column)
      row += 1
      guard rows.reduce(0, { $0 + $1.reduce(0) { $0 + $1.nodeCount } }) <= weightLimit else { throw .overflow }
    }
    // An entry that is zero to many digits but not in the canonical form is written as the zero it is.
    for r in rows.indices { for k in 0..<width where rows[r][k].isZeroEntry { rows[r][k] = .zero } }
    return (rows, pivots)
  }
}
