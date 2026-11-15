// A block of labelled values: what `stats(…)` and `linreg(…)` answer. Each value is exact; the decimals are worked out where they
// are shown, as for a matrix.

/// What a report says about the data, row by row.
public struct Report: Sendable, Equatable {
  /// What a row is called. The names are for the user interface to turn into words and symbols (n, x̄, sₓ, σₓ, …).
  public enum Label: Sendable, Equatable, Hashable {
    case count, mean, sum, sumOfSquares, sampleDeviation, populationDeviation
    case minimum, firstQuartile, median, thirdQuartile, maximum, mode
    /// The fitted line `y = a x + b`, as an expression in x.
    case equation
    case slope, intercept, correlation, determination
  }

  public struct Row: Sendable, Equatable {
    public var label: Label
    /// One value, or several when a row has more (the modes of data that have more than one).
    public var values: [Expr]

    public init(_ label: Label, _ values: [Expr]) {
      self.label = label
      self.values = values
    }
  }

  public var rows: [Row]

  public init(rows: [Row]) { self.rows = rows }

  /// The report with `transform` applied to every value.
  func mapped(_ transform: (Expr) -> Expr) -> Report {
    Report(rows: rows.map { Row($0.label, $0.values.map(transform)) })
  }
}
