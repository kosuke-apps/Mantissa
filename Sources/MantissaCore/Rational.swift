/// An exact fraction of two `BigInt`s, always in lowest terms with a positive denominator.
///
/// Because the form is canonical, two equal fractions are always `==` and hash alike. Division by zero is a
/// programming error here (as for `Int`); the layers above check for it and report a mathematical error instead.
public struct Rational: Sendable, Hashable {
  public let numerator: BigInt
  public let denominator: BigInt

  public init(_ numerator: BigInt, _ denominator: BigInt = 1) {
    precondition(!denominator.isZero, "A fraction needs a non-zero denominator")
    var numerator = numerator
    var denominator = denominator
    if denominator.isNegative {
      numerator = -numerator
      denominator = -denominator
    }
    let divisor = BigInt.gcd(numerator, denominator)
    if !divisor.isOne {
      numerator = numerator / divisor
      denominator = denominator / divisor
    }
    self.numerator = numerator
    self.denominator = denominator
  }

  public init(_ numerator: Int, _ denominator: Int = 1) {
    self.init(BigInt(numerator), BigInt(denominator))
  }

  /// Parses a decimal literal such as `12`, `-1.25`, `.5` or `2.5e-3`. Returns `nil` for anything else, and for
  /// exponents beyond ±10 000, which no calculator input needs and which would build enormous numbers.
  public init?(decimal text: String) {
    var rest = Substring(text)
    var negative = false
    if let sign = rest.first, sign == "-" || sign == "+" {
      negative = sign == "-"
      rest = rest.dropFirst()
    }

    var exponent = 0
    if let marker = rest.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      guard let value = Int(rest[rest.index(after: marker)...]), value.magnitude <= 10_000 else { return nil }
      exponent = value
      rest = rest[..<marker]
    }

    var integerPart = rest
    var fractionPart = Substring()
    if let point = rest.firstIndex(of: ".") {
      integerPart = rest[..<point]
      fractionPart = rest[rest.index(after: point)...]
    }
    let digitText = String(integerPart) + String(fractionPart)
    guard !digitText.isEmpty, digitText.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), let digits = BigInt(digitText)
    else { return nil }

    exponent -= fractionPart.count
    let scale = BigInt(10).power(abs(exponent))
    let value = exponent >= 0 ? Rational(digits * scale) : Rational(digits, scale)
    self = negative ? -value : value
  }

  public var isZero: Bool { numerator.isZero }
  public var isInteger: Bool { denominator.isOne }
  public var isNegative: Bool { numerator.isNegative }
  public var signum: Int { numerator.signum }

  /// The multiplicative inverse. The value must not be zero.
  public var reciprocal: Rational {
    precondition(!isZero, "Division by zero")
    return Rational(denominator, numerator)
  }

  public var magnitude: Rational { isNegative ? -self : self }

  /// `self` to an integer power. A negative power needs a non-zero value.
  public func power(_ exponent: Int) -> Rational {
    if exponent < 0 { return reciprocal.power(-exponent) }
    return Rational(numerator.power(exponent), denominator.power(exponent))
  }

  public static prefix func - (value: Rational) -> Rational {
    Rational(-value.numerator, value.denominator)
  }

  public static func + (lhs: Rational, rhs: Rational) -> Rational {
    Rational(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator, lhs.denominator * rhs.denominator)
  }

  public static func - (lhs: Rational, rhs: Rational) -> Rational { lhs + (-rhs) }

  public static func * (lhs: Rational, rhs: Rational) -> Rational {
    Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
  }

  /// The divisor must not be zero.
  public static func / (lhs: Rational, rhs: Rational) -> Rational { lhs * rhs.reciprocal }

  public static func += (lhs: inout Rational, rhs: Rational) { lhs = lhs + rhs }
  public static func -= (lhs: inout Rational, rhs: Rational) { lhs = lhs - rhs }
  public static func *= (lhs: inout Rational, rhs: Rational) { lhs = lhs * rhs }
  public static func /= (lhs: inout Rational, rhs: Rational) { lhs = lhs / rhs }
}

extension Rational: Comparable {
  public static func < (lhs: Rational, rhs: Rational) -> Bool {
    lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
  }
}

extension Rational: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self.init(BigInt(value)) }
}

extension Rational: CustomStringConvertible {
  public var description: String { isInteger ? "\(numerator)" : "\(numerator)/\(denominator)" }
}
