/// A named mathematical constant.
public enum MathConstant: Int, Hashable, Sendable, CaseIterable {
  case pi
  case e
  /// The imaginary unit, i² = −1. A power of it is always reduced to 1, i, −1 or −i.
  case i

  /// The character that stands for the constant.
  public var symbol: String {
    switch self {
    case .pi: return "π"
    case .e: return "e"
    case .i: return "i"
    }
  }
}

/// A function the engine knows. Angles are always in radians here; the parser converts when the user works in
/// degrees. Square roots, other roots and `exp` are not functions: they are powers (`x^(1/2)`, `e^x`).
public enum MathFunction: String, Hashable, Sendable, CaseIterable {
  case sin, cos, tan, asin, acos, atan
  case sinh, cosh, tanh, asinh, acosh, atanh
  /// Natural logarithm.
  case ln
  /// `log(x, base)`.
  case log
  case abs, floor, ceil, round
  case factorial
  case combinations = "nCr"
  case permutations = "nPr"
  case gcd, lcm

  /// Whether an absolute error in the argument carries over to the result, so large arguments need extra digits.
  var magnifiesArgumentError: Bool {
    switch self {
    case .sin, .cos, .tan, .sinh, .cosh, .tanh: return true
    default: return false
    }
  }

  /// How many arguments the function takes.
  public var arity: Int {
    switch self {
    case .log, .combinations, .permutations, .gcd, .lcm: return 2
    default: return 1
    }
  }
}

/// An exact mathematical expression in canonical form.
///
/// Build values with the operators, `divided(by:)`, `raised(to:)` and `Expr.apply(_:_:)`; they keep the form
/// canonical, and equal expressions are then `==`:
///
/// - a sum is flattened, has its numbers added and its like terms collected (`2x + 3x` is `5x`), and is sorted;
/// - a product is flattened, has its numbers multiplied into one leading coefficient and its equal bases merged
///   (`x·x` is `x²`, `√2·√2` is `2`), and a numeric coefficient multiplies through a sum (`2(x+1)` is `2x+2`);
/// - a power of a number is evaluated, and a root of a positive rational is split into an integer part and prime
///   radicals with exponents in [0, 1): `√12` is `2·3^(1/2)` and `1/√2` is `(1/2)·2^(1/2)`.
///
/// The cases are public so that code can pattern-match; constructing them directly bypasses the rules.
public indirect enum Expr: Hashable, Sendable {
  case number(Rational)
  case constant(MathConstant)
  case symbol(String)
  /// Two or more terms, sorted.
  case sum([Expr])
  /// Two or more factors, sorted, with at most one number and that first.
  case product([Expr])
  case power(Expr, Expr)
  case function(MathFunction, [Expr])
}

extension Expr: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self = .number(Rational(value)) }
}

extension Expr {
  public static let zero = Expr.number(Rational(0))
  public static let one = Expr.number(Rational(1))
  public static let minusOne = Expr.number(Rational(-1))
  public static let pi = Expr.constant(.pi)
  public static let e = Expr.constant(.e)
  public static let i = Expr.constant(.i)

  public static func integer(_ value: Int) -> Expr { .number(Rational(value)) }

  /// `numerator / denominator`; the denominator must not be zero.
  public static func fraction(_ numerator: Int, _ denominator: Int) -> Expr {
    .number(Rational(numerator, denominator))
  }

  /// The value if this is a number.
  public var rational: Rational? {
    if case .number(let value) = self { return value }
    return nil
  }

  public var isZero: Bool { rational?.isZero ?? false }
  public var isOne: Bool { rational == Rational(1) }

  /// The names of the symbols that occur in the expression.
  public var freeSymbols: Set<String> {
    switch self {
    case .number, .constant: return []
    case .symbol(let name): return [name]
    case .sum(let terms), .product(let terms), .function(_, let terms):
      return terms.reduce(into: Set<String>()) { $0.formUnion($1.freeSymbols) }
    case .power(let base, let exponent): return base.freeSymbols.union(exponent.freeSymbols)
    }
  }

  /// Whether the imaginary unit occurs anywhere in the expression, which makes its value non-real (or, if it cancels
  /// in a way the canonical form has not seen, still a complex computation).
  public var containsImaginaryUnit: Bool {
    switch self {
    case .constant(let constant): return constant == .i
    case .number, .symbol: return false
    case .sum(let parts), .product(let parts), .function(_, let parts):
      return parts.contains { $0.containsImaginaryUnit }
    case .power(let base, let exponent): return base.containsImaginaryUnit || exponent.containsImaginaryUnit
    }
  }

  /// The number of nodes, a rough measure of size.
  public var nodeCount: Int {
    switch self {
    case .number, .constant, .symbol: return 1
    case .sum(let parts), .product(let parts), .function(_, let parts):
      return 1 + parts.reduce(0) { $0 + $1.nodeCount }
    case .power(let base, let exponent): return 1 + base.nodeCount + exponent.nodeCount
    }
  }

  // MARK: Canonical order

  private var rank: Int {
    switch self {
    case .number: return 0
    case .constant: return 1
    case .symbol: return 2
    case .power: return 3
    case .function: return 4
    case .product: return 5
    case .sum: return 6
    }
  }

  /// A total order used to sort sums and products: -1, 0 or 1. It only has to be deterministic; the display layer
  /// reorders terms for reading.
  static func compare(_ lhs: Expr, _ rhs: Expr) -> Int {
    if lhs.rank != rhs.rank { return lhs.rank < rhs.rank ? -1 : 1 }
    switch (lhs, rhs) {
    case (.number(let a), .number(let b)): return a == b ? 0 : (a < b ? -1 : 1)
    case (.constant(let a), .constant(let b)): return a == b ? 0 : (a.rawValue < b.rawValue ? -1 : 1)
    case (.symbol(let a), .symbol(let b)): return a == b ? 0 : (a < b ? -1 : 1)
    case (.power(let a, let b), .power(let c, let d)):
      let first = compare(a, c)
      return first != 0 ? first : compare(b, d)
    case (.function(let f, let a), .function(let g, let b)):
      if f != g { return f.rawValue < g.rawValue ? -1 : 1 }
      return compare(lists: a, b)
    case (.product(let a), .product(let b)), (.sum(let a), .sum(let b)):
      return compare(lists: a, b)
    default: return 0
    }
  }

  private static func compare(lists a: [Expr], _ b: [Expr]) -> Int {
    for (x, y) in zip(a, b) {
      let order = compare(x, y)
      if order != 0 { return order }
    }
    return a.count == b.count ? 0 : (a.count < b.count ? -1 : 1)
  }

  static func sorted(_ items: [Expr]) -> [Expr] {
    items.sorted { compare($0, $1) < 0 }
  }
}
