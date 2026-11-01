import MantissaCore
import SwiftUI

/// The calculator: what you type, what it comes to, and the keyboard.
struct CalculatorScreen: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dynamicTypeSize) private var textSize
  @State private var showsFullGraph = false
  /// The whole window; `window` below is what is left for the calculator itself once the history column has taken its share.
  @State private var fullWindow = WindowMetrics.firstGuess
  /// The room the window controls of an iPad window take at its top-left corner; they lie over the content.
  @State private var controlsInset: CGFloat = 0

  private let historyColumnWidth: CGFloat = 300
  /// At the accessibility text sizes a column of earlier problems would be too narrow to read, and the workspace scrolls as it does
  /// on the iPhone, so that nothing is left behind the keyboard.
  private var usesLargeText: Bool { textSize >= .accessibility1 }
  private var showsHistoryColumn: Bool { fullWindow.showsHistoryColumn && !usesLargeText }
  private var window: WindowMetrics {
    showsHistoryColumn
      ? WindowMetrics(size: CGSize(width: fullWindow.width - historyColumnWidth - 1, height: fullWindow.height))
      : fullWindow
  }

  var body: some View {
    @Bindable var model = model
    HStack(spacing: 0) {
      if showsHistoryColumn {
        HistoryColumn().frame(width: historyColumnWidth)
        Divider()
      }
      calculator
    }
    .background(Color(.systemBackground))
    .takesHardwareKeyboardInput()
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      fullWindow = WindowMetrics(size: $0)
      controlsInset = Self.windowControlsInset()
    }
    .environment(\.window, window)
    .environment(\.windowControlsInset, controlsInset)
    .task { Self.setMinimumWindowSize() }
    // The history column replaces the history button, so what that button opened is closed.
    .onChange(of: showsHistoryColumn) { _, shown in if shown { model.showsHistory = false } }
    .onChange(of: model.showsHistory) { _, shown in if shown && showsHistoryColumn { model.showsHistory = false } }
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
    // On the iPhone, and in a narrow window, History and Settings are sheets; with more room they are popovers from their buttons.
    .sheet(isPresented: presented(\.showsHistory, inCompactWindow: true)) { HistoryView() }
    .sheet(isPresented: presented(\.showsSettings, inCompactWindow: true)) { SettingsView() }
  }

  /// The top bar, the workspace and the keyboard.
  private var calculator: some View {
    VStack(spacing: 0) {
      topBar
      if window.kind == .compact || usesLargeText {
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
      } else {
        Workspace(showsFullGraph: $showsFullGraph)
      }
      KeyboardView()
    }
  }

  /// Whether something that is a sheet in a compact window and a popover in a larger one is showing as the one asked for.
  private func presented(_ flag: ReferenceWritableKeyPath<AppModel, Bool>, inCompactWindow: Bool) -> Binding<Bool> {
    Binding(
      get: { model[keyPath: flag] && (window.kind == .compact) == inCompactWindow },
      set: { model[keyPath: flag] = $0 })
  }

  /// The window controls (the three dots) of an iPad window lie over its top-left corner whenever the window is not the size of the
  /// screen, and what is there has to keep clear of them. A Mac window has a title bar of its own, and an iPhone has none.
  private static func windowControlsInset() -> CGFloat {
    guard UIDevice.current.userInterfaceIdiom == .pad, !ProcessInfo.processInfo.isiOSAppOnMac else { return 0 }
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      return scene.coordinateSpace.bounds.size == scene.screen.bounds.size ? 0 : 64
    }
    return 0
  }

  /// A window cannot be made too small to use: a Stage Manager window on the iPad, a window on the Mac.
  private static func setMinimumWindowSize() {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      scene.sizeRestrictions?.minimumSize = CGSize(width: 320, height: 480)
    }
    #if DEBUG
      // `-MantissaOrientation landscape` (or `portrait`) turns an iPad to that orientation, for checking a screen without the
      // Simulator's menu.
      let arguments = ProcessInfo.processInfo.arguments
      if let index = arguments.firstIndex(of: "-MantissaOrientation"), index + 1 < arguments.count {
        let mask: UIInterfaceOrientationMask = arguments[index + 1] == "landscape" ? .landscapeRight : .portrait
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
          scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
      }
    #endif
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
          if !showsHistoryColumn {
            Button {
              model.showsHistory = true
            } label: {
              Image(systemName: "clock").scaledFont(size: 18).foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History")
            .popover(isPresented: presented(\.showsHistory, inCompactWindow: false), arrowEdge: .top) {
              HistoryView()
                .frame(minWidth: 380, idealWidth: 420, minHeight: 480, idealHeight: 620)
                .presentationCompactAdaptation(.sheet)
            }
          }
          Button {
            model.showsSettings = true
          } label: {
            Image(systemName: "gearshape").scaledFont(size: 18).foregroundStyle(.primary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
          .popover(isPresented: presented(\.showsSettings, inCompactWindow: false), arrowEdge: .top) {
            SettingsView()
              .frame(minWidth: 380, idealWidth: 420, minHeight: 480, idealHeight: 600)
              .presentationCompactAdaptation(.sheet)
          }
        }
      }
      .padding(.leading, showsHistoryColumn ? 20 : 20 + controlsInset)
      .padding(.trailing, 20)
    }
    .frame(height: 48)
  }
}

/// The workspace of a window with room. The formula goes across the top. In a regular window the answer is under it and the graph
/// takes what is left; in a wide one the answer and the graph are side by side. The graph is never behind the keyboard, and
/// without one the answer has the room.
private struct Workspace: View {
  @Environment(AppModel.self) private var model
  @Environment(\.window) private var window
  @Environment(\.dynamicTypeSize) private var textSize
  @Binding var showsFullGraph: Bool

  private let margin: CGFloat = 28
  private let gap: CGFloat = 20

  /// Side by side only when each of the two has room to be read; at a very large text size the answer needs the width.
  private var isSideBySide: Bool { window.kind == .wide && textSize < .accessibility1 }

  var body: some View {
    GeometryReader { room in
      VStack(alignment: .leading, spacing: 0) {
        InputView()
        Divider().padding(.vertical, 10)
        if let graph = model.graph {
          if isSideBySide {
            HStack(alignment: .top, spacing: gap) {
              ScrollView { answer }
                .frame(width: min(max((room.size.width - 2 * margin) * 0.42, 380), 560))
              GraphCard(graph: graph, height: nil)
            }
            .frame(maxHeight: .infinity)
          } else {
            VStack(spacing: 14) {
              // The answer as tall as it is, up to a share of the height, and then it scrolls.
              AnswerBox(maxHeight: room.size.height * 0.45) { answer }
              GraphCard(graph: graph, height: nil).frame(minHeight: 220)
            }
            .frame(maxHeight: .infinity)
          }
        } else {
          ScrollView { answer.frame(maxWidth: 720, alignment: .leading) }
        }
      }
      .padding(.horizontal, margin)
      .padding(.top, 14)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var answer: some View {
    ResultView(outcome: model.outcome).frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The answer, as tall as it is and no taller than `maxHeight`, scrolling when it is more. (`ViewThatFits` would pick the answer
/// that fits but then be as tall as the room it was offered, leaving a gap round it.)
private struct AnswerBox<Content: View>: View {
  let maxHeight: CGFloat
  @ViewBuilder var content: Content
  @State private var naturalHeight: CGFloat = 0

  var body: some View {
    ScrollView {
      content.onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        naturalHeight = $0
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: min(naturalHeight, maxHeight))
  }
}

private struct InputView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.window) private var window

  private var size: CGFloat { 30 * window.contentScale }
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
              Text("Enter an expression or an equation…").scaledFont(size: 24 * window.contentScale).foregroundStyle(
                .tertiary
              )
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
  @Environment(\.window) private var window
  let outcome: AppModel.Outcome

  /// 1 on the iPhone, larger in a window with room.
  private var k: CGFloat { window.contentScale }

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
              MathLine(nodes: answer.exact, size: 34 * k)
            }
          }
          if let decimal = answer.decimal {
            HStack(spacing: 6) {
              Text("≈").scaledFont(size: 22 * k).foregroundStyle(.secondary)
              ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: decimal, size: 24 * k) }
            }
          }
          if answer.hasNoRealValue { Text("This has no real value.").font(.footnote).foregroundStyle(.secondary) }
          ForEach(Array(answer.forms.enumerated()), id: \.offset) { _, form in
            VStack(alignment: .leading, spacing: 2) {
              Text(Self.title(of: form.kind)).font(.footnote).foregroundStyle(.secondary)
              ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: form.nodes, size: 26 * k) }
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
      Text(message).scaledFont(size: 14 * k).foregroundStyle(.secondary)
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.accentColor)
    }
  }
}

/// The answer to an equation: one line for each solution, or a sentence when there is none or every number works.
private struct SolutionsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.window) private var window
  let solutions: AppModel.Solutions

  private var k: CGFloat { window.contentScale }

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
          Text("No solution").scaledFont(size: 28 * k)
        case .everything:
          Text(solutions.lines.isEmpty ? "Every number is a solution." : "Every number is a solution, except:")
            .scaledFont(size: 20 * k)
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
        case .truth(let value):
          Text(value ? "True" : "False").scaledFont(size: 28 * k)
        case .periodic(let integer):
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
          Text("\(integer) is any integer").scaledFont(size: 18 * k).foregroundStyle(.secondary)
        case .dependent(let free):
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { _, line in row(line) }
          Text("\(free.joined(separator: ", ")) can be any number").scaledFont(size: 18 * k).foregroundStyle(.secondary)
        case .intervals:
          ForEach(Array(solutions.lines.enumerated()), id: \.offset) { index, line in
            if index > 0 { Text("or").scaledFont(size: 18 * k).foregroundStyle(.secondary) }
            row(line)
          }
          if let notation = solutions.notation {
            ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: notation, size: 24 * k) }
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .answerCard()
  }

  private func row(_ line: AppModel.Solutions.Line) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: line.exact, size: 32 * k) }
      if let decimal = line.decimal {
        HStack(spacing: 6) {
          if !line.decimalIsLabelled { Text("≈").scaledFont(size: 20 * k).foregroundStyle(.secondary) }
          ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: decimal, size: 22 * k) }
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
