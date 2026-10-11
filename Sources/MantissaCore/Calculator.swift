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
  /// The value as a decimal, or `nil` when the expression has unknowns or has no real value (see `approximationError`).
  public var approximation: BigDecimal?
  /// Why there is no decimal value, for an exact expression that cannot be evaluated (`√(-4)`).
  public var approximationError: MathError?

  public init(exact: Expr, approximation: BigDecimal? = nil, approximationError: MathError? = nil) {
    self.exact = exact
    self.approximation = approximation
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
      return evaluation(of: exact)
    case .relation: throw .unsupported(.equation)
    case .system: throw .unsupported(.system)
    }
  }

  private func evaluation(of exact: Expr) -> Evaluation {
    guard exact.freeSymbols.isEmpty else { return Evaluation(exact: exact) }
    do {
      return Evaluation(exact: exact, approximation: try exact.approximation(precision: settings.precision))
    } catch {
      return Evaluation(exact: exact, approximationError: error)
    }
  }
}
