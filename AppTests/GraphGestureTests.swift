import CoreGraphics
import MantissaCore
import XCTest

@testable import Mantissa

/// The order in which touch events reach the graph, played without a screen. The gesture that a second finger cuts short is the
/// one that matters: SwiftUI may never report its end.
final class GraphGestureTests: XCTestCase {
  private let size = CGSize(width: 400, height: 400)
  private let start = PlotViewport(xMin: -10, xMax: 10, yMin: -10, yMax: 10)
  private let origin = Date(timeIntervalSinceReferenceDate: 1000)

  /// The gesture code as it was before the touch was remembered: the window a drag or a pinch began from was kept until the gesture
  /// said it had ended. It is here only to show what the scenarios below do to it.
  private struct OldGestures {
    var panStart: PlotViewport?
    var zoomStart: PlotViewport?
    var isTracing = false

    mutating func drag(translation: CGSize, in size: CGSize, from viewport: PlotViewport) -> PlotViewport? {
      guard zoomStart == nil, !isTracing else { return nil }
      let base = panStart ?? viewport
      panStart = base
      return base.panned(
        dx: -Double(translation.width / size.width) * base.width,
        dy: Double(translation.height / size.height) * base.height)
    }

    mutating func dragEnded() { panStart = nil }

    mutating func pinch(
      startLocation: CGPoint, magnification: Double, in size: CGSize, from viewport: PlotViewport
    )
      -> PlotViewport
    {
      let base = zoomStart ?? viewport
      zoomStart = base
      let anchor = base.graphPoint(at: startLocation, in: size)
      return base.zoomed(by: magnification, aboutX: anchor.x, y: anchor.y)
    }

    mutating func pinchEnded() { zoomStart = nil }
  }

  // MARK: The ordinary orders, which must go on working

  func testADragMovesTheWindowByTheDistanceMovedAndKeepsItsScale() {
    var gestures = GraphGestureState()
    var viewport = start
    let first = gestures.drag(
      startLocation: CGPoint(x: 100, y: 100), translation: CGSize(width: 20, height: 0), in: size, from: viewport,
      at: origin)
    XCTAssertTrue(first.startsNewDrag)
    viewport = try! XCTUnwrap(first.viewport)
    XCTAssertEqual(viewport.xMin, -11, accuracy: 1e-9, "20 pt of 400 is a twentieth of the 20 units shown")
    XCTAssertEqual(viewport.width, 20, accuracy: 1e-9)
    let second = gestures.drag(
      startLocation: CGPoint(x: 100, y: 100), translation: CGSize(width: 40, height: 0), in: size, from: viewport,
      at: origin)
    XCTAssertFalse(second.startsNewDrag, "the same drag")
    XCTAssertEqual(try! XCTUnwrap(second.viewport).xMin, -12, accuracy: 1e-9)
  }

  func testAPinchScalesAboutWhereItBeganAndTheNextDragKeepsTheScale() {
    var gestures = GraphGestureState()
    var viewport = start
    let centre = CGPoint(x: 200, y: 200)
    for step in 1...4 {
      viewport = gestures.pinch(
        startLocation: centre, magnification: 1 + Double(step) * 0.25, in: size, from: viewport,
        at: origin.addingTimeInterval(Double(step) * 0.02))
    }
    XCTAssertEqual(viewport.width, 20 / 2, accuracy: 1e-9, "magnified by 2")
    XCTAssertEqual((viewport.xMin + viewport.xMax) / 2, 0, accuracy: 1e-9, "about the middle")
    gestures.pinchEnded()
    let drag = gestures.drag(
      startLocation: CGPoint(x: 50, y: 50), translation: CGSize(width: 10, height: 10), in: size, from: viewport,
      at: origin.addingTimeInterval(2))
    XCTAssertEqual(try! XCTUnwrap(drag.viewport).width, 10, accuracy: 1e-9)
  }

  func testAFingerHeldOnACurveDoesNotPanWhileItFollowsTheCurve() {
    var gestures = GraphGestureState()
    let touch = CGPoint(x: 100, y: 100)
    // The drag is the first to hear of the touch; the held finger takes it over a moment later.
    let first = gestures.drag(
      startLocation: touch, translation: CGSize(width: 5, height: 0), in: size, from: start, at: origin)
    XCTAssertNotNil(first.viewport)
    gestures.tracingBegan()
    let later = gestures.drag(
      startLocation: touch, translation: CGSize(width: 60, height: 0), in: size, from: start, at: origin)
    XCTAssertNil(later.viewport, "following a curve is not a pan")
    gestures.tracingEnded()
    gestures.dragEnded()
    let next = gestures.drag(
      startLocation: CGPoint(x: 300, y: 300), translation: CGSize(width: 20, height: 0), in: size, from: start,
      at: origin)
    XCTAssertNotNil(next.viewport, "the next touch pans again")
  }

  func testADragDoesNotMoveTheWindowWhileAPinchIsGoingOn() {
    var gestures = GraphGestureState()
    var viewport = gestures.pinch(
      startLocation: CGPoint(x: 200, y: 200), magnification: 1.5, in: size, from: start, at: origin)
    let drag = gestures.drag(
      startLocation: CGPoint(x: 150, y: 200), translation: CGSize(width: 30, height: 0), in: size, from: viewport,
      at: origin.addingTimeInterval(0.1))
    XCTAssertNil(drag.viewport)
    viewport = gestures.pinch(
      startLocation: CGPoint(x: 200, y: 200), magnification: 2, in: size, from: viewport,
      at: origin.addingTimeInterval(0.12))
    XCTAssertEqual(viewport.width, 10, accuracy: 1e-9, "the pinch went on from where it began, not from the drag")
  }

  // MARK: The orders that went wrong on the iPad

  /// What the iPad showed: a pinch, and the next touch put the scale back.
  private func dragCutShortByAPinch(_ gestures: inout GraphGestureState) -> PlotViewport {
    var viewport = start
    // A finger goes down and moves: the drag begins ...
    viewport = gestures.drag(
      startLocation: CGPoint(x: 100, y: 100), translation: CGSize(width: 10, height: 0), in: size, from: viewport,
      at: origin
    ).viewport!
    // ... a second finger joins and the pinch scales the window by 2 ...
    for step in 1...4 {
      viewport = gestures.pinch(
        startLocation: CGPoint(x: 200, y: 200), magnification: 1 + Double(step) * 0.25, in: size, from: viewport,
        at: origin.addingTimeInterval(0.1 + Double(step) * 0.02))
    }
    // ... and the fingers lift. The pinch reports its end; the drag never does.
    gestures.pinchEnded()
    return viewport
  }

  func testANewTouchAfterADragWasCutShortByAPinchKeepsTheScaleOfThePinch() {
    var gestures = GraphGestureState()
    let zoomed = dragCutShortByAPinch(&gestures)
    XCTAssertEqual(zoomed.width, 10, accuracy: 1e-9)
    let next = gestures.drag(
      startLocation: CGPoint(x: 300, y: 300), translation: CGSize(width: 8, height: 0), in: size, from: zoomed,
      at: origin.addingTimeInterval(3))
    XCTAssertEqual(try! XCTUnwrap(next.viewport).width, 10, accuracy: 1e-9)
    XCTAssertTrue(next.startsNewDrag)
  }

  func testTheOldCodeWentBackToTheScaleBeforeThePinchInThatOrder() {
    var old = OldGestures()
    var viewport = start
    viewport = old.drag(translation: CGSize(width: 10, height: 0), in: size, from: viewport)!
    for step in 1...4 {
      viewport = old.pinch(
        startLocation: CGPoint(x: 200, y: 200), magnification: 1 + Double(step) * 0.25, in: size, from: viewport)
    }
    old.pinchEnded()
    XCTAssertEqual(viewport.width, 10, accuracy: 1e-9)
    let next = old.drag(translation: CGSize(width: 8, height: 0), in: size, from: viewport)!
    XCTAssertEqual(next.width, 20, accuracy: 1e-9, "the scale was back to what it was before the pinch")
  }

  func testADragThatCarriesOnAfterAPinchMovesFromTheNewWindowWithoutAJump() {
    var gestures = GraphGestureState()
    let zoomed = dragCutShortByAPinch(&gestures)
    // One finger stays down and goes on moving; the first event after the pinch must not move anything.
    let carrying = gestures.drag(
      startLocation: CGPoint(x: 100, y: 100), translation: CGSize(width: 30, height: 0), in: size, from: zoomed,
      at: origin.addingTimeInterval(1))
    XCTAssertFalse(carrying.startsNewDrag)
    XCTAssertEqual(try! XCTUnwrap(carrying.viewport), zoomed)
    let moved = gestures.drag(
      startLocation: CGPoint(x: 100, y: 100), translation: CGSize(width: 50, height: 0), in: size, from: zoomed,
      at: origin.addingTimeInterval(1.02))
    let viewport = try! XCTUnwrap(moved.viewport)
    XCTAssertEqual(viewport.width, 10, accuracy: 1e-9)
    XCTAssertEqual(
      viewport.xMin, zoomed.xMin - 20.0 / 400 * 10, accuracy: 1e-9, "20 pt more of finger, a twentieth of 10 units")
  }

  func testAPinchWhoseEndIsNeverReportedNeitherBlocksPanningNorBringsBackAnOldWindow() {
    var gestures = GraphGestureState()
    var viewport = start
    for step in 1...4 {
      viewport = gestures.pinch(
        startLocation: CGPoint(x: 200, y: 200), magnification: 1 + Double(step) * 0.25, in: size, from: viewport,
        at: origin.addingTimeInterval(Double(step) * 0.02))
    }
    // No `pinchEnded`. A moment later a finger drags ...
    let drag = gestures.drag(
      startLocation: CGPoint(x: 120, y: 120), translation: CGSize(width: 20, height: 0), in: size, from: viewport,
      at: origin.addingTimeInterval(2))
    let dragged = try! XCTUnwrap(drag.viewport, "panning is not blocked for good")
    XCTAssertEqual(dragged.width, 10, accuracy: 1e-9)
    gestures.dragEnded()
    // ... and a new pinch, elsewhere, goes on from the window as it is.
    let again = gestures.pinch(
      startLocation: CGPoint(x: 300, y: 100), magnification: 1, in: size, from: dragged,
      at: origin.addingTimeInterval(3))
    XCTAssertEqual(again.xMin, dragged.xMin, accuracy: 1e-9)
    XCTAssertEqual(again.xMax, dragged.xMax, accuracy: 1e-9)
    XCTAssertEqual(again.yMin, dragged.yMin, accuracy: 1e-9)
    XCTAssertEqual(again.yMax, dragged.yMax, accuracy: 1e-9)
  }

  func testTheOldCodeBlockedPanningAndRestartedThePinchFromAnOldWindowWhenAPinchEndWasMissed() {
    var old = OldGestures()
    var viewport = start
    for step in 1...4 {
      viewport = old.pinch(
        startLocation: CGPoint(x: 200, y: 200), magnification: 1 + Double(step) * 0.25, in: size, from: viewport)
    }
    XCTAssertNil(old.drag(translation: CGSize(width: 20, height: 0), in: size, from: viewport), "panning blocked")
    let again = old.pinch(startLocation: CGPoint(x: 300, y: 100), magnification: 1, in: size, from: viewport)
    XCTAssertEqual(again.width, start.width, accuracy: 1e-9, "a new pinch began from the window before the first one")
  }

  func testAFollowedCurveWhoseEndIsNeverReportedDoesNotStopThePanningOfTheNextTouch() {
    var gestures = GraphGestureState()
    let touch = CGPoint(x: 100, y: 100)
    _ = gestures.drag(startLocation: touch, translation: CGSize(width: 5, height: 0), in: size, from: start, at: origin)
    gestures.tracingBegan()
    // Neither the held finger nor the drag reports its end (a pinch began).
    let next = gestures.drag(
      startLocation: CGPoint(x: 250, y: 250), translation: CGSize(width: 10, height: 0), in: size, from: start,
      at: origin.addingTimeInterval(5))
    XCTAssertNotNil(next.viewport)
  }
}
