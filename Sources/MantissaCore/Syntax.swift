/// The unevaluated structure of what the user typed. The parser produces it, `Builder` turns it into an `Expr`, and
/// the tests evaluate it directly, without any simplification, to check that simplification never changes a value.
indirect enum Syntax: Equatable, Sendable {
  case number(Rational)
  case symbol(String)
  case constant(MathConstant)
  case negate(Syntax)
  case binary(BinaryOperator, Syntax, Syntax)
  case postfix(PostfixOperator, Syntax)
  case call(FunctionName, [Syntax])
  /// A root: `√x` has no index, `∛x` has index 3.
  case radical(index: Syntax?, radicand: Syntax)
  /// ∞, which only means something as a limit, an end of an integral or a sum.
  case infinity
  /// A matrix, row by row, written `[[1, 2], [3, 4]]`; a vector is a matrix with one column.
  case matrix([[Syntax]])
}

extension Syntax {
  /// Whether the text writes π anywhere inside.
  var mentionsPi: Bool {
    switch self {
    case .constant(let constant): return constant == .pi
    case .number, .symbol, .infinity: return false
    case .negate(let operand), .postfix(_, let operand): return operand.mentionsPi
    case .binary(_, let left, let right): return left.mentionsPi || right.mentionsPi
    case .call(_, let arguments): return arguments.contains { $0.mentionsPi }
    case .radical(let index, let radicand): return (index?.mentionsPi ?? false) || radicand.mentionsPi
    case .matrix(let rows): return rows.contains { $0.contains { $0.mentionsPi } }
    }
  }

  /// Whether the text writes a matrix, or a function that gives or takes one, anywhere inside, or a letter in `bound` (one that
  /// stands for a matrix).
  func involvesMatrix(bound: Set<String> = []) -> Bool {
    switch self {
    case .matrix: return true
    case .symbol(let name): return bound.contains(name)
    case .number, .constant, .infinity: return false
    case .negate(let operand), .postfix(_, let operand): return operand.involvesMatrix(bound: bound)
    case .binary(_, let left, let right): return left.involvesMatrix(bound: bound) || right.involvesMatrix(bound: bound)
    case .call(let function, let arguments):
      return function.isMatrixFunction || arguments.contains { $0.involvesMatrix(bound: bound) }
    case .radical(let index, let radicand):
      return (index?.involvesMatrix(bound: bound) ?? false) || radicand.involvesMatrix(bound: bound)
    }
  }

  /// How many times each letter is written. The `T` of `A^T` is the mark of the transpose and not a letter.
  func letterCounts() -> [String: Int] {
    var counts: [String: Int] = [:]
    collectLetters(into: &counts)
    return counts
  }

  private func collectLetters(into counts: inout [String: Int]) {
    switch self {
    case .symbol(let name): counts[name, default: 0] += 1
    case .number, .constant, .infinity: break
    case .negate(let operand), .postfix(_, let operand): operand.collectLetters(into: &counts)
    case .binary(let op, let left, let right):
      left.collectLetters(into: &counts)
      if op == .power, case .symbol("T") = right { break }
      right.collectLetters(into: &counts)
    case .call(_, let arguments): for argument in arguments { argument.collectLetters(into: &counts) }
    case .radical(let index, let radicand):
      index?.collectLetters(into: &counts)
      radicand.collectLetters(into: &counts)
    case .matrix(let rows): for row in rows { for cell in row { cell.collectLetters(into: &counts) } }
    }
  }
}

extension Statement {
  /// Whether any line writes a matrix.
  var involvesMatrix: Bool {
    switch self {
    case .expression(let syntax): return syntax.involvesMatrix()
    case .relation(let chain):
      return chain.first.involvesMatrix() || chain.links.contains { $0.operand.involvesMatrix() }
    case .system(let parts): return parts.contains { $0.involvesMatrix }
    }
  }
}

enum BinaryOperator: Equatable, Sendable {
  case add, subtract, multiply, divide, power
}

enum PostfixOperator: Equatable, Sendable {
  case factorial
  /// `x%` is `x/100`.
  case percent
  /// `x°` is the angle `x` degrees, expressed in the unit the calculator is working in.
  case degree
}

/// The functions a user can write, including the ones that are structural in `Expr` (roots and `exp`).
enum FunctionName: String, CaseIterable, Sendable {
  /// `atan(y, x)` with two arguments is the angle of the point (x, y), in (−π, π].
  case sin, cos, tan, asin, acos, atan
  /// Cotangent, secant and cosecant: `cos/sin`, `1/cos` and `1/sin`.
  case cot, sec, csc
  /// Their inverses: `π/2 − atan(x)`, `acos(1/x)` and `asin(1/x)`.
  case acot, asec, acsc
  case sinh, cosh, tanh, asinh, acosh, atanh
  /// Hyperbolic cotangent, secant and cosecant, and their inverses (`acoth(x)` is `atanh(1/x)`).
  case coth, sech, csch, acoth, asech, acsch
  case ln, log
  case sqrt, cbrt, root, exp
  case abs, floor, ceil, round
  case nCr, nPr, gcd, lcm
  /// `mod(a, b)` is `a − b·floor(a/b)`, so it has the sign of `b`; `min` and `max` take two or more numbers.
  case mod, min, max
  /// −1, 0 or 1 for a real number, and `z/|z|` for a complex one.
  case sign
  /// The real part, imaginary part, complex conjugate and argument (the angle in (−π, π]) of a complex number.
  case re, im, conj, arg
  /// Calculus: `diff(f, x, n)`, `int(f, x, a, b)`, `lim(f, x, a)`, `sum(f, k, a, b)`.
  case diff, int, lim, sum
  /// Matrices and vectors: the determinant, inverse, transpose, trace, rank and reduced row echelon form of a matrix,
  /// the dot and cross product and the length of vectors, and the identity matrix of a size.
  case det, inverse, transpose, trace, rank, rref, dot, cross, norm, identity
  /// The eigenvalues of a matrix, as a column, and a matrix whose columns are its eigenvectors.
  case eigvals, eigvecs

  /// Whether the function takes an unknown (a letter) as an argument and works on the expression, not on a number.
  var isCalculus: Bool {
    switch self {
    case .diff, .int, .lim, .sum: return true
    default: return false
    }
  }

  /// Whether the function works on matrices or makes one, so that a formula with it is worked out as a matrix computation.
  var isMatrixFunction: Bool {
    switch self {
    case .det, .inverse, .transpose, .trace, .rank, .rref, .dot, .cross, .norm, .identity, .eigvals, .eigvecs:
      return true
    default: return false
    }
  }

  /// Alternative spellings the parser accepts.
  static let aliases: [String: FunctionName] = [
    "inv": .inverse, "eigenvalues": .eigvals, "eigenvectors": .eigvecs, "arcsin": .asin, "arccos": .acos,
    "arctan": .atan,
    "arcsinh": .asinh, "arccosh": .acosh, "arctanh": .atanh,
    "arsinh": .asinh, "arcosh": .acosh, "artanh": .atanh,
  ]

  /// Every spelling, longest first, so that "arcsin" is read before "a" or "sin".
  static let spellings: [(text: String, function: FunctionName)] = {
    var all = FunctionName.allCases.map { ($0.rawValue, $0) }
    all += aliases.map { ($0.key, $0.value) }
    return all.sorted { $0.0.count > $1.0.count }
  }()

  /// Short names that are also letters people multiply (`re` is r·e, `max` is m·a·x): they are read as a function only
  /// when an opening parenthesis follows, as the keyboard writes them.
  var needsParenthesis: Bool {
    switch self {
    case .mod, .min, .max, .sign, .re, .im, .conj, .arg: return true
    default: return isMatrixFunction
    }
  }

  /// The numbers of arguments the function accepts.
  var arities: ClosedRange<Int> {
    switch self {
    case .log, .atan: return 1...2
    case .diff: return 1...3
    case .int: return 1...4
    case .lim: return 3...4
    case .sum: return 4...4
    case .min, .max: return 2...8
    case .root, .nCr, .nPr, .gcd, .lcm, .mod, .dot, .cross: return 2...2
    default: return 1...1
    }
  }
}

enum RelationOperator: Equatable, Sendable {
  case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
}

/// `first op₁ second op₂ third …`, such as `1 < x ≤ 5`; a single comparison has one link.
struct RelationChain: Equatable, Sendable {
  var first: Syntax
  var links: [(op: RelationOperator, operand: Syntax)]

  static func == (lhs: RelationChain, rhs: RelationChain) -> Bool {
    lhs.first == rhs.first && lhs.links.count == rhs.links.count
      && zip(lhs.links, rhs.links).allSatisfy { $0.op == $1.op && $0.operand == $1.operand }
  }
}

/// A whole input: one expression, one equation or inequality (possibly chained), or several of them separated by
/// commas, semicolons or line breaks (a system).
enum Statement: Equatable, Sendable {
  case expression(Syntax)
  case relation(RelationChain)
  case system([Statement])
}

/// Why the text could not be read. `offset` counts characters from the start of the input.
public struct ParseError: Error, Equatable, Sendable {
  public enum Reason: Equatable, Sendable {
    case empty
    case unexpectedCharacter(Character)
    case invalidNumber(String)
    case unexpectedToken(String)
    case unexpectedEnd
    case missingClosingParenthesis
    case missingClosingBar
    case wrongArgumentCount(function: String, expected: String)
  }

  public var reason: Reason
  public var offset: Int
}
