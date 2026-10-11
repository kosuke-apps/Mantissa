import Foundation
import Testing

@testable import MantissaCore

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
