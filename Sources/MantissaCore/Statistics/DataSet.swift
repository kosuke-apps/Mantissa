// Data for the statistics functions (`docs/statistics.md`): real numbers, each with how often it occurs. Everything computed from it is
// exact: sums, means and variances of fractions are fractions, and a standard deviation is a root.

/// The data of a one-variable statistic: the distinct values in ascending order, each with its frequency.
struct DataSet: Sendable, Equatable {
  /// The most data a set stands for, counting each value as often as it occurs; it keeps the sums of frequencies in an `Int`.
  static let maxCount = 1_000_000_000

  /// The distinct values, ascending.
  let values: [Expr]
  /// How often each value occurs: all positive.
  let frequencies: [Int]
  /// The number of data, the sum of the frequencies.
  let count: Int
  /// `cumulative[i]` is the number of data that are at most `values[i]`.
  private let cumulative: [Int]

  /// The data `values`, each as often as `frequencies` says (once when there are none). Values that are equal are merged, a value
  /// with frequency zero is dropped, and a data set with nothing in it has no statistics.
  init(values: [Expr], frequencies: [Int]? = nil) throws(MathError) {
    let frequencies = frequencies ?? Array(repeating: 1, count: values.count)
    guard values.count == frequencies.count else { throw .dimensionMismatch }
    for value in values { try DataSet.requireReal(value) }
    guard frequencies.allSatisfy({ $0 >= 0 }) else { throw .domain }

    // Sort by value; the sort is stable, so equal values stay next to each other for merging.
    let order = values.indices.sorted { DataSet.isLess(values[$0], values[$1]) }
    var merged: [Expr] = []
    var counts: [Int] = []
    var total = 0
    for index in order where frequencies[index] > 0 {
      let (sum, overflow) = total.addingReportingOverflow(frequencies[index])
      guard !overflow, sum <= DataSet.maxCount else { throw .overflow }
      total = sum
      if let last = merged.last, DataSet.isEqual(last, values[index]) {
        counts[counts.count - 1] += frequencies[index]
      } else {
        merged.append(values[index])
        counts.append(frequencies[index])
      }
    }
    guard total > 0 else { throw .insufficientData }
    self.values = merged
    self.frequencies = counts
    self.count = total
    var running = 0
    self.cumulative = counts.map {
      running += $0
      return running
    }
  }

  // MARK: Values

  /// A datum is a real number with no letter in it: exact (`1/3`, `√2`, `π`), compared by its value.
  static func requireReal(_ value: Expr) throws(MathError) {
    guard value.freeSymbols.isEmpty, !value.containsImaginaryUnit, !value.containsInfinity else { throw .unsupported }
    if value.rational == nil, value.numericSign == nil { throw .unsupported }
  }

  /// Whether `a` is less than `b`: fractions exactly, other numbers by their decimals.
  static func isLess(_ a: Expr, _ b: Expr) -> Bool {
    if let x = a.rational, let y = b.rational { return x < y }
    return (a - b).numericSign.map { $0 < 0 } ?? false
  }

  static func isEqual(_ a: Expr, _ b: Expr) -> Bool {
    if a == b { return true }
    if a.rational != nil && b.rational != nil { return false }
    return (a - b).numericSign == 0
  }

  /// The `rank`-th smallest datum, counting from 1.
  func value(atRank rank: Int) -> Expr {
    precondition((1...count).contains(rank))
    var low = 0
    var high = values.count - 1
    while low < high {
      let middle = (low + high) / 2
      if cumulative[middle] >= rank { high = middle } else { low = middle + 1 }
    }
    return values[low]
  }

  // MARK: Sums

  /// The sum of the data, Σx.
  var total: Expr { Expr.makeSum(zip(values, frequencies).map { Expr.integer($1) * $0 }).expanded() }

  /// The sum of the squares of the data, Σx².
  var sumOfSquares: Expr { Expr.makeSum(zip(values, frequencies).map { Expr.integer($1) * $0 * $0 }).expanded() }

  var mean: Expr {
    // The count is positive, so the division cannot fail.
    (try? total.divided(by: .integer(count)).expanded()) ?? total
  }

  /// Σ(x − x̄)², the sum of squared deviations from the mean.
  var sumOfSquaredDeviations: Expr {
    let sum = total
    let correction = (try? (sum * sum).divided(by: .integer(count))) ?? .zero
    return (sumOfSquares - correction).expanded()
  }

  // MARK: Order statistics

  var minimum: Expr { values[0] }
  var maximum: Expr { values[values.count - 1] }
  var range: Expr { (maximum - minimum).expanded() }

  /// The middle of the data from the `low`-th to the `high`-th smallest: the middle one, or the mean of the middle two.
  private func middle(from low: Int, to high: Int) -> Expr {
    let size = high - low + 1
    let upper = value(atRank: low + size / 2)
    if size % 2 == 1 { return upper }
    let lower = value(atRank: low + size / 2 - 1)
    return ((lower + upper) * .fraction(1, 2)).expanded()
  }

  var median: Expr { middle(from: 1, to: count) }

  /// The first, second or third quartile: the median of the lower half, of the data, of the upper half; with an odd number of data
  /// the middle one belongs to neither half. A single datum is all three.
  func quartile(_ k: Int) throws(MathError) -> Expr {
    guard (1...3).contains(k) else { throw .domain }
    if k == 2 || count == 1 { return median }
    let half = count / 2
    return k == 1 ? middle(from: 1, to: half) : middle(from: count - half + 1, to: count)
  }

  /// The `p`-th percentile, 0 ≤ p ≤ 100: the value at position 1 + (n − 1)p/100 of the sorted data, between its neighbours linearly.
  func percentile(_ p: Rational) throws(MathError) -> Expr {
    guard !p.isNegative, p <= Rational(100) else { throw .domain }
    let position = Rational(count - 1) * p / Rational(100)  // counted from 0
    let whole = position.numerator.floorDivided(by: position.denominator)
    guard let index = whole.asInt else { throw .overflow }
    let fraction = position - Rational(whole)
    let lower = value(atRank: index + 1)
    if fraction.isZero || index + 1 >= count { return lower }
    let upper = value(atRank: index + 2)
    return (lower + Expr.number(fraction) * (upper - lower)).expanded()
  }

  /// The values that occur most often, ascending. `nil` when every value occurs equally often and there is more than one (no mode).
  var modes: [Expr]? {
    guard let highest = frequencies.max() else { return nil }
    let winners = values.indices.filter { frequencies[$0] == highest }
    if winners.count == values.count && values.count > 1 { return nil }
    return winners.map { values[$0] }
  }

  // MARK: Spread

  /// The variance: the sum of squared deviations over n − 1 (a sample) or n (a population).
  func variance(population: Bool) throws(MathError) -> Expr {
    let divisor = population ? count : count - 1
    guard divisor > 0 else { throw .insufficientData }
    return try sumOfSquaredDeviations.divided(by: .integer(divisor)).expanded()
  }

  /// The standard deviation, the root of the variance.
  func deviation(population: Bool) throws(MathError) -> Expr {
    try variance(population: population).raised(to: .fraction(1, 2))
  }
}
