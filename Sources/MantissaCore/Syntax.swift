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
}

extension Syntax {
  /// Whether the text writes π anywhere inside.
  var mentionsPi: Bool {
    switch self {
    case .constant(let constant): return constant == .pi
    case .number, .symbol: return false
    case .negate(let operand), .postfix(_, let operand): return operand.mentionsPi
    case .binary(_, let left, let right): return left.mentionsPi || right.mentionsPi
    case .call(_, let arguments): return arguments.contains { $0.mentionsPi }
    case .radical(let index, let radicand): return (index?.mentionsPi ?? false) || radicand.mentionsPi
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
  case sin, cos, tan, asin, acos, atan
  case sinh, cosh, tanh, asinh, acosh, atanh
  case ln, log
  case sqrt, cbrt, root, exp
  case abs, floor, ceil, round
  case nCr, nPr, gcd, lcm

  /// Alternative spellings the parser accepts.
  static let aliases: [String: FunctionName] = [
    "arcsin": .asin, "arccos": .acos, "arctan": .atan,
    "arcsinh": .asinh, "arccosh": .acosh, "arctanh": .atanh,
    "arsinh": .asinh, "arcosh": .acosh, "artanh": .atanh,
  ]

  /// Every spelling, longest first, so that "arcsin" is read before "a" or "sin".
  static let spellings: [(text: String, function: FunctionName)] = {
    var all = FunctionName.allCases.map { ($0.rawValue, $0) }
    all += aliases.map { ($0.key, $0.value) }
    return all.sorted { $0.0.count > $1.0.count }
  }()

  /// The numbers of arguments the function accepts.
  var arities: ClosedRange<Int> {
    switch self {
    case .log: return 1...2
    case .root, .nCr, .nPr, .gcd, .lcm: return 2...2
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
