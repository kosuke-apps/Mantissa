import MantissaCore
import Observation
import SwiftUI

/// One solved problem: what was typed and what it came to.
struct HistoryEntry: Codable, Identifiable, Equatable {
  var id = UUID()
  var date: Date
  var lines: [[MathNode]]
  /// The exact answer and, when there is one, the decimal, as they were shown.
  var exact: [MathNode]
  var decimal: [MathNode]?
  /// Saved problems are kept when the history is cleared and never dropped to make room.
  var isSaved = false

  /// The problem as the parser reads it, which is also how two entries are told to be the same.
  var text: String { MathEditor(lines: lines).text }
}

/// The history, kept in a small JSON file in the app's own storage. Nothing leaves the phone.
@MainActor @Observable
final class HistoryStore {
  private(set) var entries: [HistoryEntry] = []

  private let fileURL: URL?
  private let limit: Int

  /// `fileURL` is where the history is kept; `nil` keeps it in memory only (for tests and previews).
  init(fileURL: URL?, limit: Int = 300) {
    self.fileURL = fileURL
    self.limit = limit
    load()
  }

  /// The history in the app's own storage.
  convenience init() {
    self.init(fileURL: Self.defaultFileURL)
  }

  nonisolated static var defaultFileURL: URL? {
    guard
      let base = try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else { return nil }
    return base.appendingPathComponent("history.json")
  }

  // MARK: Changing the history

  /// Remembers a solved problem, newest first. The same problem typed again moves to the top instead of repeating.
  func record(lines: [[MathNode]], exact: [MathNode], decimal: [MathNode]?, date: Date = Date()) {
    let text = MathEditor(lines: lines).text
    var entry = HistoryEntry(date: date, lines: lines, exact: exact, decimal: decimal)
    if let index = entries.firstIndex(where: { $0.text == text }) {
      entry.id = entries[index].id
      entry.isSaved = entries[index].isSaved
      entries.remove(at: index)
    }
    entries.insert(entry, at: 0)
    trim()
    save()
  }

  func toggleSaved(_ id: HistoryEntry.ID) {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
    entries[index].isSaved.toggle()
    save()
  }

  func delete(_ ids: some Collection<HistoryEntry.ID>) {
    entries.removeAll { ids.contains($0.id) }
    save()
  }

  /// Removes everything except the saved problems, or those too when `keepingSaved` is false.
  func clear(keepingSaved: Bool = true) {
    entries = keepingSaved ? entries.filter(\.isSaved) : []
    save()
  }

  /// Drops the oldest problems that are not saved once there are more than `limit` of them.
  private func trim() {
    var unsaved = 0
    entries = entries.filter { entry in
      if entry.isSaved { return true }
      unsaved += 1
      return unsaved <= limit
    }
  }

  // MARK: Storage

  private func load() {
    guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
  }

  private func save() {
    guard let fileURL else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(entries) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }
}
