# The screens

How Mantissa looks and behaves on the phone, and what it leaves out. The engine behind it is described in `design.md`.

## Scope

Mantissa is the calculator its author wanted on the phone: a scientific calculator, a function grapher and an equation solver,
with a history, working entirely offline. It has no camera, no steps and explanations, no ads, no accounts and no network access
of any kind. Order of work: arithmetic and functions → the editor and the screen → history → graphs → equations, inequalities and
systems → derivatives, integrals, limits, sums → whatever the author misses. Complex numbers came early, because quadratics
need them. Matrices, vectors, geometry, differential equations and polar coordinates are not planned.

## The calculator screen

```text
┌──────────────────────────────────┐
│ RAD                       ⟲  ⚙  │  top bar: angle unit (tap to switch), history, settings
├──────────────────────────────────┤
│ 2x + 3 = 5                    ⊗  │  input: typeset, one equation to a line; clear button
│ ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ │
│ ┌──────────────────────────────┐ │
│ │ x = 1                        │ │  the answer, live, on a soft card
│ └──────────────────────────────┘ │  (or "This isn't a complete problem yet.")
├──────────────────────────────────┤
│ abc   ←    →    ↵   AC   ⌫      │  letters, cursor, new line, clear all, delete
│ [ Basic | Functions | Trig | Calculus | Matrix ]   the pages of the keyboard
│ (□)  >    7  8  9  ÷             │
│ □/□  √□   4  5  6  ×             │  six columns, four rows
│ □ⁿ   x    1  2  3  −             │
│ π    %    0  .  =  +             │
└──────────────────────────────────┘
```

- **Input** is typeset as you type: stacked fractions, radical signs with a bar, raised exponents. An empty slot is a dotted
  box and the cursor is a thin line in the accent colour. A clear button appears when there is input; tap the formula to put
  the cursor there. Functions are typed as a name with a slot in parentheses (`atan(□)`, `cosh(□)`); a derivative is `d/dx`
  stacked over the slot.
- **The answer is live.** It updates as the input becomes complete: `2x + 3 = 5` shows `x = 1`; `5 ≠ 1` shows `True`. A system is
  one equation per line (the `↵` key). An equation with several letters is solved for one of them, and a row of letters above
  the answer solves it for another.
- **Keys with a dot** in the bottom-right corner have alternatives. Hold the key for a moment: they appear in a row above it,
  the finger slides over the one wanted (a tick is felt on each) and lets go. Letting go on the key itself is the key's own
  action, letting go below it chooses nothing. The square-root key offers the cube root and the n-th root, the power key the
  common exponents, the parentheses key a single `(` or `)` that can go round what is already typed, and `x` offers other
  letters. VoiceOver has the alternatives as actions.
- **Pages**: Basic (the grid above), Functions (logarithms, `e`, `|x|`, `nCr`, `mod`, `gcd`, rounding), Trig (sines, cosines,
  tangents, their inverses and hyperbolic forms, and the degree sign), Calculus (limits, derivatives, integrals, sums, ∞) and
  Matrix (a matrix or vector with cells to fill in, rows and columns added or removed, and the number pad, so that a matrix is
  filled in without leaving the page). `abc` swaps the keyboard for letters (Latin with a number row and shift, Greek, symbols),
  and the same place shows `123` to swap back; the letters keyboard has its own tabs and four rows on every page, so the
  keyboard is as tall as with the maths pages and the formula above it does not move.
- **Angles**: radians are the default; `cos(30)` is radians and `cos(30°)` is degrees whatever the setting says.
- **Typing rules**: square brackets and braces are read as parentheses; `-3^2` is −9 and `(-3)^2` is 9; a percentage is a plain
  number (`10%` is 0.1).
- **Look**: system greys and one teal accent, flat; a rounded keyboard panel; the answer on a soft card. The app icon is a radical sign
  over the dotted empty box that marks an unfilled slot in the editor.

## The other screens

- **History**: opened from the clock in the top bar. Earlier problems with their answers, newest first, grouped by day; the
  star keeps a problem; tapping one puts it back in the calculator.
- **Graph**: shown under the answer when the input is a function of x, or an equation or inequality in x and y. It marks roots,
  extrema, intercepts and crossings (tap one to read it); tapping a curve reads its coordinates and holding then dragging
  follows it; it pans and zooms, and opens full screen.
- **Settings**: angle unit, number of digits, language (system, English, 日本語), and a short About.
