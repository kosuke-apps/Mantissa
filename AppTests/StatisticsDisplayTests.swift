import MantissaCore
import XCTest

@testable import Mantissa

/// What a statistics report looks like on the screen: a caption and a value on each row, and the words for what cannot be done.
final class StatisticsDisplayTests: XCTestCase {
  private func solutions(_ text: String) -> SolutionsDisplay? {
    if case .solutions(let solutions) = AppModel.outcome(for: text, calculator: Calculator(), digits: 12) {
      return solutions
    }
    return nil
  }

  func testTheSummaryOfSomeDataHasACaptionAndAValueOnEachRow() throws {
    let report = try XCTUnwrap(solutions("stats(2,4,4,4,5,5,7,9)"))
    XCTAssertEqual(report.kind, .report)
    let rows = report.lines.map { ($0.caption ?? "", $0.exact.plainText) }
    XCTAssertEqual(rows.map(\.0).prefix(4), ["Count", "Mean", "Total", "Sum of squares"])
    XCTAssertEqual(rows[0].1, "8")
    XCTAssertEqual(rows[1].1, "5")
    // The deviations are roots; the decimal of the sample one is beneath it.
    let sample = try XCTUnwrap(report.lines.first { $0.caption == "Sample standard deviation" })
    XCTAssertEqual(sample.decimal?.plainText, "2.1380899353")
    let population = try XCTUnwrap(report.lines.first { $0.caption == "Population standard deviation" })
    XCTAssertEqual(population.exact.plainText, "2")
    XCTAssertNil(population.decimal)
    XCTAssertEqual(report.lines.last?.caption, "Mode")
  }

  func testTheFittedLineIsWrittenAsAnEquation() throws {
    let report = try XCTUnwrap(solutions("linreg([[1,2],[2,4],[3,5],[4,4],[5,5]])"))
    XCTAssertEqual(report.lines.first?.caption, "Line")
    XCTAssertEqual(report.lines.first?.exact.plainText, "y = 3x/5 + 11/5")
    let slope = try XCTUnwrap(report.lines.first { $0.caption == "Slope" })
    XCTAssertEqual(slope.exact.plainText, "3/5")
    XCTAssertEqual(slope.decimal?.plainText, "0.6")
    // The one-line summary for the history is the first three rows.
    XCTAssertEqual(report.summary.plainText.hasPrefix("Line = y = "), true)
  }

  func testAColumnOfModesIsOneRow() throws {
    let report = try XCTUnwrap(solutions("stats(3,1,3,1,2)"))
    XCTAssertEqual(report.lines.last?.caption, "Mode")
    XCTAssertEqual(report.lines.last?.exact.plainText, "1, 3")
  }

  func testWhatCannotBeWorkedOutSaysSo() {
    XCTAssertEqual(AppModel.outcome(for: "stdev(5)", calculator: Calculator(), digits: 12), .failure(.needsMoreData))
    XCTAssertEqual(AppModel.outcome(for: "mode(1,2,3)", calculator: Calculator(), digits: 12), .failure(.noMode))
    XCTAssertEqual(
      AppModel.outcome(for: "slope([[1],[1]],[[1],[2]])", calculator: Calculator(), digits: 12), .failure(.noSpread))
    XCTAssertEqual(
      AppModel.outcome(for: "mean([[1],[2]],[[1],[2],[3]])", calculator: Calculator(), digits: 12),
      .failure(.sizesDoNotFit))
  }

  func testAReportOnALineOfAWorksheetIsShownRowByRow() throws {
    let report = try XCTUnwrap(solutions("D = [[1],[2],[6]]\nstats(D)"))
    XCTAssertEqual(report.lines.first?.caption, "Count")
    XCTAssertEqual(report.lines.first?.exact.plainText, "3")
  }
}
