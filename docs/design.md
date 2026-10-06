# Engine design

The goal is a result a scientific calculator would be proud of: exact when the answer is exact, otherwise correct to
at least 12 digits, and never a floating-point artefact such as `sin(π) = 1.2e-16` or `0.1 + 0.2 = 0.30000000000000004`.

## Layers

Each layer depends only on the ones before it in this list.

1. **Integers and fractions** (`BigInt`, `Rational`). Exact. Every number the user types is a `Rational` (a decimal
   literal is parsed exactly, so `0.1 + 0.2` is exactly `0.3`).
2. **Arbitrary-precision decimals** (planned). A fixed working precision of about 50 digits with guard digits, used to
   evaluate anything that is not rational: `π`, `e`, `sqrt`, `exp`, `ln`, `sin`, `cos`, `atan`. The display rounds to
   the digits the user asked for (default 12 significant). Reference values come from Python's `decimal` module.
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
