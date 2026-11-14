import MantissaCore
import XCTest

@testable import Mantissa

/// What VoiceOver is told for a formula. The English words are the keys of the String Catalog; Japanese puts the parts in its own
/// order.
@MainActor
final class SpokenMathTests: XCTestCase {
  override func setUp() { Localizer.bundle = AppLanguage.english.bundle }
  override func tearDown() { Localizer.bundle = AppLanguage.system.bundle }

  private func nodes(_ text: String) -> [MathNode] {
    var editor = MathEditor()
    XCTAssertTrue(editor.paste(text), text)
    return editor.lines[0]
  }

  private func spoken(_ text: String) -> String { SpokenMath.text(of: nodes(text)) }

  func testAnEquationIsReadWordByWord() {
    XCTAssertEqual(spoken("x^2-5x+6=0"), "x squared minus 5 x plus 6 equals 0")
  }

  func testNumbersAreOneWordAndADecimalPointStaysInTheNumber() {
    XCTAssertEqual(spoken("12.5+3"), "12.5 plus 3")
    XCTAssertEqual(spoken("123"), "123")
  }

  func testPowersAreSquaredCubedOrToThePower() {
    XCTAssertEqual(spoken("x^3"), "x cubed")
    XCTAssertEqual(spoken("x^n"), "x to the power n")
    XCTAssertEqual(spoken("2^10"), "2 to the power 10")
  }

  func testFractionsAndRootsSayWhereTheyEnd() {
    XCTAssertEqual(SpokenMath.text(of: [.fraction(numerator: [.symbol("3")], denominator: [.symbol("2")])]), "3 over 2")
    let longer = MathNode.fraction(numerator: [.symbol("1"), .symbol("+"), .symbol("x")], denominator: [.symbol("2")])
    XCTAssertEqual(SpokenMath.text(of: [longer]), "the fraction 1 plus x over 2, end of fraction")
    XCTAssertEqual(SpokenMath.text(of: [.radical(index: nil, radicand: [.symbol("6")])]), "square root of 6")
    XCTAssertEqual(
      SpokenMath.text(of: [.radical(index: nil, radicand: [.symbol("6"), .symbol("−"), .symbol("x")])]),
      "the square root of 6 minus x, end of root")
    XCTAssertEqual(SpokenMath.text(of: [.radical(index: [.symbol("3")], radicand: [.symbol("8")])]), "root 3 of 8")
  }

  func testFunctionsAndAbsoluteValuesAreNamed() {
    XCTAssertEqual(
      SpokenMath.text(of: [.function(name: "sin", argument: [.symbol("x")])]), "sine of x")
    XCTAssertEqual(SpokenMath.text(of: [.function(name: "gcd", argument: [.symbol("4")])]), "gcd of 4")
    XCTAssertEqual(SpokenMath.text(of: [.absolute([.symbol("−"), .symbol("5")])]), "absolute value of minus 5")
  }

  func testCalculusReadsAsAnEnglishSentence() {
    let integral = MathNode.calculus(
      .integral, [[.symbol("x"), .superscript([.symbol("2")])], [.symbol("x")], [], []])
    XCTAssertEqual(SpokenMath.text(of: [integral]), "integral of x squared with respect to x")
    let definite = MathNode.calculus(.integral, [[.symbol("x")], [.symbol("x")], [.symbol("0")], [.symbol("1")]])
    XCTAssertEqual(SpokenMath.text(of: [definite]), "integral from 0 to 1 of x with respect to x")
    let limit = MathNode.calculus(.limit, [[.symbol("x")], [.symbol("x")], [.symbol("0")]])
    XCTAssertEqual(SpokenMath.text(of: [limit]), "limit of x as x approaches 0")
    let derivative = MathNode.calculus(.derivative, [[.symbol("x"), .superscript([.symbol("3")])], [.symbol("x")]])
    XCTAssertEqual(SpokenMath.text(of: [derivative]), "derivative of x cubed with respect to x")
  }

  func testAMatrixIsReadRowByRowAndAVectorByEntries() {
    let cells: [[MathNode]] = [[.symbol("1")], [.symbol("2")], [.symbol("3")], [.symbol("4")]]
    XCTAssertEqual(
      SpokenMath.text(of: [.matrix(rows: 2, columns: 2, cells: cells)]),
      "matrix with 2 rows and 2 columns. row 1: 1, 2. row 2: 3, 4.")
    XCTAssertEqual(
      SpokenMath.text(of: [.matrix(rows: 3, columns: 1, cells: [[.symbol("1")], [.symbol("2")], []])]),
      "vector with 3 entries: 1, 2, empty")
  }

  func testNothingTypedIsEmpty() {
    XCTAssertEqual(SpokenMath.text(of: []), "empty")
  }

  func testJapaneseSaysTheDenominatorFirstAndKeepsTheWordsInItsOwnOrder() {
    Localizer.bundle = AppLanguage.japanese.bundle
    XCTAssertEqual(SpokenMath.text(of: [.fraction(numerator: [.symbol("2")], denominator: [.symbol("3")])]), "3分の2")
    XCTAssertEqual(SpokenMath.text(of: [.radical(index: nil, radicand: [.symbol("6")])]), "6の平方根")
    XCTAssertEqual(spoken("x^2-5x+6=0"), "xの2乗 マイナス 5 x プラス 6 イコール 0")
    let integral = MathNode.calculus(.integral, [[.symbol("x")], [.symbol("x")], [.symbol("0")], [.symbol("1")]])
    XCTAssertEqual(SpokenMath.text(of: [integral]), "xをxで0から1まで積分")
    let cells: [[MathNode]] = [[.symbol("1")], [.symbol("2")], [.symbol("3")], [.symbol("4")]]
    XCTAssertEqual(
      SpokenMath.text(of: [.matrix(rows: 2, columns: 2, cells: cells)]), "2行2列の行列．1行目：1，2． 2行目：3，4．")
  }
}
