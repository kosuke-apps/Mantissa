import MantissaCore
import SwiftUI

// Drawing a `MathNode` tree: the same views show what is being typed (with a cursor) and what the answer is (without).

extension VerticalAlignment {
  private enum MathAxisID: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
  }

  /// The line that fraction bars sit on and that the middle of ordinary symbols is on. Stacks of symbols, fractions and
  /// exponents line up along it.
  static let mathAxis = VerticalAlignment(MathAxisID.self)
}

/// Where the cursor is, relative to the sequence being drawn: `path` leads from this sequence into the slot it is in;
/// when `path` is empty the cursor is in this sequence at `offset`.
struct CursorState: Equatable {
  var path: ArraySlice<MathCursor.Step>
  var offset: Int
}

/// A font of a fixed point size that follows the user's text size setting.
private struct ScaledFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: Font.Weight

  init(size: CGFloat, weight: Font.Weight) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    self.weight = weight
  }

  func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
}

extension View {
  /// `font(.system(size:))` that grows and shrinks with Dynamic Type.
  func scaledFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
    modifier(ScaledFont(size: size, weight: weight))
  }
}

/// Where in the formula a sequence of nodes is: its line, and the chain of structure slots that lead to it.
struct LineAddress: Hashable {
  var line: Int
  var path: [MathCursor.Step] = []

  /// The address of slot `slot` of the node at `index` of this sequence.
  func entering(index: Int, slot: Int) -> LineAddress {
    LineAddress(line: line, path: path + [MathCursor.Step(index: index, slot: slot)])
  }
}

/// A place the cursor can be put, and where it is on screen: tapping the formula goes to the nearest one.
struct CaretSpot: Equatable {
  var cursor: MathCursor
  var point: CGPoint
}

struct CaretSpotsKey: PreferenceKey {
  static let defaultValue: [CaretSpot] = []
  static func reduce(value: inout [CaretSpot], nextValue: () -> [CaretSpot]) { value += nextValue() }
}

/// The coordinate space the caret spots are measured in.
let formulaSpace = "formula"

/// A sequence of nodes in a row.
struct MathLine: View {
  let nodes: [MathNode]
  @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1
  private let baseSize: CGFloat
  var cursor: CursorState?
  /// Draw a dotted box when the sequence is empty, so an unfilled slot can be seen.
  var placeholder = false
  /// Whether the size follows the text size setting. A formula inside another (a numerator, an exponent) is sized from the one
  /// around it, which has already been scaled.
  private let scalesWithTextSize: Bool
  /// The size of the characters, in points.
  var size: CGFloat { baseSize * (scalesWithTextSize ? scale : 1) }

  /// Where this sequence is in the formula being edited; `nil` for a formula that is only shown.
  let address: LineAddress?

  init(
    nodes: [MathNode], size: CGFloat, cursor: CursorState? = nil, placeholder: Bool = false,
    scalesWithTextSize: Bool = true, address: LineAddress? = nil
  ) {
    self.address = address
    self.nodes = nodes
    baseSize = size
    self.cursor = cursor
    self.placeholder = placeholder
    self.scalesWithTextSize = scalesWithTextSize
  }

  private enum Item {
    case caret
    case box
    case node(Int)
    /// A matrix and the exponent right after it (`A²`, `A⁻¹`), which sits at the top of the matrix and not at its middle.
    case matrixWithExponent(Int)
  }

  private var items: [Item] {
    var result: [Item] = []
    let cursorHere = cursor?.path.isEmpty ?? false
    var index = 0
    while index <= nodes.count {
      if cursorHere && cursor?.offset == index { result.append(.caret) }
      if index < nodes.count {
        if case .matrix = nodes[index], index + 1 < nodes.count, case .superscript = nodes[index + 1],
          !(cursorHere && cursor?.offset == index + 1)
        {
          result.append(.matrixWithExponent(index))
          index += 2
          continue
        }
        result.append(.node(index))
      }
      index += 1
    }
    if nodes.isEmpty && placeholder { result.append(.box) }
    return result
  }

  /// The node at `index`, drawn, and the places the cursor can be put around it.
  private func nodeView(_ index: Int) -> some View {
    MathNodeView(
      node: nodes[index], size: size, cursor: childCursor(index), isSign: isSign(index), address: address, index: index
    )
    .background(
      spotReader { frame in
        var spots = [spot(at: index, x: frame.minX, y: frame.midY)]
        if index == nodes.count - 1 { spots.append(spot(at: nodes.count, x: frame.maxX, y: frame.midY)) }
        return spots
      })
  }

  /// Whether the node at `index` is a plus or minus that is a sign (at the start, or after an operator or a comma) and not
  /// an operation between two things, so it sits against what it applies to.
  private func isSign(_ index: Int) -> Bool {
    guard index > 0 else { return true }
    guard case .symbol(let text) = nodes[index - 1] else { return false }
    return SymbolView.spaced.contains(text) || [",", " ", "(", "[", "{"].contains(text)
  }

  private func childCursor(_ index: Int) -> (slot: Int, state: CursorState)? {
    guard let cursor, let step = cursor.path.first, step.index == index else { return nil }
    return (step.slot, CursorState(path: cursor.path.dropFirst(), offset: cursor.offset))
  }

  /// The cursor position before the node at `offset`, drawn at (`x`, `y`).
  private func spot(at offset: Int, x: CGFloat, y: CGFloat) -> CaretSpot {
    let place = address ?? LineAddress(line: 0)
    return CaretSpot(cursor: MathCursor(line: place.line, path: place.path, offset: offset), point: CGPoint(x: x, y: y))
  }

  /// Reports where the view is, as caret spots, when the sequence is part of a formula being edited.
  private func spotReader(_ spots: @escaping (CGRect) -> [CaretSpot]) -> some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: CaretSpotsKey.self, value: address == nil ? [] : spots(proxy.frame(in: .named(formulaSpace))))
    }
  }

  var body: some View {
    HStack(alignment: .mathAxis, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        switch item {
        case .caret: Caret(size: size)
        case .box:
          PlaceholderBox(size: size).background(spotReader { [spot(at: 0, x: $0.midX, y: $0.midY)] })
        case .node(let index):
          nodeView(index)
        case .matrixWithExponent(let index):
          HStack(alignment: .top, spacing: size * 0.05) {
            nodeView(index)
            nodeView(index + 1)
          }
        }
      }
    }
    // Read as one piece of text (`(√6 − √2)/4`) rather than a glyph at a time.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(nodes.plainText)
  }
}

private struct MathNodeView: View {
  let node: MathNode
  let size: CGFloat
  let cursor: (slot: Int, state: CursorState)?
  var isSign = false
  /// Where the sequence this node is in sits, and the node's index in it, so that its slots can say where they are.
  var address: LineAddress?
  var index = 0

  /// The calculus functions are written the way they are read: d/dx, ∫ and Σ.
  private static func displayName(of name: String) -> String {
    switch name {
    case "diff": return "d/dx"
    case "int": return "∫"
    case "sum": return "Σ"
    default: return name
    }
  }

  private func slot(_ nodes: [MathNode], _ slotIndex: Int, scale: CGFloat = 1) -> MathLine {
    MathLine(
      nodes: nodes, size: size * scale, cursor: cursor?.slot == slotIndex ? cursor?.state : nil, placeholder: true,
      scalesWithTextSize: false, address: address?.entering(index: self.index, slot: slotIndex))
  }

  // MARK: Calculus operators

  private func word(_ text: String, scale: CGFloat = 1) -> some View {
    Text(text).font(.system(size: size * scale)).fixedSize()
  }

  private func parenthesised(_ nodes: [MathNode], _ index: Int) -> some View {
    slot(nodes, index)
      .padding(.horizontal, size * 0.3)
      .overlay(alignment: .leading) {
        ParenShape(opensRight: true).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
      }
      .overlay(alignment: .trailing) {
        ParenShape(opensRight: false).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
      }
  }

  /// ∫ with its ends beside it and `dx` after the integrand; Σ with the index below and the end above; lim with the variable and
  /// the point below; d/dx stacked. The expression is slot 0 and the variable slot 1 in each.
  @ViewBuilder
  private func calculus(_ kind: CalculusKind, _ slots: [[MathNode]]) -> some View {
    switch kind {
    case .integral:
      HStack(alignment: .mathAxis, spacing: size * 0.1) {
        VStack(spacing: size * 0.1) {
          slot(slots[3], 3, scale: 0.6)
          word("∫", scale: 1.5)
          slot(slots[2], 2, scale: 0.6)
        }
        .alignmentGuide(.mathAxis) { $0[VerticalAlignment.center] }
        slot(slots[0], 0)
        HStack(spacing: size * 0.05) {
          word("d")
          slot(slots[1], 1)
        }
      }
    case .sum:
      HStack(alignment: .mathAxis, spacing: size * 0.1) {
        VStack(spacing: size * 0.06) {
          slot(slots[3], 3, scale: 0.6)
          word("Σ", scale: 1.35)
          HStack(spacing: size * 0.02) {
            slot(slots[1], 1, scale: 0.6)
            word("=", scale: 0.6)
            slot(slots[2], 2, scale: 0.6)
          }
        }
        .alignmentGuide(.mathAxis) { $0[VerticalAlignment.center] }
        slot(slots[0], 0)
      }
    case .limit:
      HStack(alignment: .mathAxis, spacing: size * 0.12) {
        VStack(spacing: size * 0.02) {
          word("lim")
          HStack(spacing: size * 0.02) {
            slot(slots[1], 1, scale: 0.6)
            word("→", scale: 0.6)
            slot(slots[2], 2, scale: 0.6)
          }
        }
        .alignmentGuide(.mathAxis) { _ in size * 0.6 }
        slot(slots[0], 0)
      }
    case .derivative:
      HStack(alignment: .mathAxis, spacing: size * 0.05) {
        VStack(spacing: size * 0.06) {
          word("d", scale: 0.85)
          Rectangle()
            .frame(width: size * 1.15, height: max(1, size * 0.055))
            .alignmentGuide(.mathAxis) { $0[VerticalAlignment.center] }
          HStack(spacing: size * 0.02) {
            word("d", scale: 0.85)
            slot(slots[1], 1, scale: 0.85)
          }
        }
        .padding(.horizontal, size * 0.03)
        parenthesised(slots[0], 0)
      }
    }
  }

  var body: some View {
    switch node {
    case .symbol(let text):
      SymbolView(text: text, size: size, isSign: isSign)

    case .fraction(let numerator, let denominator):
      VStack(spacing: size * 0.08) {
        slot(numerator, 0).padding(.horizontal, size * 0.04)
        Rectangle()
          .frame(height: max(1, size * 0.055))
          .alignmentGuide(.mathAxis) { $0[VerticalAlignment.center] }
        slot(denominator, 1).padding(.horizontal, size * 0.04)
      }
      // The bar is as wide as the wider of the two lines, not as wide as the space it is offered.
      .fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, size * 0.03)

    case .radical(let index, let radicand):
      HStack(alignment: .mathAxis, spacing: 0) {
        if let index {
          slot(index, 0, scale: 0.55)
            .padding(.trailing, -size * 0.45)
            .offset(y: -size * 0.3)
        }
        slot(radicand, index == nil ? 0 : 1)
          .padding(EdgeInsets(top: size * 0.2, leading: size * 0.75, bottom: size * 0.04, trailing: size * 0.1))
          .background(
            RadicalShape(signWidth: size * 0.7).stroke(
              style: StrokeStyle(lineWidth: max(1, size * 0.05), lineJoin: .round)))
      }

    case .superscript(let content):
      slot(content, 0, scale: 0.68)
        .alignmentGuide(.mathAxis) { $0[.bottom] + size * 0.12 }

    case .group(let content):
      slot(content, 0)
        .padding(.horizontal, size * 0.3)
        .overlay(alignment: .leading) {
          ParenShape(opensRight: true).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
        }
        .overlay(alignment: .trailing) {
          ParenShape(opensRight: false).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
        }

    case .function(let name, let argument):
      HStack(alignment: .mathAxis, spacing: size * 0.04) {
        Text(Self.displayName(of: name)).font(.system(size: size)).fixedSize()
        slot(argument, 0)
          .padding(.horizontal, size * 0.3)
          .overlay(alignment: .leading) {
            ParenShape(opensRight: true).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
          }
          .overlay(alignment: .trailing) {
            ParenShape(opensRight: false).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
          }
      }

    case .logarithm(let base, let argument):
      HStack(alignment: .mathAxis, spacing: size * 0.04) {
        word("log")
        slot(base, 0, scale: 0.6)
          .alignmentGuide(.mathAxis) { $0[.top] - size * 0.18 }
        parenthesised(argument, 1)
      }

    case .calculus(let kind, let slots):
      calculus(kind, slots)

    case .matrix(let rows, let columns, let cells):
      // The rows and columns line up in a grid, with a square bracket at each side as tall as the whole.
      Grid(horizontalSpacing: size * 0.8, verticalSpacing: size * 0.3) {
        ForEach(0..<rows, id: \.self) { row in
          GridRow {
            ForEach(0..<columns, id: \.self) { column in
              // Every cell is as tall as a line of text, so that the rows do not change height with the cursor.
              slot(cells[row * columns + column], row * columns + column)
                .frame(minWidth: size * 0.6, minHeight: size * 1.2)
            }
          }
        }
      }
      .padding(.horizontal, size * 0.4)
      .padding(.vertical, size * 0.1)
      .overlay(alignment: .leading) {
        BracketShape(opensRight: true).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.18)
      }
      .overlay(alignment: .trailing) {
        BracketShape(opensRight: false).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.18)
      }

    case .absolute(let content):
      slot(content, 0)
        .padding(.horizontal, size * 0.22)
        .overlay(alignment: .leading) { Rectangle().frame(width: max(1, size * 0.05)) }
        .overlay(alignment: .trailing) { Rectangle().frame(width: max(1, size * 0.05)) }
    }
  }
}

private struct SymbolView: View {
  let text: String
  let size: CGFloat
  var isSign = false

  static let spaced: Set<String> = ["+", "−", "×", "÷", "=", "<", ">", "≤", "≥", "≠", "≈", "·", "∪"]

  var body: some View {
    let isOperation = Self.spaced.contains(text) && !(isSign && (text == "+" || text == "−"))
    Text(text)
      .font(.system(size: size))
      .monospacedDigit()
      .fixedSize()
      .padding(.horizontal, isOperation ? size * 0.2 : 0)
  }
}

private struct Caret: View {
  let size: CGFloat
  @State private var dim = false

  var body: some View {
    Rectangle()
      .fill(Color.accentColor)
      .frame(width: 2, height: size * 1.15)
      .opacity(dim ? 0.1 : 1)
      .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dim = true } }
  }
}

private struct PlaceholderBox: View {
  let size: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: 2)
      .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
      .foregroundStyle(.secondary)
      .frame(width: size * 0.55, height: size * 0.75)
      .padding(.horizontal, 1)
  }
}

private struct ParenShape: Shape {
  /// True for "(", whose bulge is on the left.
  let opensRight: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let near = opensRight ? rect.maxX : rect.minX
    let far = opensRight ? rect.minX : rect.maxX
    path.move(to: CGPoint(x: near, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: near, y: rect.maxY), control: CGPoint(x: far, y: rect.midY))
    return path
  }
}

/// A square bracket: `[` when it opens to the right.
private struct BracketShape: Shape {
  let opensRight: Bool

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let near = opensRight ? rect.maxX : rect.minX
    let far = opensRight ? rect.minX : rect.maxX
    path.move(to: CGPoint(x: near, y: rect.minY))
    path.addLine(to: CGPoint(x: far, y: rect.minY))
    path.addLine(to: CGPoint(x: far, y: rect.maxY))
    path.addLine(to: CGPoint(x: near, y: rect.maxY))
    return path
  }
}

private struct RadicalShape: Shape {
  let signWidth: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let w = min(signWidth, rect.width)
    let h = rect.height
    path.move(to: CGPoint(x: w * 0.05, y: h * 0.6))
    path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.52))
    path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.97))
    path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.05))
    path.addLine(to: CGPoint(x: rect.maxX, y: h * 0.05))
    return path
  }
}
