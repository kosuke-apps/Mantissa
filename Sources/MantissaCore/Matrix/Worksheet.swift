// Lines that give letters their values: `A = [[1,2],[3,4]]`, `C = A²B + A⁻¹`, `A X = B`.
//
// When an input has a matrix in it and is several lines, or one line with an equals sign, it is read as a worksheet: each line is
// an equation, and every letter that can be worked out is. A line whose letters are all known but one gives that one its value; a
// line that has two unknown waits until another line has settled one of them, so the lines may come in any order. An unknown that
// is only multiplied, added or turned over (`A X + B = C`, `X Aᵀ = B`, `X⁻¹ = A`) is isolated by undoing what is done to it with
// the inverse of the matrices around it; anything else (`X² = A`, a letter on both sides) is left unsolved. A line with no equals
// sign is an expression, worked out with the values found.

/// One line of the answer to a worksheet: the letter that got a value, if the line was an equation, and the value.
public struct WorkedLine: Sendable, Equatable {
  public var name: String?
  public var quantity: Quantity
  /// Whether the line only gave the letter a value written out in numbers (`A = [[1,2],[3,4]]`), which is already on the screen
  /// above the answer.
  public var isGiven: Bool

  public init(name: String?, quantity: Quantity, isGiven: Bool = false) {
    self.name = name
    self.quantity = quantity
    self.isGiven = isGiven
  }
}

extension Syntax {
  /// Numbers, with signs, and matrices of them: what a person types to give a letter its value.
  fileprivate var isWrittenOutInNumbers: Bool {
    switch self {
    case .number: return true
    case .negate(let operand): return operand.isWrittenOutInNumbers
    case .matrix(let rows): return rows.allSatisfy { $0.allSatisfy(\.isWrittenOutInNumbers) }
    default: return false
    }
  }
}

extension Calculator {
  /// Works out a worksheet, giving a line for each equation that settled a letter and for each expression, in the order written.
  func worksheet(_ statement: Statement) throws(CalculatorError) -> [WorkedLine] {
    struct Equation {
      var index: Int
      var left: Syntax
      var right: Syntax
    }
    let parts: [Statement]
    if case .system(let all) = statement { parts = all } else { parts = [statement] }

    var equations: [Equation] = []
    var expressions: [(index: Int, syntax: Syntax)] = []
    for (index, part) in parts.enumerated() {
      switch part {
      case .expression(let syntax): expressions.append((index, syntax))
      case .relation(let chain):
        guard chain.links.count == 1, chain.links[0].op == .equal else { throw .unsupported(.equation) }
        equations.append(Equation(index: index, left: chain.first, right: chain.links[0].operand))
      case .system: throw .unsupported(.system)
      }
    }

    var builder = Builder(angleUnit: settings.angleUnit)
    var results: [Int: WorkedLine] = [:]
    var pending = equations
    var progress = true
    while progress && !pending.isEmpty {
      progress = false
      var waiting: [Equation] = []
      for equation in pending {
        var letters = equation.left.letterCounts()
        for (name, count) in equation.right.letterCounts() { letters[name, default: 0] += count }
        let unknown = letters.keys.filter { builder.environment[$0] == nil }
        if unknown.isEmpty {
          progress = true  // everything in it is known: nothing is left to find
          continue
        }
        guard unknown.count == 1, let name = unknown.first else {
          waiting.append(equation)
          continue
        }
        do {
          let found = try builder.solve(equation.left, equation.right, for: name).mapped {
            $0.trigonometricallyTidied()
          }
          builder.environment[name] = found
          let given = (equation.left == .symbol(name) ? equation.right : equation.left).isWrittenOutInNumbers
          results[equation.index] = WorkedLine(name: name, quantity: found, isGiven: given)
          progress = true
        } catch {
          // Not an equation this can undo yet (or ever); a matrix with no inverse or of the wrong size is the answer.
          guard error == .unsupported else { throw .math(error) }
          waiting.append(equation)
        }
      }
      pending = waiting
    }

    for (index, syntax) in expressions {
      do {
        let value = try builder.value(syntax).mapped { $0.trigonometricallyTidied() }
        results[index] = WorkedLine(name: nil, quantity: value)
      } catch {
        throw .math(error)
      }
    }
    guard !results.isEmpty else { throw .unsupported(.equation) }
    return results.sorted { $0.key < $1.key }.map(\.value)
  }
}

extension Builder {
  /// The value of the letter `name` that makes `left = right` true, when it is written once in the equation, every other letter
  /// has a value, and it is only added to, subtracted from, multiplied by, divided by, inverted or transposed.
  func solve(_ left: Syntax, _ right: Syntax, for name: String) throws(MathError) -> Quantity {
    let inLeft = left.letterCounts()[name, default: 0]
    let inRight = right.letterCounts()[name, default: 0]
    guard inLeft + inRight == 1 else { throw .unsupported }
    let (withUnknown, without) = inLeft == 1 ? (left, right) : (right, left)
    return try peel(withUnknown, equals: try value(without), name)
  }

  /// What `node` has to be for `node = target` to hold, where `node` has the unknown `name` once inside it: the last thing done
  /// to the unknown is undone, and then what is left is solved the same way.
  private func peel(_ node: Syntax, equals target: Quantity, _ name: String) throws(MathError) -> Quantity {
    func contains(_ part: Syntax) -> Bool { part.letterCounts()[name, default: 0] > 0 }
    switch node {
    case .symbol(let letter) where letter == name:
      return target

    case .negate(let operand):
      return try peel(operand, equals: try binary(.multiply, .scalar(.minusOne), target), name)

    case .binary(let op, let a, let b):
      switch op {
      case .add:
        let (inside, outside) = contains(a) ? (a, b) : (b, a)
        return try peel(inside, equals: try binary(.subtract, target, try value(outside)), name)
      case .subtract:
        if contains(a) { return try peel(a, equals: try binary(.add, target, try value(b)), name) }
        return try peel(b, equals: try binary(.subtract, try value(a), target), name)  // a − X = target
      case .multiply:
        // Matrices do not commute: X·b = target is X = target·b⁻¹, and a·X = target is X = a⁻¹·target.
        if contains(a) { return try peel(a, equals: try binary(.multiply, target, try value(b).inverse()), name) }
        return try peel(b, equals: try binary(.multiply, try value(a).inverse(), target), name)
      case .divide:
        guard contains(a) else { throw .unsupported }
        return try peel(a, equals: try binary(.multiply, target, try value(b)), name)  // X/b = target
      case .power:
        guard contains(a), case .scalar(let exponent) = try value(b) else { throw .unsupported }
        if exponent == .symbol("T"), case .matrix(let matrix) = target {
          return try peel(a, equals: .collapsing(matrix.transposed()), name)
        }
        if exponent == .one { return try peel(a, equals: target, name) }
        if exponent == .minusOne { return try peel(a, equals: try target.inverse(), name) }
        throw .unsupported
      }

    case .call(let function, let arguments) where arguments.count == 1 && contains(arguments[0]):
      switch function {
      case .inverse: return try peel(arguments[0], equals: try target.inverse(), name)
      case .transpose:
        guard case .matrix(let matrix) = target else { return try peel(arguments[0], equals: target, name) }
        return try peel(arguments[0], equals: .collapsing(matrix.transposed()), name)
      default: throw .unsupported
      }

    default:
      throw .unsupported
    }
  }
}
