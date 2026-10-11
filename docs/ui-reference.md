# The calculator being followed

Mantissa follows the calculator of the Photomath app as it was before its solving moved to a server. This note records
what that calculator looks like and how it behaves, as far as it could be read from public material, and what
Mantissa keeps, drops or decides differently. The look of a screen is the reference; the artwork, icons, name and
wording are not copied.

## Sources

- Google, *Photomath Help*, "Use Math keyboard to input a problem"
  (support.google.com/photomath/answer/14335006): the text and the animated screenshots of the keyboard. These show
  a recent Android build, whose calculator screen is the same one the author knew.
- Google, *Photomath Help*, "Supported Math Content" (answer/14328427) and "Does Photomath need the Internet?"
  (answer/14328125): the list of what it solves, and the statement that it now needs a connection because solving
  runs in the cloud.
- The App Store page of 6 January 2022 (Wayback Machine): marketing images only (camera screens), no calculator.
- ScreensDesign's breakdown of the app (a video summary): notes that the graph and the history exist and are simple.

Not seen directly: the graph screen and the history screen. Their descriptions below come from text, not pictures.

## The calculator screen

```text
┌──────────────────────────────────┐
│ ←              Calculator        │  top bar
├──────────────────────────────────┤
│ 2x + 3 = 5                    ⊗  │  input: typeset, several lines for a system; clear button
│ ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈ │
│ ▌x = 1                           │  live answer, a red bar at its left
│                                  │  or, for input it cannot use:  ⚠ Please enter a complete math problem…
│          [ Show Solution → ]     │
├──────────────────────────────────┤
│ abc   ⟲    ←    →    ↵    ⌫      │  letters, history, cursor left/right, new line, delete
│ (+ − × ÷) (f(x) e log ln) (sin cos tan cot) (lim dx ∫ Σ ∞)   chips: the pages of the keyboard
│ (□)  >   7  8  9  ÷              │
│ □/□  √□  4  5  6  ×              │  six columns, four rows
│ □²   x   1  2  3  −              │
│ π    %   0  ,  =  +              │
└──────────────────────────────────┘
```

- **Input** is typeset as you type: stacked fractions, radical signs with a bar, raised exponents. An empty slot is a
  dotted box, the cursor is a thin red line, and the placeholder reads "Type a math problem…". A clear button appears
  when there is input. Functions are typed as a name with a slot in parentheses: `arctan(□)`, `cosh(□)`, `sign(−5)`;
  a derivative is `d/dx` stacked over the slot.
- **The answer is live.** It updates as the input becomes complete: `2x + 3 = 5` shows `x = 1`; `5 ≠ 1` shows `True`;
  `x + y = 5` alone shows "Sorry, we can't solve this one just yet…". A system is one equation per line (the `↵` key).
- **Keys** with a small dot in the bottom-right corner have alternatives on a long press, shown in a small popup above
  the key: the fraction key offers a mixed number, the square-root key offers the cube root and the n-th root, the
  power key offers the common exponents.
- **Pages** (the four chips above the grid): arithmetic (the grid above); `f(x) e log ln` (functions, e, logarithms);
  `sin cos tan cot` (trigonometry, below); `lim dx ∫ Σ ∞` (limits, derivatives, integrals, sums). `abc` swaps the whole
  keyboard for letters.
- **Trigonometry page**: `rad` and a degree key `□°`; `sin cos tan cot sec csc`, the same with `a` in front for the
  inverses, `sinh cosh tanh coth`, `asinh acosh atanh acoth`. **Radians are the default**: `cos(30)` is radians and
  `cos(30°)` is degrees; the degree sign is on this page.
- **Typing rules stated in the help**: square brackets and braces are entered as parentheses; `-3^2` is −9 and `(-3)^2` is
  9; a percentage is a plain number (`10%` is 0.1), so subtracting 10% is written `100 - (10% × 100)`.
- **Look**: grays with one red accent, flat and minimal; a rounded keyboard panel; the primary button is a red pill.

## The other screens

- **History**: opened from the clock key on the keyboard (and from the camera screen); earlier problems can be
  bookmarked. Seen only as an icon; presumably a list of earlier inputs with their answers, where tapping one reopens
  it in the calculator.
- **Graph**: shown with the answer when the problem is a function or an equation in x and y, an interactive graph
  (the breakdown calls it "interactive" and the help lists roots, extrema, inflection points, asymptotes and
  intercepts among what it finds). Presumably it zooms and pans and marks those points so that they can be tapped.
- **Solving steps and methods**: a card per method with "Show Solving Steps", then each step with an explanation.

## What Mantissa keeps, drops and decides

| Keep | Drop | Decide |
|---|---|---|
| The calculator screen as above, its keyboard, its pages and long-press alternatives | The camera and everything that needs it | The accent colour and typefaces (own, not copied) |
| Live typeset input and a live answer | "Show Solution", methods, solving steps, explanations | How the exact and decimal forms of an answer are shown together (not visible in the material) |
| Systems on separate lines; `True` / `False` for comparisons | Ads, accounts, tracking, any network access | The angle setting: radians by default as above; a switch for degrees is an addition |
| History and bookmarks, graphs with their points of interest | Textbook content, word problems, animations | How much of "Supported Math Content" to cover and in what order (see below) |

## How much to cover

Photomath's list is very long: complex numbers, matrices, vectors, geometry, sequences, differential equations, polar
coordinates, power series. The author uses the scientific calculator, the solving of equations and expressions, graphs,
history and offline use, so that is the scope; the rest is not planned. Order of work: arithmetic and functions
(done) → the editor and the screen → history → graphs → equations, inequalities and systems → derivatives, integrals,
limits, sums → whatever the author misses. (Complex numbers came first, because quadratics need them.)
