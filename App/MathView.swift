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

/// A sequence of nodes in a row.
struct MathLine: View {
  let nodes: [MathNode]
  let size: CGFloat
  var cursor: CursorState?
  /// Draw a dotted box when the sequence is empty, so an unfilled slot can be seen.
  var placeholder = false

  private enum Item {
    case caret
    case box
    case node(Int)
  }

  private var items: [Item] {
    var result: [Item] = []
    let cursorHere = cursor?.path.isEmpty ?? false
    for index in 0...nodes.count {
      if cursorHere && cursor?.offset == index { result.append(.caret) }
      if index < nodes.count { result.append(.node(index)) }
    }
    if nodes.isEmpty && placeholder { result.append(.box) }
    return result
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

  var body: some View {
    HStack(alignment: .mathAxis, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        switch item {
        case .caret: Caret(size: size)
        case .box: PlaceholderBox(size: size)
        case .node(let index):
          MathNodeView(node: nodes[index], size: size, cursor: childCursor(index), isSign: isSign(index))
        }
      }
    }
  }
}

private struct MathNodeView: View {
  let node: MathNode
  let size: CGFloat
  let cursor: (slot: Int, state: CursorState)?
  var isSign = false

  private func slot(_ nodes: [MathNode], _ index: Int, scale: CGFloat = 1) -> MathLine {
    MathLine(
      nodes: nodes, size: size * scale, cursor: cursor?.slot == index ? cursor?.state : nil, placeholder: true)
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
        Text(name).font(.system(size: size)).fixedSize()
        slot(argument, 0)
          .padding(.horizontal, size * 0.3)
          .overlay(alignment: .leading) {
            ParenShape(opensRight: true).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
          }
          .overlay(alignment: .trailing) {
            ParenShape(opensRight: false).stroke(lineWidth: max(1, size * 0.05)).frame(width: size * 0.22)
          }
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
