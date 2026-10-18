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
- **Complex numbers.** `i` is a constant of `Expr` (`MathConstant.i`) and the letter `i` always means it. A power of `i`
  is reduced to 1, `i`, −1 or −`i`, so `i·i` is `−1` through the same merging of equal bases as `x·x`. Sums with `i` in
  them are multiplied out like sums of radicals, and a division by `a + bi` is made real by the conjugate, whatever `a`
  and `b` are (`1/(1+√2+i)`). `|a + bi|` is `√(a² + b²)`.
- **Roots of negative numbers**: an odd root is real (`(−8)^(1/3)` is `−2`); an even root is the principal value
  `a^(p/q)·e^(iπp/q)`, exact whenever `q` divides 12 (`√(−4)` is `2i`, `(−4)^(1/4)` is `1 + i`), and stays as written
  otherwise. `e^(ciπ)` is exact at multiples of π/12 (Euler's formula) and so are the roots of `i` itself.
- **Complex decimals** (`ComplexDecimal`, `Expr.complexApproximation`): a real value is computed exactly as before; a
  value that is not real comes back as a pair of decimals (principal values; `ln`, `sin`, `cos`, `sinh`, `cosh`,
  `tan`, `tanh`, `abs`, any power). `Evaluation` carries it as `complexApproximation`; when the imaginary part comes
  out zero the value is reported as the real number it is (`i^i`, `e^(iπ)+1`). The inverse trigonometric functions of a
  complex argument are not supported.
- **How it was checked**: 9 000 random expressions in `i`, square roots of negative numbers, sums, products,
  quotients and small powers agree with a separate complex evaluator that does no simplification, and the complex
  functions agree with Python's `cmath` to 12 digits.
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

## Graphs

- **`Double` is allowed here and nowhere else.** `DoubleCompiler` turns the exact expression into a closure. Undefined stays
  undefined: `ln` of a non-positive number and any infinite power are `NaN`, so a pole is a gap, not a number that later turns
  `1/(1/0)` into 0. Tests compare the closure with the exact evaluation on random expressions in x (24 000 expressions at
  7 points across seeds).
- **What is drawn**: an expression whose only unknown is x, a line `y = …` in x, or several such lines. An equation to solve
  (`x² − 4 = 0`) is not a graph, and a line with another letter is not either.
- **Points are found by sampling, then refined.** A sign change between samples is bisected to a root; a turn of the slope
  (skipping flat steps, which two samples either side of a peak produce) is refined by golden-section search; the crossings of
  two curves are the roots of their difference. A pole also changes sign and also makes the slope turn, so a point is kept only
  if the function is steady in a tiny neighbourhood and, for a root, its value there is far smaller than at the ends of the
  interval. An extremum on the axis (x² at 0) is also a root.
- **The first window** is wide enough for the five points of interest nearest the origin, with room around them, and as high as
  the curves are there (the 3rd to 97th percentile of their values); curves with nothing to mark get x from −10 to 10.
- **Gestures**: drag pans, pinch zooms about the fingers, tapping a point shows it with its coordinates, the corner button
  resets. The points are looked for again, for twice the window's width, when a gesture ends.
- **Reading a curve**: a tap that is not on a marked point but within 40 points of a curve puts a marker on the curve at that x, with
  its coordinates (`GraphModel.traced`: of all the functions, the one whose value is nearest the finger). Holding and then dragging
  follows the curve; the marker stays after the finger lifts, until a tap or a drag elsewhere. The graph can be shown full screen.
- **Curves and regions in x and y** (`PlotRelation`, `Calculator.plotContent`): an equation that is not a function of x (a circle,
  `x = y²`) and an inequality (`y > x²`, `x² + y² ≤ 4`, or `x² ≥ 4`, which shades whole columns) are drawn from `left − right`
  compiled to a function of two variables (`DoubleCompiler.compilePlane`). The curve is found by **marching squares** over a
  grid of 4-point cells: where the sign changes between two corners the curve crosses that edge, at the point linear
  interpolation gives, and a cell with an undefined corner is skipped; in the ambiguous cell (opposite corners alike) the middle
  of the cell decides which way round. A region is the cells whose centre satisfies the relation, merged into runs along each
  row. The boundary is solid for `≤`, `≥` and `=` and dashed for `<` and `>`; a dashed stroke restarts its pattern with every
  piece, so the segments are first joined into lines by their shared ends (neighbouring cells compute a shared edge from the
  same two numbers, so the ends agree exactly). The window is square in scale (`matchingAspect`), fitted to where the curve meets
  the axes, so a circle is round; the axis intercepts are marked, and so are the crossings of a function with a curve (a line
  and a circle). A system is drawn when each line is a function or a relation: the common part of inequalities is where the
  tints overlap.

## Solving equations

- **The canonical form does not expand.** `(x+1)(x-2)` stays a product, so solving starts with `Expr.expanded()`, an explicit
  operation, and `together(variable:)`, which writes a sum of fractions as one numerator over the denominators that contain
  the unknown (each with the largest power any term has, so no spurious factors are added). The numerator is read as a
  `Polynomial` in the unknown whose coefficients may contain other letters (`ax + b`).
- **The unknown** is `x` if the equation has one, then `y`, `z`, otherwise the first letter alphabetically; other letters
  are constants. It is looked for in what was typed, not in the difference of the sides, so `x + 1 = x` has no solution
  and is not a false statement. `y = f(x)` is a function to draw, not an equation to solve for x.
- **Polynomials with rational coefficients**: the repeated factors are removed (`p / gcd(p, p′)`), zero is divided out,
  rational roots are found by the rational root theorem (candidates from the divisors of the constant and leading
  coefficients; skipped when they cannot be factored completely or there are more than 200 000), and what is left is solved
  by the quadratic formula, or as a polynomial in `x^k` when it has that shape (`x⁴ = 16`, `x⁶ = 1`; the roots of unity are
  exact for `k` dividing 24, by Euler's formula), and otherwise numerically. No closed form is attempted for a cubic or
  quartic that does not factor: the result would be a nest of radicals nobody can read, so those roots are decimals
  (50 digits).
- **Numeric roots** are found in `Double` by the Aberth–Ehrlich method, which finds all roots at once, and refined by
  Newton's method at the working precision. A root of a real polynomial whose imaginary part is only rounding is real.
- **Other coefficients**: degree 1 and 2 are solved symbolically (`−b/a`, `(−b ± √(b² − 4ac))/2a`), so a letter or a radical
  in a coefficient is fine; higher degrees with such coefficients are not solved.
- **A value that makes a denominator zero is not a solution** (`(x²−1)/(x−1) = 0` has only −1). An identity says which
  values are left out.
- **Complex solutions are solutions.** `x² + 1 = 0` has `−i` and `i`. They come after the real ones, which are in increasing
  order. The square root of a complex number is simplified exactly when that is simpler (`√(3+4i)` is `2+i`), which is what
  makes roots such as the sixth roots of unity come out as `(1 + √3i)/2`.
- **Display**: a sum of numbers with fractional coefficients over one denominator is written as one fraction,
  `(1 − √5)/2`, in the typeset answer and in the text form.
- **The graph** of an equation in `x` is its two sides, whose crossings are the solutions (one side that is zero is the x
  axis, so only the other is drawn).
- **How it was checked**: 250 random polynomials, some built from chosen rational roots, give as many distinct roots as the
  polynomial has and each root satisfies it to many digits; hand-worked cases for each branch.

## Systems and inequalities

- **Linear systems** are reduced by Gauss–Jordan elimination in exact arithmetic (`Expr`), so the answer is exact and
  fractions stay fractions. The result is one solution, none (a row `0 = c`), or infinitely many: the determined unknowns
  are then given in terms of the free ones (`x = 5 − y`).
- **Nonlinear systems** by substitution: an unknown is eliminated through an equation that is linear in it with a constant
  coefficient (`x + y = 7` gives `x = 7 − y`), the others are rewritten, and the process repeats until one unknown is left,
  which the single-equation solver handles. A system with no such equation (`x² + y² = 1, x² − y² = 0`) is not solved.
  Every candidate is checked against all the original equations. Solutions are in increasing order of the first unknown.
- **The unknowns** of a system are all its letters, ordered x, y, z, then alphabetically.
- **Inequalities** in one unknown: each condition `f op 0` is cut at the real roots of the numerator (where it is zero) and of
  the denominators (where it is not defined). The sign is read at one point of each stretch between them, and each critical
  point is judged by its own rule (a denominator's root never satisfies; a numerator's root satisfies `≤ ≥ =` only), then runs of
  satisfied stretches and points are joined into intervals. A chain `1 < x ≤ 5` is the conditions `1 − x < 0` and `x − 5 ≤ 0`
  judged together, so a middle operand may be any expression (`−1 < x² < 4`). `≠` works the same way.
- **How it was checked**: random linear systems built from a chosen solution return exactly that solution (or a family that
  contains it when the matrix is singular, with the rank checked independently); random polynomial inequalities agree with
  direct evaluation at 91 test points each.
- **Graphs**: an equation in x and y that is of degree 1 in y (`x + y = 3`, `xy = 1`) is drawn as the function it defines,
  so a system of them is drawn as its lines with the crossing marked.

## Equations that are not polynomials

All of these give **real** solutions (the polynomial solver gives complex ones too). Each strategy rewrites the equation into
polynomial ones and only proposes candidates; every candidate is substituted into the original and kept if it is zero to 30 digits,
which drops what squaring or a logarithm of a negative number brought in. `TranscendentalSolver` tries them in this order and
uses the first that applies.

- **Trigonometric**: every sine, cosine and tangent of `mψ + q` (`ψ = a·x` the smallest angle, `m` a whole number up to 8) is
  written with `S = sin ψ`, `C = cos ψ`, as the real and imaginary parts of `(C + iS)^m` and the addition formulas. Then: `S`
  alone or `C` alone (using `S² + C² = 1`) gives `arcsin` and `arccos` families; `A sin ψ + B cos ψ + D = 0` is `sign(A)·R·sin(ψ + φ)
  = −D`; anything else goes through `τ = tan(ψ/2)`, plus `ψ = π`. A solution is a family `offset + period·n` (`PeriodicSolution`),
  offsets brought into [0, period), and families half a period apart are merged until none are (`π/4 + π/2·n`). In degree mode
  `a = π/180`, so the same code gives `30 + 360n`.
- **Absolute values**: the line is cut where an argument of an innermost `|…|` is zero; on each closed stretch the bars are
  replaced by the signed argument and the rest is solved by recursion; nested bars resolve from the inside.
- **Exponentials** `g^(cx+d)`: all bases are written as rational powers of one (`4 = 2²`), `t = g^(x/V)` makes each a whole power,
  the polynomial in `t` is solved, and `x = V·log_g t` for each positive root.
- **Logarithms**: with natural logarithms, `Σ kᵢ ln gᵢ = δ` (the `kᵢ` rational multiples of each other) is `Π gᵢ^rᵢ = e^δ`.
  `e^(c ln a)` is `a^c` and `log_b(a^p)` is `p` when `log_b a` is a number, so `log(x) = 2` gives 100.
- **Roots**: `b^(1/L)` becomes `r` with `r^L = b`; `L` is 2 or 3. Multiplying by the conjugate (`c₀² − c₁²b`, or the cube-root
  norm) removes `r`; several roots are removed one at a time.
- **Numerically**, when nothing above applies (`e^x = x + 2`): sampled on [−100, 100], roots located in `Double` by the graph
  machinery, refined by Newton's method in 60 digits, and given as fractions when they are simple (2 and 4 for `2^x = x²`). An
  equation with none in the window is not reported as having none, and one with more than 30 is not solved.
- **Inequalities** with these use the same sign analysis: the real solutions of the equation, and the points where a root or
  logarithm begins to be defined, cut the line; the sign is read on each stretch from the expression itself (undefined is not
  satisfied).
- **Large values**: a function that needs as many extra digits as its argument has (the sine or tanh of a number with 10^8 digits)
  is an overflow, not an endless computation, and the arctangent of a huge number is π/2. Found by a random expression.
- **How it was checked**: hand-worked cases for each strategy (one of them showed a wrong expectation, not a wrong answer:
  `√(3x+1) − √(x−1) = 2` has the solution 1 as well as 5).

## Calculus

The functions `diff(f, x, n)`, `int(f, x, a, b)`, `lim(f, x, a, side)` and `sum(f, k, a, b)` (also written `∫`, `Σ`, with `∞` for
infinity) are read by the parser like any function, but `Builder` works them out on the syntax while it builds the `Expr`
(the unknown is an argument, and ∞ is only an argument), so their value is an ordinary expression. `MathError.unsupported`
is a calculation this version cannot do; `MathError.undefined` is a limit whose sides disagree or that oscillates, and an
integral or series that diverges. `MathConstant.infinity` exists only as a result; the canonical form does no arithmetic with it.

- **Derivatives** follow the rules on the canonical form (sum, product, general power `b^e`, chain rule for each function). A
  result with denominators is written as one fraction when that has fewer parts (`1/(x+1) − x/(x+1)²` is `1/(x+1)²`).
  Checked against a central difference at 50 digits on random expressions.
- **Integrals**: a table of the basic ones; linearity and constant factors; polynomial × exponential/sine/cosine by repeated
  integration by parts; polynomial × logarithm or inverse trigonometric function by parts; `e^(ax) sin(bx)` by formula;
  `sinⁿ cosᵐ` and the product of sines and cosines of different angles through Euler's formula; rational functions by partial
  fractions over the rationals (linear factors, and one irreducible quadratic); and substitution `u = g(x)` for any subexpression
  `g` when `f/g′` is a function of `g` alone (for a linear `g`, an `x` left over is `(u − b)/a`). **Every result is differentiated and
  compared with the integrand at several points before it is returned**, so a wrong antiderivative is never answered; with none
  found, `unsupported`. A definite integral is `F(b) − F(a)`, with limits at an end where `F` is not defined or is infinite; a
  pole inside the interval, or an infinite end, is `undefined`.
- **Limits**: substitution where the expression is continuous; otherwise it is evaluated at 10⁻⁸ … 10⁻³⁰ from the point (or at
  10⁶ … 10⁴⁸ out, with nearer lists where an exponential overflows) to 330 digits. A sequence that settles is recognised as zero, a
  fraction with a small denominator, or such a fraction of π, π², e, e², 1/e, ln 2, ln 3, √2, √3, √5; one that keeps growing is ±∞; the two
  sides must agree. Values too large or too small to subtract are compared by size only.
- **Sums**: a short sum is added; a polynomial summand has a closed form through Newton's differences (`n²/2 + n/2`); a geometric
  term `c·rᵏ` (with a polynomial factor, by differentiating the geometric series) in closed form or to ∞ when |r| < 1; rational
  functions with whole-number poles telescope to harmonic numbers; ζ of even numbers up to 12, the alternating 1/k, 1/k², 1/k⁴; and
  `Σ rᵏ/k!` is `e^r`. A series whose terms do not tend to zero is `undefined`.
- **Found while testing**: `BigDecimal.power` refused `(1 + 10⁻⁴⁸)^(10⁴⁸)` because it estimated the size of the result from the number of
  digits of the base and not from its logarithm; the integer power is now judged by `|exponent|·|log₁₀ base|`.

## More functions

`mod(a, b)`, `min`, `max`, `sign`, the parts of a complex number (`re`, `im`, `conj`, `arg`), the two-argument `atan(y, x)`, and
the inverse reciprocal and reciprocal hyperbolic functions have no case of their own in `MathFunction`: `Builder` writes each with
the functions the engine has (`a − b·floor(a/b)`, `(a + b ± |a − b|)/2` when the values are not numbers, `acot(x) = π/2 − atan x`,
`asec(x) = acos(1/x)`, `coth = cosh/sinh`), so every other layer (approximation, derivatives, graphs) works on them unchanged.
A number is compared by its decimal value (`max(√2, 3/2)` is `3/2`), and the angle of a point needs to know on which side of
each axis it lies, so `atan(y, x)` with unknowns in it is not supported. `re`, `im`, `conj`, `arg`, `mod`, `min`, `max` and
`sign` are read as functions only when a parenthesis follows (`re` alone is r times e), as the keyboard writes them.
A logarithm with a base is its own editor node, `log₂(8)`, written as `log(8, 2)`.

## Identities, turns and special integrals

- **Turns in trigonometric arguments** are taken out by the canonical form: for an argument `y + rπ`, a multiple of π/2 swaps sine
  and cosine by quarter turns (`sin(x + π/2)` is `cos x`, `cos(x + π)` is `−cos x`; tangent has period π, and `tan(x + π/2)` is
  `−cos x/sin x`), and any other `r` is brought into (−1, 1] by whole turns (`sin(x + 7π/3)` is `sin(x + π/3)`). A sum in degrees is
  converted term by term (`Builder.radians(fromDegrees:)`) so that `sin(x + 90)` is seen as a quarter turn. `(x²)^(1/2)` is `|x|`
  and `|x|^(2m)` is `x^(2m)`, since an even power of a real number is not negative.
- **Identities that make an answer smaller** are not in the canonical form but applied to the finished answer
  (`Expr.trigonometricallySimplified`), bottom up, and used when the result is no larger: `sin² + cos² = 1`, `1 − sin² = cos²`,
  `cos² − sin² = cos 2u`, `1 − 2 sin² = cos 2u`, `2 sin u cos u = sin 2u`, with the same product beside both terms.
- **Gaussian integrals** (`GaussianIntegrals`): `∫ x^m e^(−a x² + b x + c) dx` over the line, or over a half line when `b = 0`, by
  completing the square and the moments of `e^(−a t²)`; the antiderivative route cannot do these (erf is not elementary).
  `∫ sec` and `∫ csc` are `ln|1 + sin| − ln|cos|` and `ln|1 − cos| − ln|sin|`.
- **Periodic inequalities** (`PeriodicInequalities`): `sin x > 1/2`, `tan x ≥ 1`, `cos 2x < 0`. The roots come from the numerator and
  the poles from the denominators (with `tan u` written as `sin u/cos u`), both through the trigonometric equation solver, over
  *two* periods of the roots, since an expression can take twice as long to repeat as its roots do (`cos 2x` has roots every π/2
  and period π). The sign between neighbours is read at the middle, the stretches that hold are joined across a root when it
  belongs to the solution (≤, ≥) and never across a pole, and the result is cut to one period if it repeats after half. The answer
  is `lower + period·n < x < upper + period·n`. Tests sweep points across three periods and compare with the expression itself.

## Smaller things worth knowing

- **Substitution in a system** also eliminates through a coefficient that is a product of the other unknowns (`xy = 3` gives
  `y = 3/x`); the solutions with one of those unknowns zero are looked for separately, since the division excluded them.
- **`ln` of a prime power** is the exponent times `ln` of the prime (`ln 8 = 3 ln 2`, `ln(1/9) = −2 ln 3`), so that logarithms of
  powers of one prime are multiples of one expression and combine.
- **One fraction**: a sum of fractions in several unknowns is also shown as one fraction over the product of its denominators
  (`ExpressionForm.combined`); with one unknown the factored form already cancels.

## Pasting and copying

`SyntaxLayout` lays the parser's syntax tree out as editor nodes (fractions stacked, exponents raised, roots with their bar, ∫ Σ lim
in their boxes), so a pasted formula is edited like a typed one. A product is written side by side when that reads back the same
(`2x`, `3(x + 1)`) and with × otherwise; parentheses are added where the precedence needs them. A property test sends random
formulas through nodes and text and checks the value. `[MathNode].plainText` is the other direction, for copying an answer out:
`(√6 − √2)/4`, `x = −2, x = 2`, `e^3·e^x`. A power, a root or a denominator is in brackets unless it is a number, one letter or a
function call (`e^2x` would read as (e²)x), and a dot separates a product after a power or a root (`e^3e^x` would read as
e^(3e^x)). Another property test checks that copied text reads back as the same value.

An error that is not about a domain has its own case: `MathError.noValue` is `tan(π/2)`, `ln(0)` and `0^0`, which the app
says are undefined, where `asin(2)` has no *real* answer.

## Settings and other forms of an answer

- **Settings** are the angle unit, the number of significant digits for decimals (6 to 30) and the language (system, English, 日本語).
  They live in `UserDefaults` of the app and nowhere else. A language chosen in the app is applied at once: SwiftUI text takes the
  locale from the environment, and `Localizer` looks up the few words that are kept as data (the history) in that language's
  bundle. The top bar's `RAD`/`DEG` switches the unit with a tap, because it changes what `sin(30)` means.
- **A factored form is not an `Expr`**: the canonical form spreads a numeric coefficient over a sum, so `2(x + 1)` would be
  `2x + 2` again. `Factorization` is a coefficient with factors and a denominator, and `Typesetter` draws it. Factors are the
  linear ones with rational roots (`(2x − 1)`, with whole-number coefficients), what is left over after them, and the unknown
  itself first; the nearest roots to zero come first (`(x + 1)(x + 2)`, `(x − 2)(x − 3)`, `x(x + 1)(x − 1)`). Factors common to a
  numerator and denominator cancel, which is shown as a simplified form. Polynomials that need a factoring over the rationals
  beyond roots (`x⁴ + 4`) keep the leftover as one factor.
- **Which forms are shown**: expanded when multiplying out changes the answer and there is no fraction in it, factored when it
  says something the answer does not (checked by comparing the typeset text, so `(x + 1)(x + 2)` is not shown again as itself).
- **Cotangent, secant, cosecant** are `cos/sin`, `1/cos`, `1/sin` (so `cot(π/2)` is 0 and `sec(π/2)` a division by zero); they are not new
  functions of `Expr`.

## Calculus in the editor

`MathNode.calculus(kind, slots)` holds ∫, Σ, lim and d/dx. Its slots, in the order the arrows visit them: the expression, the
variable (`x`, or `k` for a sum, already filled in), then the ends (an integral's lower and upper; a sum's start and end, `1` and
`∞` already filled in) or the point of a limit. A new operator puts the cursor in the expression; a short run of the right arrow goes
on to the variable and the ends. It is empty, for backspace, when its expression is, so deleting the expression and one more key
removes the operator. `parserText` writes the function the parser knows (`int(f,x)`, `int(f,x,a,b)` when either end is given,
`sum(f,k,a,b)`, `lim(f,x,a)`, `diff(f,x)`); an empty slot gives an empty argument, which the parser reports as unfinished. The view
draws ∫ with its ends beside it and `dx` after the integrand, Σ with the index below and the end above, lim with `x → a` below, and
d/dx as a small fraction in front of the expression in brackets.
