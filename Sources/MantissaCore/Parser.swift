/// A recursive-descent parser for the text a maths keyboard or a person types.
///
/// From loosest to tightest binding:
///
///     statement  :=  relation ( (',' | ';' | newline) relation )*
///     relation   :=  expression ( ('=' | '≠' | '<' | '≤' | '>' | '≥') expression )*
///     expression :=  term ( ('+' | '-') term )*
///     term       :=  unary ( ('*' | '/' | juxtaposition) unary-or-power )*
///     unary      :=  ('-' | '+') unary | power
///     power      :=  postfix ( '^' exponent )?             right-associative
///     postfix    :=  primary ( '!' | '%' | '°' )*
///     primary    :=  number | letter | constant | '(' expression ')' | '|' expression '|'
///                 |  function ( '(' arguments ')' | unary )  |  '√' operand
///
/// Juxtaposition is multiplication at the same level as `*` and `/`, so `1/2x` is `(1/2)x` and `2x^2` is `2(x^2)`.
/// A function written without parentheses takes the operand after it as a unary expression, so `sin x^2` is
/// `sin(x^2)` and `sin 2x` is `sin(2)·x`. A radical takes just the next primary: `√2x` is `(√2)x`.
struct Parser {
  private let tokens: [PositionedToken]
  private let endOffset: Int
  private var index = 0
  private var barDepth = 0

  static func parse(_ text: String) throws(ParseError) -> Statement {
    let tokens = try Lexer.tokenize(text)
    if tokens.isEmpty { throw ParseError(reason: .empty, offset: 0) }
    var parser = Parser(tokens: tokens, endOffset: text.count)
    return try parser.parseStatement()
  }

  private init(tokens: [PositionedToken], endOffset: Int) {
    self.tokens = tokens
    self.endOffset = endOffset
  }

  // MARK: Token access

  private var current: PositionedToken? { index < tokens.count ? tokens[index] : nil }
  private var currentOffset: Int { current?.offset ?? endOffset }

  private mutating func advance() { index += 1 }

  private mutating func consume(_ token: Token) -> Bool {
    if current?.token == token {
      advance()
      return true
    }
    return false
  }

  private func unexpected() -> ParseError {
    guard let token = current else { return ParseError(reason: .unexpectedEnd, offset: endOffset) }
    return ParseError(reason: .unexpectedToken(token.token.text), offset: token.offset)
  }

  // MARK: Statements

  private mutating func parseStatement() throws(ParseError) -> Statement {
    var parts = [try parseRelation()]
    while consume(.separator) || consume(.comma) {
      if current == nil { break }  // a trailing separator is harmless
      parts.append(try parseRelation())
    }
    if current != nil { throw unexpected() }
    return parts.count == 1 ? parts[0] : .system(parts)
  }

  private mutating func parseRelation() throws(ParseError) -> Statement {
    let first = try parseExpression()
    var links: [(op: RelationOperator, operand: Syntax)] = []
    while case .relation(let op)? = current?.token {
      advance()
      links.append((op, try parseExpression()))
    }
    return links.isEmpty ? .expression(first) : .relation(RelationChain(first: first, links: links))
  }

  // MARK: Expressions

  private mutating func parseExpression() throws(ParseError) -> Syntax {
    var left = try parseTerm()
    while true {
      if consume(.plus) {
        left = .binary(.add, left, try parseTerm())
      } else if consume(.minus) {
        left = .binary(.subtract, left, try parseTerm())
      } else {
        return left
      }
    }
  }

  private mutating func parseTerm() throws(ParseError) -> Syntax {
    var left = try parseUnary()
    while true {
      if consume(.star) {
        left = .binary(.multiply, left, try parseUnary())
      } else if consume(.slash) {
        left = .binary(.divide, left, try parseUnary())
      } else if let next = current, startsPrimary(next.token) {
        // Juxtaposition. Two numbers side by side ("2 3") are almost certainly a typing slip, not 2·3.
        if case .number = next.token, index > 0, case .number = tokens[index - 1].token { throw unexpected() }
        left = .binary(.multiply, left, try parsePower())
      } else {
        return left
      }
    }
  }

  private func startsPrimary(_ token: Token) -> Bool {
    switch token {
    case .number, .letter, .constant, .function, .leftParen, .radical: return true
    case .bar: return barDepth == 0  // inside |…| a bar closes it
    default: return false
    }
  }

  private mutating func parseUnary() throws(ParseError) -> Syntax {
    if consume(.minus) { return .negate(try parseUnary()) }
    if consume(.plus) { return try parseUnary() }
    return try parsePower()
  }

  private mutating func parsePower() throws(ParseError) -> Syntax {
    let base = try parsePostfix()
    guard consume(.caret) else { return base }
    return .binary(.power, base, try parseExponent())
  }

  private mutating func parseExponent() throws(ParseError) -> Syntax {
    if consume(.minus) { return .negate(try parseExponent()) }
    if consume(.plus) { return try parseExponent() }
    return try parsePower()
  }

  private mutating func parsePostfix() throws(ParseError) -> Syntax {
    var value = try parsePrimary()
    while true {
      if consume(.bang) {
        value = .postfix(.factorial, value)
      } else if consume(.percent) {
        value = .postfix(.percent, value)
      } else if consume(.degree) {
        value = .postfix(.degree, value)
      } else {
        return value
      }
    }
  }

  // MARK: Primaries

  private mutating func parsePrimary() throws(ParseError) -> Syntax {
    guard let positioned = current else { throw unexpected() }
    switch positioned.token {
    case .number(let value):
      advance()
      return .number(value)
    case .letter(let name):
      advance()
      return .symbol(name)
    case .constant(let constant):
      advance()
      return .constant(constant)
    case .leftParen:
      advance()
      let inner = try parseExpression()
      guard consume(.rightParen) else {
        throw ParseError(reason: .missingClosingParenthesis, offset: currentOffset)
      }
      return inner
    case .bar:
      advance()
      barDepth += 1
      let inner = try parseExpression()
      barDepth -= 1
      guard consume(.bar) else { throw ParseError(reason: .missingClosingBar, offset: currentOffset) }
      return .call(.abs, [inner])
    case .radical(let degree):
      advance()
      let operand = try parseRadicalOperand()
      return .radical(index: degree == 2 ? nil : .number(Rational(degree)), radicand: operand)
    case .function(let function):
      advance()
      return try parseCall(function, at: positioned.offset)
    default:
      throw unexpected()
    }
  }

  private mutating func parseRadicalOperand() throws(ParseError) -> Syntax {
    if consume(.minus) { return .negate(try parseRadicalOperand()) }
    return try parsePostfix()
  }

  private mutating func parseCall(_ function: FunctionName, at offset: Int) throws(ParseError) -> Syntax {
    var arguments: [Syntax] = []
    if consume(.leftParen) {
      if current?.token != .rightParen {
        repeat { arguments.append(try parseExpression()) } while consume(.comma)
      }
      guard consume(.rightParen) else {
        throw ParseError(reason: .missingClosingParenthesis, offset: currentOffset)
      }
    } else {
      arguments = [try parseUnary()]
    }
    guard function.arities.contains(arguments.count) else {
      let range = function.arities
      let expected =
        range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound) or \(range.upperBound)"
      throw ParseError(reason: .wrongArgumentCount(function: function.rawValue, expected: expected), offset: offset)
    }
    return .call(function, arguments)
  }
}
