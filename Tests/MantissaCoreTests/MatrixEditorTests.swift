import Testing

@testable import MantissaCore

@Suite("Matrices in the editor")
struct MatrixEditorTests {
  private func matrix(_ text: String) throws -> [[String]] {
    guard case .matrix(let matrix) = try Calculator().compute(text) else { return [] }
    return matrix.rows.map { $0.map(\.description) }
  }

  /// A 2×2 matrix typed the way the keys do it: a comma goes to the next cell and return to the next row.
  private func typedTwoByTwo() -> MathEditor {
    var editor = MathEditor()
    editor.insertMatrix(rows: 2, columns: 2)
    editor.type("1")
    editor.insert(",")
    editor.type("2")
    editor.newLine()
    editor.type("3")
    editor.insert(",")
    editor.type("4")
    return editor
  }

  @Test("A matrix is typed cell by cell and reads back as the matrix")
  func typing() throws {
    let editor = typedTwoByTwo()
    #expect(editor.isValid)
    #expect(editor.lines.count == 1, "return went to the next row and not to a new line")
    #expect(editor.text == "[[1,2],[3,4]]")
    #expect(try matrix(editor.text) == [["1", "2"], ["3", "4"]])
    #expect(editor.isInMatrix)
  }

  @Test("An unfilled cell is an unfinished formula")
  func unfinished() {
    var editor = MathEditor()
    editor.insertMatrix(rows: 2, columns: 2)
    editor.type("1")
    #expect(throws: (any Error).self) { try Calculator().compute(editor.text) }
  }

  @Test("The arrows visit every cell in reading order and leave the matrix at the ends")
  func moving() {
    var editor = MathEditor()
    editor.insertMatrix(rows: 2, columns: 3)
    var slots: [Int] = []
    for _ in 0..<20 {
      if let step = editor.cursor.path.last { slots.append(step.slot) }
      let before = editor.cursor
      editor.moveRight()
      #expect(editor.isValid)
      if editor.cursor == before { break }
    }
    #expect(slots.starts(with: [0, 1, 2, 3, 4, 5]))
    #expect(editor.cursor.path.isEmpty, "after the last cell the cursor is outside the matrix")
    #expect(editor.isInMatrix == false)
    editor.moveLeft()
    #expect(editor.cursor.path.last?.slot == 5)
  }

  @Test("A comma and return only move inside a matrix, and stop at the last cell")
  func commaAndReturn() {
    var editor = MathEditor()
    editor.insertMatrix(rows: 1, columns: 2)
    editor.insert(",")
    editor.insert(",")  // already at the last cell: nothing happens
    editor.insert("5")
    editor.newLine()  // already in the last row
    #expect(editor.lines.count == 1)
    #expect(editor.text == "[[,5]]")
    // Outside a matrix they are what they always were.
    editor.moveRight()
    editor.insert(",")
    editor.newLine()
    #expect(editor.lines.count == 2)
  }

  @Test("A comma inside a function in a cell is still a comma")
  func commaInAFunction() throws {
    var editor = MathEditor()
    editor.insertMatrix(rows: 1, columns: 2)
    editor.insertFunction("max")
    editor.type("1")
    editor.insert(",")
    editor.type("3")
    editor.insert(")")
    editor.insert(",")
    editor.type("0")
    #expect(editor.text == "[[max(1,3),0]]")
    #expect(try matrix(editor.text) == [["3", "0"]])
  }

  @Test("A row or a column is added after the one the cursor is in, and the cursor stays in its cell")
  func adding() {
    var editor = typedTwoByTwo()
    editor.moveLeft()
    editor.moveLeft()  // the cell holding 3
    #expect(editor.cursor.path.last?.slot == 2)
    let did1 = editor.change(matrix: .addColumn)
    #expect(did1)
    #expect(editor.isValid)
    #expect(editor.cursor.path.last?.slot == 3, "still in the cell holding 3, which is now the fourth")
    editor.type("9")
    #expect(editor.text == "[[1,,2],[39,,4]]")
    editor.moveRight()  // into the new column
    editor.type("7")
    #expect(editor.text == "[[1,,2],[39,7,4]]")
    let did2 = editor.change(matrix: .addRow)
    #expect(did2)
    #expect(editor.isValid)
    #expect(editor.text == "[[1,,2],[39,7,4],[,,]]")
    #expect(editor.cursor.path.last?.slot == 4)
  }

  @Test("Removing a row or a column takes the cursor to the cell that takes its place")
  func removing() throws {
    var editor = MathEditor()
    editor.insertMatrix(rows: 3, columns: 2)
    for (index, digit) in "123456".enumerated() {
      editor.type(String(digit))
      if index < 5 { editor.moveRight() }
    }
    #expect(editor.text == "[[1,2],[3,4],[5,6]]")
    // The cursor is in the cell holding 6, in the last row: remove that row.
    let did3 = editor.change(matrix: .removeRow)
    #expect(did3)
    #expect(editor.isValid)
    #expect(editor.text == "[[1,2],[3,4]]")
    #expect(editor.cursor.path.last?.slot == 3, "the last row is now the second")
    let did4 = editor.change(matrix: .removeColumn)
    #expect(did4)
    #expect(editor.isValid)
    #expect(editor.text == "[[1],[3]]")
    // The last row or column cannot go.
    let did5 = editor.change(matrix: .removeColumn)
    #expect(did5 == false)
    let did6 = editor.change(matrix: .removeRow)
    #expect(did6)
    let did7 = editor.change(matrix: .removeRow)
    #expect(did7 == false)
    #expect(editor.text == "[[1]]")
  }

  @Test("A matrix can have no more than the largest size")
  func limits() {
    var editor = MathEditor()
    editor.insertMatrix(rows: 99, columns: 99)
    guard case .matrix(let rows, let columns, _)? = editor.lines[0].first else {
      Issue.record("no matrix")
      return
    }
    #expect(rows == Matrix.maxDimension && columns == Matrix.maxDimension)
    let did8 = editor.change(matrix: .addRow)
    #expect(did8 == false)
    let did9 = editor.change(matrix: .addColumn)
    #expect(did9 == false)
    #expect(editor.isValid)
  }

  @Test("Row and column keys act on the innermost matrix, and do nothing outside one")
  func innermost() {
    var editor = MathEditor()
    let did10 = editor.change(matrix: .addRow)
    #expect(did10 == false)
    editor.insertMatrix(rows: 1, columns: 1)
    editor.insertFraction()  // a fraction inside the cell
    editor.type("5")
    #expect(editor.isInMatrix)
    let did11 = editor.change(matrix: .addRow)
    #expect(did11, "from inside the fraction in the cell")
    #expect(editor.isValid)
    guard case .matrix(let rows, _, _)? = editor.lines[0].first else {
      Issue.record("no matrix")
      return
    }
    #expect(rows == 2)
  }

  @Test("Backspace removes an empty matrix, and steps back through one with something in it")
  func deleting() {
    var empty = MathEditor()
    empty.insertMatrix(rows: 2, columns: 2)
    empty.backspace()
    #expect(empty.lines == [[]])
    #expect(empty.isValid)

    var editor = typedTwoByTwo()
    editor.moveLeft()  // to the start of the last cell
    editor.backspace()  // at the start of a cell: back to the one before, deleting nothing
    #expect(editor.isValid)
    #expect(editor.text == "[[1,2],[3,4]]")
    #expect(editor.cursor.path.last?.slot == 2)
  }

  @Test("A matrix answer is typeset as a matrix that reads back")
  func typesetting() throws {
    guard case .matrix(let result) = try Calculator().compute("[[1,2],[3,4]]^(-1)") else {
      Issue.record("no matrix")
      return
    }
    let nodes = Typesetter.nodes(for: result)
    // Read back, the text is the same matrix.
    #expect(try matrix(nodes.parserText) == [["-2", "1"], ["3/2", "-1/2"]])
    #expect(nodes.plainText == "[[−2, 1], [3/2, −1/2]]")
  }

  @Test("A matrix written as text can be pasted into the editor and edited")
  func pasting() throws {
    var editor = MathEditor()
    let pasted = editor.paste("[[1,2],[3,4]]*2")
    #expect(pasted)
    #expect(editor.isValid)
    guard case .matrix(let rows, let columns, let cells)? = editor.lines[0].first else {
      Issue.record("not pasted as a matrix")
      return
    }
    #expect(rows == 2 && columns == 2 && cells.count == 4)
    #expect(try matrix(editor.text) == [["2", "4"], ["6", "8"]])
  }
}
