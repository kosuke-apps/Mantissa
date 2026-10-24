import SwiftUI

/// What is drawn on a key.
enum Glyph: Hashable {
  case text(String)
  case fraction
  case root
  case power
  case group
  case absolute
  /// `log` with a small box for its base.
  case logarithm
}

struct KeySpec: Identifiable {
  struct Alternate: Identifiable {
    var title: String
    var actions: [KeyAction]
    var id: String { title }
  }

  enum Tone {
    /// Digits.
    case number
    /// Everything else.
    case plain
  }

  var id: String
  var glyph: Glyph
  var actions: [KeyAction]
  var alternates: [Alternate] = []
  var tone = Tone.plain

  /// A key labelled with its own `id` as text.
  init(_ id: String, _ actions: [KeyAction], alternates: [Alternate] = [], tone: Tone = .plain) {
    self.init(id, .text(id), actions, alternates: alternates, tone: tone)
  }

  init(_ id: String, _ glyph: Glyph, _ actions: [KeyAction], alternates: [Alternate] = [], tone: Tone = .plain) {
    self.id = id
    self.glyph = glyph
    self.actions = actions
    self.alternates = alternates
    self.tone = tone
  }
}

/// The pages of the maths keyboard, which the tabs above the keys switch between.
enum KeyboardPage: CaseIterable, Identifiable {
  case basic
  case functions
  case trigonometry
  case calculus

  var id: Self { self }

  /// What VoiceOver says for the page.
  var spokenName: LocalizedStringKey {
    switch self {
    case .basic: return "Basic keys"
    case .functions: return "Functions and logarithms"
    case .trigonometry: return "Trigonometry"
    case .calculus: return "Calculus"
    }
  }

  /// The word on the page's tab.
  var title: LocalizedStringKey {
    switch self {
    case .basic: return "Basic"
    case .functions: return "Functions"
    case .trigonometry: return "Trig"
    case .calculus: return "Calculus"
    }
  }
}

/// The keys of each page, six to a row.
enum KeyboardLayout {
  private static func symbol(
    _ text: String, tone: KeySpec.Tone = .plain, alternates: [KeySpec.Alternate] = []
  ) -> KeySpec {
    KeySpec(text, [.symbol(text)], alternates: alternates, tone: tone)
  }

  private static func digit(_ text: String) -> KeySpec { symbol(text, tone: .number) }

  private static func function(_ name: String, alternates: [String] = []) -> KeySpec {
    KeySpec(name, [.function(name)], alternates: alternates.map(functionAlternate))
  }

  private static func functionAlternate(_ name: String) -> KeySpec.Alternate {
    .init(title: name, actions: [.function(name)])
  }

  private static func alternate(_ text: String) -> KeySpec.Alternate { .init(title: text, actions: [.symbol(text)]) }

  static func rows(for page: KeyboardPage) -> [[KeySpec]] {
    switch page {
    case .basic:
      return [
        [
          symbol("x", alternates: ["y", "z", "a", "b", "t"].map(alternate)),
          KeySpec(
            "group", .group, [.group],
            alternates: [
              .init(title: "(", actions: [.literal("(")]), .init(title: ")", actions: [.literal(")")]),
              .init(title: "|□|", actions: [.absolute]),
            ]),
          digit("7"), digit("8"), digit("9"), symbol("÷"),
        ],
        [
          KeySpec("fraction", .fraction, [.fraction]),
          KeySpec(
            "root", .root, [.squareRoot],
            alternates: [
              .init(title: "ⁿ√□", actions: [.nthRoot]), .init(title: "∛□", actions: [.nthRoot, .symbol("3"), .right]),
            ]),
          digit("4"), digit("5"), digit("6"),
          symbol(
            "×",
            alternates: [
              .init(title: "×10ⁿ", actions: [.symbol("×"), .symbol("1"), .symbol("0"), .power])
            ]),
        ],
        [
          symbol("π", alternates: [alternate("e"), alternate("i")]),
          KeySpec(
            "power", .power, [.power],
            alternates: [.init(title: "□²", actions: [.exponent("2")]), .init(title: "□³", actions: [.exponent("3")])]),
          digit("1"), digit("2"), digit("3"), symbol("−"),
        ],
        [
          symbol("%", alternates: [alternate("!"), alternate("°")]),
          symbol(">", alternates: ["<", "≤", "≥", "≠"].map(alternate)),
          digit("0"), symbol(".", alternates: [alternate(",")]), symbol("=", alternates: [alternate("≠")]), symbol("+"),
        ],
      ]

    case .functions:
      return [
        [
          function("ln"), function("log"), KeySpec("log□", .logarithm, [.logarithm]),
          KeySpec("eˣ", [.symbol("e"), .power]), symbol("e"),
          KeySpec("abs", .absolute, [.absolute], alternates: ["re", "im", "conj", "arg"].map(functionAlternate)),
        ],
        [function("nCr"), function("nPr"), symbol("!"), function("mod"), function("gcd"), function("lcm")],
        [function("floor"), function("ceil"), function("round"), function("sign"), function("min"), function("max")],
        [
          symbol(","), KeySpec("(", [.symbol("(")]), KeySpec(")", [.symbol(")")]), symbol("π"), symbol("i"),
          symbol("="),
        ],
      ]

    case .trigonometry:
      return [
        [
          function("sin"), function("cos"), function("tan"), function("asin"), function("acos"),
          KeySpec(
            "atan", [.function("atan")],
            alternates: [
              .init(title: "atan(y, x)", actions: [.function("atan"), .symbol("y"), .symbol(","), .symbol("x")])
            ]),
        ],
        [
          function("sinh"), function("cosh"), function("tanh"), function("asinh"), function("acosh"), function("atanh"),
        ],
        [
          function("cot", alternates: ["acot", "coth", "acoth"]),
          function("sec", alternates: ["asec", "sech", "asech"]),
          function("csc", alternates: ["acsc", "csch", "acsch"]), symbol("°"), symbol("π"), symbol("="),
        ],
        [
          KeySpec("(", [.symbol("(")]), KeySpec(")", [.symbol(")")]), symbol(","), symbol("x"), symbol("y"),
          symbol("e"),
        ],
      ]

    case .calculus:
      // Each key places the operator with its slots; the arrow keys move from one slot to the next.
      return [
        [
          KeySpec("lim", [.calculus(.limit)]), KeySpec("d/dx", [.calculus(.derivative)]),
          KeySpec("∫", [.calculus(.integral)]), KeySpec("Σ", [.calculus(.sum)]), symbol("∞"), symbol(","),
        ],
        [
          symbol("x"), symbol("y"), symbol("k"), symbol("n"), KeySpec("(", [.symbol("(")]),
          KeySpec(")", [.symbol(")")]),
        ],
        [symbol("π"), symbol("e"), symbol("i"), symbol("−"), symbol("+"), symbol("=")],
        [
          // After the point of a limit: approaching it from above (x → a⁺) or from below (x → a⁻).
          KeySpec("above", .text("a⁺"), [.symbol("⁺")]), KeySpec("below", .text("a⁻"), [.symbol("⁻")]),
          digit("0"), digit("1"), digit("2"), KeySpec("power", .power, [.power]),
        ],
      ]
    }
  }

  /// What VoiceOver says for a key that is not plain text (or whose symbol is not read well).
  static func spokenName(for id: String) -> LocalizedStringKey? {
    switch id {
    case "group": return "Parentheses"
    case "fraction": return "Fraction"
    case "root": return "Square root"
    case "power": return "Power"
    case "abs": return "Absolute value"
    case "log□": return "Logarithm with a base"
    case "eˣ": return "e to the power"
    case "÷": return "Divide"
    case "×": return "Times"
    case "−": return "Minus"
    case "+": return "Plus"
    case "=": return "Equals"
    case ">": return "Greater than"
    case "<": return "Less than"
    case "≤": return "Less than or equal to"
    case "≥": return "Greater than or equal to"
    case "≠": return "Not equal to"
    case ".": return "Decimal point"
    case ",": return "Comma"
    case "(": return "Open parenthesis"
    case ")": return "Close parenthesis"
    case "%": return "Percent"
    case "!": return "Factorial"
    case "°": return "Degrees"
    case "π": return "Pi"
    case "∞": return "Infinity"
    case "above": return "Approaching from above"
    case "below": return "Approaching from below"
    case "lim": return "Limit"
    case "d/dx": return "Derivative"
    case "∫": return "Integral"
    case "Σ": return "Sum"
    default: return nil
    }
  }

  /// The letter keys, for variables.
  static let letterRows: [[String]] = [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    ["z", "x", "c", "v", "b", "n", "m"],
  ]
}
