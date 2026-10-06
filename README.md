# Mantissa

A free scientific and graphing calculator for iPhone. It works entirely offline, shows exact results (fractions,
roots, π), solves equations and keeps a history. No ads, no accounts, no network access.

> **Status: early development.** Only the number foundation of the calculation engine exists so far; there is no app
> to run yet.

## Features

Working today (in the `MantissaCore` package):

- Arbitrary-precision integers (`BigInt`).
- Exact fractions (`Rational`), including exact parsing of decimals such as `0.1` and `2.5e-3`.

Planned: maths keyboard with stacked fractions and roots, scientific functions, exact results with a decimal switch,
equation and inequality solving, graphs, history, English and Japanese.

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

## License

MIT, see `LICENSE`.
