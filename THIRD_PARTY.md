# Third-party material

Mantissa's own code is under the MIT licence (`LICENSE`, Copyright (c) 2026 Kosuke Satake).

## Shipped in the app

Nothing yet. The calculation engine (`Sources/MantissaCore`) is written from scratch against textbook algorithms
(Knuth's Algorithm D for long division, Machin's formula for π, Taylor and atanh series) and uses no library other
than Swift's standard library. The statistics and special functions (`Sources/MantissaCore/Statistics`, `SpecialFunctions*.swift`, `SpecialDouble.swift`)
are written from the mathematics, with the formulas from the literature and no code from it: Stirling's series for ln Γ, the series and continued fractions
for the error function and the incomplete gamma and beta functions (Digital Library of Mathematical Functions, chapters 5, 7 and 8), Lentz's method for
continued fractions, and Newton's method. Quartiles are the median of the halves; the other conventions are named in `docs/statistics.md`. It depends on no package. Apple's own frameworks that the app will use (SwiftUI) are
part of the system and need no entry.

## Used to build and test, not shipped

| What | Where | Licence |
|---|---|---|
| Python 3 standard library (`int`, `fractions`, `decimal`, `math`) | `tools/gen_number_vectors.py`, `tools/gen_decimal_vectors.py` produce the reference values in `Tests/MantissaCoreTests/Resources/` | PSF License; only the numbers it computes are stored, no Python code is copied |
| Python 3 standard library (`fractions`, `decimal`, `math`, `statistics`) | `tools/gen_statistics_vectors.py` produces `Tests/MantissaCoreTests/Resources/statistics-vectors.json`, written with algorithms independent of the Swift ones (Spouge's approximation of Γ, termwise series of the incomplete functions, Abramowitz and Stegun 26.7.3 and 26.7.4 for the t distribution with whole degrees of freedom) | PSF License; only the numbers it computes are stored, no Python code is copied |
| Swift Testing | the test target | Part of the Swift toolchain (Apache License 2.0 with Runtime Library Exception) |
