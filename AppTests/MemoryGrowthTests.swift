import Darwin
import MantissaCore
import XCTest

@testable import Mantissa

/// The same work done again and again must not make the process grow: each kind of problem is typed, answered and cleared 50
/// times after a warm-up, and the physical footprint (what the process holds in memory, as Xcode's memory gauge shows it) is
/// compared before and after. A leak of anything the size of a formula would show.
@MainActor
final class MemoryGrowthTests: XCTestCase {
  /// The allowed growth over 50 repetitions. A leak of a formula per repetition would be hundreds of kilobytes in total.
  private let allowedGrowth = 8 * 1024 * 1024

  private func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
  }

  private func makeModel() -> AppModel {
    let defaults = UserDefaults(suiteName: "dev.kosuke.mantissa.growth")!
    defaults.removePersistentDomain(forName: "dev.kosuke.mantissa.growth")
    return AppModel(history: HistoryStore(fileURL: nil), defaults: defaults)
  }

  /// Waits for the answer to what is typed.
  private func settle(_ model: AppModel) async {
    for _ in 0..<250 {
      try? await Task.sleep(nanoseconds: 4_000_000)
      if model.outcome != .empty { return }
    }
  }

  private func type(_ model: AppModel, _ text: String) {
    for character in text { model.press(.symbol(String(character))) }
  }

  /// Runs `work` 10 times to warm up, then 50 times, and checks the footprint did not grow by much.
  private func assertSteady(_ name: String, _ work: () async -> Void) async {
    for _ in 0..<10 { await work() }
    let before = footprint()
    for _ in 0..<50 { await work() }
    let after = footprint()
    print("MEMORY \(name): footprint \(before) → \(after) bytes (\(after - before) over 50 repetitions)")
    XCTAssertLessThan(after - before, allowedGrowth, "\(name) grew by \(after - before) bytes over 50 repetitions")
  }

  func testAMatrixInverseTypedAnsweredAndClearedDoesNotGrowTheProcess() async {
    let model = makeModel()
    await assertSteady("matrix inverse") {
      model.press(.matrix(rows: 3, columns: 3))
      for (index, digit) in "2013012210".prefix(9).enumerated() {
        model.press(.symbol(String(digit)))
        if index < 8 { model.press(.symbol(",")) }
      }
      model.press(.right)
      model.press([.power, .symbol("−"), .symbol("1")])
      await settle(model)
      model.clearAll()
    }
  }

  func testALetterForAMatrixAndAnEquationInItDoesNotGrowTheProcess() async {
    let model = makeModel()
    await assertSteady("worksheet of matrices") {
      type(model, "A=")
      model.press(.matrix(rows: 2, columns: 2))
      for (index, digit) in "1234".enumerated() {
        model.press(.symbol(String(digit)))
        if index < 3 { model.press(.symbol(",")) }
      }
      model.press(.right)
      model.press(.newLine)
      type(model, "AX=A")
      await settle(model)
      model.clearAll()
    }
  }

  func testAnEquationWithItsGraphDoesNotGrowTheProcess() async {
    let model = makeModel()
    await assertSteady("equation and graph") {
      type(model, "x^2-5x+6=0")
      await settle(model)
      model.clearAll()
    }
  }

  func testAnIntegralDoesNotGrowTheProcess() async {
    let model = makeModel()
    await assertSteady("integral") {
      model.press(.calculus(.integral))
      type(model, "x")
      model.press(.right)
      model.press(.right)
      await settle(model)
      model.clearAll()
    }
  }

  func testTheAnswerBeingReplacedWhileTypingDoesNotGrowTheProcess() async {
    let model = makeModel()
    await assertSteady("typing a formula key by key") {
      for character in "1234+5678×9" { model.press(.symbol(String(character))) }
      model.press(.fraction)
      model.press(.symbol("3"))
      await settle(model)
      model.clearAll()
    }
  }
}
