import SwiftUI

/// The maths keyboard: a row of controls, the tabs that switch pages, and six columns of keys.
struct KeyboardView: View {
  @Environment(AppModel.self) private var model
  @State private var page = KeyboardPage.basic
  @State private var showsLetters = false

  private let rowHeight: CGFloat = 54

  var body: some View {
    VStack(spacing: 0) {
      controlRow
      if !showsLetters { pageTabs }
      Group {
        if showsLetters { letterKeys } else { keys }
      }
      .padding(.horizontal, 6)
      .padding(.bottom, 6)
    }
    .background {
      UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
        .fill(Color(.secondarySystemBackground))
        .ignoresSafeArea(edges: .bottom)
    }
  }

  // MARK: Controls

  private var controlRow: some View {
    HStack(spacing: 0) {
      controlButton("abc", accessibility: "Letters") { showsLetters.toggle() }
      controlButton(systemImage: "arrow.left", accessibility: "Move left", repeats: true) { model.press(.left) }
      controlButton(systemImage: "arrow.right", accessibility: "Move right", repeats: true) { model.press(.right) }
      controlButton(systemImage: "return", accessibility: "New line") { model.press(.newLine) }
      // Everything at once, where the delete key takes one step at a time.
      controlButton("AC", accessibility: "Clear all", tint: .accentColor) { model.clearAll() }
      controlButton(systemImage: "delete.left", accessibility: "Delete", repeats: true) { model.press(.backspace) }
    }
    .frame(height: 44)
    .padding(.horizontal, 6)
    .padding(.top, 4)
  }

  private func controlButton(
    _ title: LocalizedStringKey, accessibility: LocalizedStringKey, tint: Color = .primary,
    action: @escaping () -> Void
  )
    -> some View
  {
    Button(action: action) {
      Text(title).font(.system(size: 17, weight: tint == .primary ? .regular : .semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibility)
  }

  /// A control with an icon. One that `repeats` goes on acting while it is held (delete, the arrows).
  private func controlButton(
    systemImage: String, accessibility: LocalizedStringKey, repeats: Bool = false, action: @escaping () -> Void
  )
    -> some View
  {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .buttonRepeatBehavior(repeats ? .enabled : .disabled)
    .accessibilityLabel(accessibility)
  }

  /// The pages of the keyboard, named in words, as one segmented control.
  private var pageTabs: some View {
    Picker("Keyboard page", selection: $page) {
      ForEach(KeyboardPage.allCases) { candidate in Text(candidate.title).tag(candidate) }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal, 10)
    .padding(.bottom, 6)
  }

  // MARK: Keys

  private var keys: some View {
    // Every page is four rows of six, so the keyboard keeps its height when the page changes.
    let rows = KeyboardLayout.rows(for: page)
    return VStack(spacing: 1) {
      ForEach(0..<4, id: \.self) { index in
        let row = index < rows.count ? rows[index] : []
        HStack(spacing: 1) {
          ForEach(row) { spec in KeyView(spec: spec) { model.press($0) }.frame(height: rowHeight) }
          ForEach(0..<max(0, 6 - row.count), id: \.self) { _ in Color.clear.frame(height: rowHeight) }
        }
      }
    }
  }

  private var letterKeys: some View {
    VStack(spacing: 1) {
      ForEach(Array(KeyboardLayout.letterRows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 1) {
          ForEach(row, id: \.self) { letter in
            Button {
              model.press(.symbol(letter))
            } label: {
              Text(letter).font(.system(size: 22)).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
            .buttonStyle(.plain)
            .frame(height: rowHeight)
          }
        }
      }
      HStack(spacing: 1) {
        Button {
          showsLetters = false
        } label: {
          Text("123").font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity).background(
            Color(.systemBackground))
        }
        .buttonStyle(.plain)
        Button {
          model.press(.symbol(","))
        } label: {
          Text(",").font(.system(size: 22)).frame(maxWidth: .infinity, maxHeight: .infinity).background(
            Color(.systemBackground))
        }
        .buttonStyle(.plain)
      }
      .frame(height: rowHeight)
    }
  }
}

/// What a key looks like, with a darker face while it is pressed.
private struct KeyFace: View {
  let spec: KeySpec
  var isPressed = false

  private var fill: Color { spec.tone == .number ? Color(.systemGray5) : Color(.systemBackground) }

  var body: some View {
    GlyphView(glyph: spec.glyph)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(fill)
      .overlay(Color.primary.opacity(isPressed ? 0.10 : 0))
      .overlay(alignment: .bottomTrailing) {
        if !spec.alternates.isEmpty {
          Circle().fill(Color.accentColor).frame(width: 4, height: 4).padding(5)
        }
      }
      .contentShape(Rectangle())
      .accessibilityLabel(KeyboardLayout.spokenName(for: spec.id) ?? LocalizedStringKey(spec.id))
  }
}

private struct KeyPressStyle: ButtonStyle {
  let spec: KeySpec

  func makeBody(configuration: Configuration) -> some View {
    KeyFace(spec: spec, isPressed: configuration.isPressed)
  }
}

/// One key. A key with alternatives performs its own action when tapped, and when it is held shows them in a row above it:
/// without lifting the finger it slides over the one it wants, feels a tick on each, and lets go to put it in.
private struct KeyView: View {
  let spec: KeySpec
  let perform: ([KeyAction]) -> Void

  var body: some View {
    if spec.alternates.isEmpty {
      Button {
        perform(spec.actions)
      } label: {
        KeyFace(spec: spec)
      }
      .buttonStyle(KeyPressStyle(spec: spec))
    } else {
      HeldKey(spec: spec, perform: perform)
    }
  }
}

private struct HeldKey: View {
  let spec: KeySpec
  let perform: ([KeyAction]) -> Void

  /// One thing the row above the key offers; the first is the key's own action.
  private struct Option {
    var glyph: Glyph?
    var title: String?
    var actions: [KeyAction]
  }

  private struct Popup {
    /// 1 when the row runs to the right of the key, −1 when it runs to the left (a key near the right edge).
    var direction: CGFloat
    var highlighted: Int?
  }

  @State private var frame = CGRect.zero
  @State private var isDown = false
  @State private var popup: Popup?
  @State private var hold: Task<Void, Never>?

  private let holdDelay = Duration.milliseconds(250)
  private let cellHeight: CGFloat = 52
  private let selection = UISelectionFeedbackGenerator()

  private var options: [Option] {
    [Option(glyph: spec.glyph, title: nil, actions: spec.actions)]
      + spec.alternates.map { Option(glyph: nil, title: $0.title, actions: $0.actions) }
  }

  /// The first cell is as wide as the key, so that it sits right above it; the others fit what they say.
  private var widths: [CGFloat] {
    options.enumerated().map { index, option in
      index == 0 ? max(frame.width, 44) : max(48, CGFloat(option.title?.count ?? 1) * 11 + 24)
    }
  }

  var body: some View {
    KeyFace(spec: spec, isPressed: isDown)
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        frame = $0
      }
      .overlay(alignment: (popup?.direction ?? 1) >= 0 ? .topLeading : .topTrailing) {
        if let popup { row(popup).offset(x: popup.direction >= 0 ? -4 : 4, y: -(cellHeight + 14)) }
      }
      .zIndex(popup == nil ? 0 : 1)
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
          .onChanged { value in
            if !isDown {
              isDown = true
              selection.prepare()
              hold = Task {
                try? await Task.sleep(for: holdDelay)
                if !Task.isCancelled, isDown { show() }
              }
            }
            if popup != nil { slide(to: value.location) }
          }
          .onEnded { value in finish(value) }
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(KeyboardLayout.spokenName(for: spec.id) ?? LocalizedStringKey(spec.id))
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { perform(spec.actions) }
      .accessibilityActions {
        ForEach(spec.alternates) { alternate in Button(alternate.title) { perform(alternate.actions) } }
      }
  }

  // MARK: The gesture

  private func show() {
    let total = widths.reduce(0, +)
    let screen = UIScreen.main.bounds.width
    // The row runs towards the side with room for it.
    let direction: CGFloat = frame.minX + total <= screen - 6 ? 1 : -1
    popup = Popup(direction: direction, highlighted: 0)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  /// The option under the finger: how far it is from the key's near edge, along the row.
  private func slide(to location: CGPoint) {
    guard let current = popup else { return }
    var index: Int? = nil
    // Let go below the key and nothing is chosen.
    if location.y <= frame.maxY + 36 {
      let distance = current.direction >= 0 ? location.x - frame.minX : frame.maxX - location.x
      var start: CGFloat = 0
      index = widths.count - 1
      for (position, width) in widths.enumerated() {
        if distance < start + width {
          index = position
          break
        }
        start += width
      }
    }
    if index != current.highlighted {
      popup?.highlighted = index
      if index != nil { selection.selectionChanged() }
    }
  }

  private func finish(_ value: DragGesture.Value) {
    hold?.cancel()
    hold = nil
    defer {
      isDown = false
      popup = nil
    }
    if let popup {
      if let index = popup.highlighted { perform(options[index].actions) }
    } else if hypot(value.translation.width, value.translation.height) < 24 {
      perform(spec.actions)
    }
  }

  // MARK: The row

  private func row(_ popup: Popup) -> some View {
    HStack(spacing: 2) {
      // A row that runs to the left has the key's own cell at its right end, nearest the key.
      let order = popup.direction >= 0 ? Array(options.indices) : Array(options.indices.reversed())
      ForEach(order, id: \.self) { index in
        let option = options[index]
        let selected = popup.highlighted == index
        Group {
          if let glyph = option.glyph {
            GlyphView(glyph: glyph)
          } else {
            Text(option.title ?? "").font(.system(size: 21)).lineLimit(1).minimumScaleFactor(0.7)
          }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .frame(width: widths[index], height: cellHeight)
        .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9))
      }
    }
    .padding(4)
    .background(
      RoundedRectangle(cornerRadius: 13).fill(Color(.tertiarySystemBackground))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color(.separator), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 9, y: 3)
    )
    .fixedSize()
    .allowsHitTesting(false)
  }
}

private struct GlyphView: View {
  let glyph: Glyph

  private var box: some View {
    RoundedRectangle(cornerRadius: 1.5)
      .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
      .frame(width: 9, height: 11)
  }

  var body: some View {
    switch glyph {
    case .text(let text):
      Text(text).font(.system(size: text.count > 2 ? 19 : 24)).minimumScaleFactor(0.6).lineLimit(1)
    case .fraction:
      VStack(spacing: 2) {
        box
        Rectangle().frame(width: 16, height: 1)
        box
      }
    case .root:
      HStack(spacing: 1) {
        Text("√").font(.system(size: 26))
        box
      }
    case .power:
      HStack(alignment: .top, spacing: 0) {
        box.padding(.top, 8)
        RoundedRectangle(cornerRadius: 1)
          .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
          .frame(width: 6, height: 7)
          .padding(.top, 2)
      }
    case .group:
      HStack(spacing: 1) {
        Text("(").font(.system(size: 24))
        box
        Text(")").font(.system(size: 24))
      }
    case .logarithm:
      HStack(alignment: .bottom, spacing: 0) {
        Text("log").font(.system(size: 22))
        RoundedRectangle(cornerRadius: 1)
          .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
          .frame(width: 6, height: 7)
          .padding(.bottom, -2)
      }
    case .absolute:
      HStack(spacing: 2) {
        Text("|").font(.system(size: 24))
        box
        Text("|").font(.system(size: 24))
      }
    }
  }
}
