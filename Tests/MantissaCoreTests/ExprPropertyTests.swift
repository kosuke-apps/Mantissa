import Foundation
import Testing

@testable import MantissaCore

/// Builds random syntax trees from numbers, π, e and the operators and functions the parser knows. Domain errors are
/// common (a negative square root, ln of zero) and expected; the tests skip those.
private struct SyntaxGenerator {
  var random: SplitMix64

  init(seed: UInt64) { random = SplitMix64(seed: seed) }

  mutating func int(_ range: ClosedRange<Int>) -> Int {
    Int(random.next() % UInt64(range.count)) + range.lowerBound
  }

  mutating func leaf() -> Syntax {
    switch int(0...9) {
    case 0...3: return .number(Rational(int(0...12)))
    case 4: return .number(Rational(decimal: ["0.5", "2.25", "0.1", "1.5", "3.75", "0.125"][int(0...5)])!)
    case 5: return .constant(.pi)
    case 6: return .constant(.e)
    case 7: return .number(Rational(int(1...5), int(2...7)))
    default: return .number(Rational(int(1...30)))
    }
  }

  /// A number in [-1, 1], so inverse sine and cosine are usually in range.
  mutating func unitInterval() -> Syntax {
    .number(Rational(int(-8...8), 8))
  }

  mutating func exponent() -> Syntax {
    switch int(0...7) {
    case 0: return .number(Rational(-1))
    case 1: return .number(Rational(2))
    case 2: return .number(Rational(3))
    case 3: return .number(Rational(1, 2))
    case 4: return .number(Rational(1, 3))
    case 5: return .number(Rational(2, 3))
    case 6: return .number(Rational(3, 2))
    default: return .number(Rational(int(-3...4)))
    }
  }

  mutating func make(depth: Int) -> Syntax {
    if depth == 0 || int(0...3) == 0 { return leaf() }
    let child = depth - 1
    switch int(0...16) {
    case 0: return .negate(make(depth: child))
    case 1, 2: return .binary(.add, make(depth: child), make(depth: child))
    case 3: return .binary(.subtract, make(depth: child), make(depth: child))
    case 4, 5: return .binary(.multiply, make(depth: child), make(depth: child))
    case 6: return .binary(.divide, make(depth: child), make(depth: child))
    case 7: return .binary(.power, make(depth: child), exponent())
    case 8: return .radical(index: nil, radicand: make(depth: child))
    case 9: return .call(.sqrt, [make(depth: child)])
    case 10: return .call([.sin, .cos, .tan][int(0...2)], [make(depth: child)])
    case 11: return .call([.asin, .acos, .atan][int(0...2)], [unitInterval()])
    case 12: return .call([.ln, .abs, .exp][int(0...2)], [make(depth: child)])
    case 13: return .call(.log, [make(depth: child)])
    case 14: return .postfix(.factorial, .number(Rational(int(0...8))))
    case 15: return .call([.sinh, .cosh, .tanh, .atan][int(0...3)], [make(depth: child)])
    default: return .call(.root, [make(depth: child), .number(Rational(int(2...4)))])
    }
  }
}

/// Set `MANTISSA_TRACE=1` to print every generated case to stderr; the last line printed names a crashing input.
private let traceCases = ProcessInfo.processInfo.environment["MANTISSA_TRACE"] != nil

/// `MANTISSA_SEED=n` changes the random sequence and `MANTISSA_SAMPLES=n` the number of cases, for wider searches than
/// the fixed default that runs in every build.
private let seedOffset = UInt64(ProcessInfo.processInfo.environment["MANTISSA_SEED"] ?? "") ?? 0
private let sampleCount = Int(ProcessInfo.processInfo.environment["MANTISSA_SAMPLES"] ?? "") ?? 400

@Suite("Expression properties")
struct ExprPropertyTests {
  /// For many random expressions: the canonical value equals the naively computed one, building is stable, and the
  /// printed form reads back as the same expression.
  @Test("Simplification never changes a value", arguments: [AngleUnit.radians, AngleUnit.degrees])
  func canonicalFormPreservesValue(angleUnit: AngleUnit) throws {
    var generator = SyntaxGenerator(seed: (angleUnit == .radians ? 2026 : 4052) &+ seedOffset &* 7919)
    let evaluator = NaiveEvaluator(angleUnit: angleUnit)
    let builder = Builder(angleUnit: angleUnit)
    var compared = 0
    var skipped = 0
    var failures: [String] = []

    for _ in 0..<sampleCount {
      let syntax = generator.make(depth: 3)
      if traceCases { FileHandle.standardError.write(Data("CASE \(angleUnit) \(syntax)\n".utf8)) }
      guard let naive = try? evaluator.evaluate(syntax) else {
        skipped += 1
        continue
      }
      let built: Expr
      do {
        built = try builder.build(syntax)
      } catch {
        failures.append("builder threw \(error) where the naive value is \(naive): \(syntax)")
        continue
      }
      do {
        let value = try built.approximation(precision: 40)
        let scale = max(BigDecimal(1), value.magnitude, naive.magnitude)
        let tolerance = scale * BigDecimal(BigInt(1), exponent: -30)
        if (value - naive).magnitude > tolerance {
          failures.append("value \(value) but naive \(naive) for \(built)  from \(syntax)")
        }
      } catch {
        failures.append("approximation threw \(error) for \(built) where the naive value is \(naive)")
      }
      compared += 1

      // Rebuilding a canonical expression changes nothing.
      if let again = try? built.rebuilt(), again != built {
        failures.append("not stable: \(built) rebuilds as \(again)")
      }

      // The printed form is parseable and means the same thing.
      let text = built.description
      do {
        guard case .expression(let reparsed) = try Parser.parse(text) else {
          failures.append("\(text) did not parse as an expression")
          continue
        }
        let rebuilt = try Builder(angleUnit: .radians).build(reparsed)
        if rebuilt != built { failures.append("round trip changed \(built) into \(rebuilt) via \(text)") }
      } catch {
        failures.append("round trip of \(built) failed with \(error) via \(text)")
      }
    }
    #expect(compared >= sampleCount * 4 / 10, "only \(compared) expressions were comparable (\(skipped) skipped)")
    if traceCases { FileHandle.standardError.write(Data("COMPARED \(compared) SKIPPED \(skipped)\n".utf8)) }
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(6))")
  }
}
