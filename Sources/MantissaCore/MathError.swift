/// Why a calculation has no result. The layers above turn these into messages the user sees.
public enum MathError: Error, Equatable, Sendable {
  /// A division by zero, such as `1 / 0` or `0^(-1)`.
  case divisionByZero
  /// An argument outside the function's domain, such as `ln(-1)`, `√(-1)` or `asin(2)`.
  case domain
  /// An argument or result beyond what the engine represents, such as `exp(1e12)`.
  case overflow
  /// A value was asked of an expression that still contains an unknown (a symbol with no value given).
  case notNumeric
  /// An expression with no value, though no argument is outside a domain: `tan(π/2)`, `ln(0)`, `0^0`.
  case noValue
  /// A calculation this version cannot do, such as an integral it finds no antiderivative for.
  case unsupported
  /// A limit whose two sides disagree or that oscillates, an integral or a series that does not converge: there is no value.
  case undefined
}
