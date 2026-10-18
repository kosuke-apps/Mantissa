import Foundation

@testable import MantissaCore

/// Loads a JSON file written by `tools/gen_number_vectors.py`.
func loadVectors<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
  guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Resources/\(name).json"])
  }
  return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
}

/// `MANTISSA_SEED=n` changes the random sequences of the property tests that read it, for wider searches than the fixed seeds
/// that run in every build.
let propertySeedOffset = UInt64(ProcessInfo.processInfo.environment["MANTISSA_SEED"] ?? "") ?? 0

/// A small deterministic generator, so a failing random test fails the same way every time.
struct SplitMix64: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

extension BigInt {
  /// A random non-negative number built from `limbCount` 32-bit limbs, biased toward all-ones and all-zeros limbs
  /// because those provoke the rare paths of long division.
  static func random(limbCount: Int, using generator: inout SplitMix64) -> BigInt {
    var value = BigInt(0)
    let base = BigInt(1) * BigInt(4_294_967_296)
    for _ in 0..<limbCount {
      let limb: UInt32
      switch generator.next() % 5 {
      case 0: limb = 0
      case 1: limb = 0xFFFF_FFFF
      case 2: limb = 0x8000_0000
      default: limb = UInt32(truncatingIfNeeded: generator.next())
      }
      value = value * base + BigInt(Int(limb))
    }
    return value
  }
}
