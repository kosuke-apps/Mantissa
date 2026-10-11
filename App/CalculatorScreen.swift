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
  }

  private var topBar: some View {
    Text("Calculator")
      .font(.system(size: 17, weight: .semibold))
      .frame(maxWidth: .infinity)
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
      case .notSupportedYet: warning("Equations and inequalities are not supported yet.")
      }
    case .answer(let answer):
      HStack(alignment: .top, spacing: 12) {
        Rectangle().fill(Color.accentColor).frame(width: 4)
        VStack(alignment: .leading, spacing: 8) {
          ScrollView(.horizontal, showsIndicators: false) {
            MathLine(nodes: answer.exact, size: 34)
          }
          if let decimal = answer.decimal {
            HStack(spacing: 6) {
              Text("≈").font(.system(size: 22)).foregroundStyle(.secondary)
              ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: decimal, size: 24) }
            }
          }
          if answer.hasNoRealValue { Text("This has no real value.").font(.footnote).foregroundStyle(.secondary) }
        }
      }
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
