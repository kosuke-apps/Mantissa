enum Token: Equatable, Sendable {
  case number(Rational)
  /// A one-letter variable.
  case letter(String)
  case constant(MathConstant)
  case function(FunctionName)
  case plus, minus, star, slash, caret
  case bang, percent, degree
  case leftParen, rightParen, bar
  case comma, separator
  case relation(RelationOperator)
  /// √ (index 2), ∛ (3) or ∜ (4).
  case radical(Int)

  /// A readable form for error messages.
  var text: String {
    switch self {
    case .number(let value): return BigDecimal(value, precision: 20).description
    case .letter(let name): return name
    case .constant(let constant): return constant == .pi ? "π" : "e"
    case .function(let function): return function.rawValue
    case .plus: return "+"
    case .minus: return "-"
    case .star: return "×"
    case .slash: return "/"
    case .caret: return "^"
    case .bang: return "!"
    case .percent: return "%"
    case .degree: return "°"
    case .leftParen: return "("
    case .rightParen: return ")"
    case .bar: return "|"
    case .comma: return ","
    case .separator: return ";"
    case .relation(let op):
      switch op {
      case .equal: return "="
      case .notEqual: return "≠"
      case .less: return "<"
      case .lessOrEqual: return "≤"
      case .greater: return ">"
      case .greaterOrEqual: return "≥"
      }
    case .radical(let index): return index == 2 ? "√" : (index == 3 ? "∛" : "∜")
    }
  }
}

struct PositionedToken: Equatable, Sendable {
  var token: Token
  /// The character offset in the original input.
  var offset: Int
}

/// Turns text into tokens. It accepts what a keyboard, a pasted formula or a Japanese input method produces:
/// full-width digits and signs, `×` `÷` `−`, `√`, `π`, `≤` `≥` `≠`, superscript digits, and any of `()[]{}` as
/// parentheses.
enum Lexer {
  static func tokenize(_ text: String) throws(ParseError) -> [PositionedToken] {
    let characters = Array(text).map(normalized)
    var tokens: [PositionedToken] = []
    var index = 0

    func peek(_ offset: Int = 0) -> Character? {
      index + offset < characters.count ? characters[index + offset] : nil
    }
    func add(_ token: Token, at offset: Int) { tokens.append(PositionedToken(token: token, offset: offset)) }

    while let character = peek() {
      let start = index
      if character == "\n" {
        add(.separator, at: start)
        index += 1
      } else if character.isWhitespace {
        index += 1
      } else if character.isASCIIDigit || (character == "." && (peek(1)?.isASCIIDigit ?? false)) {
        add(.number(try scanNumber(characters, &index, start)), at: start)
      } else if superscripts[character] != nil {
        // x² is x^2; a run of superscript digits, with an optional superscript minus, is one exponent.
        add(.caret, at: start)
        let negative = superscripts[character] == "-"
        if negative { index += 1 }
        var digits = ""
        while let next = peek(), let digit = superscripts[next], digit != "-" {
          digits.append(digit)
          index += 1
        }
        guard !digits.isEmpty, let value = Rational(decimal: digits) else {
          throw ParseError(reason: .invalidNumber(digits), offset: start)
        }
        if negative {
          for token in [Token.leftParen, .minus, .number(value), .rightParen] { add(token, at: start) }
        } else {
          add(.number(value), at: start)
        }
      } else if character.isLetter {
        scanLetters(characters, &index, &tokens)
      } else {
        index += 1
        switch character {
        case "+": add(.plus, at: start)
        case "-": add(.minus, at: start)
        case "*": add(.star, at: start)
        case "/": add(.slash, at: start)
        case "^": add(.caret, at: start)
        case "!":
          if peek() == "=" {
            index += 1
            add(.relation(.notEqual), at: start)
          } else {
            add(.bang, at: start)
          }
        case "%": add(.percent, at: start)
        case "°": add(.degree, at: start)
        case "(", "[", "{": add(.leftParen, at: start)
        case ")", "]", "}": add(.rightParen, at: start)
        case "|": add(.bar, at: start)
        case ",": add(.comma, at: start)
        case ";": add(.separator, at: start)
        case "=":
          if peek() == "=" { index += 1 }
          add(.relation(.equal), at: start)
        case "≠": add(.relation(.notEqual), at: start)
        case "<", ">":
          let orEqual = peek() == "="
          if orEqual { index += 1 }
          let op: RelationOperator =
            character == "<" ? (orEqual ? .lessOrEqual : .less) : (orEqual ? .greaterOrEqual : .greater)
          add(.relation(op), at: start)
        case "≤": add(.relation(.lessOrEqual), at: start)
        case "≥": add(.relation(.greaterOrEqual), at: start)
        case "√": add(.radical(2), at: start)
        case "∛": add(.radical(3), at: start)
        case "∜": add(.radical(4), at: start)
        default: throw ParseError(reason: .unexpectedCharacter(character), offset: start)
        }
      }
    }
    return tokens
  }

  // MARK: Numbers

  /// Reads digits with an optional fraction and an optional `E` exponent (`1.5E-3`, never a lowercase `e`, which is
  /// Euler's number: `2e` is 2·e).
  private static func scanNumber(
    _ characters: [Character], _ index: inout Int, _ start: Int
  ) throws(ParseError)
    -> Rational
  {
    var text = ""
    while index < characters.count, characters[index].isASCIIDigit {
      text.append(characters[index])
      index += 1
    }
    if index < characters.count, characters[index] == "." {
      text.append(".")
      index += 1
      while index < characters.count, characters[index].isASCIIDigit {
        text.append(characters[index])
        index += 1
      }
    }
    if index < characters.count, characters[index] == "E" || characters[index] == "ᴇ" {
      var lookahead = index + 1
      var exponent = "E"
      if lookahead < characters.count, characters[lookahead] == "+" || characters[lookahead] == "-" {
        exponent.append(characters[lookahead])
        lookahead += 1
      }
      if lookahead < characters.count, characters[lookahead].isASCIIDigit {
        while lookahead < characters.count, characters[lookahead].isASCIIDigit {
          exponent.append(characters[lookahead])
          lookahead += 1
        }
        text += exponent
        index = lookahead
      }
    }
    guard let value = Rational(decimal: text) else { throw ParseError(reason: .invalidNumber(text), offset: start) }
    return value
  }

  // MARK: Names and letters

  /// Splits a run of letters into function names, constants and one-letter variables: "sinx" is `sin` and `x`,
  /// "xy" is `x` and `y`, "pi" is π.
  private static func scanLetters(_ characters: [Character], _ index: inout Int, _ tokens: inout [PositionedToken]) {
    var end = index
    while end < characters.count, characters[end].isLetter { end += 1 }
    let run = String(characters[index..<end])
    var position = run.startIndex
    while position < run.endIndex {
      let offset = index + run.distance(from: run.startIndex, to: position)
      let rest = run[position...]
      if let match = FunctionName.spellings.first(where: { rest.hasPrefix($0.text) }) {
        tokens.append(PositionedToken(token: .function(match.function), offset: offset))
        position = run.index(position, offsetBy: match.text.count)
      } else if rest.hasPrefix("pi") {
        tokens.append(PositionedToken(token: .constant(.pi), offset: offset))
        position = run.index(position, offsetBy: 2)
      } else {
        let letter = rest.first!
        let token: Token = letter == "π" ? .constant(.pi) : (letter == "e" ? .constant(.e) : .letter(String(letter)))
        tokens.append(PositionedToken(token: token, offset: offset))
        position = run.index(after: position)
      }
    }
    index = end
  }

  // MARK: Character normalisation

  private static let superscripts: [Character: Character] = [
    "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-",
  ]

  /// Maps the many spellings of an operator to one: full-width ASCII to ASCII, `×·⋅∙` to `*`, `÷∕⁄` to `/`, and the
  /// various minus signs to `-`.
  private static func normalized(_ character: Character) -> Character {
    switch character {
    case "×", "·", "⋅", "∙", "✕": return "*"
    case "÷", "∕", "⁄": return "/"
    case "−", "–", "—", "‐", "‑", "ー": return "-"
    case "\u{3000}": return " "
    case "＾": return "^"
    default:
      if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
        (0xFF01...0xFF5E).contains(scalar.value), let ascii = Unicode.Scalar(scalar.value - 0xFEE0)
      {
        return Character(ascii)
      }
      return character
    }
  }
}

extension Character {
  fileprivate var isASCIIDigit: Bool { self >= "0" && self <= "9" }
}
