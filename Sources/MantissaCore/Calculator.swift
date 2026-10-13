/// How a `Calculator` reads and answers.
public struct CalculatorSettings: Sendable, Equatable {
  /// The unit of angles typed into and returned by trigonometric functions. Radians, as in the app this one follows:
  /// `cos(30)` is radians and `cos(30°)` is degrees.
  public var angleUnit: AngleUnit = .radians
  /// Significant digits of the decimal approximation.
  public var precision = 50

  public init() {}
}

/// The answer to one input.
public struct Evaluation: Sendable, Equatable {
  /// The exact value in canonical form.
  public var exact: Expr
  /// The value as a decimal, or `nil` when the expression has unknowns or its value is not a real number.
  public var approximation: BigDecimal?
  /// The value as a complex decimal, when it is not a real number (`2i`, `(1 + i)/√2`).
  public var complexApproximation: ComplexDecimal?
  /// Why there is no decimal value, for an exact expression that cannot be evaluated (`1/0`, `ln(0)`).
  public var approximationError: MathError?
  /// Whether the answer is an antiderivative, which is one of many that differ by a constant (`+ C`).
  public var isAntiderivative = false

  public init(
    exact: Expr, approximation: BigDecimal? = nil, complexApproximation: ComplexDecimal? = nil,
    approximationError: MathError? = nil
  ) {
    self.exact = exact
    self.approximation = approximation
    self.complexApproximation = complexApproximation
    self.approximationError = approximationError
  }
}

/// Why an input produced no answer.
public enum CalculatorError: Error, Equatable, Sendable {
  case parse(ParseError)
  case math(MathError)
  /// The input is valid but is not something this version can answer yet.
  case unsupported(Unsupported)

  public enum Unsupported: Equatable, Sendable {
    case equation
    case system
  }
}

/// The entry point: text in, exact and decimal answer out.
public struct Calculator: Sendable {
  public var settings: CalculatorSettings

  public init(settings: CalculatorSettings = CalculatorSettings()) {
    self.settings = settings
  }

  /// Reads `text` as an expression and evaluates it.
  public func evaluate(_ text: String) throws(CalculatorError) -> Evaluation {
    let statement: Statement
    do {
      statement = try Parser.parse(text)
    } catch {
      throw .parse(error)
    }
    switch statement {
    case .expression(let syntax):
      let exact: Expr
      do {
        exact = try Builder(angleUnit: settings.angleUnit).build(syntax)
      } catch {
        throw .math(error)
      }
      var result = evaluation(of: exact)
      if case .call(.int, let arguments) = syntax, arguments.count <= 2 { result.isAntiderivative = true }
      return result
    case .relation: throw .unsupported(.equation)
    case .system: throw .unsupported(.system)
    }
  }

  private func evaluation(of exact: Expr) -> Evaluation {
    guard exact.freeSymbols.isEmpty, !exact.containsInfinity else { return Evaluation(exact: exact) }
    do throws(MathError) {
      return Evaluation(exact: exact, approximation: try exact.approximation(precision: settings.precision))
    } catch {
      // A value that is not real is still a number: try it as a complex one.
      if error == .domain, let complex = try? exact.complexApproximation(precision: settings.precision) {
        if complex.isReal { return Evaluation(exact: exact, approximation: complex.real) }
        return Evaluation(exact: exact, complexApproximation: complex)
      }
      return Evaluation(exact: exact, approximationError: error)
    }
  }
}
