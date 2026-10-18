/// Lays an answer out as a formula: stacked fractions, radical signs, raised exponents, a minus sign that is a minus
/// sign. The result is the same `MathNode` tree the editor works with, so one view draws what you type and what you get.
///
/// `parserText` of what comes out reads back, through the parser, as the expression it was made from.
public enum Typesetter {
  /// The exact expression, typeset.
  public static func nodes(for expression: Expr) -> [MathNode] {
    typeset(expression).nodes
  }

  /// A decimal rounded to `significantDigits` digits: `0.0125`, `3.14159265`, or `1.5 × 10^30` when it is very large or
  /// very small. Trailing zeros are not shown.
  public static func nodes(for decimal: BigDecimal, significantDigits: Int) -> [MathNode] {
    let rounded = decimal.rounded(toSignificantDigits: significantDigits)
    guard let order = rounded.decimalOrder else { return [.symbol("0")] }
    let scientificExponent = order - 1
    let sign: [MathNode] = rounded.isNegative ? [.symbol("−")] : []
    let digits = rounded.significand.magnitude.description

    if (-6...15).contains(scientificExponent) {
      var text: String
      if rounded.exponent >= 0 {
        text = digits + String(repeating: "0", count: rounded.exponent)
      } else if scientificExponent >= 0 {
        let split = digits.index(digits.startIndex, offsetBy: digits.count + rounded.exponent)
        text = String(digits[..<split]) + "." + String(digits[split...])
      } else {
        text = "0." + String(repeating: "0", count: -scientificExponent - 1) + digits
      }
      return sign + text.map { .symbol(String($0)) }
    }

    var mantissa = String(digits.prefix(1))
    if digits.count > 1 { mantissa += "." + digits.dropFirst() }
    let exponentSign: [MathNode] = scientificExponent < 0 ? [.symbol("−")] : []
    let exponentDigits = String(scientificExponent.magnitude).map { MathNode.symbol(String($0)) }
    return sign + mantissa.map { .symbol(String($0)) } + [.symbol("×"), .symbol("1"), .symbol("0")]
      + [.superscript(exponentSign + exponentDigits)]
  }

  /// A complex decimal: `1.5 + 2.25i`, `−0.5i`, `i`. Each part is rounded to `significantDigits` digits.
  public static func nodes(for value: ComplexDecimal, significantDigits: Int) -> [MathNode] {
    let real = value.real.rounded(toSignificantDigits: significantDigits)
    let imaginary = value.imaginary.rounded(toSignificantDigits: significantDigits)
    let unit = MathNode.symbol("i")
    var imaginaryNodes: [MathNode] = []
    if !imaginary.isZero {
      imaginaryNodes =
        imaginary.magnitude == BigDecimal(1)
        ? [] : nodes(for: imaginary.magnitude, significantDigits: significantDigits)
      imaginaryNodes.append(unit)
    }
    if real.isZero {
      return (imaginary.isNegative ? [.symbol("−")] : []) + (imaginary.isZero ? [.symbol("0")] : imaginaryNodes)
    }
    let realNodes = nodes(for: real, significantDigits: significantDigits)
    if imaginary.isZero { return realNodes }
    return realNodes + [.symbol(imaginary.isNegative ? "−" : "+")] + imaginaryNodes
  }

  /// A factored form: `2(x + 1)(x − 3)²`, or a fraction of two such products.
  public static func nodes(for factorization: Factorization) -> [MathNode] {
    func product(_ factors: [Factorization.Factor], leading: BigInt?) -> [MathNode] {
      var nodes: [MathNode] = []
      if let leading, !leading.isOne || factors.isEmpty { nodes += digits(leading) }
      for factor in factors {
        // A lone factor needs no brackets: x + 1, not (x + 1).
        let alone = factors.count == 1 && factor.power == 1 && (leading?.isOne ?? true)
        var piece = alone ? typeset(factor.base).nodes : typeset(factor.base).wrapped(minimum: Level.atom)
        if factor.power > 1 { piece.append(.superscript(digits(BigInt(factor.power)))) }
        nodes += piece
      }
      return nodes
    }
    let coefficient = factorization.coefficient
    let sign: [MathNode] = coefficient.isNegative ? [.symbol("−")] : []
    let top = product(factorization.numerator, leading: coefficient.numerator.magnitude)
    if factorization.denominator.isEmpty && coefficient.denominator.isOne { return sign + top }
    let bottom = product(factorization.denominator, leading: coefficient.denominator)
    return sign + [.fraction(numerator: top, denominator: bottom)]
  }

  // MARK: Pieces

  /// How tightly a piece binds; one that binds too loosely for where it is used is put in parentheses.
  private enum Level {
    static let sum = 1
    static let product = 2
    static let factor = 3
    static let power = 4
    static let atom = 5
  }

  private struct Piece {
    var nodes: [MathNode]
    var level: Int

    func wrapped(minimum: Int) -> [MathNode] { level < minimum ? [.group(nodes)] : nodes }
  }

  private static func digits(_ value: BigInt) -> [MathNode] {
    value.magnitude.description.map { .symbol(String($0)) }
  }

  private static func typeset(_ expression: Expr) -> Piece {
    switch expression {
    case .number(let value): return number(value)
    case .constant(let constant): return Piece(nodes: [.symbol(constant.symbol)], level: Level.atom)
    case .symbol(let name): return Piece(nodes: [.symbol(name)], level: Level.atom)
    case .sum(let terms): return sum(terms)
    case .product(let factors): return fraction(of: factors)
    case .power(let base, let exponent):
      if let number = exponent.rational, number.isNegative { return fraction(of: [expression]) }
      return power(base, exponent)
    case .function(let function, let arguments): return call(function, arguments)
    }
  }

  private static func number(_ value: Rational) -> Piece {
    let sign: [MathNode] = value.isNegative ? [.symbol("−")] : []
    if value.isInteger {
      return Piece(nodes: sign + digits(value.numerator), level: value.isNegative ? Level.sum : Level.atom)
    }
    let stacked = MathNode.fraction(numerator: digits(value.numerator), denominator: digits(value.denominator))
    return Piece(nodes: sign + [stacked], level: value.isNegative ? Level.sum : Level.product)
  }

  private static func sum(_ terms: [Expr]) -> Piece {
    if let (denominator, numerator) = Presentation.commonDenominator(terms) {
      let stacked = MathNode.fraction(numerator: typeset(numerator).nodes, denominator: digits(denominator))
      return Piece(nodes: [stacked], level: Level.product)
    }
    var nodes: [MathNode] = []
    for (index, term) in Presentation.displayOrder(terms).enumerated() {
      let (negative, magnitude) = Presentation.splitSign(term)
      let body = typeset(magnitude).wrapped(minimum: Level.product)
      if index == 0 {
        nodes += (negative ? [.symbol("−")] : []) + body
      } else {
        nodes += [.symbol(negative ? "−" : "+")] + body
      }
    }
    return Piece(nodes: nodes, level: Level.sum)
  }

  /// A product, or a power with a negative exponent, as a fraction: factors with negative exponents go below the line and
  /// so does the denominator of a rational coefficient.
  private static func fraction(of factors: [Expr]) -> Piece {
    var coefficient = Rational(1)
    var numerator: [Expr] = []
    var denominator: [Expr] = []
    for factor in factors {
      switch factor {
      case .number(let value): coefficient *= value
      case .power(let base, let exponent):
        if let number = exponent.rational, number.isNegative {
          denominator.append(number == Rational(-1) ? base : .power(base, .number(-number)))
        } else {
          numerator.append(factor)
        }
      default: numerator.append(factor)
      }
    }

    let sign: [MathNode] = coefficient.isNegative ? [.symbol("−")] : []
    let level = coefficient.isNegative ? Level.sum : Level.product
    let top = join(numerator, leading: coefficient.numerator.magnitude)
    if denominator.isEmpty && coefficient.denominator.isOne { return Piece(nodes: sign + top, level: level) }

    // A denominator that multiplies a sum of plain numbers by anything else would be multiplied out when read back; a
    // chain of divisions, one factor at a time, reads back as it was.
    let hasNumericSum = denominator.contains {
      if case .sum = $0 { return $0.freeSymbols.isEmpty } else { return false }
    }
    if denominator.count >= 2 && hasNumericSum {
      var chain = top
      if !coefficient.denominator.isOne {
        chain = [.fraction(numerator: chain, denominator: digits(coefficient.denominator))]
      }
      for factor in denominator { chain = [.fraction(numerator: chain, denominator: typeset(factor).nodes)] }
      return Piece(nodes: sign + chain, level: level)
    }
    let bottom = join(denominator, leading: coefficient.denominator)
    return Piece(nodes: sign + [.fraction(numerator: top, denominator: bottom)], level: level)
  }

  /// The factors one after another, with a leading whole number when it is not 1. Square roots of whole numbers are merged
  /// into one radical: 2^(1/2) · 3^(1/2) is √6.
  private static func join(_ factors: [Expr], leading: BigInt) -> [MathNode] {
    var pieces: [[MathNode]] = []
    if !leading.isOne || factors.isEmpty { pieces.append(digits(leading)) }

    var radicand = BigInt(1)
    var hasRadical = false
    var others: [Expr] = []
    for factor in factors {
      // Only positive whole numbers merge: √(−7) is not a factor to fold into a shared radical.
      if case .power(.number(let base), .number(let exponent)) = factor, base.isInteger, base.signum > 0,
        exponent == Rational(1, 2)
      {
        radicand *= base.numerator
        hasRadical = true
      } else {
        others.append(factor)
      }
    }
    // The imaginary unit is written last, after any radical: 2√3 i.
    for factor in displayOrder(others) where factor != .i {
      pieces.append(typeset(factor).wrapped(minimum: Level.factor))
    }
    if hasRadical { pieces.append([.radical(index: nil, radicand: digits(radicand))]) }
    if others.contains(.i) { pieces.append([.symbol("i")]) }

    var nodes = pieces[0]
    for piece in pieces.dropFirst() {
      // Two numbers side by side would read as one, so a times sign separates a factor that starts with a digit.
      if let first = piece.first?.symbolCharacter, first.isNumber { nodes.append(.symbol("×")) }
      nodes += piece
    }
    return nodes
  }

  /// The factors in the order they are read: powers of the unknown first (x³e^x, not e^x x³), then sums in brackets, then
  /// other powers such as e^x and 2^x, then functions. The order within each kind is the canonical one.
  private static func displayOrder(_ factors: [Expr]) -> [Expr] {
    func rank(_ factor: Expr) -> Int {
      switch factor {
      case .number, .constant: return 0
      case .symbol: return 1
      case .power(let base, _):
        if case .symbol = base { return 1 }
        if case .sum = base { return 2 }
        return 3
      case .sum, .product: return 2
      case .function: return 4
      }
    }
    return factors.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
  }

  private static func power(_ base: Expr, _ exponent: Expr) -> Piece {
    if exponent == .fraction(1, 2) {
      return Piece(nodes: [.radical(index: nil, radicand: typeset(base).nodes)], level: Level.atom)
    }
    let baseNodes = typeset(base).wrapped(minimum: Level.atom)
    return Piece(nodes: baseNodes + [.superscript(typeset(exponent).nodes)], level: Level.power)
  }

  private static func call(_ function: MathFunction, _ arguments: [Expr]) -> Piece {
    switch function {
    case .factorial:
      return Piece(nodes: typeset(arguments[0]).wrapped(minimum: Level.atom) + [.symbol("!")], level: Level.atom)
    case .abs:
      return Piece(nodes: [.absolute(typeset(arguments[0]).nodes)], level: Level.atom)
    case .log where arguments[1] != .integer(10):
      return Piece(
        nodes: [.logarithm(base: typeset(arguments[1]).nodes, argument: typeset(arguments[0]).nodes)], level: Level.atom
      )
    case .log:
      return Piece(nodes: [.function(name: "log", argument: typeset(arguments[0]).nodes)], level: Level.atom)
    default:
      var list: [MathNode] = []
      for (index, argument) in arguments.enumerated() {
        if index > 0 { list.append(.symbol(",")) }
        list += typeset(argument).nodes
      }
      return Piece(nodes: [.function(name: function.rawValue, argument: list)], level: Level.atom)
    }
  }
}
