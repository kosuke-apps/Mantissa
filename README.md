# Mantissa

A free scientific and graphing calculator for iPhone. It works entirely offline, shows exact results (fractions,
roots, π), solves equations and keeps a history. No ads, no accounts, no network access.

> **Status: early development.** The calculator, history, graphs, equations, systems and inequalities work in the iOS
> Simulator. Not released yet.
> Not released yet.

## Features

Working today (in the `MantissaCore` package):

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
  English and Japanese.

- Calculus: derivatives (`d/dx`), integrals (indefinite, definite and improper), limits (including at ∞ and one-sided) and
  sums and series, with exact answers (`∫ x e^x dx`, `lim (1 + 1/x)^x = e`, `Σ 1/k² = π²/6`).

Planned: structured input for ∫, lim and Σ, and a step back to the one-by-one entry of arguments.

## Getting started

Needs Xcode (Swift 6) on macOS.

```bash
swift build
swift test
```

## Architecture

The engine is a Swift package with no dependencies; the app will sit on top of it. See `docs/design.md`.

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
