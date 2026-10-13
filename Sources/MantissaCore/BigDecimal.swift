import Foundation

/// An arbitrary-precision decimal number: `significand × 10^exponent`.
///
/// Addition, subtraction and multiplication are exact. Division, roots and the transcendental functions take a
/// `precision` (a number of significant digits) and round half away from zero to it, the way a calculator display
/// does. The stored form is canonical (no trailing zeros in the significand, zero is `0 × 10^0`), so equal values
/// are `==` and hash alike.
///
/// Exact addition lines the two operands up, which costs memory proportional to the gap between their exponents.
/// Callers keep operands within a few hundred digits of each other; the functions in this package do.
public struct BigDecimal: Sendable, Hashable {
  public let significand: BigInt
  public let exponent: Int

  /// The number of significant digits the functions use when none is given.
  public static let defaultPrecision = 50

  public init(_ significand: BigInt, exponent: Int = 0) {
    var significand = significand
    var exponent = exponent
    if significand.isZero {
      self.significand = significand
      self.exponent = 0
      return
    }
    // Strip trailing zeros, nine at a time while possible.
    let billion = BigInt(1_000_000_000)
    let ten = BigInt(10)
    while true {
      let (quotient, remainder) = significand.quotientAndRemainder(dividingBy: billion)
      if !remainder.isZero { break }
      significand = quotient
      exponent += 9
    }
    while true {
      let (quotient, remainder) = significand.quotientAndRemainder(dividingBy: ten)
      if !remainder.isZero { break }
      significand = quotient
      exponent += 1
    }
    self.significand = significand
    self.exponent = exponent
  }

  public init(_ value: Int) { self.init(BigInt(value)) }

  /// Parses a decimal literal such as `12`, `-1.25`, `.5` or `2.5e-30`. Returns `nil` for anything else, and for
  /// exponents beyond ±1 000 000 000.
  public init?(_ text: String) {
    var rest = Substring(text)
    var negative = false
    if let sign = rest.first, sign == "-" || sign == "+" {
      negative = sign == "-"
      rest = rest.dropFirst()
    }

    var exponent = 0
    if let marker = rest.firstIndex(where: { $0 == "e" || $0 == "E" }) {
      guard let value = Int(rest[rest.index(after: marker)...]), value.magnitude <= 1_000_000_000 else { return nil }
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

    self.init(negative ? -digits : digits, exponent: exponent - fractionPart.count)
  }

  /// `numerator / denominator` rounded to `precision` significant digits.
  public init(_ value: Rational, precision: Int = BigDecimal.defaultPrecision) {
    // The denominator is never zero, so this cannot fail.
    self = try! BigDecimal(value.numerator).divided(by: BigDecimal(value.denominator), precision: precision)
  }

  public var isZero: Bool { significand.isZero }
  public var isNegative: Bool { significand.isNegative }
  public var signum: Int { significand.signum }
  public var isInteger: Bool { exponent >= 0 }

  public var magnitude: BigDecimal { BigDecimal(significand.magnitude, exponent: exponent) }

  /// The number `n` such that `10^(n-1) <= |self| < 10^n`; `nil` for zero. For example 1234 has order 4, 0.5 has
  /// order 0 and 0.05 has order -1.
  public var decimalOrder: Int? {
    isZero ? nil : significand.decimalDigitCount + exponent
  }

  /// The exact value as a fraction. The exponent must be small enough for the numerator or denominator to fit in
  /// memory, which is true of every value this package produces.
  public var rational: Rational {
    exponent >= 0
      ? Rational(significand * BigInt.power10(exponent))
      : Rational(significand, BigInt.power10(-exponent))
  }

  /// The nearest `Double`, which overflows to infinity or underflows to zero outside Double's range.
  public var doubleValue: Double { Double(description) ?? 0 }

  /// The largest integer not greater than the value.
  public var floor: BigInt {
    exponent >= 0
      ? significand * BigInt.power10(exponent)
      : significand.floorDivided(by: BigInt.power10(-exponent))
  }

  /// The value as an `Int` if it is a whole number that fits.
  public var asInt: Int? {
    guard isInteger, let order = decimalOrder, order <= 19 else { return isZero ? 0 : nil }
    return (significand * BigInt.power10(exponent)).asInt
  }

  // MARK: Rounding

  /// Rounds half away from zero to `digits` significant digits.
  public func rounded(toSignificantDigits digits: Int) -> BigDecimal {
    precondition(digits >= 1, "Significant digits must be at least 1")
    let count = significand.decimalDigitCount
    return count <= digits ? self : droppingLowDigits(count - digits)
  }

  /// Rounds half away from zero to `places` digits after the decimal point (before it when negative).
  public func rounded(toPlaces places: Int) -> BigDecimal {
    let drop = -places - exponent
    if drop <= 0 { return self }
    // Fewer digits than the rounding position means the value is below a tenth of a unit: it rounds to zero.
    return drop > significand.decimalDigitCount ? BigDecimal(0) : droppingLowDigits(drop)
  }

  private func droppingLowDigits(_ count: Int) -> BigDecimal {
    let divisor = BigInt.power10(count)
    var (quotient, remainder) = significand.magnitude.quotientAndRemainder(dividingBy: divisor)
    if remainder + remainder >= divisor { quotient += BigInt(1) }
    return BigDecimal(isNegative ? -quotient : quotient, exponent: exponent + count)
  }

  // MARK: Arithmetic

  public static prefix func - (value: BigDecimal) -> BigDecimal {
    BigDecimal(-value.significand, exponent: value.exponent)
  }

  public static func + (lhs: BigDecimal, rhs: BigDecimal) -> BigDecimal {
    if lhs.isZero { return rhs }
    if rhs.isZero { return lhs }
    let exponent = min(lhs.exponent, rhs.exponent)
    return BigDecimal(lhs.alignedSignificand(to: exponent) + rhs.alignedSignificand(to: exponent), exponent: exponent)
  }

  public static func - (lhs: BigDecimal, rhs: BigDecimal) -> BigDecimal { lhs + (-rhs) }

  /// `self + other` rounded to `precision` significant digits, without lining the operands up when one is so much
  /// smaller than the other that it cannot reach the digits kept (the exact `+` would build a huge integer). In the
  /// one case where the larger operand sits exactly on a rounding boundary the result can differ in the last digit.
  public func adding(_ other: BigDecimal, precision: Int) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    guard let order = decimalOrder, let otherOrder = other.decimalOrder else {
      return (isZero ? other : self).rounded(toSignificantDigits: precision)
    }
    if order - otherOrder > precision + 3 { return rounded(toSignificantDigits: precision) }
    if otherOrder - order > precision + 3 { return other.rounded(toSignificantDigits: precision) }
    return (self + other).rounded(toSignificantDigits: precision)
  }

  public static func * (lhs: BigDecimal, rhs: BigDecimal) -> BigDecimal {
    BigDecimal(lhs.significand * rhs.significand, exponent: lhs.exponent + rhs.exponent)
  }

  public static func += (lhs: inout BigDecimal, rhs: BigDecimal) { lhs = lhs + rhs }
  public static func -= (lhs: inout BigDecimal, rhs: BigDecimal) { lhs = lhs - rhs }
  public static func *= (lhs: inout BigDecimal, rhs: BigDecimal) { lhs = lhs * rhs }

  /// Twice the value, exactly.
  var doubled: BigDecimal { BigDecimal(significand * BigInt(2), exponent: exponent) }

  /// Half the value, exactly (5 × 10^-1 is one half).
  var halved: BigDecimal { BigDecimal(significand * BigInt(5), exponent: exponent - 1) }

  /// The significand rewritten for a smaller or equal exponent: `self == result × 10^exponent`.
  private func alignedSignificand(to exponent: Int) -> BigInt {
    let gap = self.exponent - exponent
    precondition(gap >= 0 && gap <= 100_000_000, "Exponents are too far apart to add exactly")
    return gap == 0 ? significand : significand * BigInt.power10(gap)
  }

  /// `self / divisor` rounded to `precision` significant digits.
  public func divided(
    by divisor: BigDecimal, precision: Int = BigDecimal.defaultPrecision
  ) throws(MathError)
    -> BigDecimal
  {
    precondition(precision >= 1, "Precision must be at least 1")
    guard !divisor.isZero else { throw .divisionByZero }
    if isZero { return self }

    // Scale the numerator so the integer quotient has at least precision + 1 digits.
    let numeratorDigits = significand.decimalDigitCount
    let divisorDigits = divisor.significand.decimalDigitCount
    let shift = max(0, precision + 2 + divisorDigits - numeratorDigits)
    let (quotient, remainder) = (significand.magnitude * BigInt.power10(shift))
      .quotientAndRemainder(dividingBy: divisor.significand.magnitude)
    return Self.roundedQuotient(
      quotient, hasRemainder: !remainder.isZero, exponent: exponent - divisor.exponent - shift,
      negative: isNegative != divisor.isNegative, precision: precision)
  }

  /// Rounds `quotient × 10^exponent`, which was truncated from a larger exact value when `hasRemainder` is true.
  /// A trailing 1 digit stands in for the discarded part so that rounding sees "a little more than this".
  static func roundedQuotient(
    _ quotient: BigInt, hasRemainder: Bool, exponent: Int, negative: Bool, precision: Int
  )
    -> BigDecimal
  {
    var quotient = quotient
    var exponent = exponent
    if hasRemainder {
      quotient = quotient * BigInt(10) + BigInt(1)
      exponent -= 1
    }
    return BigDecimal(negative ? -quotient : quotient, exponent: exponent).rounded(toSignificantDigits: precision)
  }

  /// The principal square root, rounded to `precision` significant digits.
  public func squareRoot(precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    if isNegative { throw .domain }
    if isZero { return self }

    var radicand = significand
    var exponent = exponent
    if exponent & 1 != 0 {
      radicand = radicand * BigInt(10)
      exponent -= 1
    }
    // Pad the radicand with pairs of zeros so that the root has at least precision + 2 digits.
    let pairs = max(0, (2 * (precision + 2) - radicand.decimalDigitCount + 1) / 2)
    radicand = radicand * BigInt.power10(2 * pairs)
    let root = radicand.integerSquareRoot()
    return Self.roundedQuotient(
      root, hasRemainder: root * root != radicand, exponent: exponent / 2 - pairs, negative: false,
      precision: precision)
  }

  /// `self` to an integer power, rounded to `precision` significant digits. `0^0` is a domain error.
  public func power(_ exponent: Int, precision: Int = BigDecimal.defaultPrecision) throws(MathError) -> BigDecimal {
    precondition(precision >= 1, "Precision must be at least 1")
    if isZero {
      if exponent == 0 { throw .domain }
      if exponent < 0 { throw .divisionByZero }
      return self
    }
    if exponent == 0 { return BigDecimal(1) }

    // The result has about |exponent| × |log₁₀ self| digits (1.0000000001^(10¹²) has 22, not 10¹²); refuse what cannot be
    // represented.
    let approximate = magnitude.doubleValue
    let digitsPerFactor =
      approximate.isFinite && approximate > 0
      ? abs(Foundation.log10(approximate)) : Double((decimalOrder ?? 0).magnitude)
    guard digitsPerFactor * Double(exponent.magnitude) < 1_000_000_000 else { throw .overflow }

    // Square and multiply, rounding each step. Every rounding adds at most half a unit of the last digit and there
    // are at most 2 log2(n) of them, so a few guard digits per bit of the exponent are plenty.
    let exponentBits = UInt.bitWidth - exponent.magnitude.leadingZeroBitCount
    let working = precision + 10 + exponentBits
    var result = BigDecimal(1)
    var base = rounded(toSignificantDigits: working)
    var remaining = exponent.magnitude
    while remaining > 0 {
      if remaining & 1 == 1 { result = (result * base).rounded(toSignificantDigits: working) }
      remaining >>= 1
      if remaining > 0 { base = (base * base).rounded(toSignificantDigits: working) }
    }
    return exponent < 0
      ? try BigDecimal(1).divided(by: result, precision: precision)
      : result.rounded(toSignificantDigits: precision)
  }
}

extension BigDecimal: Comparable {
  public static func < (lhs: BigDecimal, rhs: BigDecimal) -> Bool {
    if lhs.signum != rhs.signum { return lhs.signum < rhs.signum }
    guard let lhsOrder = lhs.decimalOrder, let rhsOrder = rhs.decimalOrder else { return false }
    if lhsOrder != rhsOrder { return lhs.isNegative ? lhsOrder > rhsOrder : lhsOrder < rhsOrder }
    let exponent = min(lhs.exponent, rhs.exponent)
    return lhs.alignedSignificand(to: exponent) < rhs.alignedSignificand(to: exponent)
  }
}

extension BigDecimal: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self.init(value) }
}

extension BigDecimal: CustomStringConvertible {
  /// An exact rendering that `BigDecimal(_: String)` reads back: plain digits for moderate sizes and scientific
  /// notation (`1.5e-30`, `1e+25`) for very small or large ones.
  public var description: String {
    if isZero { return "0" }
    let digits = significand.magnitude.description
    let sign = isNegative ? "-" : ""
    let scientificExponent = exponent + digits.count - 1
    if exponent >= 0 && scientificExponent < 21 {
      return sign + digits + String(repeating: "0", count: exponent)
    }
    if exponent < 0 && scientificExponent >= -6 {
      if scientificExponent >= 0 {
        let split = digits.index(digits.startIndex, offsetBy: digits.count + exponent)
        return sign + String(digits[..<split]) + "." + String(digits[split...])
      }
      return sign + "0." + String(repeating: "0", count: -scientificExponent - 1) + digits
    }
    let mantissa = digits.count == 1 ? digits : String(digits.prefix(1)) + "." + String(digits.dropFirst())
    return sign + mantissa + "e" + (scientificExponent >= 0 ? "+" : "-") + String(scientificExponent.magnitude)
  }
}
