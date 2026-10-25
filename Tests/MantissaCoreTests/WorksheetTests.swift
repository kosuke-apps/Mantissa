import Testing

@testable import MantissaCore

/// Lines that give letters their values. Each expectation was worked out by hand, and where it is an equation, by putting the
/// answer back into it.
@Suite("Worksheets of matrices")
struct WorksheetTests {
  /// What each line comes to, as `A = [[1, 2], [3, 4]]` (`name = value`) or just the value for an expression.
  private func worked(_ text: String) throws -> [String] {
    guard case .lines(let lines) = try Calculator().compute(text) else {
      Issue.record("\(text) is not a worksheet")
      return []
    }
    return lines.map { line in
      let value: String
      switch line.quantity {
      case .scalar(let number): value = Typesetter.nodes(for: number).plainText
      case .matrix(let matrix): value = Typesetter.nodes(for: matrix).plainText
      }
      return line.name.map { "\($0) = \(value)" } ?? value
    }
  }

  private func failure(_ text: String) -> CalculatorError? {
    do {
      _ = try Calculator().compute(text)
      return nil
    } catch { return error }
  }

  @Test("Every letter given a value is shown, with what it comes to")
  func definitions() throws {
    let lines = try worked(
      """
      A = [[1,2],[3,4]]
      B = [[0,1],[1,0]]
      C = A B
      """)
    // Multiplying by B swaps the columns: [[1·0+2·1, 1·1+2·0], [3·0+4·1, 3·1+4·0]].
    #expect(lines == ["A = [[1, 2], [3, 4]]", "B = [[0, 1], [1, 0]]", "C = [[2, 1], [4, 3]]"])
  }

  @Test("A letter given its value in numbers is marked as given, and one worked out is not")
  func givenValues() throws {
    guard case .lines(let lines) = try Calculator().compute("A = [[1,2],[-3,4]]\nB = -2\nC = A B\nD = [[1,2]]*3\nA C")
    else {
      Issue.record("not a worksheet")
      return
    }
    #expect(lines.map(\.isGiven) == [true, true, false, false, false])
  }

  @Test("A line with no equals sign is worked out with the values, and shown too")
  func expressionLines() throws {
    let lines = try worked(
      """
      A = [[1,2],[3,4]]
      B = [[0,1],[1,0]]
      A^2 B + A^(-1)
      det(A)
      """)
    // A² = [[7,10],[15,22]], A²B = [[10,7],[22,15]], A⁻¹ = [[−2,1],[3/2,−1/2]].
    #expect(lines[2] == "[[8, 8], [47/2, 29/2]]")
    #expect(lines[3] == "−2")
  }

  @Test("The lines may come in any order, and the answer is in the order written")
  func anyOrder() throws {
    let lines = try worked(
      """
      C = A B
      B = [[0,1],[1,0]]
      A = [[1,2],[3,4]]
      """)
    #expect(lines == ["C = [[2, 1], [4, 3]]", "B = [[0, 1], [1, 0]]", "A = [[1, 2], [3, 4]]"])
  }

  @Test("An unknown matrix is found by undoing what is done to it, on the right side of the product")
  func unknownMatrices() throws {
    let a = "A = [[1,2],[3,4]]\nB = [[5,6],[7,8]]\n"
    // A⁻¹ = [[−2,1],[3/2,−1/2]]; A⁻¹B = [[−3,−4],[4,5]], and A times that is B.
    #expect(try worked(a + "A X = B").last == "X = [[−3, −4], [4, 5]]")
    // B A⁻¹ = [[−1,2],[−2,3]], and that times A is B.
    #expect(try worked(a + "X A = B").last == "X = [[−1, 2], [−2, 3]]")
    // The unknown on the right of the equals sign works as well.
    #expect(try worked(a + "B = A X").last == "X = [[−3, −4], [4, 5]]")
  }

  @Test("Sums, differences, transposes, inverses and scalars around the unknown are undone")
  func aroundTheUnknown() throws {
    // C − B = [[3,3],[7,7]] = A·[[1,1],[1,1]].
    let sum = "A = [[1,2],[3,4]]\nB = [[1,0],[0,1]]\nC = [[4,3],[7,8]]\n"
    #expect(try worked(sum + "A X + B = C").last == "X = [[1, 1], [1, 1]]")
    #expect(try worked(sum + "B - X = C").last == "X = [[−3, −3], [−7, −7]]")
    #expect(try worked("A = [[1,2],[3,4]]\nX^T = A").last == "X = [[1, 3], [2, 4]]")
    #expect(try worked("A = [[1,2],[3,4]]\ninverse(X) = A").last == "X = [[−2, 1], [3/2, −1/2]]")
    #expect(try worked("A = [[1,2],[3,4]]\nX^(-1) = A").last == "X = [[−2, 1], [3/2, −1/2]]")
    #expect(try worked("A = [[1,2],[3,4]]\n-X = A").last == "X = [[−1, −2], [−3, −4]]")
    #expect(try worked("A = [[1,2],[3,4]]\n2 X = A").last == "X = [[1/2, 1], [3/2, 2]]")
    #expect(try worked("A = [[2,4],[6,8]]\nX/2 = A").last == "X = [[4, 8], [12, 16]]")
  }

  @Test("A letter whose value another line needs waits for it")
  func chains() throws {
    // X = A⁻¹B, then Y = X + A.
    let lines = try worked(
      """
      Y = X + A
      A X = B
      A = [[1,2],[3,4]]
      B = [[5,6],[7,8]]
      """)
    #expect(lines[0] == "Y = [[−2, −2], [7, 9]]")
    #expect(lines[1] == "X = [[−3, −4], [4, 5]]")
  }

  @Test("A number can be a letter too, and found from an equation")
  func scalars() throws {
    #expect(try worked("a = 2\nB = a [[1,2]]") == ["a = 2", "B = [[2, 4]]"])
    #expect(try worked("3 k = 12\nD = k [[1,1]]") == ["k = 4", "D = [[4, 4]]"])
    // The letter of an integral is not the number a letter of the same name stands for.
    let lines = try worked("x = 2\nM = [[1,2]]\nint(x^2, x)")
    #expect(lines[0] == "x = 2")
    guard case .lines(let all) = try Calculator().compute("x = 2\nM = [[1,2]]\nint(x^2, x)"),
      case .scalar(let integral) = all[2].quantity
    else {
      Issue.record("no integral")
      return
    }
    #expect(integral.substituting("x", with: 3) == 9)  // x³/3 at 3
  }

  @Test("What cannot be settled is left out, and nothing is guessed")
  func unsolved() throws {
    // B is not given, so A X = B says nothing about X.
    #expect(try worked("A = [[1,2],[3,4]]\nA X = B") == ["A = [[1, 2], [3, 4]]"])
    // X is squared, and a letter on both sides is not undone either.
    #expect(try worked("A = [[1,2],[3,4]]\nX^2 = A") == ["A = [[1, 2], [3, 4]]"])
    #expect(try worked("A = [[1,2],[3,4]]\nA X = X") == ["A = [[1, 2], [3, 4]]"])
    // Nothing settled at all.
    #expect(failure("A X = B") == .unsupported(.equation))
    // An inequality is not a definition.
    #expect(failure("A = [[1,2]]\nA < 3") == .unsupported(.equation))
  }

  @Test("A matrix with no inverse, or of the wrong size, is said so")
  func errors() {
    #expect(failure("A = [[1,2],[2,4]]\nA X = [[1],[1]]") == .math(.singular))
    #expect(failure("A = [[1,2],[3,4]]\nA X = [[1,2,3]]") == .math(.dimensionMismatch))
    #expect(failure("A = [[1,2],[3,4]]\nB = A + [[1,2,3]]") == .math(.dimensionMismatch))
  }

  @Test("The answer to a worksheet checks: every equation holds with the values found")
  func checks() throws {
    let text = "A = [[2,1],[1,3]]\nB = [[1,2],[3,4]]\nC = A X B - A\nD = [[1,0],[0,2]]\nC = D"
    // C = D is then a check on the others: D is known, so C is known too, and X comes out of the first equation.
    guard case .lines(let lines) = try Calculator().compute(text) else {
      Issue.record("not a worksheet")
      return
    }
    let values = Dictionary(uniqueKeysWithValues: lines.compactMap { line in line.name.map { ($0, line.quantity) } })
    guard case .matrix(let a)? = values["A"], case .matrix(let b)? = values["B"], case .matrix(let x)? = values["X"],
      case .matrix(let d)? = values["D"]
    else {
      Issue.record("missing values: \(values.keys.sorted())")
      return
    }
    let left = try a.multiplied(by: x).multiplied(by: b).subtracting(a)
    #expect(left == d)
  }

  @Test("Without a matrix, the lines are equations as they always were")
  func withoutMatrices() {
    #expect(failure("x^2 = 4") == .unsupported(.equation))
    #expect(failure("x + y = 3\nx - y = 1") == .unsupported(.system))
  }
}
