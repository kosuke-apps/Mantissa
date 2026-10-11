import MantissaCore
import SwiftUI

/// The list of earlier problems, newest first, grouped by day. Tapping one puts it back into the calculator.
struct HistoryView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var showsSavedOnly = false
  @State private var confirmsClearing = false

  private var entries: [HistoryEntry] {
    showsSavedOnly ? model.history.entries.filter(\.isSaved) : model.history.entries
  }

  /// The entries split by calendar day, newest day first.
  private var days: [(day: Date, entries: [HistoryEntry])] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
    return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
  }

  var body: some View {
    NavigationStack {
      Group {
        if entries.isEmpty {
          ContentUnavailableView(
            showsSavedOnly ? "Nothing saved yet" : "No history yet", systemImage: showsSavedOnly ? "star" : "clock",
            description: Text(
              showsSavedOnly ? "Tap the star on a problem to keep it here." : "Problems you work out show up here."))
        } else {
          list
        }
      }
      .navigationTitle("History")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showsSavedOnly.toggle()
          } label: {
            Image(systemName: showsSavedOnly ? "star.fill" : "star")
          }
          .accessibilityLabel("Show saved problems only")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .bottomBar) {
          Button("Clear history", role: .destructive) { confirmsClearing = true }
            .disabled(model.history.entries.isEmpty)
        }
      }
      .confirmationDialog("Clear the history?", isPresented: $confirmsClearing, titleVisibility: .visible) {
        Button("Clear history", role: .destructive) { model.history.clear() }
      } message: {
        Text("Saved problems are kept.")
      }
    }
  }

  private var list: some View {
    List {
      ForEach(days, id: \.day) { day, entries in
        Section {
          ForEach(entries) { entry in
            Button {
              model.open(entry)
              dismiss()
            } label: {
              HistoryRow(entry: entry)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button(role: .destructive) {
                model.history.delete([entry.id])
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
            .swipeActions(edge: .leading) {
              Button {
                model.history.toggleSaved(entry.id)
              } label: {
                Label(entry.isSaved ? "Unsave" : "Save", systemImage: entry.isSaved ? "star.slash" : "star")
              }
              .tint(.accentColor)
            }
          }
        } header: {
          Text(Self.title(for: day))
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private static func title(for day: Date) -> LocalizedStringKey {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    return LocalizedStringKey(day.formatted(date: .abbreviated, time: .omitted))
  }
}

private struct HistoryRow: View {
  @Environment(AppModel.self) private var model
  let entry: HistoryEntry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
          ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: line, size: 20) }
        }
        if entry.exact.isEmpty {
          Label("Graph", systemImage: "chart.xyaxis.line").font(.footnote).foregroundStyle(Color.accentColor)
        } else {
          HStack(spacing: 6) {
            Text("=").font(.system(size: 17)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) { MathLine(nodes: entry.exact, size: 22) }
          }
          .foregroundStyle(Color.accentColor)
        }
      }
      Spacer(minLength: 0)
      Button {
        model.history.toggleSaved(entry.id)
      } label: {
        Image(systemName: entry.isSaved ? "star.fill" : "star")
          .foregroundStyle(entry.isSaved ? Color.accentColor : Color.secondary)
          .frame(width: 32, height: 32)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(entry.isSaved ? "Unsave" : "Save")
    }
    .contentShape(Rectangle())
    .padding(.vertical, 4)
  }
}
