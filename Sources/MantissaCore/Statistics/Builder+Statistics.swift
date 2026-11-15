// The statistics functions of `docs/statistics.md`, worked out on values that are numbers, vectors and tables.

extension Builder {
  // MARK: Reading the data

  /// A whole number from a value that must be one, at least `minimum`.
  private func wholeNumber(_ value: Expr, atLeast minimum: Int = 0) throws(MathError) -> Int {
    guard let number = value.rational, number.isInteger, let whole = number.numerator.asInt, whole >= minimum else {
      throw .domain
    }
    return whole
  }

  /// A column or a row: what holds one variable's data.
  private func vector(_ quantity: Quantity) -> [Expr]? {
    switch quantity {
    case .scalar(let number): return [number]
    case .matrix(let matrix): return matrix.isVector ? matrix.entries : nil
    case .report: return nil
    }
  }

  /// The data of a one-variable statistic: numbers, one vector, or values and then their frequencies as two vectors.
  func dataSet(_ values: [Quantity], vectors: [Bool] = []) throws(MathError) -> DataSet {
    if values.count == 1, let data = vector(values[0]) { return try DataSet(values: data) }
    // Two vectors are the values and their frequencies, even when each has a single entry. A 1×1 matrix is a number, so `vectors`
    // says which arguments were written as matrices.
    let written = vectors.count == values.count && vectors.allSatisfy { $0 }
    if values.count == 2, written || values.contains(where: { $0.asScalar == nil }),
      let data = vector(values[0]), let counts = vector(values[1]), data.count == counts.count
    {
      var frequencies: [Int] = []
      for count in counts { frequencies.append(try wholeNumber(count)) }
      return try DataSet(values: data, frequencies: frequencies)
    }
    if values.allSatisfy({ $0.asScalar != nil }) { return try DataSet(values: values.compactMap(\.asScalar)) }
    throw .dimensionMismatch
  }

  /// The data of a two-variable statistic: a table with the x in its first column and the y in its second, or two vectors.
  func pairedData(_ values: [Quantity]) throws(MathError) -> PairedData {
    if values.count == 1 {
      guard case .matrix(let table) = values[0], table.columnCount == 2 else { throw .dimensionMismatch }
      let rows = table.rows
      return try PairedData(xs: rows.map { $0[0] }, ys: rows.map { $0[1] })
    }
    guard values.count == 2, let xs = vector(values[0]), let ys = vector(values[1]) else { throw .dimensionMismatch }
    return try PairedData(xs: xs, ys: ys)
  }

  /// The values of a call's arguments, and which of them were written as matrices.
  func quantities(_ arguments: [Syntax]) throws(MathError) -> (values: [Quantity], written: [Bool]) {
    var values: [Quantity] = []
    var written: [Bool] = []
    for argument in arguments {
      values.append(try value(argument))
      switch argument {
      case .matrix: written.append(true)
      case .symbol(let name):
        if case .matrix? = environment[name] { written.append(true) } else { written.append(false) }
      default: written.append(false)
      }
    }
    return (values, written)
  }

  // MARK: Calls

  /// The value of a statistics function of values that have been worked out. The functions that make several numbers give a column;
  /// `stats` and `linreg` give a report.
  func statisticsCall(
    _ function: FunctionName, _ values: [Quantity], vectors: [Bool] = []
  ) throws(MathError) -> Quantity {
    if values.contains(where: { if case .report = $0 { return true } else { return false } }) { throw .unsupported }
    switch function {
    case .quartile, .percentile:
      guard values.count == 2, let parameter = values[1].asScalar else { throw .dimensionMismatch }
      let data = try dataSet([values[0]])
      if function == .quartile { return .scalar(try data.quartile(try wholeNumber(parameter))) }
      guard let percent = parameter.rational else { throw .unsupported }
      return .scalar(try data.percentile(percent))

    case .cov, .covp, .corr, .slope, .intercept:
      let pairs = try pairedData(values)
      switch function {
      case .cov: return .scalar(try pairs.covariance(population: false))
      case .covp: return .scalar(try pairs.covariance(population: true))
      case .corr: return .scalar(try pairs.correlation())
      case .slope: return .scalar(try pairs.slope())
      default: return .scalar(try pairs.intercept())
      }

    case .linreg, .polyreg, .expreg, .powreg, .logreg:
      return .report(try regression(function, values, vectors: vectors).report)

    case .stats:
      return .report(try summary(try dataSet(values, vectors: vectors)))

    case .sort:
      let data = try dataSet(values, vectors: vectors)
      guard data.count <= Matrix.maxRows else { throw .overflow }
      let sorted = zip(data.values, data.frequencies).flatMap { Array(repeating: $0, count: $1) }
      return .collapsing(Matrix(rowCount: sorted.count, columnCount: 1, entries: sorted))

    case .mode:
      guard let modes = try dataSet(values, vectors: vectors).modes else { throw .noMode }
      return .collapsing(Matrix(rowCount: modes.count, columnCount: 1, entries: modes))

    default:
      let data = try dataSet(values, vectors: vectors)
      switch function {
      case .count: return .scalar(.integer(data.count))
      case .total: return .scalar(data.total)
      case .sumsq: return .scalar(data.sumOfSquares)
      case .mean: return .scalar(data.mean)
      case .median: return .scalar(data.median)
      case .range: return .scalar(data.range)
      case .min: return .scalar(data.minimum)
      case .max: return .scalar(data.maximum)
      case .variance: return .scalar(try data.variance(population: false))
      case .varp: return .scalar(try data.variance(population: true))
      case .stdev: return .scalar(try data.deviation(population: false))
      case .stdevp: return .scalar(try data.deviation(population: true))
      case .iqr: return .scalar((try data.quartile(3) - data.quartile(1)).expanded())
      default: throw .unsupported
      }
    }
  }

  /// A statistic of numbers written out one by one, which has no matrix in it.
  func statisticsCall(_ function: FunctionName, scalars: [Expr]) throws(MathError) -> Expr {
    guard case .scalar(let value) = try statisticsCall(function, scalars.map { Quantity.scalar($0) }) else {
      throw .unsupported
    }
    return value
  }

  // MARK: Reports

  /// What `stats` says about one variable. The sample deviation needs two data and is left out of a single one; a set with no mode
  /// leaves that row out.
  private func summary(_ data: DataSet) throws(MathError) -> Report {
    var rows: [Report.Row] = [
      .init(.count, [.integer(data.count)]),
      .init(.mean, [data.mean]),
      .init(.sum, [data.total]),
      .init(.sumOfSquares, [data.sumOfSquares]),
    ]
    if data.count >= 2 { rows.append(.init(.sampleDeviation, [try data.deviation(population: false)])) }
    rows += [
      .init(.populationDeviation, [try data.deviation(population: true)]),
      .init(.minimum, [data.minimum]),
      .init(.firstQuartile, [try data.quartile(1)]),
      .init(.median, [data.median]),
      .init(.thirdQuartile, [try data.quartile(3)]),
      .init(.maximum, [data.maximum]),
    ]
    if let modes = data.modes { rows.append(.init(.mode, modes)) }
    return Report(rows: rows)
  }
}
