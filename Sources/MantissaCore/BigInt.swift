/// An arbitrary-precision signed integer.
///
/// The value is stored as sign and magnitude. `limbs` holds the magnitude in 32-bit digits, least significant first,
/// with no zero digit at the most significant end, so zero is the empty array. Zero is never negative.
///
/// Multiplication is the schoolbook method and division is Knuth's Algorithm D. Both are fast enough for the numbers
/// a calculator meets (a few hundred digits) and stay easy to check.
public struct BigInt: Sendable, Hashable {
  private(set) var limbs: [UInt32]
  public private(set) var isNegative: Bool

  public init() {
    limbs = []
    isNegative = false
  }

  public init(_ value: Int) {
    let magnitude = value.magnitude
    self.init(
      limbs: [UInt32(truncatingIfNeeded: magnitude), UInt32(truncatingIfNeeded: magnitude >> 32)],
      isNegative: value < 0
    )
  }

  /// Parses an optionally signed run of decimal digits. Returns `nil` for anything else, including the empty string.
  public init?(_ text: String) {
    var digits = Substring(text)
    var negative = false
    if let sign = digits.first, sign == "-" || sign == "+" {
      negative = sign == "-"
      digits = digits.dropFirst()
    }
    guard !digits.isEmpty, digits.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }

    var limbs: [UInt32] = []
    // Nine decimal digits fit in a 32-bit limb with room to spare, so feed them in nine at a time.
    var index = digits.startIndex
    while index < digits.endIndex {
      let end = digits.index(index, offsetBy: 9, limitedBy: digits.endIndex) ?? digits.endIndex
      let chunk = digits[index..<end]
      var scale: UInt32 = 1
      for _ in 0..<chunk.count { scale *= 10 }
      Self.multiplyAdd(&limbs, by: scale, adding: UInt32(chunk)!)
      index = end
    }
    self.init(limbs: limbs, isNegative: negative)
  }

  init(limbs: [UInt32], isNegative: Bool) {
    var limbs = limbs
    Self.trim(&limbs)
    self.limbs = limbs
    self.isNegative = isNegative && !limbs.isEmpty
  }

  public var isZero: Bool { limbs.isEmpty }
  public var isEven: Bool { limbs.first.map { $0 & 1 == 0 } ?? true }
  public var isOne: Bool { limbs == [1] && !isNegative }

  /// -1, 0 or 1.
  public var signum: Int { isZero ? 0 : (isNegative ? -1 : 1) }

  /// The number of bits needed for the magnitude; 0 for zero.
  public var bitWidth: Int {
    guard let top = limbs.last else { return 0 }
    return limbs.count * 32 - top.leadingZeroBitCount
  }

  public var magnitude: BigInt { BigInt(limbs: limbs, isNegative: false) }

  /// The value as an `Int`, or `nil` when it does not fit.
  public var asInt: Int? {
    guard limbs.count <= 2 else { return nil }
    var magnitude: UInt = 0
    for (index, limb) in limbs.enumerated() { magnitude |= UInt(limb) << (32 * index) }
    if isNegative {
      return magnitude <= UInt(Int.max) + 1 ? Int(truncatingIfNeeded: 0 &- magnitude) : nil
    }
    return magnitude <= UInt(Int.max) ? Int(magnitude) : nil
  }

  /// `self` to the power `exponent`, which must not be negative.
  public func power(_ exponent: Int) -> BigInt {
    precondition(exponent >= 0, "BigInt.power needs a non-negative exponent")
    var result = BigInt(1)
    var base = self
    var remaining = exponent
    while remaining > 0 {
      if remaining & 1 == 1 { result *= base }
      remaining >>= 1
      if remaining > 0 { base *= base }
    }
    return result
  }

  /// The greatest common divisor, never negative. `gcd(0, 0)` is 0.
  public static func gcd(_ a: BigInt, _ b: BigInt) -> BigInt {
    var x = a.magnitude
    var y = b.magnitude
    while !y.isZero { (x, y) = (y, x % y) }
    return x
  }

  /// Quotient and remainder, truncating toward zero like `Int`: the remainder has the sign of the dividend.
  public func quotientAndRemainder(dividingBy divisor: BigInt) -> (quotient: BigInt, remainder: BigInt) {
    precondition(!divisor.isZero, "Division by zero")
    let (quotient, remainder) = Self.divide(limbs, by: divisor.limbs)
    return (
      BigInt(limbs: quotient, isNegative: isNegative != divisor.isNegative),
      BigInt(limbs: remainder, isNegative: isNegative)
    )
  }

  // MARK: Operators

  public static prefix func - (value: BigInt) -> BigInt {
    BigInt(limbs: value.limbs, isNegative: !value.isNegative)
  }

  public static func + (lhs: BigInt, rhs: BigInt) -> BigInt {
    if lhs.isNegative == rhs.isNegative {
      return BigInt(limbs: add(lhs.limbs, rhs.limbs), isNegative: lhs.isNegative)
    }
    switch compare(lhs.limbs, rhs.limbs) {
    case 0: return BigInt()
    case 1: return BigInt(limbs: subtract(lhs.limbs, rhs.limbs), isNegative: lhs.isNegative)
    default: return BigInt(limbs: subtract(rhs.limbs, lhs.limbs), isNegative: rhs.isNegative)
    }
  }

  public static func - (lhs: BigInt, rhs: BigInt) -> BigInt { lhs + (-rhs) }

  public static func * (lhs: BigInt, rhs: BigInt) -> BigInt {
    BigInt(limbs: multiply(lhs.limbs, rhs.limbs), isNegative: lhs.isNegative != rhs.isNegative)
  }

  public static func / (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.quotientAndRemainder(dividingBy: rhs).quotient }
  public static func % (lhs: BigInt, rhs: BigInt) -> BigInt { lhs.quotientAndRemainder(dividingBy: rhs).remainder }

  public static func += (lhs: inout BigInt, rhs: BigInt) { lhs = lhs + rhs }
  public static func -= (lhs: inout BigInt, rhs: BigInt) { lhs = lhs - rhs }
  public static func *= (lhs: inout BigInt, rhs: BigInt) { lhs = lhs * rhs }

  // MARK: Magnitude arithmetic (little-endian 32-bit limbs)

  private static func trim(_ limbs: inout [UInt32]) {
    while limbs.last == 0 { limbs.removeLast() }
  }

  /// -1, 0 or 1 as `a` is smaller than, equal to or larger than `b`. Both must be trimmed.
  private static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
    if a.count != b.count { return a.count < b.count ? -1 : 1 }
    for index in stride(from: a.count - 1, through: 0, by: -1) where a[index] != b[index] {
      return a[index] < b[index] ? -1 : 1
    }
    return 0
  }

  private static func add(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    let (long, short) = a.count >= b.count ? (a, b) : (b, a)
    var result: [UInt32] = []
    result.reserveCapacity(long.count + 1)
    var carry: UInt64 = 0
    for index in 0..<long.count {
      let sum = UInt64(long[index]) + (index < short.count ? UInt64(short[index]) : 0) + carry
      result.append(UInt32(truncatingIfNeeded: sum))
      carry = sum >> 32
    }
    if carry != 0 { result.append(UInt32(carry)) }
    return result
  }

  /// `a - b`, where `a >= b`.
  private static func subtract(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    var result: [UInt32] = []
    result.reserveCapacity(a.count)
    var borrow: Int64 = 0
    for index in 0..<a.count {
      var difference = Int64(a[index]) - (index < b.count ? Int64(b[index]) : 0) - borrow
      if difference < 0 {
        difference += 1 << 32
        borrow = 1
      } else {
        borrow = 0
      }
      result.append(UInt32(difference))
    }
    trim(&result)
    return result
  }

  private static func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
    if a.isEmpty || b.isEmpty { return [] }
    var result = [UInt32](repeating: 0, count: a.count + b.count)
    for i in 0..<a.count {
      let factor = UInt64(a[i])
      if factor == 0 { continue }
      var carry: UInt64 = 0
      for j in 0..<b.count {
        // At most (2^32-1)^2 + 2(2^32-1) = 2^64-1, so this cannot overflow.
        let product = factor * UInt64(b[j]) + UInt64(result[i + j]) + carry
        result[i + j] = UInt32(truncatingIfNeeded: product)
        carry = product >> 32
      }
      result[i + b.count] = UInt32(carry)
    }
    trim(&result)
    return result
  }

  /// `limbs = limbs * factor + addend`, in place.
  private static func multiplyAdd(_ limbs: inout [UInt32], by factor: UInt32, adding addend: UInt32) {
    var carry = UInt64(addend)
    for index in 0..<limbs.count {
      let value = UInt64(limbs[index]) * UInt64(factor) + carry
      limbs[index] = UInt32(truncatingIfNeeded: value)
      carry = value >> 32
    }
    if carry != 0 { limbs.append(UInt32(carry)) }
  }

  /// Divides `limbs` by a one-limb divisor in place and returns the remainder.
  private static func divideInPlace(_ limbs: inout [UInt32], by divisor: UInt32) -> UInt32 {
    var remainder: UInt64 = 0
    for index in stride(from: limbs.count - 1, through: 0, by: -1) {
      let current = (remainder << 32) | UInt64(limbs[index])
      limbs[index] = UInt32(current / UInt64(divisor))
      remainder = current % UInt64(divisor)
    }
    trim(&limbs)
    return UInt32(remainder)
  }

  private static func shiftLeft(_ limbs: [UInt32], by bits: Int) -> [UInt32] {
    precondition(bits >= 0 && bits < 32)
    if bits == 0 { return limbs }
    var result: [UInt32] = []
    result.reserveCapacity(limbs.count + 1)
    var carry: UInt32 = 0
    for limb in limbs {
      result.append((limb << UInt32(bits)) | carry)
      carry = limb >> UInt32(32 - bits)
    }
    if carry != 0 { result.append(carry) }
    return result
  }

  private static func shiftRight(_ limbs: [UInt32], by bits: Int) -> [UInt32] {
    precondition(bits >= 0 && bits < 32)
    if bits == 0 { return limbs }
    var result = limbs
    for index in 0..<result.count {
      let high = index + 1 < result.count ? result[index + 1] << UInt32(32 - bits) : 0
      result[index] = (result[index] >> UInt32(bits)) | high
    }
    trim(&result)
    return result
  }

  /// Knuth, The Art of Computer Programming vol. 2, section 4.3.1, Algorithm D. `divisor` must not be zero.
  private static func divide(_ dividend: [UInt32], by divisor: [UInt32]) -> (quotient: [UInt32], remainder: [UInt32]) {
    if compare(dividend, divisor) < 0 { return ([], dividend) }
    if divisor.count == 1 {
      var quotient = dividend
      let remainder = divideInPlace(&quotient, by: divisor[0])
      return (quotient, remainder == 0 ? [] : [remainder])
    }

    // Normalise so that the top bit of the divisor's leading limb is set; this keeps the estimate of each quotient
    // digit within 2 of the true digit.
    let shift = divisor[divisor.count - 1].leadingZeroBitCount
    let v = shiftLeft(divisor, by: shift)
    var u = shiftLeft(dividend, by: shift)
    if u.count == dividend.count { u.append(0) }

    let n = v.count
    let m = dividend.count - n
    let base: UInt64 = 1 << 32
    var quotient = [UInt32](repeating: 0, count: m + 1)

    for j in stride(from: m, through: 0, by: -1) {
      let numerator = (UInt64(u[j + n]) << 32) | UInt64(u[j + n - 1])
      var estimate = numerator / UInt64(v[n - 1])
      var remainder = numerator % UInt64(v[n - 1])
      // `||` short-circuits, so the product below is only formed once estimate < 2^32 and cannot overflow.
      while estimate >= base || estimate * UInt64(v[n - 2]) > ((remainder << 32) | UInt64(u[j + n - 2])) {
        estimate -= 1
        remainder += UInt64(v[n - 1])
        if remainder >= base { break }
      }

      // Multiply and subtract: u[j...j+n] -= estimate * v.
      var borrow: Int64 = 0
      for i in 0..<n {
        let product = estimate * UInt64(v[i])
        let difference = Int64(u[i + j]) - borrow - Int64(product & 0xFFFF_FFFF)
        u[i + j] = UInt32(truncatingIfNeeded: difference)
        borrow = Int64(product >> 32) - (difference >> 32)
      }
      let top = Int64(u[j + n]) - borrow
      u[j + n] = UInt32(truncatingIfNeeded: top)

      if top < 0 {
        // The estimate was one too large (rare): add the divisor back.
        estimate -= 1
        var carry: UInt64 = 0
        for i in 0..<n {
          let sum = UInt64(u[i + j]) + UInt64(v[i]) + carry
          u[i + j] = UInt32(truncatingIfNeeded: sum)
          carry = sum >> 32
        }
        u[j + n] = UInt32(truncatingIfNeeded: UInt64(u[j + n]) + carry)
      }
      quotient[j] = UInt32(truncatingIfNeeded: estimate)
    }

    trim(&quotient)
    var remainderLimbs = Array(u[0..<n])
    trim(&remainderLimbs)
    return (quotient, shiftRight(remainderLimbs, by: shift))
  }
}

extension BigInt: Comparable {
  public static func < (lhs: BigInt, rhs: BigInt) -> Bool {
    if lhs.isNegative != rhs.isNegative { return lhs.isNegative }
    let order = compare(lhs.limbs, rhs.limbs)
    return lhs.isNegative ? order > 0 : order < 0
  }
}

extension BigInt: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self.init(value) }
}

extension BigInt: CustomStringConvertible {
  public var description: String {
    if isZero { return "0" }
    var rest = limbs
    var chunks: [UInt32] = []
    while !rest.isEmpty { chunks.append(Self.divideInPlace(&rest, by: 1_000_000_000)) }
    var text = isNegative ? "-" : ""
    text += String(chunks[chunks.count - 1])
    for chunk in chunks.dropLast().reversed() {
      let digits = String(chunk)
      text += String(repeating: "0", count: 9 - digits.count) + digits
    }
    return text
  }
}
