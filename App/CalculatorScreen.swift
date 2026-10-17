import MantissaCore
import SwiftUI

/// The calculator: what you type, what it comes to, and the keyboard.
struct CalculatorScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      topBar
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          InputView()
          Divider().padding(.vertical, 10)
          ResultView(outcome: model.outcome)
          if let graph = model.graph { GraphCard(graph: graph).padding(.top, 16) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      KeyboardView()
    }
    .background(Color(.systemBackground))
    .sheet(isPresented: $model.showsHistory) { HistoryView() }
    .sheet(isPresented: $model.showsSettings) { SettingsView() }
  }

  /// The title, the angle unit (tap to switch) and Settings.
  private var topBar: some View {
    ZStack {
      Text("Calculator").font(.system(size: 17, weight: .semibold))
      HStack {
        Button {
          model.angleUnit = model.angleUnit == .radians ? .degrees : .radians
        } label: {
          Text(model.angleUnit == .radians ? "RAD" : "DEG")
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Angle unit")
        Spacer()
        Button {
          model.showsSettings = true
        } label: {
          Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
      }
      .padding(.horizontal, 20)
    }
    .frame(height: 48)
  }
}

private struct InputView: View {
  @Environment(AppModel.self) private var model

  private let size: CGFloat = 30

  var body: some View {
    let editor = model.editor
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(editor.lines.enumerated()), id: \.offset) { index, line in
          // Short formulas sit at the left; a long one scrolls sideways and stays scrolled to its end.
          ViewThatFits(in: .horizontal) {
            MathLine(nodes: line, size: size, cursor: cursorState(in: editor, line: index))
              .frame(minHeight: size * 1.4)
              .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
              MathLine(nodes: line, size: size, cursor: cursorState(in: editor, line: index))
                .frame(minHeight: size * 1.4)
            }
            .defaultScrollAnchor(.trailing)
          }
          .overlay(alignment: .leading) {
            if editor.isEmpty && index == 0 {
              Text("Type a math problem…").font(.system(size: 24)).foregroundStyle(.tertiary).allowsHitTesting(false)
            }
          }
        }
      }
      if !editor.isEmpty {
        Button {
          model.clearAll()
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.secondary)
        }
        .accessibilityLabel("Clear")
      }
    }
  }

  private func cursorState(in editor: MathEditor, line: Int) -> CursorState? {
    guard editor.cursor.line == line else { return nil }
    return CursorState(path: editor.cursor.path[...], offset: editor.cursor.offset)
  }
}

private struct ResultView: View {
  let outcome: AppModel.Outcome

  var body: some View {
    switch outcome {
    case .empty:
      EmptyView()
    case .incomplete:
      warning("Please enter a complete math problem so we can solve it!")
    case .failure(let failure):
      switch failure {
      case .divisionByZero: warning("Dividing by zero has no answer.")
      case .noRealAnswer: warning("This has no real answer.")
      case .tooLarge: warning("This is too large to work out.")
      case .notSupportedYet: warning("This isn't supported yet.")
      case .doesNotExist: warning("This does not exist: it diverges, or the two sides of a limit disagree.")
      }
    case .solutions(let solutions):
      SolutionsView(solutions: solutions)
    case .answer(let answer):
      HStack(alignment: .top, spacing: 12) {
        Rectangle().fill(Color.accentColor).frame(width: 4)
        VStack(alignment: .leading, spacing: 8) {
          if !answer.exact.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              MathLine(nodes: answer.exact, size: 34)
            }
          }
          if let decimal = answer.decimal {
            HStack(spacing: 6) {
              Text("≈").font(.system(size: 22)).foregroundStyle(.secondary)
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
    }
  }

  private static func title(of kind: AppModel.Answer.Form.Kind) -> LocalizedStringKey {
    switch kind {
    case .expanded: return "Expanded form"
    case .factored: return "Factored form"
    case .simplified: return "Simplified form"
    }
  }

  private func warning(_ message: LocalizedStringKey) -> some View {
    Label {
      Text(message).font(.system(size: 14)).foregroundStyle(.secondary)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.accentColor)
    }
  }
}

/// The answer to an equation: one line for each solution, or a sentence when there is none or every number works.
private struct SolutionsView: View {
  let solutions: AppModel.Solutions

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Rectangle().fill(Color.accentColor).frame(width: 4)
      VStack(alignment: .leading, spacing: 14) {
        switch solutions.kind {
        case .values:
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
        case .none:
          Text("No solution").font(.system(size: 28))
        case .everything:
          Text(solutions.lines.isEmpty ? "Every number is a solution." : "Every number is a solution, except:")
            .font(.system(size: 20))
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
        case .truth(let value):
          Text(value ? "True" : "False").font(.system(size: 28))
        case .periodic(let integer):
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
          Text("\(integer) is any integer").font(.system(size: 18)).foregroundStyle(.secondary)
        case .dependent(let free):
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
          Text("\(free.joined(separator: ", ")) can be any number").font(.system(size: 18)).foregroundStyle(.secondary)
        case .intervals:
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { index, line in
            if index > 0 { Text("or").font(.system(size: 18)).foregroundStyle(.secondary) }
            row(line)
          }
          if let notation = solutions.notation {
            ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: notation, size: 24) }
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func row(_ line: AppModel.Solutions.Line) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: line.exact, size: 32) }
      if let decimal = line.decimal {
        HStack(spacing: 6) {
          if !line.decimalIsLabelled { Text("≈").font(.system(size: 20)).foregroundStyle(.secondary) }
          ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: decimal, size: 22) }
        }
      }
    }
  }
}
