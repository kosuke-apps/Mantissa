// A readable linear rendering of an expression: `2√3 + π/6`, `x^2 - 3x + 2`, `sin(x)/2`.
//
// The text uses the same syntax the parser reads, so `Parser.parse(expression.description)` gives the expression back.
// The display layer will typeset expressions properly; this is for tests, history storage and debugging.

extension Expr: CustomStringConvertible {
  public var description: String { Renderer.render(self).text }
}

/// How tightly an operator binds; a rendering is parenthesised when it is used where something tighter is needed.
private enum Level {
  /// A sum, or anything starting with a minus sign.
  static let sum = 1
  /// A product or a quotient.
  static let product = 2
  /// A factor of a product: anything except a sum or a leading minus.
  static let factor = 3
  /// A power.
  static let power = 4
  /// A number, symbol, constant, function call or radical.
  static let atom = 5
}

private struct Rendered {
  var text: String
  var level: Int

  func wrapped(minimum: Int) -> String { level < minimum ? "(" + text + ")" : text }
}

private enum Renderer {
  static func render(_ expression: Expr) -> Rendered {
    switch expression {
    case .number(let value): return render(value)
    case .constant(let constant): return Rendered(text: constant == .pi ? "π" : "e", level: Level.atom)
    case .symbol(let name): return Rendered(text: name, level: Level.atom)
    case .sum(let terms): return renderSum(terms)
    case .product(let factors): return renderFraction(of: factors)
    case .power(let base, let exponent):
      if let number = exponent.rational, number.isNegative { return renderFraction(of: [expression]) }
      return renderPower(base, exponent)
    case .function(let function, let arguments): return renderFunction(function, arguments)
    }
  }

  // MARK: Numbers

  static func render(_ value: Rational) -> Rendered {
    if value.isInteger {
      return Rendered(text: value.description, level: value.isNegative ? Level.sum : Level.atom)
    }
    return Rendered(text: value.description, level: value.isNegative ? Level.sum : Level.product)
  }

  // MARK: Sums

  private static func renderSum(_ terms: [Expr]) -> Rendered {
    var text = ""
    for (index, term) in displayOrder(terms).enumerated() {
      let (negative, magnitude) = splitSign(term)
      let body = render(magnitude).wrapped(minimum: Level.product)
      if index == 0 {
        text += negative ? "-" + body : body
      } else {
        text += (negative ? " - " : " + ") + body
      }
    }
    return Rendered(text: text, level: Level.sum)
  }

  /// `(true, |term|)` for a negative number or a product with a negative coefficient, else `(false, term)`.
  private static func splitSign(_ term: Expr) -> (Bool, Expr) {
    switch term {
    case .number(let value): return value.isNegative ? (true, .number(-value)) : (false, term)
    case .product(let factors):
      if case .number(let coefficient) = factors[0], coefficient.isNegative { return (true, -term) }
      return (false, term)
    default: return (false, term)
    }
  }

  /// How the terms of a sum are ordered for reading. With unknowns: highest degree first, plain numbers last
  /// (`x^2 - 3x + 2`). Without: a plain number first, then the rest with positive terms before negative ones
  /// (`2 - √3`, `√6/4 - √2/4`).
  private static func displayOrder(_ terms: [Expr]) -> [Expr] {
    let hasUnknowns = terms.contains { !$0.freeSymbols.isEmpty }
    func group(_ term: Expr) -> Int {
      if case .number = term { return hasUnknowns ? 2 : 0 }
      return term.freeSymbols.isEmpty ? 1 : 0
    }
    let indexed = terms.enumerated().map { (index: $0.offset, term: $0.element) }
    return indexed.sorted { a, b in
      let (ga, gb) = (group(a.term), group(b.term))
      if ga != gb { return ga < gb }
      if hasUnknowns {
        let (da, db) = (degree(a.term), degree(b.term))
        if da != db { return da > db }
        // Same degree: by the names of the unknowns, so that x comes before y.
        let (ka, kb) = (a.term.freeSymbols.sorted().joined(), b.term.freeSymbols.sorted().joined())
        if ka != kb { return ka < kb }
      } else {
        let (na, nb) = (splitSign(a.term).0, splitSign(b.term).0)
        if na != nb { return !na }
      }
      return a.index < b.index
    }.map(\.term)
  }

  /// A polynomial-style degree, used only to order terms for reading.
  private static func degree(_ term: Expr) -> Double {
    switch term {
    case .symbol: return 1
    case .power(let base, let exponent):
      guard let number = exponent.rational else { return degree(base) }
      return degree(base) * (Double(number.numerator.description) ?? 1) / (Double(number.denominator.description) ?? 1)
    case .product(let factors): return factors.reduce(0) { $0 + degree($1) }
    case .sum(let terms): return terms.map(degree).max() ?? 0
    default: return 0
    }
  }

  // MARK: Products and quotients

  /// Renders a product, or a power with a negative exponent, as a fraction: factors with negative exponents go below
  /// the line, and so does the denominator of a rational coefficient.
  private static func renderFraction(of factors: [Expr]) -> Rendered {
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

    let top = joinFactors(numerator, leading: coefficient.numerator.magnitude)
    let sign = coefficient.isNegative ? "-" : ""
    if denominator.isEmpty && coefficient.denominator.isOne {
      return Rendered(text: sign + top, level: coefficient.isNegative ? Level.sum : Level.product)
    }
    // A denominator that multiplies a sum of plain numbers by anything else would be multiplied out when read back,
    // which is a different (if equal) expression; dividing one factor at a time reads back exactly.
    let hasNumericSum = denominator.contains {
      if case .sum = $0 { return $0.freeSymbols.isEmpty } else { return false }
    }
    if denominator.count >= 2 && hasNumericSum {
      var text = sign + top
      if !coefficient.denominator.isOne { text += "/" + coefficient.denominator.description }
      for factor in denominator { text += "/" + render(factor).wrapped(minimum: Level.power) }
      return Rendered(text: text, level: coefficient.isNegative ? Level.sum : Level.product)
    }
    let bottom = joinFactors(denominator, leading: coefficient.denominator)
    let bottomText = denominator.count + (coefficient.denominator.isOne ? 0 : 1) > 1 ? "(" + bottom + ")" : bottom
    return Rendered(text: sign + top + "/" + bottomText, level: coefficient.isNegative ? Level.sum : Level.product)
  }

  /// The factors written one after another, with a leading whole number when it is not 1. Square roots of whole
  /// numbers are merged into one radical: 2^(1/2) 3^(1/2) is √6.
  private static func joinFactors(_ factors: [Expr], leading: BigInt) -> String {
    var pieces: [String] = []
    if !leading.isOne || factors.isEmpty { pieces.append(leading.description) }

    var radicand = BigInt(1)
    var hasRadical = false
    var others: [Expr] = []
    for factor in factors {
      if case .power(.number(let base), .number(let exponent)) = factor, base.isInteger,
        exponent == Rational(1, 2)
      {
        radicand *= base.numerator
        hasRadical = true
      } else {
        others.append(factor)
      }
    }
    for factor in others { pieces.append(render(factor).wrapped(minimum: Level.factor)) }
    if hasRadical { pieces.append(radical(of: Rendered(text: radicand.description, level: Level.atom))) }

    var text = pieces[0]
    for piece in pieces.dropFirst() {
      // Two numbers side by side would read as one, so a dot separates a factor that starts with a digit; and a
      // function name after a letter gets a space so that "x sin(2)" is not read as one word.
      let startsWithName = piece.prefix(2).allSatisfy(\.isLetter) && piece.count > 2 && piece.contains("(")
      let separator = piece.first?.isNumber == true ? "·" : (startsWithName && text.last?.isLetter == true ? " " : "")
      text += separator + piece
    }
    return text
  }

  // MARK: Powers, roots

  private static func renderPower(_ base: Expr, _ exponent: Expr) -> Rendered {
    if exponent == .fraction(1, 2) { return Rendered(text: radical(of: render(base)), level: Level.atom) }
    let exponentText = render(exponent)
    let exponentString =
      exponentText.level >= Level.atom && exponent.rational?.isNegative != true
      ? exponentText.text : "(" + exponentText.text + ")"
    return Rendered(text: render(base).wrapped(minimum: Level.atom) + "^" + exponentString, level: Level.power)
  }

  private static func radical(of operand: Rendered) -> String {
    "√" + operand.wrapped(minimum: Level.atom)
  }

  // MARK: Functions

  private static func renderFunction(_ function: MathFunction, _ arguments: [Expr]) -> Rendered {
    if function == .factorial {
      return Rendered(text: render(arguments[0]).wrapped(minimum: Level.atom) + "!", level: Level.atom)
    }
    let list = arguments.map { render($0).text }.joined(separator: ", ")
    return Rendered(text: function.rawValue + "(" + list + ")", level: Level.atom)
  }
}
