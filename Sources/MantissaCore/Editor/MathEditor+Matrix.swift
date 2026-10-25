// Matrices in the editor: placing one, adding and removing rows and columns, and moving between the cells.

extension MathEditor {
  /// A change to the matrix the cursor is in.
  public enum MatrixChange: Sendable {
    /// A row after the one the cursor is in.
    case addRow
    /// A column after the one the cursor is in.
    case addColumn
    /// The row the cursor is in, which the cursor leaves for the one that takes its place.
    case removeRow
    /// The column the cursor is in, likewise.
    case removeColumn
  }

  /// A matrix with empty cells, with the cursor in the first. A vector is a matrix with one column.
  public mutating func insertMatrix(rows: Int, columns: Int) {
    let rows = min(max(rows, 1), Matrix.maxDimension)
    let columns = min(max(columns, 1), Matrix.maxDimension)
    insertStructure(.matrix(rows: rows, columns: columns, cells: Array(repeating: [], count: rows * columns)))
  }

  /// The innermost matrix the cursor is in: where its step is in the cursor's path, its size, and the cell the cursor is in.
  private var enclosingMatrix: (position: Int, rows: Int, columns: Int, row: Int, column: Int)? {
    var sequence = lines[cursor.line]
    var found: (Int, Int, Int, Int, Int)?
    for (position, step) in cursor.path.enumerated() {
      let node = sequence[step.index]
      if case .matrix(let rows, let columns, _) = node {
        found = (position, rows, columns, step.slot / columns, step.slot % columns)
      }
      sequence = node.slot(step.slot)
    }
    return found
  }

  /// Whether the cursor is in a matrix, at any depth.
  public var isInMatrix: Bool { enclosingMatrix != nil }

  /// Adds or removes a row or a column of the matrix the cursor is in. Returns false, and changes nothing, when the cursor is
  /// in no matrix or the matrix is as large (or as small) as it can be.
  @discardableResult
  public mutating func change(matrix change: MatrixChange) -> Bool {
    guard let (position, rows, columns, row, column) = enclosingMatrix else { return false }
    let step = cursor.path[position]
    let parent = Array(cursor.path[0..<position])
    guard case .matrix(_, _, var cells) = Self.sequence(in: lines[cursor.line], path: parent[...])[step.index] else {
      return false
    }

    var newRows = rows
    var newColumns = columns
    var slot = step.slot
    var leavesCell = false
    switch change {
    case .addRow:
      guard rows < Matrix.maxDimension else { return false }
      cells.insert(contentsOf: Array(repeating: [], count: columns), at: (row + 1) * columns)
      newRows += 1
    case .addColumn:
      guard columns < Matrix.maxDimension else { return false }
      for line in (0..<rows).reversed() { cells.insert([], at: line * columns + column + 1) }
      newColumns += 1
      slot = row * newColumns + column
    case .removeRow:
      guard rows > 1 else { return false }
      cells.removeSubrange(row * columns..<(row + 1) * columns)
      newRows -= 1
      slot = min(row, newRows - 1) * columns + column
      leavesCell = true
    case .removeColumn:
      guard columns > 1 else { return false }
      for line in (0..<rows).reversed() { cells.remove(at: line * columns + column) }
      newColumns -= 1
      slot = row * newColumns + min(column, newColumns - 1)
      leavesCell = true
    }

    let changed = MathNode.matrix(rows: newRows, columns: newColumns, cells: cells)
    Self.update(&lines[cursor.line], path: parent[...]) { sequence in sequence[step.index] = changed }
    cursor.path[position].slot = slot
    if leavesCell {
      // What was in the cell the cursor was in has gone with it.
      cursor.path.removeSubrange((position + 1)...)
      cursor.offset = 0
    }
    return true
  }

  /// When the cursor is directly in a cell of a matrix: the matrix's size and the cell the cursor is in.
  private var cellOfMatrix: (rows: Int, columns: Int, slot: Int)? {
    guard let step = cursor.path.last, case .matrix(let rows, let columns, _)? = container else { return nil }
    return (rows, columns, step.slot)
  }

  /// In a cell of a matrix, moves to the start of the next cell, along the row and on to the next. At the last cell it stays,
  /// so that a stray comma does not do anything. Returns whether the cursor was in a cell.
  mutating func goToNextCell() -> Bool {
    guard let (rows, columns, slot) = cellOfMatrix else { return false }
    if slot + 1 < rows * columns {
      cursor.path[cursor.path.count - 1].slot += 1
      cursor.offset = 0
    }
    return true
  }

  /// In a cell of a matrix, moves to the start of the first cell of the next row; in the last row it stays. Returns whether the
  /// cursor was in a cell.
  mutating func goToNextRow() -> Bool {
    guard let (rows, columns, slot) = cellOfMatrix else { return false }
    let row = slot / columns
    if row + 1 < rows {
      cursor.path[cursor.path.count - 1].slot = (row + 1) * columns
      cursor.offset = 0
    }
    return true
  }
}
