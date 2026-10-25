import Testing

@testable import MantissaCore

/// Matrices and vectors. Each expectation was worked out by hand (or follows from a definition, like `A·A⁻¹ = I`), not copied
/// from the program's output.
@Suite("Matrices")
struct MatrixTests {
  /// The entries of the matrix `text` comes to, row by row, each written as the engine writes it.
  private func entries(_ text: String) throws -> [[String]] {
    guard case .matrix(let matrix) = try Calculator().compute(text) else {
      Issue.record("\(text) is not a matrix")
      return []
    }
    return matrix.rows.map { $0.map(\.description) }
  }

  private func number(_ text: String) throws -> String {
    guard case .number(let evaluation) = try Calculator().compute(text) else {
      Issue.record("\(text) is not a number")
      return ""
    }
    return evaluation.exact.description
  }

  private func failure(_ text: String) -> MathError? {
    do {
      _ = try Calculator().compute(text)
      return nil
    } catch {
      if case .math(let problem) = error { return problem }
      return nil
    }
  }

  @Test("A matrix is written in square or curly brackets, and brackets round a formula are still brackets")
  func reading() throws {
    #expect(try entries("[[1,2],[3,4]]") == [["1", "2"], ["3", "4"]])
    #expect(try entries("{{1,2},{3,4}}") == [["1", "2"], ["3", "4"]])
    #expect(try entries("[[1, -2, 3]]") == [["1", "-2", "3"]])
    #expect(try entries("[[1+1, 2/4],[√4, 0.5]]") == [["2", "1/2"], ["2", "1/2"]])
    #expect(try number("[[1+2]*3]") == "9")
    #expect(try number("[1+2]*3") == "9")
    #expect(try number("[[5]]") == "5")  // a 1×1 matrix is the number in it
    // Not a matrix: rows of different lengths.
    #expect(throws: (any Error).self) { try Calculator().compute("[[1,2],[3]]") }
  }

  @Test("Sums, scalar multiples and products")
  func arithmetic() throws {
    #expect(try entries("[[1,2],[3,4]]+[[5,6],[7,8]]") == [["6", "8"], ["10", "12"]])
    #expect(try entries("[[5,6],[7,8]]-[[1,2],[3,4]]") == [["4", "4"], ["4", "4"]])
    #expect(try entries("2[[1,2],[3,4]]") == [["2", "4"], ["6", "8"]])
    #expect(try entries("[[1,2],[3,4]]*3") == [["3", "6"], ["9", "12"]])
    #expect(try entries("[[1,2],[3,4]]/2") == [["1/2", "1"], ["3/2", "2"]])
    #expect(try entries("-[[1,-2]]") == [["-1", "2"]])
    // Rows times columns: 1·5 + 2·7 = 19, 1·6 + 2·8 = 22, 3·5 + 4·7 = 43, 3·6 + 4·8 = 50.
    #expect(try entries("[[1,2],[3,4]][[5,6],[7,8]]") == [["19", "22"], ["43", "50"]])
    // A 2×3 times a 3×1 is a 2×1.
    #expect(try entries("[[1,2,3],[4,5,6]]*[[1],[0],[2]]") == [["7"], ["16"]])
    // A row times a column is a number.
    #expect(try number("[[1,2,3]]*[[4],[5],[6]]") == "32")
    // Matrix multiplication is not commutative.
    #expect(try entries("[[5,6],[7,8]][[1,2],[3,4]]") == [["23", "34"], ["31", "46"]])
  }

  @Test("Powers: whole numbers, the inverse, and the transpose")
  func powers() throws {
    // Fibonacci: [[1,1],[1,0]]^n holds F(n+1), F(n), F(n), F(n−1).
    #expect(try entries("[[1,1],[1,0]]^10") == [["89", "55"], ["55", "34"]])
    #expect(try entries("[[1,1],[1,0]]^0") == [["1", "0"], ["0", "1"]])
    #expect(try entries("[[1,2],[3,4]]^2") == [["7", "10"], ["15", "22"]])
    #expect(try entries("[[1,2],[3,4]]^(-1)") == [["-2", "1"], ["3/2", "-1/2"]])
    // The square of the inverse: [[-2,1],[3/2,-1/2]]² = [[4+3/2, -2-1/2],[-3-3/4, 3/2+1/4]].
    #expect(try entries("[[1,2],[3,4]]^(-2)") == [["11/2", "-5/2"], ["-15/4", "7/4"]])
    #expect(try entries("[[1,2,3]]^T") == [["1"], ["2"], ["3"]])
    #expect(try entries("transpose([[1,2],[3,4]])") == [["1", "3"], ["2", "4"]])
    #expect(try entries("[[2,0],[0,3]]^20")[1][1] == "3486784401")  // 3^20
    // Not a whole number.
    #expect(failure("[[1,2],[3,4]]^(1/2)") == .unsupported)
    #expect(failure("[[1,2,3]]^2") == .dimensionMismatch)
  }

  @Test("Determinant and trace")
  func determinant() throws {
    #expect(try number("det([[1,2],[3,4]])") == "-2")
    #expect(try number("det([[2,0,1],[1,3,2],[1,1,4]])") == "18")  // 2(12−2) − 0 + 1(1−3)
    #expect(try number("|[[1,2],[3,4]]|") == "-2")
    #expect(try number("det([[1,2,3,4],[0,5,6,7],[0,0,8,9],[0,0,0,10]])") == "400")
    #expect(try number("det([[0,5,6,7],[1,2,3,4],[0,0,8,9],[0,0,0,10]])") == "-400")  // two rows swapped
    #expect(try number("det([[1,2,3],[4,5,6],[7,8,9]])") == "0")
    #expect(try number("det([[a,b],[c,d]])") == "ad - bc")
    #expect(try number("det([[a,0,0],[0,b,0],[0,0,c]])") == "abc")
    #expect(try number("det(identity(5))") == "1")
    #expect(try number("trace([[1,2],[3,4]])") == "5")
    #expect(failure("det([[1,2,3]])") == .dimensionMismatch)
    // A determinant is a number like any other.
    #expect(try number("2det([[1,2],[3,4]])+1") == "-3")
  }

  @Test("The inverse, and what has none")
  func inverse() throws {
    #expect(try entries("inverse([[1,2],[3,4]])") == [["-2", "1"], ["3/2", "-1/2"]])
    #expect(try entries("inv([[2,0],[0,4]])") == [["1/2", "0"], ["0", "1/4"]])
    #expect(failure("inverse([[1,2],[2,4]])") == .singular)
    #expect(failure("[[1,2],[2,4]]^(-1)") == .singular)
    #expect(failure("inverse([[1,2,3]])") == .dimensionMismatch)
    // A number is a 1×1 matrix, and its inverse is its reciprocal.
    #expect(try number("inverse(x)") == "1/x")
    #expect(try number("inverse(4)") == "1/4")
    #expect(failure("inverse(0)") == .singular)
    // With roots in it.
    #expect(try entries("inverse([[√2,0],[0,√2]])") == [["√2/2", "0"], ["0", "√2/2"]])
    // With a letter in it: put numbers back for the letters and it is the inverse of the numbers.
    guard case .matrix(let symbolic) = try Calculator().compute("inverse([[a,b],[c,d]])") else {
      Issue.record("no matrix")
      return
    }
    let values: [String: Expr] = ["a": 1, "b": 2, "c": 3, "d": 4]
    let filled = symbolic.entries.map { entry in
      values.reduce(entry) { $0.substituting($1.key, with: $1.value) ?? $0 }
    }
    #expect(filled.map(\.description) == ["-2", "1", "3/2", "-1/2"])
  }

  @Test("A matrix times its inverse is the identity, for matrices of every size")
  func inverseProperty() throws {
    var generator = SplitMix64(seed: 77 &+ propertySeedOffset)
    for size in 1...6 {
      var rows: [String] = []
      for _ in 0..<size {
        rows.append("[" + (0..<size).map { _ in String(Int(generator.next() % 19) - 9) }.joined(separator: ",") + "]")
      }
      let text = "[" + rows.joined(separator: ",") + "]"
      if try number("det(\(text))") == "0" { continue }
      if size == 1 {
        #expect(try number("\(text)inverse(\(text))") == "1", "\(text)")
      } else {
        #expect(try entries("\(text)inverse(\(text))") == entries("identity(\(size))"), "\(text)")
      }
    }
  }

  @Test("Rank and reduced row echelon form")
  func elimination() throws {
    #expect(try number("rank([[1,2,3],[4,5,6],[7,8,9]])") == "2")
    #expect(try number("rank(identity(4))") == "4")
    #expect(try number("rank([[0,0],[0,0]])") == "0")
    #expect(try number("rank([[1,2,3],[2,4,6]])") == "1")
    #expect(try entries("rref([[1,2,3],[4,5,6],[7,8,9]])") == [["1", "0", "-1"], ["0", "1", "2"], ["0", "0", "0"]])
    #expect(try entries("rref([[2,4],[1,2]])") == [["1", "2"], ["0", "0"]])
    #expect(try entries("rref([[1,2,5],[3,4,6]])") == [["1", "0", "-4"], ["0", "1", "9/2"]])  // x = −4, y = 9/2
    #expect(failure("rank([[a,b],[c,d]])") == .unsupported)
  }

  @Test("Vectors: dot and cross products and length")
  func vectors() throws {
    #expect(try number("dot([[1],[2],[3]],[[4],[5],[6]])") == "32")
    #expect(try number("dot([[1,2,3]],[[4],[5],[6]])") == "32")  // either way round
    #expect(try entries("cross([[1],[0],[0]],[[0],[1],[0]])") == [["0"], ["0"], ["1"]])
    #expect(try entries("cross([[1],[2],[3]],[[4],[5],[6]])") == [["-3"], ["6"], ["-3"]])
    #expect(try entries("cross([[1,0,0]],[[0,1,0]])") == [["0", "0", "1"]])
    #expect(try number("norm([[3],[4]])") == "5")
    #expect(try number("|[[3],[4]]|") == "5")
    #expect(try number("norm([[1,1]])") == "√2")
    #expect(try number("norm([[1],[2],[2]])") == "3")
    #expect(try number("norm([[i],[1]])") == "√2")
    #expect(failure("dot([[1,2]],[[1,2,3]])") == .dimensionMismatch)
    #expect(failure("cross([[1],[2]],[[3],[4]])") == .dimensionMismatch)
    // The cross product is perpendicular to both: its dot product with each is zero.
    #expect(try number("dot(cross([[1],[2],[3]],[[4],[5],[6]]),[[1],[2],[3]])") == "0")
  }

  @Test("Entries may be roots, π, i or letters")
  func entriesOfAnyKind() throws {
    #expect(try entries("[[√2,0],[0,√2]][[√2,0],[0,√2]]") == [["2", "0"], ["0", "2"]])
    #expect(try entries("[[i,0],[0,i]]^2") == [["-1", "0"], ["0", "-1"]])
    #expect(try entries("[[1,x],[0,1]]^3") == [["1", "3x"], ["0", "1"]])
    #expect(try entries("[[a,b]]+[[c,d]]") == [["a + c", "b + d"]])
    #expect(try entries("2[[π,1]]") == [["2π", "2"]])
    #expect(try entries("[[cos(0), sin(0)]]") == [["1", "0"]])
    #expect(try entries("identity(2)") == [["1", "0"], ["0", "1"]])
  }

  @Test("Sizes that do not fit, and what is not a matrix thing")
  func errors() {
    #expect(failure("[[1,2],[3,4]]+[[1,2,3]]") == .dimensionMismatch)
    #expect(failure("[[1,2],[3,4]]+1") == .dimensionMismatch)
    #expect(failure("[[1,2,3],[4,5,6]][[1,2,3],[4,5,6]]") == .dimensionMismatch)
    #expect(failure("sin([[1,2]])") == .unsupported)
    #expect(failure("[[1,2]]!") == .unsupported)
    #expect(failure("1/[[1,2],[3,4]]") == .unsupported)
    #expect(failure("[[1,2],[3,4]]/[[1,2],[3,4]]") == .unsupported)
    #expect(failure("2^[[1,2],[3,4]]") == .unsupported)
    #expect(failure("identity(0)") == .domain)
    #expect(failure("identity(11)") == .domain)
    #expect(failure("[[1,2],[3,4]]/0") == .divisionByZero)
  }

  @Test("A matrix answer is not an Evaluation, and a matrix in an equation is not solved")
  func apiShape() {
    #expect(throws: (any Error).self) { try Calculator().evaluate("[[1,2]]") }
    #expect(throws: (any Error).self) { try Calculator().solve("[[1,2]] = [[1,2]]") }
  }

  @Test("Eigenvalues, each as often as it is a root, smallest first")
  func eigenvalues() throws {
    #expect(try entries("eigvals([[2,0],[0,3]])") == [["2"], ["3"]])
    // (λ − 2)² − 1 = 0
    #expect(try entries("eigvals([[2,1],[1,2]])") == [["1"], ["3"]])
    // λ² − 12λ + 11 = 0 for the block, and 2 from the corner.
    #expect(try entries("eigvals([[2,0,0],[0,3,4],[0,4,9]])") == [["1"], ["2"], ["11"]])
    #expect(try entries("eigenvalues([[2,0],[0,2]])") == [["2"], ["2"]])
    #expect(try entries("eigvals([[1,1],[0,1]])") == [["1"], ["1"]])
    // A quarter turn has no real eigenvalue: λ² + 1 = 0.
    #expect(try entries("eigvals([[0,-1],[1,0]])") == [["-i"], ["i"]])
    #expect(try number("eigvals(7)") == "7")
    #expect(failure("eigvals([[1,2,3]])") == .dimensionMismatch)
    #expect(failure("eigvals([[a,b],[c,d]])") == .unsupported)
    // A characteristic polynomial of degree 5 with no closed form: x⁵ − x − 1.
    #expect(failure("eigvals([[0,0,0,0,1],[1,0,0,0,1],[0,1,0,0,0],[0,0,1,0,0],[0,0,0,1,0]])") == .unsupported)
  }

  @Test("The eigenvalues of the Fibonacci matrix are the golden ratio and its conjugate")
  func fibonacciEigenvalues() throws {
    guard case .matrix(let result) = try Calculator().compute("eigvals([[1,1],[1,0]])") else {
      Issue.record("no matrix")
      return
    }
    // They add up to the trace, 1, and multiply to the determinant, −1.
    let (small, large) = (result.entries[0], result.entries[1])
    #expect((small + large).expanded() == 1)
    #expect((small * large).expanded() == -1)
    #expect(small.description == "(1 - √5)/2")
    #expect(large.description == "(1 + √5)/2")
  }

  @Test("Eigenvectors are columns with A·v = λ·v, in whole numbers where they can be")
  func eigenvectors() throws {
    #expect(try entries("eigvecs([[2,1],[1,2]])") == [["1", "1"], ["-1", "1"]])
    #expect(try entries("eigvecs([[2,0],[0,2]])") == [["1", "0"], ["0", "1"]])
    #expect(failure("eigvecs([[1,1],[0,1]])") == .unsupported)  // too few: the matrix is defective

    // A·P = P·D, with the eigenvalues down the diagonal of D.
    for text in [
      "[[2,1],[1,2]]", "[[1,1],[1,0]]", "[[0,-1],[1,0]]", "[[4,1,0],[1,4,0],[0,0,1]]", "[[2,0,0],[0,3,4],[0,4,9]]",
    ] {
      guard case .matrix(let a) = try Calculator().compute(text.hasPrefix("[[") ? "\(text)^1" : text) else {
        // A 1×1 or other shapes cannot occur here.
        continue
      }
      let values = try a.eigenvalues()
      let vectors = try a.eigenvectors()
      let diagonal = try Matrix.generated(rows: a.rowCount, columns: a.rowCount) { row, column in
        row == column ? values[row] : .zero
      }
      let left = try a.multiplied(by: vectors)
      let right = try vectors.multiplied(by: diagonal)
      for (x, y) in zip(left.entries, right.entries) { #expect((x - y).expanded().isZeroEntry, "\(text): \(x) ≠ \(y)") }
    }
  }
}
