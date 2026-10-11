import SwiftUI

/// The maths keyboard: a row of controls, the chips that switch pages, and six columns of keys.
struct KeyboardView: View {
  @Environment(AppModel.self) private var model
  @State private var page = KeyboardPage.basic
  @State private var showsLetters = false

  private let rowHeight: CGFloat = 54

  var body: some View {
    VStack(spacing: 0) {
      controlRow
      if !showsLetters { chipRow }
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
      controlButton(systemImage: "clock", accessibility: "History") { model.showsHistory = true }
      controlButton(systemImage: "arrow.left", accessibility: "Move left") { model.press(.left) }
      controlButton(systemImage: "arrow.right", accessibility: "Move right") { model.press(.right) }
      controlButton(systemImage: "return", accessibility: "New line") { model.press(.newLine) }
      controlButton(systemImage: "delete.left", accessibility: "Delete") { model.press(.backspace) }
    }
    .frame(height: 44)
    .padding(.horizontal, 6)
    .padding(.top, 4)
  }

  private func controlButton(
    _ title: LocalizedStringKey, accessibility: LocalizedStringKey, action: @escaping () -> Void
  )
    -> some View
  {
    Button(action: action) { Text(title).font(.system(size: 17)).frame(maxWidth: .infinity, maxHeight: .infinity) }
      .buttonStyle(.plain)
      .accessibilityLabel(accessibility)
  }

  private func controlButton(
    systemImage: String, accessibility: LocalizedStringKey, action: @escaping () -> Void
  )
    -> some View
  {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibility)
  }

  private var chipRow: some View {
    HStack(spacing: 8) {
      ForEach(KeyboardPage.allCases) { candidate in
        Button {
          page = candidate
        } label: {
          VStack(spacing: -1) {
            Text(candidate.chip.0)
            Text(candidate.chip.1)
          }
          .font(.system(size: 11, weight: .medium))
          .frame(maxWidth: .infinity)
          .frame(height: 34)
          .foregroundStyle(page == candidate ? Color(.systemBackground) : Color.primary)
          .background(page == candidate ? Color.primary : Color(.systemBackground), in: Capsule())
          .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: page == candidate ? 0 : 1))
        }
        .buttonStyle(.plain)
      }
    }
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

/// One key. A key with alternatives performs its own action when tapped and offers the alternatives when held.
private struct KeyView: View {
  let spec: KeySpec
  let perform: ([KeyAction]) -> Void

  private var fill: Color {
    spec.tone == .number ? Color(.systemGray5) : Color(.systemBackground)
  }

  private var face: some View {
    GlyphView(glyph: spec.glyph)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(fill)
      .overlay(alignment: .bottomTrailing) {
        if !spec.alternates.isEmpty {
          Circle().fill(Color.accentColor).frame(width: 4, height: 4).padding(5)
        }
      }
      .contentShape(Rectangle())
  }

  var body: some View {
    if spec.alternates.isEmpty {
      Button {
        perform(spec.actions)
      } label: {
        face
      }.buttonStyle(.plain)
    } else {
      Menu {
        ForEach(spec.alternates) { alternate in Button(alternate.title) { perform(alternate.actions) } }
      } label: {
        face
      } primaryAction: {
        perform(spec.actions)
      }
      .buttonStyle(.plain)
    }
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
    case .absolute:
      HStack(spacing: 2) {
        Text("|").font(.system(size: 24))
        box
        Text("|").font(.system(size: 24))
      }
    }
  }
}
