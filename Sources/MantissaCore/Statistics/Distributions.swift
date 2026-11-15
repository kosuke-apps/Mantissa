// Probability distributions whose probabilities are exact (`docs/statistics.md`): binomial, Poisson, geometric, hypergeometric, uniform
// and exponential. A probability of a binomial, geometric or hypergeometric distribution is a fraction, of a Poisson distribution a
// fraction times e^−λ, of an exponential one an expression with e^−λx; nothing here is rounded.

enum Distributions {
  /// The most trials, successes or values in a sum: a larger one is not worked out ("too large").
  static let maxCount = 2000

  static func evaluate(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    switch function {
    case .binompdf, .binomcdf, .binominv: return try binomial(function, x)
    case .poissonpdf, .poissoncdf, .poissoninv: return try poisson(function, x)
    case .geompdf, .geomcdf, .geominv: return try geometric(function, x)
    case .hyperpdf, .hypercdf: return try hypergeometric(function, x)
    case .uniformpdf, .uniformcdf, .uniforminv: return try uniform(function, x)
    case .exponentialpdf, .exponentialcdf, .exponentialinv: return try exponential(function, x)
    default: throw .unsupported
    }
  }

  // MARK: Arguments

  /// A fraction: the value of an argument that must be exact and rational.
  private static func rational(_ value: Expr) throws(MathError) -> Rational {
    // A number that is not rational (√2, π) is not taken here.
    guard let number = value.rational else { throw .unsupported }
    return number
  }

  /// A whole number in a range (a count of trials, or of things in a population).
  private static func whole(_ value: Expr, _ range: ClosedRange<Int>) throws(MathError) -> Int {
    let number = try rational(value)
    guard number.isInteger, let integer = number.numerator.asInt else { throw .domain }
    // Beyond the largest size that is worked out is too large; beyond what the other arguments allow is outside the domain.
    guard range.contains(integer) else {
      throw integer > range.upperBound && range.upperBound == maxCount ? .overflow : .domain
    }
    return integer
  }

  /// A probability, 0 to 1.
  private static func probability(_ value: Expr) throws(MathError) -> Rational {
    let number = try rational(value)
    guard !number.isNegative, number <= Rational(1) else { throw .domain }
    return number
  }

  /// The place a discrete cdf is asked at: the whole number at or below it, clamped to −1 (nothing) and `upper` (everything).
  private static func floorAt(_ value: Expr, upper: Int) throws(MathError) -> Int {
    let number = try rational(value)
    if number.isNegative { return -1 }
    guard let integer = number.numerator.floorDivided(by: number.denominator).asInt else { return upper }
    return min(integer, upper)
  }

  /// The place a discrete pmf is asked at: nothing happens at a number that is not whole.
  private static func wholeAt(_ value: Expr) throws(MathError) -> Int? {
    let number = try rational(value)
    guard number.isInteger, let integer = number.numerator.asInt else { return nil }
    return integer
  }

  // MARK: Binomial

  private static func combinations(_ n: Int, _ k: Int) throws(MathError) -> BigInt {
    guard let value = NumberTheory.combinations(n, k) else { throw .overflow }
    return value
  }

  private static func binomialMass(_ n: Int, _ k: Int, _ p: Rational) throws(MathError) -> Rational {
    guard (0...n).contains(k) else { return Rational(0) }
    return Rational(try combinations(n, k)) * p.power(k) * (Rational(1) - p).power(n - k)
  }

  private static func binomial(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let n = try whole(x[0], 0...maxCount)
    let p = try probability(x[1])
    switch function {
    case .binompdf:
      guard let k = try wholeAt(x[2]) else { return .zero }
      return .number(try binomialMass(n, k, p))
    case .binomcdf:
      let k = try floorAt(x[2], upper: n)
      var sum = Rational(0)
      if k >= 0 { for j in 0...k { sum += try binomialMass(n, j, p) } }
      return .number(sum)
    default:
      let q = try probability(x[2])
      var sum = Rational(0)
      for k in 0...n {
        sum += try binomialMass(n, k, p)
        if sum >= q { return .integer(k) }
      }
      return .integer(n)
    }
  }

  // MARK: Hypergeometric

  private static func hypergeometric(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let population = try whole(x[0], 0...maxCount)
    let successes = try whole(x[1], 0...population)
    let drawn = try whole(x[2], 0...population)
    let low = max(0, drawn - (population - successes))
    let high = min(drawn, successes)
    func mass(_ k: Int) throws(MathError) -> Rational {
      guard (low...high).contains(k) else { return Rational(0) }
      let ways = try combinations(successes, k) * combinations(population - successes, drawn - k)
      return Rational(ways, try combinations(population, drawn))
    }
    if function == .hyperpdf {
      guard let k = try wholeAt(x[3]) else { return .zero }
      return .number(try mass(k))
    }
    let k = try floorAt(x[3], upper: high)
    var sum = Rational(0)
    if k >= low { for j in low...k { sum += try mass(j) } }
    return .number(sum)
  }

  // MARK: Poisson

  /// λ^j/j!
  private static func poissonTerm(_ rate: Rational, _ j: Int) throws(MathError) -> Rational {
    guard let factorial = NumberTheory.factorial(j) else { throw .overflow }
    return rate.power(j) / Rational(factorial)
  }

  private static func poisson(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let rate = try rational(x[0])
    guard !rate.isNegative else { throw .domain }
    let decay = try Expr.e.raised(to: .number(-rate))
    switch function {
    case .poissonpdf:
      guard let k = try wholeAt(x[1]) else { return .zero }
      guard k >= 0 else { return .zero }
      guard k <= maxCount else { throw .overflow }
      return decay * .number(try poissonTerm(rate, k))
    case .poissoncdf:
      let k = try floorAt(x[1], upper: maxCount)
      guard k >= 0 else { return .zero }
      var sum = Rational(0)
      for j in 0...k { sum += try poissonTerm(rate, j) }
      return decay * .number(sum)
    default:
      let q = try probability(x[1])
      guard q < Rational(1) else { throw .domain }  // every whole number has a probability left over
      if rate.isZero || q.isZero { return .zero }
      // The smallest k with e^−λ Σ λ^j/j! ≥ q, found in decimals at 70 digits (the cdf is irrational, so it is never equal to q).
      let digits = 70
      let lambda = BigDecimal(rate, precision: digits)
      let threshold = try BigDecimal(q, precision: digits) * lambda.exp(precision: digits)
      var term = BigDecimal(1)
      var sum = BigDecimal(1)
      var k = 0
      while sum < threshold {
        k += 1
        guard k <= maxCount * 5 else { throw .overflow }
        term = try (term * lambda).divided(by: BigDecimal(k), precision: digits)
        sum = sum + term
      }
      return .integer(k)
    }
  }

  // MARK: Geometric

  private static func geometric(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let p = try rational(x[0])
    guard p > Rational(0), p <= Rational(1) else { throw .domain }
    let failure = Rational(1) - p
    switch function {
    case .geompdf:
      guard let k = try wholeAt(x[1]), k >= 1 else { return .zero }
      guard k <= maxCount * 5 else { throw .overflow }
      return .number(failure.power(k - 1) * p)
    case .geomcdf:
      let k = try floorAt(x[1], upper: maxCount * 5)
      guard k >= 1 else { return .zero }
      return .number(Rational(1) - failure.power(k))
    default:
      let q = try probability(x[1])
      guard q < Rational(1) else { throw .domain }
      if q.isZero || failure.isZero { return .one }
      // k = ⌈ln(1 − q) / ln(1 − p)⌉; when the quotient is a whole number to many digits it is a tie that is decided exactly.
      let digits = 80
      let ratio = try BigDecimal(Rational(1) - q, precision: digits).ln(precision: digits).divided(
        by: BigDecimal(failure, precision: digits).ln(precision: digits), precision: digits)
      let nearest = ratio.rounded(toPlaces: 0)
      guard (ratio - nearest).magnitude < BigDecimal(BigInt(1), exponent: -50) else {
        guard let floor = ratio.floor.asInt, floor < 1_000_000_000 else { throw .overflow }
        return .integer(max(1, floor + 1))
      }
      guard var k = nearest.asInt, k <= maxCount * 5 else { throw .overflow }
      k = max(k, 1)
      let target = Rational(1) - q
      while k > 1, failure.power(k - 1) <= target { k -= 1 }
      while failure.power(k) > target { k += 1 }
      return .integer(k)
    }
  }

  // MARK: Normal

  /// The normal distribution with a mean and a standard deviation (0 and 1 when left out): the density is exact; the cumulative
  /// probability is written with the complementary error function (its lower half as erfc, so that a tiny tail keeps all its digits)
  /// and the quantile with `probit`.
  static func normal(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let mean = x.count >= 2 ? x[1] : Expr.zero
    let deviation = x.count == 3 ? x[2] : Expr.one
    guard try sign(deviation) > 0 else { throw .domain }
    let root2 = try Expr.integer(2).raised(to: .fraction(1, 2))
    switch function {
    case .normalpdf:
      let distance = (x[0] - mean).expanded()
      let exponent = try (-(distance * distance)).divided(by: Expr.integer(2) * deviation * deviation)
      let width = deviation * (try (Expr.integer(2) * .pi).raised(to: .fraction(1, 2)))
      return try Expr.e.raised(to: exponent.expanded()).divided(by: width)
    case .normalcdf:
      let z = try (x[0] - mean).divided(by: deviation * root2).expanded()
      let half = Expr.fraction(1, 2)
      // With a letter in it (a graph of the cdf) the side is not known, and the error function does for both.
      guard let side = z.numericSign else { return half + half * (try Expr.apply(.erf, [z])) }
      if side < 0 { return half * (try Expr.apply(.erfc, [-z])) }
      return Expr.one - half * (try Expr.apply(.erfc, [z]))
    default:
      let z = try Expr.apply(.probit, [x[0]])
      return (mean + deviation * z).expanded()
    }
  }

  // MARK: Uniform and exponential

  /// −1, 0 or 1 for a real number with no letter in it.
  fileprivate static func sign(_ value: Expr) throws(MathError) -> Int {
    guard let sign = value.numericSign else { throw .unsupported }
    return sign
  }

  private static func uniform(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let (a, b) = (x[1], x[2])
    let width = (b - a).expanded()
    guard try sign(width) > 0 else { throw .domain }
    switch function {
    case .uniformpdf:
      let belowStart = try sign(x[0] - a)
      let aboveEnd = try sign(b - x[0])
      return belowStart < 0 || aboveEnd < 0 ? .zero : try Expr.one.divided(by: width)
    case .uniformcdf:
      if try sign(x[0] - a) <= 0 { return .zero }
      if try sign(b - x[0]) <= 0 { return .one }
      return try (x[0] - a).divided(by: width).expanded()
    default:
      let p = x[0]
      guard try sign(p) >= 0, try sign(Expr.one - p) >= 0 else { throw .domain }
      return (a + p * width).expanded()
    }
  }

  private static func exponential(_ function: FunctionName, _ x: [Expr]) throws(MathError) -> Expr {
    let rate = x[1]
    guard try sign(rate) > 0 else { throw .domain }
    switch function {
    case .exponentialpdf:
      if try sign(x[0]) < 0 { return .zero }
      return rate * (try Expr.e.raised(to: -(rate * x[0])))
    case .exponentialcdf:
      if try sign(x[0]) <= 0 { return .zero }
      return Expr.one - (try Expr.e.raised(to: -(rate * x[0])))
    default:
      let p = x[0]
      guard try sign(p) >= 0, try sign(Expr.one - p) > 0 else { throw .domain }
      return try (-(try Expr.apply(.ln, [Expr.one - p]))).divided(by: rate)
    }
  }
}
