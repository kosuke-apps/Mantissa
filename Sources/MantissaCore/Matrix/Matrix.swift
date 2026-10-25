/// A rectangular array of exact expressions: a matrix, or a vector when it has a single column (or a single row).
///
/// The entries are `Expr`s kept expanded, so that equal matrices are `==`. Everything here is exact: a matrix of fractions has
/// an inverse of fractions, one with `√2` in it an inverse with `√2` in it, and one with letters keeps them.
public struct Matrix: Hashable, Sendable {
  /// The most rows or columns a matrix can have. A larger one is not something to read on a phone, and the work grows with
  /// the cube of the size.
  public static let maxDimension = 10

  public let rowCount: Int
  public let columnCount: Int
  /// The entries, row by row.
  public let entries: [Expr]

  /// A matrix of these rows, or `nil` when there are none, they have different lengths, or the matrix is larger than
  /// `maxDimension`.
  public init?(rows: [[Expr]]) {
    guard let first = rows.first, !first.isEmpty, rows.count <= Matrix.maxDimension,
      first.count <= Matrix.maxDimension, rows.allSatisfy({ $0.count == first.count })
    else { return nil }
    self.init(rowCount: rows.count, columnCount: first.count, entries: rows.flatMap { $0 })
  }

  init(rowCount: Int, columnCount: Int, entries: [Expr]) {
    precondition(rowCount > 0 && columnCount > 0 && entries.count == rowCount * columnCount)
    self.rowCount = rowCount
    self.columnCount = columnCount
    self.entries = entries
  }

  public subscript(row: Int, column: Int) -> Expr { entries[row * columnCount + column] }

  public func row(_ index: Int) -> [Expr] { Array(entries[index * columnCount..<(index + 1) * columnCount]) }

  public var rows: [[Expr]] { (0..<rowCount).map(row) }

  public var isSquare: Bool { rowCount == columnCount }

  /// A single column or a single row.
  public var isVector: Bool { rowCount == 1 || columnCount == 1 }

  /// The names of the letters in the entries.
  public var freeSymbols: Set<String> { entries.reduce(into: Set<String>()) { $0.formUnion($1.freeSymbols) } }

  /// The identity matrix of size `size`, which must be between 1 and `maxDimension`.
  public static func identity(_ size: Int) -> Matrix {
    var entries = [Expr](repeating: .zero, count: size * size)
    for index in 0..<size { entries[index * size + index] = .one }
    return Matrix(rowCount: size, columnCount: size, entries: entries)
  }

  /// A matrix whose entry at each place is `body(row, column)`.
  static func generated(
    rows: Int, columns: Int, _ body: (Int, Int) throws(MathError) -> Expr
  ) throws(MathError) -> Matrix {
    var entries: [Expr] = []
    entries.reserveCapacity(rows * columns)
    for row in 0..<rows { for column in 0..<columns { entries.append(try body(row, column)) } }
    return Matrix(rowCount: rows, columnCount: columns, entries: entries)
  }

  /// The matrix with `transform` applied to every entry.
  func mapped<Failure: Error>(_ transform: (Expr) throws(Failure) -> Expr) throws(Failure) -> Matrix {
    var result: [Expr] = []
    result.reserveCapacity(entries.count)
    for entry in entries { result.append(try transform(entry)) }
    return Matrix(rowCount: rowCount, columnCount: columnCount, entries: result)
  }

  /// A rough measure of how large the entries are together, so that a calculation that would grow without bound is stopped.
  var weight: Int { entries.reduce(0) { $0 + $1.nodeCount } }

  /// The most that the entries may weigh before a result is given up as too large.
  static let weightLimit = 100_000

  /// The decimal value of every entry to `precision` significant digits, or `nil` when some entry is not a real number or has a
  /// letter in it.
  public func approximations(precision: Int) -> [BigDecimal]? {
    var values: [BigDecimal] = []
    for entry in entries {
      guard entry.freeSymbols.isEmpty, !entry.containsInfinity,
        let value = try? entry.approximation(precision: precision)
      else { return nil }
      values.append(value)
    }
    return values
  }
}
