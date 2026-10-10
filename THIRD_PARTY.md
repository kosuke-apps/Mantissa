# Third-party material

Mantissa's own code is under the MIT licence (`LICENSE`, Copyright (c) 2026 Kosuke Satake).

## Shipped in the app

Nothing yet. The calculation engine (`Sources/MantissaCore`) is written from scratch against textbook algorithms
(Knuth's Algorithm D for long division, Machin's formula for π, Taylor and atanh series) and uses no library other
than Swift's standard library. It depends on no package. Apple's own frameworks that the app will use (SwiftUI) are
part of the system and need no entry.

## Used to build and test, not shipped

| What | Where | Licence |
|---|---|---|
| Python 3 standard library (`int`, `fractions`, `decimal`, `math`) | `tools/gen_number_vectors.py`, `tools/gen_decimal_vectors.py` produce the reference values in `Tests/MantissaCoreTests/Resources/` | PSF License; only the numbers it computes are stored, no Python code is copied |
| Swift Testing | the test target | Part of the Swift toolchain (Apache License 2.0 with Runtime Library Exception) |
