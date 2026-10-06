/// Why a calculation has no result. The layers above turn these into messages the user sees.
public enum MathError: Error, Equatable, Sendable {
  /// A division by zero, such as `1 / 0` or `0^(-1)`.
  case divisionByZero
  /// An argument outside the function's domain, such as `ln(-1)`, `√(-1)` or `asin(2)`.
  case domain
  /// An argument or result beyond what the engine represents, such as `exp(1e12)`.
  case overflow
}
