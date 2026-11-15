// A block of labelled values: what `stats(…)` and the regressions answer. Each value is exact where it can be; the decimals are worked
// out where they are shown, as for a matrix. A value that has no exact form (the coefficients of an exponential fit) is a decimal.

/// What a report says about the data, row by row.
public struct Report: Sendable, Equatable {
  /// What a row is called. The names are for the user interface to turn into words and symbols (n, x̄, sₓ, σₓ, …).
  public enum Label: Sendable, Equatable, Hashable {
    case count, mean, sum, sumOfSquares, sampleDeviation, populationDeviation
    case minimum, firstQuartile, median, thirdQuartile, maximum, mode
    /// The fitted curve, as an expression in x.
    case equation
    case slope, intercept, correlation, determination
    /// The coefficient of x to this power in a polynomial fit.
    case coefficient(Int)
    /// The two parameters `a` and `b` of an exponential, power or logarithmic fit.
    case parameterA, parameterB
  }

  /// The kind of curve a report is the fit of.
  public enum Model: Sendable, Equatable {
    case linear
    /// A polynomial of this degree.
    case polynomial(Int)
    /// `y = a bˣ`
    case exponential
    /// `y = a xᵇ`
    case power
    /// `y = a + b ln x`
    case logarithmic
  }

  public struct Row: Sendable, Equatable {
    public var label: Label
    /// One value, or several when a row has more (the modes of data that have more than one).
    public var values: [Expr]
    /// The decimal values of a row that has no exact form: `values` is empty then.
    public var approximations: [BigDecimal]

    public init(_ label: Label, _ values: [Expr]) {
      self.label = label
      self.values = values
      approximations = []
    }

    public init(_ label: Label, approximations: [BigDecimal]) {
      self.label = label
      values = []
      self.approximations = approximations
    }
  }

  public var rows: [Row]
  /// The curve that a regression fitted, when the report is of one.
  public var model: Model?

  public init(rows: [Row], model: Model? = nil) {
    self.rows = rows
    self.model = model
  }

  /// The report with `transform` applied to every exact value.
  func mapped(_ transform: (Expr) -> Expr) -> Report {
    var report = self
    report.rows = rows.map { row in
      var changed = row
      changed.values = row.values.map(transform)
      return changed
    }
    return report
  }
}
