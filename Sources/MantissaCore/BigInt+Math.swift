extension BigInt {
  /// `10` to the power `exponent`, which must not be negative.
  public static func power10(_ exponent: Int) -> BigInt { BigInt(10).power(exponent) }

  /// The number of decimal digits in the magnitude; 1 for zero.
  public var decimalDigitCount: Int {
    if isZero { return 1 }
    // 2^(b-1) <= magnitude < 2^b, so the digit count is one of two neighbours of b * log10(2). Start from the
    // estimate and correct it in both directions so that rounding in the Double product can never matter.
    var digits = Int(Double(bitWidth - 1) * 0.301_029_995_663_981_2) + 1
    let value = magnitude
    while digits > 1 && value < BigInt.power10(digits - 1) { digits -= 1 }
    while value >= BigInt.power10(digits) { digits += 1 }
    return digits
  }

  /// The largest integer whose square is at most `self`, which must not be negative.
  public func integerSquareRoot() -> BigInt {
    precondition(!isNegative, "The square root of a negative number is not an integer")
    if isZero { return self }
    // Newton's method from above: 2^ceil(bitWidth/2) is at least the root, and the iterates then decrease to
    // floor(sqrt(self)). The first iterate that fails to decrease is the answer.
    var guess = BigInt(2).power((bitWidth + 1) / 2)
    while true {
      let next = (guess + self / guess) / BigInt(2)
      if next >= guess { return guess }
      guess = next
    }
  }

  /// The quotient rounded toward negative infinity (unlike `/`, which truncates toward zero).
  public func floorDivided(by divisor: BigInt) -> BigInt {
    let (quotient, remainder) = quotientAndRemainder(dividingBy: divisor)
    if !remainder.isZero && remainder.isNegative != divisor.isNegative { return quotient - BigInt(1) }
    return quotient
  }
}
