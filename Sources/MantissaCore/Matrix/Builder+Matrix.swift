// Formulas that have matrices in them: `[[1, 2], [3, 4]]^(-1)`, `2A + B`, `det(M)`, `cross(u, v)`.
//
// `Builder.build` makes an `Expr` and so cannot hold a matrix. `value` works out what a formula comes to, an `Expr` or a
// matrix, and hands everything that has no matrix in it to `build`.

/// What a formula comes to.
enum Value {
  case scalar(Expr)
  case matrix(Matrix)

  /// A 1×1 matrix is the number in it.
  static func collapsing(_ matrix: Matrix) -> Value {
    matrix.entries.count == 1 ? .scalar(matrix.entries[0]) : .matrix(matrix)
  }

  /// The value as a matrix; a number is a 1×1 matrix.
  var asMatrix: Matrix {
    if case .matrix(let matrix) = self { return matrix } else { return Matrix(scalar: asScalar!) }
  }

  var asScalar: Expr? { if case .scalar(let value) = self { return value } else { return nil } }
}

extension Matrix {
  init(scalar: Expr) { self.init(rowCount: 1, columnCount: 1, entries: [scalar]) }
}

extension Builder {
  func value(_ syntax: Syntax) throws(MathError) -> Value {
    guard syntax.involvesMatrix else { return .scalar(try build(syntax)) }
    switch syntax {
    case .number, .symbol, .constant, .infinity: return .scalar(try build(syntax))

    case .matrix(let rows):
      var built: [[Expr]] = []
      for row in rows {
        var cells: [Expr] = []
        for cell in row {
          // The entries are numbers and expressions; a matrix in a cell would be a block matrix.
          guard case .scalar(let entry) = try value(cell) else { throw .unsupported }
          cells.append(entry.trigonometricallyTidied())
        }
        built.append(cells)
      }
      guard let matrix = Matrix(rows: built) else { throw .overflow }
      return .collapsing(matrix)

    case .negate(let operand):
      switch try value(operand) {
      case .scalar(let number): return .scalar(-number)
      case .matrix(let matrix): return .matrix(matrix.negated())
      }

    case .binary(let op, let left, let right):
      return try binary(op, try value(left), try value(right))

    case .postfix(let op, let operand):
      // `det(A)!` and `trace(A)%` are fine; a matrix has no factorial, percent or degree.
      guard let number = try value(operand).asScalar else { throw .unsupported }
      return .scalar(try postfix(op, number))

    case .radical(let index, let radicand):
      guard let number = try value(radicand).asScalar else { throw .unsupported }
      var builtIndex: Expr?
      if let index {
        guard let built = try value(index).asScalar else { throw .unsupported }
        builtIndex = built
      }
      return .scalar(try radical(index: builtIndex, number))

    case .call(let function, let arguments):
      var values: [Value] = []
      if !function.isCalculus { for argument in arguments { values.append(try value(argument)) } }
      return try call(function, arguments, values)
    }
  }

  // MARK: Operators

  private func binary(_ op: BinaryOperator, _ left: Value, _ right: Value) throws(MathError) -> Value {
    switch (left, right) {
    case (.scalar(let a), .scalar(let b)):
      switch op {
      case .add: return .scalar(a + b)
      case .subtract: return .scalar(a - b)
      case .multiply: return .scalar(a * b)
      case .divide: return .scalar(try a.divided(by: b))
      case .power: return .scalar(try a.raised(to: b))
      }
    case (.matrix(let a), .matrix(let b)):
      switch op {
      case .add: return .matrix(try a.adding(b))
      case .subtract: return .matrix(try a.subtracting(b))
      case .multiply: return .collapsing(try a.multiplied(by: b))
      case .divide, .power: throw .unsupported
      }
    case (.scalar(let a), .matrix(let b)):
      switch op {
      case .multiply: return .matrix(try b.scaled(by: a))
      case .add, .subtract: throw .dimensionMismatch
      case .divide, .power: throw .unsupported
      }
    case (.matrix(let a), .scalar(let b)):
      switch op {
      case .multiply: return .matrix(try a.scaled(by: b))
      case .divide: return .matrix(try a.divided(by: b))
      case .add, .subtract: throw .dimensionMismatch
      case .power: return try power(a, b)
      }
    }
  }

  /// A matrix to a power: a whole number, or `T` for the transpose.
  private func power(_ matrix: Matrix, _ exponent: Expr) throws(MathError) -> Value {
    if case .symbol("T") = exponent { return .collapsing(matrix.transposed()) }
    guard let value = exponent.rational, value.isInteger, let whole = value.numerator.asInt else { throw .unsupported }
    return .collapsing(try matrix.raised(to: whole))
  }

  // MARK: Functions

  private func call(_ function: FunctionName, _ arguments: [Syntax], _ values: [Value]) throws(MathError) -> Value {
    if function.isCalculus {
      // The calculus of matrices is not here: a matrix inside `build` is reported as unsupported.
      return .scalar(try build(.call(function, arguments)))
    }
    if function.isMatrixFunction { return try matrixCall(function, values) }
    // An ordinary function of numbers; a matrix is not a number, except that |A| is the length of a vector or the
    // determinant of a square matrix.
    if values.contains(where: { $0.asScalar == nil }) {
      guard function == .abs, values.count == 1 else { throw .unsupported }
      let matrix = values[0].asMatrix
      return .scalar(try matrix.isVector ? matrix.norm() : matrix.determinant())
    }
    let numbers = values.compactMap(\.asScalar)
    return .scalar(try call(function, numbers, argumentMentionsPi: arguments.contains { $0.mentionsPi }))
  }

  private func matrixCall(_ function: FunctionName, _ values: [Value]) throws(MathError) -> Value {
    switch function {
    case .identity:
      guard let size = values[0].asScalar?.rational, size.isInteger, let count = size.numerator.asInt,
        (1...Matrix.maxDimension).contains(count)
      else { throw .domain }
      return .collapsing(Matrix.identity(count))
    case .det: return .scalar(try values[0].asMatrix.determinant())
    case .inverse: return .collapsing(try values[0].asMatrix.inverse())
    case .transpose: return .collapsing(values[0].asMatrix.transposed())
    case .trace: return .scalar(try values[0].asMatrix.trace())
    case .rank: return .scalar(.integer(try values[0].asMatrix.rank()))
    case .rref: return .collapsing(try values[0].asMatrix.reducedRowEchelonForm())
    case .dot: return .scalar(try values[0].asMatrix.dot(values[1].asMatrix))
    case .cross: return .matrix(try values[0].asMatrix.cross(values[1].asMatrix))
    case .norm: return .scalar(try values[0].asMatrix.norm())
    case .eigvals:
      let eigenvalues = try values[0].asMatrix.eigenvalues()
      return .collapsing(Matrix(rowCount: eigenvalues.count, columnCount: 1, entries: eigenvalues))
    case .eigvecs: return .collapsing(try values[0].asMatrix.eigenvectors())
    default: throw .unsupported
    }
  }
}
