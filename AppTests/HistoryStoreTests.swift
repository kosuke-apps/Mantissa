import MantissaCore
import XCTest

@testable import Mantissa

@MainActor
final class HistoryStoreTests: XCTestCase {
  private func lines(_ text: String) -> [[MathNode]] { [text.map { .symbol(String($0)) }] }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
  }

  func testNewestFirstAndTheSameProblemMovesToTheTop() {
    let store = HistoryStore(fileURL: nil)
    store.record(lines: lines("1+1"), exact: lines("2")[0], decimal: nil, date: Date(timeIntervalSince1970: 100))
    store.record(lines: lines("2+2"), exact: lines("4")[0], decimal: nil, date: Date(timeIntervalSince1970: 200))
    XCTAssertEqual(store.entries.map(\.text), ["2+2", "1+1"])
    store.record(lines: lines("1+1"), exact: lines("2")[0], decimal: nil, date: Date(timeIntervalSince1970: 300))
    XCTAssertEqual(store.entries.map(\.text), ["1+1", "2+2"])
    XCTAssertEqual(store.entries.count, 2)
    XCTAssertEqual(store.entries[0].date, Date(timeIntervalSince1970: 300))
  }

  func testSavedProblemsSurviveClearingAndTheLimit() {
    let store = HistoryStore(fileURL: nil, limit: 3)
    store.record(lines: lines("1+1"), exact: lines("2")[0], decimal: nil)
    store.toggleSaved(store.entries[0].id)
    for n in 2...6 { store.record(lines: lines("\(n)+\(n)"), exact: lines("\(2 * n)")[0], decimal: nil) }
    // Three unsaved problems fit, and the saved one stays however old it is.
    XCTAssertEqual(store.entries.map(\.text), ["6+6", "5+5", "4+4", "1+1"])
    store.clear()
    XCTAssertEqual(store.entries.map(\.text), ["1+1"])
    store.clear(keepingSaved: false)
    XCTAssertTrue(store.entries.isEmpty)
  }

  func testSavingSurvivesRecordingTheSameProblemAgain() {
    let store = HistoryStore(fileURL: nil)
    store.record(lines: lines("3+3"), exact: lines("6")[0], decimal: nil)
    store.toggleSaved(store.entries[0].id)
    store.record(lines: lines("3+3"), exact: lines("6")[0], decimal: nil)
    XCTAssertEqual(store.entries.count, 1)
    XCTAssertTrue(store.entries[0].isSaved)
  }

  func testDeleting() {
    let store = HistoryStore(fileURL: nil)
    store.record(lines: lines("1+1"), exact: lines("2")[0], decimal: nil)
    store.record(lines: lines("2+2"), exact: lines("4")[0], decimal: nil)
    store.delete([store.entries[0].id])
    XCTAssertEqual(store.entries.map(\.text), ["1+1"])
  }

  func testTheHistoryIsKeptBetweenLaunches() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file) }
    let first = HistoryStore(fileURL: file)
    let fraction = MathNode.fraction(numerator: [.symbol("1")], denominator: [.symbol("2")])
    // The file stores whole seconds, so the date used here has none to lose.
    first.record(
      lines: [[fraction, .symbol("+"), .symbol("1")]], exact: lines("3/2")[0], decimal: lines("1.5")[0],
      date: Date(timeIntervalSince1970: 1_700_000_000))
    first.toggleSaved(first.entries[0].id)

    let second = HistoryStore(fileURL: file)
    XCTAssertEqual(second.entries, first.entries)
    XCTAssertEqual(second.entries[0].text, "((1)/(2))+1")
    XCTAssertTrue(second.entries[0].isSaved)
  }

  func testAFileThatCannotBeReadGivesAnEmptyHistory() throws {
    let file = temporaryFile()
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("not json".utf8).write(to: file)
    XCTAssertTrue(HistoryStore(fileURL: file).entries.isEmpty)
  }

  func testASolvedProblemIsRecordedOnceAndCanBeReopened() async throws {
    let store = HistoryStore(fileURL: nil)
    let model = AppModel(history: store)
    for key in ["1", "+", "2"] { model.press(.symbol(key)) }
    // The answer must stand for a moment before it is recorded; typing on does not leave an entry per key.
    try await Task.sleep(for: .seconds(2))
    XCTAssertEqual(store.entries.map(\.text), ["1+2"])

    model.clearAll()
    XCTAssertTrue(model.editor.isEmpty)
    model.open(store.entries[0])
    XCTAssertEqual(model.editor.text, "1+2")
  }
}
