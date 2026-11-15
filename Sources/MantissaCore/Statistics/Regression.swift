// Least-squares fits of curves to points (`docs/statistics.md`): a polynomial exactly, and the exponential, power and logarithmic
// curves, which are lines in transformed coordinates, to 60 significant digits.

/// What a regression comes to: the report, the curve to draw, and the points.
struct Regression: Sendable {
  var report: Report
  /// The fitted curve as an expression in `x`. For the exponential, power and logarithmic fits its coefficients are the decimals
  /// as fractions: it is for drawing, not for showing as an exact answer.
  var curve: Expr
  var data: PairedData
}

extension PairedData {
  /// The digits that the numerical fits are worked to.
  fileprivate static let digits = 60

  // MARK: Polynomial

  /// The least-squares polynomial of this degree, exactly: the coefficients from the lowest power up, and the square of the
  /// correlation of the fit (`nil` when all the y are equal, which has no spread to explain).
  func polynomialFit(degree: Int) throws(MathError) -> (coefficients: [Expr], determination: Expr?) {
    guard (1...6).contains(degree) else { throw .domain }
    guard count > degree else { throw .insufficientData }
    let size = degree + 1
    // The normal equations: Σ x^(i+j) · a_j = Σ x^i · y.
    var powers: [[Expr]] = [Array(repeating: .one, count: count)]
    for _ in 1...(2 * degree) {
      powers.append(zip(powers[powers.count - 1], xs).map { ($0 * $1).expanded() })
    }
    let sums = powers.map { Expr.makeSum($0).expanded() }
    let normal = try Matrix.generated(rows: size, columns: size) { row, column throws(MathError) in sums[row + column] }
    let right = Matrix(
      rowCount: size, columnCount: 1,
      entries: (0..<size).map { Expr.makeSum(zip(powers[$0], ys).map { ($0 * $1).expanded() }).expanded() })
    let solution: Matrix
    do {
      solution = try normal.inverse().multiplied(by: right)
    } catch {
      // The points do not have enough different x for a polynomial of this degree.
      throw error == .singular ? .degenerateData : error
    }
    let coefficients = solution.entries
    let syy = self.syy
    guard !syy.isZeroEntry else { return (coefficients, nil) }
    var residual: [Expr] = []
    for (x, y) in zip(xs, ys) {
      var value = Expr.zero
      var power = Expr.one
      for coefficient in coefficients {
        value = value + coefficient * power
        power = (power * x).expanded()
      }
      let difference = y - value
      residual.append((difference * difference).expanded())
    }
    let fraction = try Expr.makeSum(residual).expanded().divided(by: syy).expanded()
    return (coefficients, (Expr.one - fraction).expanded())
  }

  // MARK: Transformed lines

  struct LineFit {
    var slope: BigDecimal
    var intercept: BigDecimal
    /// The correlation and its square; `nil` when the y have no spread.
    var correlation: BigDecimal?
    var determination: BigDecimal?
  }

  /// The least-squares line through points given as decimals.
  fileprivate static func lineFit(_ xs: [BigDecimal], _ ys: [BigDecimal]) throws(MathError) -> LineFit {
    let p = digits
    let n = BigDecimal(xs.count)
    var sumX = BigDecimal(0)
    var sumY = BigDecimal(0)
    for (x, y) in zip(xs, ys) {
      sumX += x
      sumY += y
    }
    let meanX = try sumX.divided(by: n, precision: p + 10)
    let meanY = try sumY.divided(by: n, precision: p + 10)
    var sxx = BigDecimal(0)
    var syy = BigDecimal(0)
    var sxy = BigDecimal(0)
    for (x, y) in zip(xs, ys) {
      let dx = (x - meanX).rounded(toSignificantDigits: p + 10)
      let dy = (y - meanY).rounded(toSignificantDigits: p + 10)
      sxx += dx * dx
      syy += dy * dy
      sxy += dx * dy
    }
    // A spread this small is rounding, not data.
    let tiny = BigDecimal(BigInt(1), exponent: -(p - 5))
    guard sxx.magnitude > tiny else { throw .degenerateData }
    let slope = try sxy.divided(by: sxx, precision: p)
    let intercept = (meanY - slope * meanX).rounded(toSignificantDigits: p)
    guard syy.magnitude > tiny else { return LineFit(slope: slope, intercept: intercept) }
    let determination = try (sxy * sxy).divided(by: sxx * syy, precision: p)
    var correlation = try determination.squareRoot(precision: p)
    if sxy.isNegative { correlation = -correlation }
    return LineFit(slope: slope, intercept: intercept, correlation: correlation, determination: determination)
  }

  /// The decimal value of a datum, to the working digits.
  private static func decimal(_ value: Expr) throws(MathError) -> BigDecimal {
    try value.approximation(precision: digits + 10)
  }

  private static func logarithms(_ values: [BigDecimal]) throws(MathError) -> [BigDecimal] {
    var logs: [BigDecimal] = []
    for value in values {
      guard !value.isNegative, !value.isZero else { throw .domain }
      logs.append(try value.ln(precision: digits + 10))
    }
    return logs
  }

  /// `y = a bˣ`: a line through (x, ln y), with a = e^intercept and b = e^slope. All y must be positive.
  func exponentialFit() throws(MathError) -> (a: BigDecimal, b: BigDecimal, fit: LineFit) {
    let x = try xs.map { (value: Expr) throws(MathError) -> BigDecimal in try Self.decimal(value) }
    let y = try Self.logarithms(try ys.map { (value: Expr) throws(MathError) -> BigDecimal in try Self.decimal(value) })
    let fit = try Self.lineFit(x, y)
    let p = Self.digits
    return (try fit.intercept.exp(precision: p), try fit.slope.exp(precision: p), fit)
  }

  /// `y = a xᵇ`: a line through (ln x, ln y), with a = e^intercept and b = the slope. All x and y must be positive.
  func powerFit() throws(MathError) -> (a: BigDecimal, b: BigDecimal, fit: LineFit) {
    let x = try Self.logarithms(try xs.map { (value: Expr) throws(MathError) -> BigDecimal in try Self.decimal(value) })
    let y = try Self.logarithms(try ys.map { (value: Expr) throws(MathError) -> BigDecimal in try Self.decimal(value) })
    let fit = try Self.lineFit(x, y)
    return (try fit.intercept.exp(precision: Self.digits), fit.slope, fit)
  }

  /// `y = a + b ln x`: a line through (ln x, y). All x must be positive.
  func logarithmicFit() throws(MathError) -> (a: BigDecimal, b: BigDecimal, fit: LineFit) {
    let x = try Self.logarithms(try xs.map { (value: Expr) throws(MathError) -> BigDecimal in try Self.decimal(value) })
    let y = try ys.map { (value: Expr) throws(MathError) -> BigDecimal in try Self.decimal(value) }
    let fit = try Self.lineFit(x, y)
    return (fit.intercept, fit.slope, fit)
  }
}

extension Builder {
  /// The fit of a curve to points, as a report and as a curve to draw.
  func regression(_ function: FunctionName, _ values: [Quantity], vectors: [Bool] = []) throws(MathError) -> Regression
  {
    var values = values
    var degree = 0
    if function == .polyreg {
      // The last argument is the degree.
      guard values.count >= 2, let last = values.popLast()?.asScalar else { throw .dimensionMismatch }
      guard let whole = last.rational, whole.isInteger, let asInt = whole.numerator.asInt else { throw .domain }
      degree = asInt
    }
    let data = try pairedData(values)
    let x = Expr.symbol("x")

    switch function {
    case .linreg:
      let slope = try data.slope()
      let intercept = try data.intercept()
      let line = (slope * x + intercept).expanded()
      let report = Report(
        rows: [
          .init(.equation, [line]), .init(.slope, [slope]), .init(.intercept, [intercept]),
          .init(.correlation, [try data.correlation()]), .init(.determination, [try data.determination()]),
          .init(.count, [.integer(data.count)]),
        ], model: .linear)
      return Regression(report: report, curve: line, data: data)

    case .polyreg:
      let (coefficients, determination) = try data.polynomialFit(degree: degree)
      var curve = Expr.zero
      var power = Expr.one
      for coefficient in coefficients {
        curve = curve + coefficient * power
        power = power * x
      }
      curve = curve.expanded()
      var rows: [Report.Row] = [.init(.equation, [curve])]
      for (power, coefficient) in coefficients.enumerated().reversed() {
        rows.append(.init(.coefficient(power), [coefficient]))
      }
      if let determination { rows.append(.init(.determination, [determination])) }
      rows.append(.init(.count, [.integer(data.count)]))
      return Regression(report: Report(rows: rows, model: .polynomial(degree)), curve: curve, data: data)

    case .expreg, .powreg, .logreg:
      let (a, b, fit, model): (BigDecimal, BigDecimal, PairedData.LineFit, Report.Model)
      switch function {
      case .expreg:
        (a, b, fit) = try data.exponentialFit()
        model = .exponential
      case .powreg:
        (a, b, fit) = try data.powerFit()
        model = .power
      default:
        (a, b, fit) = try data.logarithmicFit()
        model = .logarithmic
      }
      var rows: [Report.Row] = [.init(.parameterA, approximations: [a]), .init(.parameterB, approximations: [b])]
      if let correlation = fit.correlation, let determination = fit.determination {
        rows.append(.init(.correlation, approximations: [correlation]))
        rows.append(.init(.determination, approximations: [determination]))
      }
      rows.append(.init(.count, [.integer(data.count)]))
      // The curve to draw has the coefficients as fractions of 40 digits, which is far more than a screen can tell apart.
      let fractionA = Expr.number(a.rounded(toSignificantDigits: 40).rational)
      let fractionB = Expr.number(b.rounded(toSignificantDigits: 40).rational)
      let curve: Expr
      switch model {
      case .exponential: curve = fractionA * fractionB.raisedToSymbolExponent(x)
      case .power: curve = fractionA * x.raisedToSymbolExponent(fractionB)
      default: curve = fractionA + fractionB * (try Expr.apply(.ln, [x]))
      }
      return Regression(report: Report(rows: rows, model: model), curve: curve, data: data)

    default:
      throw .unsupported
    }
  }
}

extension Expr {
  /// `self ^ exponent` where the base is not zero, which holds for the fitted coefficients (they are positive).
  fileprivate func raisedToSymbolExponent(_ exponent: Expr) -> Expr { Expr.makePower(self, exponent) }
}

extension Calculator {
  /// What a regression draws: the points and the curve fitted to them. `nil` when the input is not a regression of data that can be
  /// worked out.
  func regressionContent(_ text: String) -> PlotContent? {
    guard let statement = try? Parser.parse(text), case .expression(.call(let function, let arguments)) = statement,
      function.isRegression
    else { return nil }
    let builder = Builder(angleUnit: settings.angleUnit)
    guard let (values, written) = try? builder.quantities(arguments),
      let regression = try? builder.regression(function, values, vectors: written)
    else { return nil }
    let points = zip(regression.data.xs, regression.data.ys).compactMap { x, y -> PlotDataPoint? in
      guard let px = try? x.approximation(precision: 20).doubleValue,
        let py = try? y.approximation(precision: 20).doubleValue
      else { return nil }
      return PlotDataPoint(x: px, y: py)
    }
    return PlotContent(functions: [PlotFunction(regression.curve)], points: points)
  }
}
