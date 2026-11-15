// Data of two variables for correlation and regression: a list of points (x, y), all numbers exact.

struct PairedData: Sendable, Equatable {
  let xs: [Expr]
  let ys: [Expr]

  var count: Int { xs.count }

  /// At least two points, of real numbers; the same number of x and y.
  init(xs: [Expr], ys: [Expr]) throws(MathError) {
    guard xs.count == ys.count else { throw .dimensionMismatch }
    guard xs.count >= 2 else { throw .insufficientData }
    for value in xs + ys { try DataSet.requireReal(value) }
    self.xs = xs
    self.ys = ys
  }

  // MARK: Sums

  private static func sum(_ terms: [Expr]) -> Expr { Expr.makeSum(terms).expanded() }

  var sumX: Expr { Self.sum(xs) }
  var sumY: Expr { Self.sum(ys) }
  var sumXX: Expr { Self.sum(xs.map { $0 * $0 }) }
  var sumYY: Expr { Self.sum(ys.map { $0 * $0 }) }
  var sumXY: Expr { Self.sum(zip(xs, ys).map { $0 * $1 }) }

  private func centered(_ squares: Expr, _ first: Expr, _ second: Expr) -> Expr {
    let correction = (try? (first * second).divided(by: .integer(count))) ?? .zero
    return (squares - correction).expanded()
  }

  /// Σ(x − x̄)², Σ(y − ȳ)² and Σ(x − x̄)(y − ȳ).
  var sxx: Expr { centered(sumXX, sumX, sumX) }
  var syy: Expr { centered(sumYY, sumY, sumY) }
  var sxy: Expr { centered(sumXY, sumX, sumY) }

  var meanX: Expr { (try? sumX.divided(by: .integer(count)).expanded()) ?? sumX }
  var meanY: Expr { (try? sumY.divided(by: .integer(count)).expanded()) ?? sumY }

  // MARK: Statistics

  /// The covariance: Σ(x − x̄)(y − ȳ) over n − 1 (a sample) or n (a population).
  func covariance(population: Bool) throws(MathError) -> Expr {
    try sxy.divided(by: .integer(population ? count : count - 1)).expanded()
  }

  /// Pearson's correlation coefficient r = Sxy / √(Sxx Syy), with the sign of the slope.
  func correlation() throws(MathError) -> Expr {
    let (sxx, syy) = (self.sxx, self.syy)
    guard !sxx.isZeroEntry, !syy.isZeroEntry else { throw .degenerateData }
    return try sxy.divided(by: (sxx * syy).expanded().raised(to: .fraction(1, 2)))
  }

  /// The square of the correlation: a fraction when the data are.
  func determination() throws(MathError) -> Expr {
    let (sxx, syy, sxy) = (self.sxx, self.syy, self.sxy)
    guard !sxx.isZeroEntry, !syy.isZeroEntry else { throw .degenerateData }
    return try (sxy * sxy).expanded().divided(by: (sxx * syy).expanded()).expanded()
  }

  /// The slope a of the least-squares line y = a x + b.
  func slope() throws(MathError) -> Expr {
    let sxx = self.sxx
    guard !sxx.isZeroEntry else { throw .degenerateData }
    return try sxy.divided(by: sxx).expanded()
  }

  /// The intercept b of the least-squares line y = a x + b.
  func intercept() throws(MathError) -> Expr {
    (meanY - (try slope()) * meanX).expanded()
  }
}
