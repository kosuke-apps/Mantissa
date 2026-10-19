# Mantissa

A free, fully offline scientific and graphing calculator for iPhone that shows exact results and solves equations.
Workspace rules are in `~/Developer/AGENTS.md`; this file adds what is specific to this project.

## Product

- Purpose: bring back the calculator the Photomath app had before Google acquired it, without the parts nobody
  wanted. The author used it daily as a scientific calculator, a function grapher and an equation solver, with a
  history, entirely offline. The current app lost those features, and the alternatives are either plain calculators,
  imitations of a physical scientific calculator, or GeoGebra (too hard to use). A standard iOS Calculator is not an
  option for the author.
- Intended users: the author first; students and anyone who wants a normal scientific calculator that is pleasant.
- Core user journey: open the app, type a problem in ordinary maths notation on a maths keyboard (stacked fractions,
  roots, powers), see the exact answer (fraction, root, π) with a switch to the decimal, tap to see the graph, find
  it again in the history.
- In scope (all of it must work offline): scientific functions; exact results; solving equations, inequalities and
  systems; simplifying and expanding; derivatives, integrals, limits and sums as far as they can be done reliably;
  graphs with zoom, pan, trace and the points that matter (roots, intersections, extremes); history.
- Out of scope, permanently: camera or photo input, ads, step-by-step explanations, accounts, analytics, any network
  access, subscriptions, textbook content.
- Precision target: scientific-calculator grade. Exact when the result is exact; otherwise at least 12 correct
  digits, and never a result like `sin(π) = 1.2e-16` where the exact answer is 0.
- Do not copy the original app's name, logo, icons, artwork or wording. Behaviour and layout feel are the reference,
  not its assets. UX: it should feel instant.

## Technical context

- Stack: Swift 6, SwiftUI, iOS 17+ (macOS 14+ for the core package so it tests on the Mac). No third-party
  dependencies. Tests use Swift Testing. UI strings in English with a maintained Japanese String Catalog.
- Bundle identifier (planned): `dev.kosuke.mantissa`, as for Headway.
- Layout:
  - `Package.swift`: the engine as a Swift package. `App/` is the iPhone app on top of it, generated into
    `Mantissa.xcodeproj` by XcodeGen from `project.yml` (the project file is not committed; Swift 5 mode for the app,
    Swift 6 for the package). `App/AppModel.swift` holds the editor and the latest answer (computed off the main
    thread); `MathView.swift` draws a `MathNode` tree; `GraphView.swift` the graph (canvas, pan, pinch, tap a point);
    `History.swift` and `HistoryView.swift` the saved problems; `Settings.swift` and `SettingsView.swift` the angle unit,
    digits and in-app language (kept in `UserDefaults`; `Localizer` looks up strings that are not views);
    `SolutionsDisplay.swift` an equation's answer typeset; `KeyboardLayout.swift` and `KeyboardView.swift` are the keys
    and pages; `CalculatorScreen.swift` the screen; strings in `Resources/Localizable.xcstrings` (English, Japanese).
  - `Sources/MantissaCore/BigInt.swift`: arbitrary-precision integer (sign and magnitude, 32-bit limbs, Knuth D
    division). Own implementation so there is no dependency.
  - `Sources/MantissaCore/Rational.swift`: exact fraction in lowest terms; parses decimal literals exactly.
  - `Sources/MantissaCore/BigInt+Math.swift`: decimal digit count, integer square root, floor division.
  - `Sources/MantissaCore/BigDecimal.swift`: arbitrary-precision decimal (`significand × 10^exponent`): exact
    `+ - ×`, rounded division, square root, integer power, parsing and printing.
  - `Sources/MantissaCore/FixedPoint.swift` (internal): `BigInt` fixed-point helpers and the series for π, ln 2,
    ln 10, atan, atanh, sin, cos and exp.
  - `Sources/MantissaCore/BigDecimal+Functions.swift`: `pi`, `e`, `exp`, `ln`, `log`, `power`, trigonometric,
    inverse trigonometric and hyperbolic functions, all taking a `precision` in significant digits.
  - `Sources/MantissaCore/MathError.swift`: `divisionByZero`, `domain`, `overflow`, `notNumeric`; thrown (typed throws),
    never trapped.
  - `Sources/MantissaCore/NumberTheory.swift`: factoring by trial division, factorial, nCr, nPr, exact logarithms.
  - `Sources/MantissaCore/Expr.swift`: the exact expression type and its canonical order. `Expr+Build.swift`: the smart
    constructors (sum, product, power, radicals, expansion of numeric sums, rationalising). `Expr+Functions.swift`:
    function application with exact values and symmetries. `Expr+Approximation.swift`: the decimal value;
    `Expr+ComplexApproximation.swift` and `ComplexDecimal.swift`: the same for values with the imaginary unit.
    `Expr+Description.swift`: the linear text form that the parser reads back.
  - `Sources/MantissaCore/Editor/`: the model behind the maths keyboard, with no UI. `MathNode` (a formula as a tree of
    symbols and structures with slots), `MathEditor` (every key as a method: characters, fraction, power, root, group,
    function, arrows, backspace, new line; cursor as a path), `MathNode+Text` (writes the lines as parser text),
    `Typesetter` (an exact `Expr`, or a decimal, as `MathNode`s for display).
  - `Sources/MantissaCore/Plot/`: graphing in `Double` (the only place it is used for a result). `DoubleCompiler` (an
    `Expr` to a closure of one or two variables), `PlotFunction` (+ `Calculator.plotFunctions`: which inputs are the graph
    of a function), `PlotRelation` (+ `Calculator.plotContent`: curves and regions in x and y), `PlotContours` (marching
    squares and shaded runs), `PlotViewport` (fit, pan, zoom, equal scales, `PlotSampler` that cuts a curve at gaps and
    poles), `PlotAnalysis` (roots, intercepts, y-intercept, extrema, crossings).
  - `Sources/MantissaCore/Algebra/`: what the canonical form deliberately does not do on its own. `Expand` (multiply
    out, substitute, put a sum over a common denominator), `Polynomial` and `RationalPolynomial` (coefficients as `Expr`
    or `Rational`; rational roots, squarefree part), `PolynomialRoots` and `NumericRoots` (exact roots, then decimals),
    `Factor` (a polynomial or fraction as a product of factors, and the other forms an answer is shown in),
    `MultiPolynomial` (+ `+GCD`, `+Factor`: polynomials in several unknowns with a work budget in `PolynomialRing`; gcd,
    repeated factors, perfect squares, factoring by discriminant, divisors and homogeneous forms), `UnivariateFactoring`
    (irreducible factors by roots and Kronecker's method),
    `TrigonometricSimplify` (identities applied to a finished answer), `PeriodicInequalities` (`sin x > 1/2`), `Solver` (one
    equation in one unknown), `SystemSolver` (linear by Gauss–Jordan, nonlinear by substitution),
    `InequalitySolver` (sign analysis between the real roots), `Calculator+Solve` (`Calculator.solve` routes the input),
    `TranscendentalSolver` and its strategies (`AbsoluteValueEquations`, `ExponentialEquations`, `LogarithmicEquations`,
    `RadicalEquations`, `TrigonometricEquations`, `NumericEquations`), `Atoms` (find and replace parts of an `Expr`).
  - `Sources/MantissaCore/Calculus/`: `Differentiation` (rules on the canonical form), `Integration` (a toolbox that checks
    every answer by differentiating it), `Limits` (substitution, then sequences at high precision and recognising the value),
    `Series` (sums), `GaussianIntegrals`, `Simplify` (one fraction when that is smaller), `Calculus` (the `diff`, `int`, `lim`, `sum` functions, which
    the builder works out while it turns the syntax into an `Expr`).
  - `Sources/MantissaCore/Syntax.swift`, `Lexer.swift`, `Parser.swift`: text to syntax tree (grammar in the comment on
    `Parser`). `Builder.swift`: syntax to `Expr`, applying the angle unit; `Builder+Functions.swift`: the functions that
    are written with others (`mod`, `min`, `max`, `sign`, `re`, `im`, `conj`, `arg`, `acot`, `coth`, …). `Calculator.swift`: `evaluate(_:)` returns the
    exact value and its decimal approximation, or a `CalculatorError`.
  - `Tests/MantissaCoreTests/`: Swift Testing suites. `Resources/*.json` are reference vectors produced by
    `tools/gen_number_vectors.py` (Python's exact `int` and `Fraction`) and `tools/gen_decimal_vectors.py` (Python's
    `decimal` at 300 digits; sin, cos, atan written independently of the Swift algorithms). Fixed seeds; rerunning
    reproduces them byte for byte.
  - `docs/design.md`: the engine's layers and the decisions behind them. Read it before changing the engine.
- Constraints: the engine stays free of UI and Foundation types where practical so it runs anywhere; value types
  only; everything `Sendable`. Doubles are for plotting only, never for results shown as exact.

## Plan

Order is chosen so that the app is usable early and the heavy symbolic work comes last.

1. Numbers (done): `BigInt`, `Rational`, `BigDecimal` with π, e, exp, ln, log, power, sqrt, trigonometric, inverse
   trigonometric and hyperbolic functions, verified against Python to the last digit.
2. Expressions (done): parser, expression tree, exact simplification, evaluation with angle modes, the imaginary unit.
3. App: maths keyboard and editor, result card (exact and decimal) (done, first version: `docs/ui-reference.md` says
   what is followed), history, icon (done); the keyboard's remaining pages and long-press alternatives.
4. Graphs (done, first version): a function of x, or `y = …`, or several lines, with roots, y-intercept, extrema and
   crossings marked and tappable; pan and pinch. To do: implicit curves, inequalities, a trace along the curve.
5. Solving: equations in one unknown (polynomial, rational, with roots, absolute values, exponentials, logarithms,
   trigonometric functions; the rest numerically), systems, inequalities in one unknown (done).
6. Calculus: derivatives, indefinite and definite integrals (improper too), limits, sums and series, with the keyboard page
   and structured ∫, Σ, lim and d/dx in the editor (`MathNode.calculus`, written as `int(…)`, `sum(…)`, `lim(…)`, `diff(…)`)
   (done).
7. Settings (angle unit, digits, language), `cot sec csc`, expanded and factored forms of an answer (done). Polish:
   accessibility; running on the author's iPhone.

## Commands

- Build: `swift build`; test: `swift test`. A wider random search of the expression engine:
  `MANTISSA_SEED=3 MANTISSA_SAMPLES=2500 swift test --no-parallel --filter ExprPropertyTests` (add `MANTISSA_TRACE=1` to
  print each case; the last one printed names a crashing input).
- Format: `xcrun swift-format format -i -r Sources Tests Package.swift`; lint:
  `xcrun swift-format lint --strict -r Sources Tests Package.swift` (config in `.swift-format`).
- If a command fails because `xcode-select` points at the Command Line Tools, prefix it with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Regenerate the test vectors: `python3 tools/gen_number_vectors.py` and `python3 tools/gen_decimal_vectors.py`
  (need only Python 3; the files in `Tests/MantissaCoreTests/Resources` must not change when you rerun them).
- App: `xcodegen generate`, then
  `xcodebuild -project Mantissa.xcodeproj -scheme Mantissa -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`;
  icon: `swift tools/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset` (light, dark, tinted); the
  simulator keeps the old icon until the app is uninstalled and installed again;
  app tests: the same with `test` (use `id=<simulator UDID>` when two simulators are booted). Format and lint also
  cover `App` and `AppTests`.

## Definition of done

- The requested behaviour is complete, including edge and error states (division by zero, domain errors, overflow,
  malformed input).
- Formatting, linting and tests pass. New numeric code is checked against an independent oracle (Python's `int`,
  `Fraction`, `decimal`), not only against itself, and the rare branches are shown to run.
- UI is checked in the iOS Simulator at representative sizes, in light and dark mode, with Dynamic Type and VoiceOver.
- Documentation matches what was delivered.
