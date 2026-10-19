# Mantissa

A free scientific and graphing calculator for iPhone. It works entirely offline, shows exact results (fractions,
roots, π), solves equations and keeps a history. No ads, no accounts, no network access.

> **Status: early release (0.22).** The calculator, graphs, equations, systems, inequalities, calculus and history work. It
> is not on the App Store: install it as described under [Installing](#installing). Expect rough edges and answers the
> solver cannot give yet (it says so rather than guessing).

<p>
  <img src="docs/screenshots/equation.png" width="240" alt="Solving x² − 5x + 6 = 0, with its graph">
  <img src="docs/screenshots/factored-form.png" width="240" alt="The factored form of x² − 5x + 6">
  <img src="docs/screenshots/integral.png" width="240" alt="An integral, with the graph of its answer">
</p>

Everything is worked out on the phone and nothing is sent anywhere; see [PRIVACY.md](PRIVACY.md).

## Features

What it does (the maths is in the `MantissaCore` package, which has no dependencies; the app is a thin screen on top):

- Arbitrary-precision integers (`BigInt`).
- Exact fractions (`Rational`), including exact parsing of decimals such as `0.1` and `2.5e-3`.
- Arbitrary-precision decimals (`BigDecimal`) with π, e, square roots, powers, `exp`, `ln`, `log`, the trigonometric,
  inverse trigonometric and hyperbolic functions, rounded to the last digit (checked against Python's `decimal` at 15,
  50 and 100 digits).

- A calculator engine: type `√12 + √3`, `sin(15°)`, `1/(1+√2)`, `(x+1)*2` or `5!` and get the exact answer
  (`3√3`, `√6/4 - √2/4`, `-1 + √2`, `2x + 2`, `120`) and a decimal approximation to any precision. Radians, or degrees
  with the ° sign (`sin(15°)`); English or Japanese full-width input.

- An iPhone app on top of the engine: a maths keyboard with stacked fractions and roots, a live exact and decimal
  answer, a history of solved problems (saved on the phone), and graphs of functions of x with their roots, extrema and
  crossings marked, solutions of equations (exact where there is a closed form, complex ones included, the rest as
  decimals), equations with roots, absolute values, exponentials, logarithms and trigonometric functions (`sin x = 1/2`
  is `π/6 + 2πn` or `5π/6 + 2πn`), systems of equations, and inequalities in one unknown (`x² > 4` is `x < −2 or x > 2`).
  English and Japanese (the language can be chosen in the app).
- An answer with an unknown in it also shows its expanded and factored forms (`x² − 5x + 6` is `(x − 2)(x − 3)`), and a fraction
  with common factors is shown simplified; this works with several unknowns too (`(a² − b²)/(a − b)` is `a + b`). A sum with
  a factor in every term shows it taken out (`x eˣ − eˣ` is `eˣ(x − 1)`). Radians or degrees, and the number of digits, are settings.

- Calculus: derivatives (`d/dx`), integrals (indefinite, definite and improper), limits (including at ∞ and one-sided) and
  sums and series, with exact answers (`∫ x e^x dx`, `lim (1 + 1/x)^x = e`, `Σ 1/k² = π²/6`).

The keyboard places ∫, Σ, lim and d/dx with boxes for their expression, variable and ends, as in the app this one follows.
`log` with a base is typed with its base small below it (`log₂(8)`), and a small + or − after the point of a limit means from above
or from below.

- Also: `mod`, `min`, `max`, `sign`, the real and imaginary parts, conjugate and argument of a complex number, `atan(y, x)`, and
  the reciprocal trigonometric and hyperbolic functions with their inverses.
- Trigonometric inequalities (`sin x > 1/2` is `π/6 + 2πn < x < 5π/6 + 2πn`), trigonometric identities in answers (`sin²x + cos²x`
  is 1, `tan x cos x` is `sin x`, `1/cos²x − tan²x` is 1), the Gaussian integral (`∫ e^(−x²) dx` over the line is √π) and the integrals of sec and csc.
- Integrals with the square root of a quadratic (`∫ √(x² + 1) dx`, `∫ x²/√(1 − x²) dx`, `∫ dx/(x²√(x² + 1))`) and the by-parts
  integrals of the inverse trigonometric and hyperbolic functions (`∫ x asin x dx`).
- An equation with several letters (`v = u + at`) is solved for one of them, and a row of letters above the answer solves it for
  another (`t = (v − u)/a`).
- Tap the formula to put the cursor there, also inside a fraction or an exponent.
- Paste a formula from anywhere (`2x^2 + sqrt(3)`) and it is laid out like one typed on the keyboard; hold the answer to copy
  it as text or to use it as the next input; hold the delete or arrow key to repeat it.
- Systems such as `x² + y² = 10, xy = 3`, logarithms of powers of a prime (`ln 8` is `3 ln 2`, so `log₂x + log₄x = 3` gives 4), and a
  sum of fractions in several letters as one fraction (`1/x + 1/y` is `(x + y)/(xy)`).
- Graphs: tap a curve to read its coordinates, hold and drag to follow it, and open it full screen.
- Graphs of circles and other curves in x and y (`x² + y² = 25`, with the intercepts marked) and shaded regions for inequalities
  (`y > x²`, dashed where the edge is not included); a line and a circle show where they cross.

## Installing

There is no App Store build and no signed build. Each [release](https://github.com/kosuke-apps/Mantissa/releases) has an
unsigned `Mantissa-<version>-unsigned.ipa` and its SHA-256 (`.sha256`). iOS only runs apps that are signed, so you sign it yourself with your
own Apple ID, using a sideloading tool such as [AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io). Their
instructions apply; this project does not run or endorse either.

A free Apple ID is widely reported (blog posts and forums, not an official statement from Apple) to give apps that expire
after 7 days, which a sideloading tool can renew, and to allow only three such apps at a time. A paid Apple Developer
Program membership is not needed for either way to work.

Check the download against the published checksum before installing it:

```bash
shasum -a 256 -c Mantissa-<version>-unsigned.ipa.sha256
```

### Building from source

Needs a Mac with a recent Xcode (Swift 6; it was built with Xcode 27.1) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The app targets iOS 17 or later.

```bash
git clone https://github.com/kosuke-apps/Mantissa.git && cd Mantissa
cp Config/Local.xcconfig.example Config/Local.xcconfig   # put your Apple team ID in it
xcodegen generate
open Mantissa.xcodeproj                                  # run on a device or a simulator
```

The engine alone builds and tests without Xcode projects: `swift build` and `swift test`.

### Where it has been run

Checked by the author on the iOS 27.0 simulator (Xcode 27.1, macOS 26.6), which is where the automated app tests run, and
installed and started on one iPhone 12 Pro with iOS 18.6.2. Nothing else has been tried: other devices and iOS versions
should work (the deployment target is iOS 17) but are not verified. It is for iPhone, in portrait.

## Accuracy

Mantissa is for studying and everyday sums, not for work where a wrong digit costs something; the MIT licence gives no
warranty (see [LICENSE](LICENSE)). What is checked:

- **Exact answers** (`3√3`, `π/6 + 2πn`, `ln 2`) are built from whole-number arithmetic and are exact. An antiderivative is
  differentiated and compared with the integrand at several points before it is shown, and one that does not match is dropped. A
  solution is substituted back where that can be done. A solver that cannot find an answer says "not supported yet" rather than
  guessing.
- **Limits** are the least certain part: they are found by substitution, or from a sequence of values at high precision that is
  recognised as a known number, and an unusual function can fool the second.
- **Decimals** are rounded to the digits asked for (6 to 30 in Settings; 50 inside). The functions are computed with 15 guard
  digits and compared, in the tests, with Python's `decimal` at 300 digits: the last digit has to be the same, not just close.
  Rounding can still differ in the last digit where the true value lies within about 10⁻¹⁵ of a rounding boundary.
- **Graphs and the points marked on them** (roots, extrema, crossings) are found with ordinary floating-point numbers (about 12
  digits), enough to place a point, not to read digits from. Use the answer line for digits.
- A **numerical root** (`x = cos x`) is found inside −100 to 100 only, and a root outside it is not claimed or ruled out.
- Anything whose value is astronomically large (`e^1000000` as a bound, a power with thousands of digits in the exponent) is
  given up on, not approximated.

The numbers behind the engine are tested against reference values made by Python, which has its own arbitrary-precision integers
and decimals, so the tests do not check the Swift code with itself. To make the reference files again (they must come out
byte for byte the same, as the seed is fixed):

```bash
python3 tools/gen_number_vectors.py     # BigInt and Rational
python3 tools/gen_decimal_vectors.py    # BigDecimal and the functions
```

Random inputs, solved and compared with a naive evaluator, run with the tests; `MANTISSA_SEED=n` and `MANTISSA_SAMPLES=n` widen
them. See [docs/design.md](docs/design.md) for how each part reaches its accuracy.

## Development

```bash
swift build
swift test
```

## Architecture

The engine is a Swift package with no dependencies (`Sources/MantissaCore`); the SwiftUI app (`App`) sits on top of it and
adds no maths. See [docs/design.md](docs/design.md), and [AGENTS.md](AGENTS.md) for a map of the files.

## Quality checks

```bash
xcrun swift-format lint --strict -r Sources Tests Package.swift
swift test
```

## Licence

Mantissa is released under the MIT licence: Copyright (c) 2026 Kosuke Satake (see [LICENSE](LICENSE)). It has no
third-party code or data: see [THIRD_PARTY.md](THIRD_PARTY.md).

This project accepts issues, not code contributions.

## About the making of this app

This app was built with the help of Claude (Anthropic) through Claude Code; design, review and testing are by Kosuke Satake. Anthropic does not endorse this app.
