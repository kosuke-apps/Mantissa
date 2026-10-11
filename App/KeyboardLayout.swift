import SwiftUI

/// What is drawn on a key.
enum Glyph: Hashable {
  case text(String)
  case fraction
  case root
  case power
  case group
  case absolute
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

/// The pages of the maths keyboard, which the chips above the keys switch between.
enum KeyboardPage: CaseIterable, Identifiable {
  case basic
  case functions
  case trigonometry

  var id: Self { self }

  /// The two lines written on the chip.
  var chip: (String, String) {
    switch self {
    case .basic: return ("+ −", "× ÷")
    case .functions: return ("f(x) e", "log ln")
    case .trigonometry: return ("sin cos", "tan cot")
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

  private static func function(_ name: String) -> KeySpec { KeySpec(name, [.function(name)]) }

  private static func alternate(_ text: String) -> KeySpec.Alternate { .init(title: text, actions: [.symbol(text)]) }

  static func rows(for page: KeyboardPage) -> [[KeySpec]] {
    switch page {
    case .basic:
      return [
        [
          KeySpec("group", .group, [.group], alternates: [.init(title: "|□|", actions: [.absolute])]),
          symbol(">", alternates: ["<", "≤", "≥", "≠"].map(alternate)),
          digit("7"), digit("8"), digit("9"), symbol("÷"),
        ],
        [
          KeySpec("fraction", .fraction, [.fraction]),
          KeySpec(
            "root", .root, [.squareRoot],
            alternates: [
              .init(title: "ⁿ√□", actions: [.nthRoot]), .init(title: "∛□", actions: [.nthRoot, .symbol("3"), .right]),
            ]),
          digit("4"), digit("5"), digit("6"), symbol("×"),
        ],
        [
          KeySpec(
            "power", .power, [.power],
            alternates: [.init(title: "□²", actions: [.exponent("2")]), .init(title: "□³", actions: [.exponent("3")])]),
          symbol("x", alternates: ["y", "z", "a", "b", "t"].map(alternate)),
          digit("1"), digit("2"), digit("3"), symbol("−"),
        ],
        [
          symbol("π", alternates: [alternate("e"), alternate("i")]),
          symbol("%", alternates: [alternate("!"), alternate("°")]),
          digit("0"), symbol(".", alternates: [alternate(",")]), symbol("=", alternates: [alternate("≠")]), symbol("+"),
        ],
      ]

    case .functions:
      return [
        [
          function("ln"), function("log"), symbol("e"), KeySpec("eˣ", [.symbol("e"), .power]),
          KeySpec("abs", .absolute, [.absolute]), symbol("!"),
        ],
        [function("nCr"), function("nPr"), function("gcd"), function("lcm"), function("floor"), function("ceil")],
        [function("round"), symbol(","), symbol("π"), symbol("%"), symbol("<"), symbol(">")],
        [
          symbol("≤"), symbol("≥"), symbol("≠"), symbol("="), KeySpec("(", [.symbol("(")]),
          KeySpec(")", [.symbol(")")]),
        ],
      ]

    case .trigonometry:
      return [
        [function("sin"), function("cos"), function("tan"), function("asin"), function("acos"), function("atan")],
        [
          function("sinh"), function("cosh"), function("tanh"), function("asinh"), function("acosh"), function("atanh"),
        ],
        [
          symbol("°"), symbol("π"), KeySpec("(", [.symbol("(")]), KeySpec(")", [.symbol(")")]), symbol(","),
          symbol("="),
        ],
      ]
    }
  }

  /// The letter keys, for variables.
  static let letterRows: [[String]] = [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    ["z", "x", "c", "v", "b", "n", "m"],
  ]
}
