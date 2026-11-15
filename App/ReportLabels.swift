import MantissaCore

extension Report.Label {
  /// What a row of a report is called, in the user's language.
  var title: String {
    switch self {
    case .count: return Localizer.string("Count")
    case .mean: return Localizer.string("Mean")
    case .sum: return Localizer.string("Total")
    case .sumOfSquares: return Localizer.string("Sum of squares")
    case .sampleDeviation: return Localizer.string("Sample standard deviation")
    case .populationDeviation: return Localizer.string("Population standard deviation")
    case .minimum: return Localizer.string("Smallest value")
    case .firstQuartile: return Localizer.string("First quartile")
    case .median: return Localizer.string("Median")
    case .thirdQuartile: return Localizer.string("Third quartile")
    case .maximum: return Localizer.string("Largest value")
    case .mode: return Localizer.string("Mode")
    case .equation: return Localizer.string("Line")
    case .slope: return Localizer.string("Slope")
    case .intercept: return Localizer.string("Intercept")
    case .correlation: return Localizer.string("Correlation r")
    case .determination: return Localizer.string("r squared")
    }
  }
}
