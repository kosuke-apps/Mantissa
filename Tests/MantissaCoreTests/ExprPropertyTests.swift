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
    try checkValuesArePreserved(
      angleUnit: angleUnit, seed: (angleUnit == .radians ? 2026 : 4052) &+ seedOffset &* 7919, derived: false)
  }

  /// The same with `mod`, `min`, `max`, `sign` and the reciprocal functions in the mix.
  @Test(
    "Simplification never changes a value, with the derived functions",
    arguments: [AngleUnit.radians, AngleUnit.degrees])
  func derivedFunctionsPreserveValue(angleUnit: AngleUnit) throws {
    try checkValuesArePreserved(
      angleUnit: angleUnit, seed: (angleUnit == .radians ? 3131 : 6262) &+ seedOffset &* 7919, derived: true)
  }

  private func checkValuesArePreserved(angleUnit: AngleUnit, seed: UInt64, derived: Bool) throws {
    var generator = SyntaxGenerator(seed: seed)
    generator.includesDerivedFunctions = derived
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

  /// The same for complex arithmetic: i, square roots of negative numbers, sums, products, quotients and small powers.
  @Test("Simplification never changes a complex value")
  func complexValuesArePreserved() throws {
    var generator = ComplexSyntaxGenerator(seed: 6006 &+ seedOffset &* 104_729)
    let evaluator = NaiveComplexEvaluator()
    let builder = Builder(angleUnit: .radians)
    var compared = 0
    var skipped = 0
    var failures: [String] = []

    for _ in 0..<sampleCount {
      let syntax = generator.make(depth: 3)
      if traceCases { FileHandle.standardError.write(Data("COMPLEX CASE \(syntax)\n".utf8)) }
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
        let value = try built.complexApproximation(precision: 40)
        let scale = max(
          BigDecimal(1), value.real.magnitude, value.imaginary.magnitude, naive.real.magnitude,
          naive.imaginary.magnitude)
        let tolerance = scale * BigDecimal(BigInt(1), exponent: -30)
        if (value.real - naive.real).magnitude > tolerance || (value.imaginary - naive.imaginary).magnitude > tolerance
        {
          failures.append("value \(value) but naive \(naive) for \(built)  from \(syntax)")
        }
      } catch {
        failures.append("approximation threw \(error) for \(built) where the naive value is \(naive)")
      }
      compared += 1

      if let again = try? built.rebuilt(), again != built {
        failures.append("not stable: \(built) rebuilds as \(again)")
      }

      let text = built.description
      do {
        guard case .expression(let reparsed) = try Parser.parse(text) else {
          failures.append("\(text) did not parse as an expression")
          continue
        }
        let rebuilt = try builder.build(reparsed)
        if rebuilt != built { failures.append("round trip changed \(built) into \(rebuilt) via \(text)") }
      } catch {
        failures.append("round trip of \(built) failed with \(error) via \(text)")
      }
    }
    #expect(compared >= sampleCount * 6 / 10, "only \(compared) expressions were comparable (\(skipped) skipped)")
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(6))")
  }

  /// Rules that act on an unknown (`sin(x + π)` is `−sin x`, `√(x²)` is `|x|`) change a value if they are wrong, which the
  /// numeric tests above cannot see because they have no unknown: put numbers in for `x` and compare with the naive value.
  @Test("Rules that act on an unknown keep the value", arguments: [AngleUnit.radians, AngleUnit.degrees])
  func rulesWithUnknownsKeepTheValue(angleUnit: AngleUnit) throws {
    var generator = SyntaxGenerator(seed: (angleUnit == .radians ? 5150 : 1999) &+ seedOffset &* 7919)
    generator.includesUnknown = true
    generator.includesPiWithUnknown = true
    generator.includesDerivedFunctions = true
    let evaluator = NaiveEvaluator(angleUnit: angleUnit)
    let builder = Builder(angleUnit: angleUnit)
    var compared = 0
    var failures: [String] = []
    for _ in 0..<sampleCount {
      let syntax = generator.make(depth: 3)
      guard let expression = try? builder.build(syntax) else { continue }
      for point in [Rational(13, 10), Rational(-7, 10), Rational(2)] {
        guard let naive = try? evaluator.evaluate(Self.substituted(syntax, point)),
          let value = try? expression.approximation(precision: 40, values: ["x": BigDecimal(point, precision: 40)])
        else { continue }
        compared += 1
        // A wrong rule is wrong by an amount of order 1; a looser tolerance lets acos(1 − ε) and its like pass.
        let tolerance = max(BigDecimal(1), value.magnitude, naive.magnitude) * BigDecimal(BigInt(1), exponent: -18)
        if (value - naive).magnitude > tolerance {
          failures.append("at x = \(point): \(value) but naive \(naive) for \(expression)")
        }
      }
    }
    #expect(compared >= sampleCount / 2, "only \(compared) comparisons")
    #expect(failures.isEmpty, "\(failures.count) failures; first: \(failures.prefix(4))")
  }

  private static func substituted(_ syntax: Syntax, _ value: Rational) -> Syntax {
    func go(_ s: Syntax) -> Syntax { substituted(s, value) }
    switch syntax {
    case .symbol: return .number(value)
    case .number, .constant, .infinity: return syntax
    case .negate(let operand): return .negate(go(operand))
    case .binary(let op, let left, let right): return .binary(op, go(left), go(right))
    case .postfix(let op, let operand): return .postfix(op, go(operand))
    case .call(let function, let arguments): return .call(function, arguments.map(go))
    case .radical(let index, let radicand): return .radical(index: index.map(go), radicand: go(radicand))
    }
  }
}
