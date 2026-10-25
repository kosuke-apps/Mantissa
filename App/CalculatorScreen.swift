import MantissaCore
import SwiftUI

/// The calculator: what you type, what it comes to, and the keyboard.
struct CalculatorScreen: View {
  @Environment(AppModel.self) private var model
  @State private var showsFullGraph = false

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      topBar
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          InputView()
          Divider().padding(.vertical, 10)
          ResultView(outcome: model.outcome)
          if let graph = model.graph {
            GraphCard(
              graph: graph,
              expand: ("arrow.up.left.and.arrow.down.right", "Show the graph larger", { showsFullGraph = true })
            )
            .padding(.top, 16)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      KeyboardView()
    }
    .background(Color(.systemBackground))
    .fullScreenCover(isPresented: $showsFullGraph) {
      if let graph = model.graph {
        GraphCard(
          graph: graph, height: nil,
          expand: ("arrow.down.right.and.arrow.up.left", "Close the large graph", { showsFullGraph = false })
        )
        .padding(12)
        .background(Color(.systemBackground))
      }
    }
    .sheet(isPresented: $model.showsHistory) { HistoryView() }
    .sheet(isPresented: $model.showsSettings) { SettingsView() }
  }

  /// The title, the angle unit (tap to switch) and Settings.
  private var topBar: some View {
    ZStack {
      HStack {
        Button {
          model.angleUnit = model.angleUnit == .radians ? .degrees : .radians
        } label: {
          Text(model.angleUnit == .radians ? "RAD" : "DEG")
            .scaledFont(size: 13, weight: .semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Angle unit")
        Spacer()
        HStack(spacing: 22) {
          Button {
            model.showsHistory = true
          } label: {
            Image(systemName: "clock").scaledFont(size: 18).foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("History")
          Button {
            model.showsSettings = true
          } label: {
            Image(systemName: "gearshape").scaledFont(size: 18).foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
        }
      }
      .padding(.horizontal, 20)
    }
    .frame(height: 48)
  }
}

private struct InputView: View {
  @Environment(AppModel.self) private var model

  private let size: CGFloat = 30
  @State private var spots: [CaretSpot] = []

  var body: some View {
    let editor = model.editor
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(editor.lines.enumerated()), id: \.offset) { index, line in
          // Short formulas sit at the left; a long one scrolls sideways and stays scrolled to its end.
          ViewThatFits(in: .horizontal) {
            MathLine(
              nodes: line, size: size, cursor: cursorState(in: editor, line: index), address: LineAddress(line: index)
            )
            .frame(minHeight: size * 1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
              MathLine(
                nodes: line, size: size, cursor: cursorState(in: editor, line: index),
                address: LineAddress(line: index)
              )
              .frame(minHeight: size * 1.4)
            }
            .defaultScrollAnchor(.trailing)
          }
          .overlay(alignment: .leading) {
            if editor.isEmpty && index == 0 {
              Text("Enter an expression or an equation…").scaledFont(size: 24).foregroundStyle(.tertiary)
                .allowsHitTesting(false)
            }
          }
        }
      }
      .coordinateSpace(name: formulaSpace)
      .onPreferenceChange(CaretSpotsKey.self) { spots = $0 }
      // A tap puts the cursor in the nearest place between two parts of the formula.
      .gesture(
        SpatialTapGesture(coordinateSpace: .named(formulaSpace)).onEnded { tap in
          guard let nearest = spots.min(by: { distance($0.point, tap.location) < distance($1.point, tap.location) })
          else { return }
          model.moveCursor(to: nearest.cursor)
        })
      if !editor.isEmpty {
        Button {
          model.clearAll()
        } label: {
          Image(systemName: "xmark.circle.fill").scaledFont(size: 22).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Clear")
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
      if model.canPaste { Button("Paste", systemImage: "doc.on.clipboard") { model.paste() } }
      if !editor.isEmpty { Button("Copy", systemImage: "doc.on.doc") { model.copyInput() } }
    }
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, (a.y - b.y) * 1.5) }

  private func cursorState(in editor: MathEditor, line: Int) -> CursorState? {
    guard editor.cursor.line == line else { return nil }
    return CursorState(path: editor.cursor.path[...], offset: editor.cursor.offset)
  }
}

private struct ResultView: View {
  @Environment(AppModel.self) private var model
  let outcome: AppModel.Outcome

  var body: some View {
    content.contextMenu {
      if let copyable = model.copyable {
        Button("Copy", systemImage: "doc.on.doc") { model.copy(copyable.exact) }
        if let decimal = copyable.decimal {
          Button("Copy decimal", systemImage: "doc.on.doc") { model.copy(decimal) }
        }
        if copyable.canBeInput { Button("Use as input", systemImage: "arrow.up.left") { model.useAnswerAsInput() } }
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch outcome {
    case .empty:
      EmptyView()
    case .incomplete:
      warning("This isn't a complete problem yet.")
    case .failure(let failure):
      switch failure {
      case .divisionByZero: warning("Dividing by zero has no answer.")
      case .noRealAnswer: warning("This has no real answer.")
      case .sizesDoNotFit: warning("These sizes do not fit together.")
      case .noInverse: warning("This matrix has no inverse.")
      case .undefinedHere: warning("This is undefined.")
      case .tooLarge: warning("This is too large to work out.")
      case .notSupportedYet: warning("This isn't supported yet.")
      case .doesNotExist: warning("This does not exist: it diverges, or the two sides of a limit disagree.")
      }
    case .solutions(let solutions):
      SolutionsView(solutions: solutions)
    case .answer(let answer):
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          if !answer.exact.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              MathLine(nodes: answer.exact, size: 34)
            }
          }
          if let decimal = answer.decimal {
            HStack(spacing: 6) {
              Text("≈").scaledFont(size: 22).foregroundStyle(.secondary)
              ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: decimal, size: 24) }
            }
          }
          if answer.hasNoRealValue { Text("This has no real value.").font(.footnote).foregroundStyle(.secondary) }
          ForEach(Array(answer.forms.enumerated()), id: \.offset) { _, form in
            VStack(alignment: .leading, spacing: 2) {
              Text(Self.title(of: form.kind)).font(.footnote).foregroundStyle(.secondary)
              ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: form.nodes, size: 26) }
            }
            .padding(.top, 6)
          }
        }
      }
      .answerCard()
    }
  }

  private static func title(of kind: AppModel.Answer.Form.Kind) -> LocalizedStringKey {
    switch kind {
    case .expanded: return "Expanded form"
    case .factored: return "Factored form"
    case .simplified: return "Simplified form"
    case .combined: return "As one fraction"
    }
  }

  private func warning(_ message: LocalizedStringKey) -> some View {
    Label {
      Text(message).scaledFont(size: 14).foregroundStyle(.secondary)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.accentColor)
    }
  }
}

/// The answer to an equation: one line for each solution, or a sentence when there is none or every number works.
private struct SolutionsView: View {
  @Environment(AppModel.self) private var model
  let solutions: AppModel.Solutions

  /// "Solve for  x  a  b": the letters of an equation, the one in use filled.
  private var choices: some View {
    HStack(spacing: 8) {
      Text("Solve for").scaledFont(size: 15).foregroundStyle(.secondary)
      ForEach(solutions.choices, id: \.self) { letter in
        let selected = letter == solutions.chosen
        Button {
          model.solve(for: letter)
        } label: {
          Text(letter)
            .scaledFont(size: 17, weight: .medium)
            .frame(minWidth: 36, minHeight: 32)
            .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
            .background(selected ? Color.primary : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Solve for \(letter)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      VStack(alignment: .leading, spacing: 14) {
        if solutions.choices.count >= 2 { choices }
        switch solutions.kind {
        case .values:
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
        case .none:
          Text("No solution").scaledFont(size: 28)
        case .everything:
          Text(solutions.lines.isEmpty ? "Every number is a solution." : "Every number is a solution, except:")
            .scaledFont(size: 20)
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
        case .truth(let value):
          Text(value ? "True" : "False").scaledFont(size: 28)
        case .periodic(let integer):
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
          Text("\(integer) is any integer").scaledFont(size: 18).foregroundStyle(.secondary)
        case .dependent(let free):
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
          Text("\(free.joined(separator: ", ")) can be any number").scaledFont(size: 18).foregroundStyle(.secondary)
        case .intervals:
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { index, line in
            if index > 0 { Text("or").scaledFont(size: 18).foregroundStyle(.secondary) }
            row(line)
          }
          if let notation = solutions.notation {
            ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: notation, size: 24) }
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .answerCard()
  }

  private func row(_ line: AppModel.Solutions.Line) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: line.exact, size: 32) }
      if let decimal = line.decimal {
        HStack(spacing: 6) {
          if !line.decimalIsLabelled { Text("≈").scaledFont(size: 20).foregroundStyle(.secondary) }
          ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: decimal, size: 22) }
        }
      }
    }
  }
}

extension View {
  /// What an answer sits on: a soft rounded card.
  fileprivate func answerCard() -> some View {
    padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
  }
}
