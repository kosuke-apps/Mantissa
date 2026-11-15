# Roadmap

Decided with the owner on 2026-11-13. The aim is the calculator that does everything the scientific, graphing and computer-algebra
calculators do, exactly and offline, and goes beyond them, while the everyday path stays as simple and instant as a plain calculator.
`AGENTS.md` says what is in and out of scope; this file says in what order the rest is built.

## Versions

From the release after 0.28.0 Mantissa numbers its versions `1.MINOR.PATCH`:

- **1.0.0** is the next release: the accessibility polish that closes the original plan, on top of what 0.28.0 has. 0.28.0 stays as it
  was published.
- A release with new features raises the minor number (1.1.0, 1.2.0, …). A release with fixes only raises the patch number (1.0.1);
  a fix-only release goes out after the management thread's check, without asking the owner again.
- `CFBundleVersion` keeps rising by one for every build.

## What stays true while it grows

1. **Exact when the answer is exact**, at least 12 correct digits otherwise; every new function is checked against an independent
   oracle (Python's `int`, `Fraction`, `decimal`, `statistics`, or a hand-derived value), not against the Swift code itself.
2. **A feature that cannot be done reliably says so** instead of guessing ("not supported yet"), as the solver and the integrator do.
3. **The main screen does not get heavier.** New abilities come as typed function names, structures in the editor and keyboard pages
   of their own; the first screen, the Basic page and the answer card stay as they are. The calculator stays instant: heavy work runs
   off the main thread and can be cancelled.
4. **Offline, no accounts, no network, no camera, no step-by-step explanations** (the cost of explanations that are always right is out
   of proportion; showing an expression rewritten, such as an expanded or factored form, is a different thing and stays).
5. **Every release** is checked as the 0.28.0 one was: the tests with the sanitizers, the iPhone and iPad simulators, a real device
   where one is at hand, the iPhone screens compared against the last release, a candidate `.ipa` made from a fresh clone, and the
   management thread's check before it is published.

## The order

| Release | What | Notes |
|---|---|---|
| 1.0.0 | Accessibility: VoiceOver (reading order, labels, the answer and the graph described), larger text, the 44 pt targets and the setting that tells curves apart without colour; shipped 2026-11-15. VoiceOver speaking it, Switch Control, Voice Control and Full Keyboard Access were not tried | the last item of the original plan |
| 1.1 | **Statistics and probability**: lists and data entry; mean, median, mode, variance, standard deviation, quartiles; linear, polynomial, exponential, power and logarithmic regression with the fit drawn; correlation; normal, binomial, Poisson, uniform, t, χ² and F distributions (density, cumulative, inverse); random numbers | needs a list editor |
| 1.2 | **Graphs, more**: parametric curves, polar curves, sliders for parameters, a table of values, tangent lines, the area under a curve, intersections and extremes between several curves, a derivative or integral drawn over a function, sequences | the viewport and the marked points are in place |
| 1.3 | **Differential equations and series**: first-order equations (separable, linear, exact), linear equations with constant coefficients of any order, initial conditions, the slope field; Taylor and Maclaurin series; partial derivatives and multiple integrals | the symbolic layer exists for the pieces |
| 1.4 | **Integers, bases and units**: primality, factorisation shown in full, modular arithmetic and inverses, the Chinese remainder theorem, Euler's φ, continued fractions; binary, octal and hexadecimal with bitwise operations; units and conversions; physical constants; engineering notation | `NumberTheory.swift` is the start |
| 1.5 | **Definitions**: functions (`f(x) = …`), variables, piecewise functions, sequences and recurrences, lists as values | extends the worksheet that matrices already use |
| 1.6 | **Geometry**: triangles solved from any sufficient data, areas, volumes and surface areas of the usual solids, conic sections from their equations, lines and planes in coordinates; interactive constructions come later | formula geometry first |
| 1.7 | **3D graphs**: surfaces `z = f(x, y)`, parametric curves and surfaces, level curves | rotation and zoom with the fingers |
| 1.8 | **Linear algebra, more**: LU, QR, Cholesky, diagonalisation, singular values, eigenvalues of larger matrices with irrational roots, complex matrices, vector calculus | builds on the matrix layer |
| later | complex numbers in polar form and on the plane; finance (time value of money, amortisation); interactive geometry; a programmable layer | order decided when they are reached |

Order inside a release is free; a feature is shipped when it is exact and tested, and the release number is spent on a set of them, not on
a date. If a feature turns out unreliable it moves to a later release instead of going out half done.

## Each feature starts with a short note

Before the code, a note in `design.md` (or its own file when it is large): what the user types, what the answer card shows, the limits (size,
time), the oracle the tests use, and what it will say when it cannot answer. The owner's earlier rule holds: Mantissa's own names,
wording, icons and code; ideas and conventions of other calculators are studied, never copied.
