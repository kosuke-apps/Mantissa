# Engine design

The goal is a result a scientific calculator would be proud of: exact when the answer is exact, otherwise correct to
at least 12 digits, and never a floating-point artefact such as `sin(π) = 1.2e-16` or `0.1 + 0.2 = 0.30000000000000004`.

## Layers

Each layer depends only on the ones before it in this list.

1. **Integers and fractions** (`BigInt`, `Rational`). Exact. Every number the user types is a `Rational` (a decimal
   literal is parsed exactly, so `0.1 + 0.2` is exactly `0.3`).
2. **Arbitrary-precision decimals** (`BigDecimal`, `FixedPoint`; done). `significand × 10^exponent`. `+ - ×` are exact;
   division, roots and every function take a `precision` (significant digits, default 50), compute with 15 guard
   digits and round half away from zero once at the end. Used to evaluate anything that is not rational: `π`, `e`,
   `sqrt`, `exp`, `ln`, `log`, `power`, `sin`, `cos`, `tan`, `atan`, `asin`, `acos` and the six hyperbolic functions.
   The display rounds further to the digits the user asked for (default 12 significant). See "Numerics" below.
3. **Expressions** (planned). A tree of rationals, symbols (`x`, `y`, …), constants (`π`, `e`, `i`), sums, products,
   powers and function calls, kept in a canonical form: flattened, like terms collected, rational coefficients
   gathered, radicals reduced (`√12 → 2√3`), exact trigonometric values at the usual angles (`sin(π/6) → 1/2`).
   Exact results come from here; the decimal layer only supplies the approximation shown next to them.
4. **Parser** (planned). Text to expression, with implicit multiplication (`2x`, `3π`, `2(x+1)`), functions,
   factorial, percent, `nPr`, `nCr`, and `=`, `<`, `≤`, … for equations and inequalities. The maths editor in the app
   produces the same structure, so history stores one canonical text form.
5. **Solver** (planned). Linear, quadratic and higher polynomial equations (rational roots, factoring, Cardano and
   Ferrari only when the result stays readable), systems of linear equations, one-variable inequalities by sign
   analysis, then derivatives, integrals, limits and sums. Where an answer cannot be found reliably the engine says so;
   it never returns a guess presented as exact.
6. **Plotting** (planned). The only place `Double` is used. An expression is compiled into a closure over `Double`,
   sampled adaptively to catch asymptotes and jumps. Roots, intersections and extremes are then refined with the exact
   layers or high-precision decimals, so the points marked on a graph match the numbers shown in results.

## Decisions

- **No dependencies.** `BigInt` is about 350 lines and is checked against an independent oracle, so the package stays
  self-contained and the app has nothing to audit or update. Candidates that were considered: `attaswift/BigInt`
  (fine, but one more dependency for a small job), SymEngine (C++ and a bridge, heavy), Giac and Maxima (GPL, which
  rules out distribution).
- **Truncating division** in `BigInt` follows `Int` (quotient toward zero, remainder takes the dividend's sign), so
  the type behaves as Swift programmers expect. Floor division and modulo are added where the maths needs them.
- **Division by zero traps in the number types**, as it does for `Int`. The layers above check first and turn it into a
  mathematical error the user sees.
- **Tests compare with Python**, not with the Swift code itself. `tools/gen_number_vectors.py` writes reference
  vectors with a fixed seed. Operands are chosen near limb boundaries and include the dividends that force the rare
  "add back" step of Knuth's Algorithm D; that branch was confirmed to run by trapping on it once.
- **Swift 6 language mode**, value types, `Sendable` throughout, so the engine can run off the main thread (solving
  and plotting must never block the keyboard).

## Numerics (BigDecimal)

How the functions reach their accuracy, so that a change does not quietly lose it.

- **Fixed-point inside, decimal outside.** Each function builds a `FixedPoint(digits: precision + 15 + extra)`, does
  its series with `BigInt` arithmetic (every step truncates, so each is off by under one unit in the last place) and
  converts once. The 15 guard digits absorb the accumulated error; `extra` handles cancellation (below).
- **Constants** come from series, not tables: π by Machin (`16 atan(1/5) − 4 atan(1/239)`), ln 2 = 2 atanh(1/3),
  ln 10 = 6 atanh(1/3) + 2 atanh(1/9), e from the exponential series. They are recomputed on every call: the test
  suite makes about 1,400 function evaluations at up to 100 digits in a few seconds in a Debug build, and π and e
  to a thousand digits take 0.8 s together, so there is no cache to keep consistent.
- **exp**: x = k ln 10 + r with 0 ≤ r < ln 10, then e^r by Taylor after halving r ten times and squaring ten times;
  the answer is `10^k × e^r`, so the decimal exponent costs nothing.
- **ln**: x = 10^d × y × 2^-j with y in [0.8, 1.6), then 2 atanh((y−1)/(y+1)) − j ln 2 + d ln 10. Numbers in [0.1, 10)
  skip the power of ten so that values near 1 are not computed as `ln(0.1…) + ln 10`, a difference of equals.
- **sin and cos**: reduce modulo π/2 with π carried to `order(x)` extra digits, Taylor on |r| ≤ π/4, rotate by the
  quadrant. **atan**: use `π/2 − atan(1/a)` above 1, halve the argument four times, Taylor. asin and acos go through
  atan with `1 − x²` formed exactly, so there is no cancellation near ±1. The hyperbolic functions use `exp` and `ln`.
- **Cancellation is handled by adding digits where the answer is small**, not by hoping: near multiples of π/2 the
  reduced angle `r` must keep `precision + 10` significant digits or the working precision is raised and the
  reduction repeated; `ln` near 1 adds as many digits as `x − 1` has leading zeros; `sinh`, `tanh`, `asinh` and
  `atanh` near 0 do the same. The tests include arguments chosen to hit each of these (`ln(1 + 1e-20)`,
  `sin(355)`, `sin(π₃₆)`, `tan(π/2 rounded)`, `acosh(1 + 1e-33)`). The guard digits, the `ln` near-1 handling and the
  sine/cosine reduction were each shown to make the tests fail when removed; the near-0 handling of the hyperbolic
  functions is covered by the vectors but was not mutation-tested.
- **Absurd arguments stay cheap.** Below `10^-(precision/2 + 1)` the odd functions equal x to the digits asked for, so
  they return it; `exp` rejects |x| ≥ 10^9 and trigonometric functions reject |x| ≥ 10^1000 with
  `MathError.overflow`; large `tanh` is ±1. Exact addition of numbers with exponents that differ by millions of digits
  would build enormous integers, so the functions never do it (`BigDecimal.+` traps beyond a 10^8-digit gap).
- **Verification** is against Python's `decimal` at 300 digits (`tools/gen_decimal_vectors.py`), 472 function values
  compared at 15, 50 and 100 digits. The test demands the *same last digit*, not a tolerance, which holds because the
  guard digits make a misrounding need the true value to sit within about 10^-15 of a rounding boundary.
