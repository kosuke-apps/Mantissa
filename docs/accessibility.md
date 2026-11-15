# Accessibility

What Mantissa does for VoiceOver, larger text, and people who cannot tap small targets or tell colours apart, and how it is checked.

## What is done (1.0.0)

- **Formulas are spoken, not spelled.** `SpokenMath` turns a typeset formula into words: "x squared minus 5 x plus 6 equals 0", a fraction as
  "3 over 2" (or "the fraction … over …, end of fraction" when a part is longer), a root as "square root of 6", a matrix row by row, an
  integral, sum, limit or derivative as a sentence. The words are in the String Catalog with numbered placeholders, so Japanese puts the
  parts in its own order ("3分の2", "6の平方根"). A formula is one accessibility element (an accessibility representation of a
  `Text`); the glyphs are not separate elements. `plainText` is still what copying a formula gives.
- **The graph can be read.** It has a label and a summary (how many curves, the window it shows, the roots, extremes and intersections
  marked), an Audio Graph of its curves (VoiceOver offers it in the rotor and plays it as a tone; values outside the window are held at
  its edge), and actions to zoom in, zoom out and move it left, right, up and down. With "Differentiate Without Color" on, the first four
  curves are solid, dashed, dotted and dash-and-dot.
- **Targets are at least 44 pt.** The keyboard's control keys (arrows, new line, delete, AC, `abc`) answer over the whole cell, and the
  History and Settings icons have 44 pt targets without moving.
- **Text scales.** Formula and answer sizes follow the text size setting (`@ScaledMetric`); at the accessibility sizes the iPad drops
  its history column and the workspace scrolls, so nothing is left behind the keyboard.
- Keys, buttons and tabs have labels (the keyboard has spoken names for every symbol key).

## How it is checked

- `AppTests/SpokenMathTests.swift` and `GraphAccessibilityTests.swift`: the words in English and Japanese, the graph summary, the actions.
- `AppUITests` (the `MantissaUITests` scheme, `xcodebuild test -scheme MantissaUITests …`): `AccessibilityAuditTests` runs Xcode's accessibility audit on
  seven screens and prints what it finds; `AccessibilityLabelTests` reads the accessibility tree for the formula, the answer, the graph and a
  matrix. Run them on a simulator; they use the debug launch argument `-MantissaInput`.
- What the audit still lists: contrast on the system's own Done and Clear history buttons and section headers, and "text clipped" and
  "Dynamic Type partially unsupported" on typeset formulas, which the screenshots at the accessibility text sizes do not bear out (the
  formulas do grow). They are listed so that a change that adds a real one stands out.

## Not covered

VoiceOver speaking the result has not been tried on a device: the tests read the same tree VoiceOver reads but do not speak it, so the
wording (the Japanese in particular) is unheard, and a report from someone who uses VoiceOver is welcome. Switch Control, Voice Control and
Full Keyboard Access have not been tried.
