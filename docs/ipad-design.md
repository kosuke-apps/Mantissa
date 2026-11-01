# Mantissa on iPad: design note

Status: built for 0.28.0, except what "Not built" below lists. It says, screen by screen, what the iPad layout is and why, what
stays as it is on the iPhone, and what went wrong on the way. The aim is an iPad app, not the iPhone screen stretched: the same
`.ipa` runs on both, the iPhone layout does not change, and the extra room is spent on a bigger workspace, a bigger two-part
keyboard and a persistent history.

## What the iPad has that the iPhone does not

| | iPhone (today) | iPad |
|---|---|---|
| Width | 402 pt, portrait only | 744 pt (mini) to 1376 pt (Pro 13-inch); any orientation; windows from about 320 pt (Slide Over) up |
| The answer and the graph | stacked; the graph is 320 pt tall and its lower part is behind the keyboard (the page scrolls) | side by side, or stacked with room to spare |
| The keyboard | one page of 6 × 4 keys at a time, switched by tabs | two pages at once: the basic keys always in view |
| Input | touch | touch, hardware keyboard, trackpad or mouse |

## Rules

1. **The layout follows the width the calculator is given, not the device.** A `GeometryReader` at the root measures it, and one
   value, `WindowMetrics` (its `kind` is a `WindowClass`), is put into the environment: `compact` (under 640 pt), `regular` (640 to under 900 pt) or `wide` (900 pt and
   more). Size classes are not used: they say "compact" for different widths on different iPads, and the app also runs in Split
   View, Slide Over, Stage Manager windows and a resizable window on the Mac. The same rule makes an iPad in a narrow Split View
   look like an iPhone.
2. **`compact` is today's layout, untouched.** Every view keeps its iPhone code path; the iPad layouts are new views chosen
   above it. A check at each step compares iPhone screenshots before and after (same simulator, same inputs, a pixel difference
   of zero).
3. **iPhone stays portrait.** `UISupportedInterfaceOrientations` is unchanged; a separate `UISupportedInterfaceOrientations~ipad`
   lists all four, which Split View requires (no `UIRequiresFullScreen`).
4. **One window.** The app keeps a single scene. `AppModel` lives in the `App` struct, so two windows of a multi-scene app would
   show one editor twice; multiple windows would need a model per scene and a shared history store, and nothing here asks for them.

Expected widths of the window, from the full width of each iPad (to be measured, since the system chooses the split widths):

| iPad | Full screen, portrait | Full screen, landscape | Split View, landscape, one third | one half | two thirds |
|---|---|---|---|---|---|
| mini (744 × 1133 pt) | 744: `regular` | 1133: `wide` | about 378: `compact` | about 566: `compact` | about 755: `regular` |
| Pro 13-inch (1032 × 1376 pt) | 1032: `wide` | 1376: `wide` | about 460: `compact` | about 690: `regular` | about 920: `wide` |

## The calculator screen

The top bar, the formula input and the answer cards are the same views as on the iPhone, at a larger size (formula 38 pt instead
of 30, answer 44 instead of 34, from the text size setting as now, so Dynamic Type still scales them).

```text
regular (portrait, 640 to 900 pt)           wide, with the history column (1180 pt and more)
┌───────────────────────────────┐           ┌─────────────┬─────────────────────────────┐
│ RAD                    ⟲   ⚙  │           │ History     │ RAD                    ⚙   │
│ x² − 5x + 6 = 0           ⊗   │           │             │ x² − 5x + 6 = 0           ⊗ │
│ ┌───────────────────────────┐ │           │ x²−5x+6=0   │ ┌──────────┐ ┌────────────┐ │
│ │ x = 2          x = 3      │ │           │ ∫ x² dx     │ │ x = 2    │ │   graph    │ │
│ └───────────────────────────┘ │           │ …           │ │ x = 3    │ │            │ │
│ ┌───────────────────────────┐ │           │             │ └──────────┘ └────────────┘ │
│ │          graph            │ │           │             ├─────────────────────────────┤
│ └───────────────────────────┘ │           │             │ abc ← → ↵ AC ⌫              │
│ abc  ←  →  ↵  AC  ⌫           │           │             │ [Func|Trig|Calc|Matrix] Basic│
│ [Func|Trig|Calc|Matrix]  Basic│           │             │  keys             keys      │
│  keys                  keys   │           └─────────────┴─────────────────────────────┘
└───────────────────────────────┘
```

- **Workspace.** `regular`: the formula, then the answer, then the graph, stacked; the graph takes the rest of the height, so it
  is no longer cut off by the keyboard (the iPhone graph has a fixed 320 pt and sits partly behind the keys). `wide`: the formula
  across the top, then the answer cards on the left and the graph on the right, side by side. If there is no graph the answer
  uses the width, to a limit of 720 pt, left-aligned as on the iPhone. A matrix or a long answer scrolls sideways inside its
  card, as now. The side-by-side arrangement applies only when each column would be at least 380 pt; at a large text size it
  falls back to the stacked one.
- **Why not a bigger iPhone screen.** The graph is the part the iPhone has to compromise on most, and the iPad can show it whole next
  to the answer, as the point of a calculator that draws.
- **The expand button of the graph** (full-screen cover) is hidden in `regular` and `wide`: the graph is already large. It stays in
  `compact`.
- **History** is a column on the left when the window is at least 1180 pt wide and 600 pt tall (the 11-inch and the 13-inch in landscape;
  not the mini in landscape at 1133 pt, nor two thirds of a 13-inch): about 300 pt wide, the same list (days, stars, "Clear history")
  without the sheet's Done button, and tapping an entry puts it into the calculator as now. Everywhere else on the iPad (`regular`, and
  `wide` below 1180 pt) it is a popover from the clock button; it adapts to a sheet in `compact` (`presentationCompactAdaptation`), as the
  sheet it is today. The list code is split from its `NavigationStack` and its `dismiss` so that one list serves all three. This is the
  one piece of the plan that adds a persistent area; if it proves fiddly it can be dropped to the popover without touching the rest.
- **Settings** is a popover from the gear in `regular` and `wide`, a sheet in `compact` (as now).
- **Dividers and spacing** use the iPhone's values, scaled by `WindowMetrics` (20 pt side margins on the iPhone, 28 on the iPad).

## The keyboard

- **Two pages at once (`regular`, `wide`).** The right-hand block is always the Basic page (digits and operators); the left-hand block
  has the tabs Functions, Trig, Calculus and Matrix. Nobody has to switch to the digits to fill in a matrix or a limit, which is the
  main cost of the iPhone keyboard. Each block is 6 columns by 4 rows with the iPhone keys, so the key code is shared and only the
  frame differs. The control row (`abc`, arrows, `↵`, AC, delete) spans both blocks above them.
- **Bigger keys.** Row height is 54 pt on the iPhone; on the iPad it is 8.5 % of the window height, kept between 46 and 68 pt, so a
  short window (Stage Manager, Split View) gets smaller keys and a workspace that can still be read. The keyboard is at most 900 pt
  wide and centred, so the keys do not become wide slabs on a 13-inch in landscape.
- **The Matrix page, wider.** With the digits already at the right, the Matrix page on the iPad drops its own number pad and shows
  the operations as keys instead of hold-and-slide alternatives: matrix 2×2, 3×3, 4×4 and vector (3 or 4 entries), add and remove a
  row and a column, determinant, trace, rank, row echelon form, inverse, transpose, dot, cross, length, eigenvalues, eigenvectors,
  the identity, `|□|`, comma, brackets and the power key. Keys that have alternatives still have them. The iPhone's Matrix page is
  as it is.
- **Letters (`abc`).** The letters keyboard takes the whole keyboard width as one block (10 columns for Latin, 8 for Greek and for
  symbols), with its own tabs, as on the iPhone; `123` returns. The height does not change when it opens (the rule from 0.26).
- **Hold and slide.** The popup row above a key is placed with the width of the window. Today it asks `UIScreen.main.bounds`, which
  is the whole screen and would be wrong in Split View, in a window on the Mac and on a rotated iPad: it will use the keyboard's
  own width. With a pointer it works as a press-hold-drag; hovering over a key shows a highlight, and the popup follows the pointer.
- **Feedback.** The iPad has no Taptic Engine, so the ticks of the hold-and-slide and the key click are silent there and on the
  Mac; the highlighted cell in the popup and the pressed key face are the only feedback, and they already exist. Nothing is added.

## Hardware keyboard

A focusable root view receives key presses (`onKeyPress`, `HardwareKeys.swift`); there is no text field, so no software keyboard
opens. Focus is taken again when a sheet or a popover closes. Menu commands (`commands`, in `MantissaApp.swift`) list the shortcuts in
the overlay shown by holding ⌘ on the iPad and in the menu bar on the Mac.

Built:

| Keys | Does |
|---|---|
| digits, letters, `.`, `,`, `;`, `+`, `=`, `<`, `>`, `!`, `%`, `^`, `/` | types the character (a slash and a caret are the characters, not a fraction or a power to fill in: `1/2+3` must not become `1/(2+3)`) |
| `-`, `*` | types − and × |
| `(`, `)` | the brackets: `(` opens a pair, `)` steps out of it; after the letters of a function's name (`cos`) it makes that function |
| `[`, `]`, `{`, `}`, `\|` | single characters |
| π, θ and other Greek letters, `°`, `∞`, `≤`, `≥`, `≠`, `²`, `³` | typed when the keyboard makes them (Option-P is π on a US keyboard) |
| Return | new line; in a matrix, the first cell of the next row |
| Tab, Shift-Tab | in a matrix, the next or the previous cell (from inside a fraction in a cell too); outside a matrix left to the system |
| ← → | move through the formula |
| Delete | delete one step (it repeats when held) |
| ⌘C | copy the answer as text, or what is typed when there is no answer |
| ⌘V | paste a formula |
| ⌘Y, ⌘, | history (a popover or sheet; with the history column it is already there), settings |

Anything else is ignored (it is left to the system): space, other scripts such as kana from an input method, Command and Control
combinations that are not listed.

Not built: ⌘1 … ⌘4 and ⌘L (the key pages and the letters keyboard), ⌘+, ⌘− and ⌘0 (zoom the graph), ⌘⌫ and Esc (clear), ⌥⌘C (copy the
decimal), ↑ and ↓ (the editor has no vertical movement between lines or matrix rows yet), undo and redo (the editor keeps no
history of edits). Drag and drop: the app has nothing to drag today, so none is added.

## Pointer (not built in 0.28.0)

The plan, if it is built:

- Hover states on the keys, the page tabs and the two small graph buttons (`hoverEffect`).
- The answer's context menu (copy, use as input) opens on right-click as it does on a long press.
- The graph: a pinch on a trackpad zooms (the existing `MagnifyGesture`), a drag with the pointer pans, and a hover reads the value of
  the nearest curve at the pointer, as a held finger does now (`onContinuousHover`). Two-finger scrolling to pan is not supported by
  SwiftUI gestures that the iOS 17 target can use, as far as is known (to be confirmed); it would need a `UIPanGestureRecognizer` with a scroll mask, and is left out unless it turns out to matter.

## Split View, Slide Over, Stage Manager, other sizes

- The width decides (rule 1), so every size has a layout: Slide Over and a third of the screen are the iPhone layout, half a
  13-inch is `regular`, two thirds `wide`. The size of the window can change while the app runs; the editor state, the cursor and the
  answer are in `AppModel` and survive a change of layout.
- A window shorter than about 520 pt (a small Stage Manager window) keeps its layout, with the smallest keys; the workspace scrolls.
- The app asks for a minimum window size of 320 × 480 pt (`UIWindowScene.sizeRestrictions`), so the window cannot be made too small to
  use; this matters on the Mac. The iPad simulator of iOS 27 stopped at 375 pt wide.
- **Window controls.** An iPad window that is not the size of the screen has the three window dots over its top-left corner, on the
  content. The top bar (and the history column's title) start 64 pt further right then (`windowControlsInset`, from comparing the
  scene's size with the screen's; 0 on an iPhone and on a Mac, which has a title bar of its own). Found by looking at a resized
  window: the angle-unit button was under the dots.
- **Larger text.** From the accessibility sizes up the history column is dropped (it would be too narrow to read) and the workspace
  scrolls as on the iPhone, so that nothing is left behind the keyboard.
- **The answer's height.** In the stacked layout the answer is as tall as it is, up to 45 % of the workspace, and scrolls beyond that
  (`AnswerBox`); `ViewThatFits` had made it as tall as the space it was offered and left a gap round it.

### What was measured

The simulator of iOS 27 has no Split View in the sense of the older iPadOS; windows are resized freely (windowed apps, with a corner
handle), and that is how the widths below were made: a drag of the handle, then the width measured from a screenshot. They are near,
not equal to, a third, a half and two thirds.

| iPad Pro 13-inch simulator | Width (pt) | Layout |
|---|---|---|
| portrait, full screen | 1032 | `wide`, answer and graph side by side |
| portrait window | 678 | `regular`, answer above the graph, two key blocks |
| portrait window | 518 | `compact` |
| portrait window, the narrowest allowed | 375 | `compact` |
| landscape, full screen | 1376 | `wide` with the history column |
| landscape window | 876 | `regular` |
| landscape window | 692 | `regular` |
| landscape window | 470 | `compact` |

The iPad mini simulator (744 × 1133 pt) was looked at full screen in portrait (`regular`) and landscape (`wide`).

## Risks, and how they are met

| Risk | Where it shows | Plan |
|---|---|---|
| `UIScreen.main.bounds` in the key popup | wrong side for the popup row in Split View, in a Mac window | measure the keyboard's own width (done) |
| Orientation list is portrait only | iPad stuck in portrait, Split View refused | `~ipad` key with all four; iPhone key unchanged |
| The iPhone layout changes by accident | regression on the phone | the `compact` path is the old code; before/after screenshots compared by pixel difference |
| A hardware keyboard in a Japanese input mode | kana characters arrive from `onKeyPress` and the parser rejects them | only ASCII and a few mathematical characters are typed and the rest are ignored (unit-tested); **not tried with a Japanese input source** |
| Focus is lost after a popover or a sheet closes | typing stops working until a tap | the root takes focus again when a presentation ends (written; **not tried**) |
| Two sizes of keyboard in one codebase | duplicated key code | one `KeyView` and one layout table; only the grid frame and the page set differ by `WindowMetrics` |
| Dynamic Type at the largest sizes | columns too narrow | side by side only when each column is 380 pt or more; otherwise stacked, and the workspace scrolls |
| Paste: `UIPasteboard` asks permission on the iPhone | prompt on first paste, may differ on the Mac | to be seen on each; the paste check (`canPaste`) is not called while drawing |
| `LazyVGrid`-style layout on a very wide window | oversized keys | cap the keyboard at 900 pt and centre it |
| Mac (Designed for iPad), see below | | |

### The Mac (Designed for iPad)

Run from Xcode with the "Mac (Designed for iPad)" destination on an Apple silicon Mac. The release stays an unsigned `.ipa`, and there is
no supported way to install that on a Mac, so no Mac download is promised; the Mac run is a test.

- Things the Mac does not have, and what the app does without them: **haptics** (`UIImpactFeedbackGenerator`,
  `UISelectionFeedbackGenerator`: calls do nothing; the visual feedback stays), **Dynamic Type** (the app keeps its default sizes),
  motion sensors and location (the app does not use them), the touch-only gestures (replaced by pointer ones above).
- Things that behave differently (expected, each to be checked in the run): the window can be resized and then needs the minimum size above; the menu bar shows the app's
  commands, so every shortcut in the table must be in `commands` or it will not appear; a Mac keyboard may be in a Japanese input
  mode (see the table); the first paste may ask for permission differently; sheets and popovers look like Mac ones.
- The history file and the settings are in the app's own container, as on the iPad; nothing leaves the machine.
- To be written down after the run: what was missing or different, in the release notes (only what was checked).

## Order of work (all of it done for 0.28.0 except the Mac run and the pointer; see "Not built")

1. Plumbing: `TARGETED_DEVICE_FAMILY: "1,2"`, the `~ipad` orientations, `WindowMetrics` from the root width, the popup width fix, the History and
   Settings presentation. The iPhone screenshots must not change. The first iPad build can already be run.
2. The workspace: `regular` stacked, `wide` side by side, the full-height graph, the hidden expand button.
3. The two-block keyboard, the Matrix page, the key sizes; the letters keyboard across the width.
4. The history column.
5. Hardware keyboard, menu commands, hover and graph pointer input.
6. Checks: iPad Pro 13-inch and iPad mini simulators, portrait and landscape, Split View at a third, a half and two thirds, a larger
   text size; the Mac (Designed for iPad) destination; the iPhone before-and-after comparison; the sanitizer, leaks and growth checks of
   the release procedure.
7. README screenshots from the iPad Pro 13-inch simulator (light, 9:41, demo data, a dedicated simulator); version 0.28.0; release notes
   that say only what was checked (the iPad simulator and the Mac run; no real iPad has been used unless one is).

## Not in this change

- More than one window; a keyboard that remembers its pages; undo; ↑ and ↓ movement; Apple Pencil input.
- Anything that changes what the engine computes: this is layout and input only, so the engine tests are not touched.
