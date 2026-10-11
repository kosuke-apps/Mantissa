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
3. **Expressions** (`Expr`, `NumberTheory`; done, see "Expressions" below). A tree of rationals, symbols (`x`, `y`, …),
   the constants `π` and `e`, sums, products, powers and function calls, kept in a canonical form: flattened, like
   terms collected, rational coefficients gathered, radicals reduced (`√12 → 2√3`), exact trigonometric values at
   multiples of 15° (`sin(π/6) → 1/2`). Exact results come from here; the decimal layer only supplies the
   approximation shown next to them.
4. **Parser** (`Lexer`, `Parser`, `Syntax`, `Builder`, `Calculator`; done). Text to syntax tree to `Expr`, with
   implicit multiplication (`2x`, `3π`, `2(x+1)`), functions with or without parentheses, factorial, percent, degrees,
   and `=`, `<`, `≤`, … for equations and inequalities (parsed, not yet solved). The maths editor in the app will
   produce the same structure, so history stores one text form, `Expr.description`, which the parser reads back.
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

## Expressions

- **Canonical form is the equality test.** Every combination goes through `makeSum`, `makeProduct`, `makePower` and
  `Expr.apply`, so equal expressions are `==`. The rules are listed on `Expr`: like terms collected, equal bases merged,
  a number multiplies through a sum, radicals split into an integer part and prime radicals `p^f` with 0 < f < 1
  (so `1/√2` is `(1/2)·2^(1/2)`, and `√2 + √8` is `3√2` because both are multiples of the same atom).
- **Canonical forms are sufficient, not necessary, for equality.** Two equal expressions can still have different
  forms: `(x+1)^2` and `x^2 + 2x + 1` are not merged, because unwanted expansion is as bad as missing expansion.
  `expand`, `factor` and `simplify` will be explicit operations in the solver layer. What is expanded automatically:
  products and whole-number powers of sums of plain numbers and radicals (`(1+√2)(1−√2)` is `−1`), because they are
  numbers and the user expects a number back. Sums with unknowns are left as written.
- **Denominators are rationalised** for a two-term sum of square roots and rationals: `1/(1+√2)` is `√2 − 1`. Longer
  sums (`1/(1+√2+√3)`) are left as they are.
- **The numeric content of a sum is taken out of powers**: `(2x+2)^2` is `4(x+1)^2` and `1/(2x+2)` is
  `(1/2)(x+1)^-1`. Without that, `1/(2(x+1))` and `1/(2x+2)` would be different expressions, and an expression would
  not read back as itself.
- **Roots of negative numbers**: an odd root is real (`(−8)^(1/3)` is `−2`); an even root stays as written
  (`√(-4)`) and has no decimal value (`MathError.domain`). The imaginary unit comes with the equation solver, which
  needs it for quadratics; `i` is an ordinary variable until then.
- **Safe powers only**: `(x²)^(1/2)` is not `x` (it is `|x|`), so powers of powers are combined only for whole
  exponents or positive bases. `x/x` is 1, as in every computer algebra system, and `0^0` is an error.
- **Size limits**: exact integer results above about 21 000 digits (70 000 bits) are kept as written (`2^100000`) and
  only approximated; factorials and counts beyond that are `MathError.overflow`. Factoring is by trial division
  (completely below 10^12, up to 50 000 for larger numbers); a number with a larger prime factor is split as far as
  possible and the rest is treated as one opaque factor.
- **Angles**: functions work in radians, and radians are the default, as in the app this one follows (`cos(30)` is
  radians, `cos(30°)` is degrees). `°` after a number means that many degrees in whatever unit the calculator works
  in, so `sin(30°)` is `1/2` in both. In degree mode (a setting) the `Builder` converts: `sin(30)` becomes
  `sin(30π/180)`, which the exact table turns into `1/2`, and an argument that *writes* π (`sin(π/6)`) is already
  radians. Exact values exist at multiples of 15°; other angles stay as `sin(π/180)` with a decimal value beside them.
- **Approximation** evaluates the exact tree with 15 guard digits. Where an error is magnified it adds digits: the
  trigonometric and hyperbolic functions and powers get extra digits for large arguments (`cos(2·10^37)`), and a sum
  far below its largest term is treated as zero (`sin²1° + cos²1° − 1`).

### How it was checked

`NaiveEvaluator` (test target) computes the value of a parsed expression directly with `BigDecimal`: no radical
rules, no collected terms, no exact trigonometric tables, and 120 digits. A seeded generator builds random syntax trees
(numbers, π, e, the operators, roots, trigonometric, logarithmic and hyperbolic functions; both angle units) and the
test requires, for each one the naive evaluator can compute: the canonical form's value agrees to 30 digits; rebuilding
the canonical form from its parts changes nothing; and printing it and reading it back gives the same expression.
`MANTISSA_SEED` and `MANTISSA_SAMPLES` widen the search (`MANTISSA_TRACE=1` prints each case, so the last line names
a crashing input). It found: two infinite recursions (splitting `e^(π−1/8)` and squaring a sum each re-merged what
was just split), `cos` of a 38-digit angle wrong from the 16th digit, and three ways in which one expression had two
forms. It also showed that the evaluator itself needed 120 digits to be a fair judge.

## The editor and the typesetter

- **One tree for input and output.** A formula is a sequence of `MathNode`s; a structure (fraction, radical, exponent,
  parentheses, function, bars) holds slots, each a sequence. The editor edits that tree and the typesetter turns an
  `Expr` into it, so the app draws both with the same view.
- **Cursor = a path.** `MathCursor` is a line, a list of (node index, slot) steps, and an offset. Right and left move
  through every slot in reading order (numerator, denominator, out the end); the tests walk right from the start and left
  from the end of random documents and require the same positions in reverse order and no position twice.
- **Keys follow the old app's keyboard.** The fraction key takes the operand before the cursor (a number with its decimal
  point, a variable or constant, or a whole structure, each with any exponent, factorial, percent or degree it carries)
  as the numerator and puts the cursor in the denominator; with nothing there it starts in an empty numerator. A closing
  parenthesis steps out of the group, function or bars the cursor is in. Backspace removes a symbol, enters a filled
  structure from its end, removes an empty one, and at the start of a slot steps back (removing the structure only when
  all of it is empty).
- **The text written for the parser is exact, not pretty.** A fraction is `((n)/(d))`, an exponent `^(e)`, a root
  `√(r)` or `root(r,n)`; letters typed one by one are joined with `*` so that s, i, n are three variables and "a" before a
  `sin` key is `a*sin(…)`, not `asin`. An empty slot gives empty parentheses, which the parser rejects, so an unfinished
  formula is reported as unfinished instead of guessed.
- **Checked by reading back.** Typeset text of random expressions (40 000 across seeds) parses back to the same
  expression. That found a defect in the shared-radical rule (`√(−7)` lost its sign); it is fixed in both the text
  rendering and the typesetter.
