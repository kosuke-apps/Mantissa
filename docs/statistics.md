# Statistics and probability

Design note for the 1.1 line of `docs/roadmap.md`, written 2026-11-15 before any code, and edited as the slices were built: the last section says
what was delivered, how it was checked, and what was left out.

The aim is what a statistics calculator does (one- and two-variable statistics, regressions, the usual distributions), with Mantissa's own
rules: **exact when the answer is exact** (the mean of fractions is a fraction, a standard deviation is a root, a binomial probability is a
fraction), at least 12 correct digits otherwise, and a typed function name for everything, so that the first screen stays as it is.

## What the user types

Data is not a new kind of value in this release (lists as values come with definitions, `docs/roadmap.md` 1.5). It is given in one of three
ways, all of which already exist in the editor:

1. **As arguments:** `mean(2, 4, 4, 4, 5, 5, 7, 9)`, up to 100 numbers. The quick way for a handful of values.
2. **As a vector:** a matrix with one column (or one row), `mean([[2],[4],[4],[4],[5],[5],[7],[9]])`, or a letter that stands for one
   (`D = [[…]]` on a line of its own, then `mean(D)`). The matrix editor is the data editor: Return goes to the next row, Tab to the next
   cell, and the Statistics and Matrix pages have the keys that add and remove rows. In a column of data or a table of two columns Return after a
   value starts a new row, as in a spreadsheet (a stray Return in the empty row adds none), up to 200 rows; a long column is set smaller.
3. **As a table:** a matrix with two columns, `linreg([[1,2],[2,4],[3,5]])`, for two variables (x in the first column, y in the second), or
   two vectors, `linreg(X, Y)`.

A one-variable function also takes **values and frequencies** as two vectors, `mean(V, F)`: the frequencies are whole numbers, and
`mean(V, F)` is the mean of the data in which each value is written as often as its frequency says (nothing is expanded; the formulas
use the frequencies).

**Size.** The matrix is limited to 10 columns and now to 200 rows (it was 10 × 10; `Matrix.maxDimension` is split into rows and columns, and
everything that needs a square matrix keeps its limit of 10). A data set is at most 200 values (or 200 value and frequency pairs).

**Values.** Data are real numbers, exact or not (`1/3`, `0.25`, `√2`). Order is decided by their decimal values; equality is exact. A data
set with a letter in it is not supported ("not supported yet"), as everywhere else.

## Functions

One variable (data as above). A function that takes a parameter besides the data takes the data as a vector, first: `quartile(D, 1)`.

| Function | Meaning |
|---|---|
| `count`, `total`, `sumsq` | n, Σx, Σx² |
| `mean`, `median`, `mode` | the mean; the middle value (the mean of the middle two when n is even); the most frequent values, ascending, as a column (see Conventions) |
| `min`, `max`, `range`, `sort` | extend the existing `min` and `max` to vectors; `range` is max − min; `sort(D)` is the data in ascending order, as a column |
| `variance`, `stdev` | the sample variance and standard deviation (divide by n − 1); needs n ≥ 2 |
| `varp`, `stdevp` | the population ones (divide by n) |
| `quartile(D, k)`, `iqr` | the k-th quartile, k = 1, 2, 3 (k = 2 is the median); Q₃ − Q₁ |
| `percentile(D, p)` | the p-th percentile, 0 ≤ p ≤ 100, by linear interpolation (see Conventions) |

Two variables (a table, or X and Y of the same length, n ≥ 2):

| Function | Meaning |
|---|---|
| `cov`, `covp` | the sample (n − 1) and the population (n) covariance |
| `corr` | Pearson's r = S_xy / √(S_xx S_yy), exact (a root of a fraction) |
| `slope`, `intercept` | a and b of the least-squares line y = a x + b |

Reports (a block of labelled values, only as the whole input, not inside a formula):

| Function | What it reports |
|---|---|
| `stats(D)` | n, Σx, Σx², x̄, sₓ, σₓ, min, Q₁, median, Q₃, max (and the mode when there is one) |
| `linreg(T)` | y = a x + b, a, b, r, r², n |
| `polyreg(T, d)` | the least-squares polynomial of degree d (2 to 6, and n > d): its equation, the coefficients, R², n |
| `expreg(T)`, `powreg(T)`, `logreg(T)` | y = a bˣ, y = a xᵇ, y = a + b ln x, fitted on the transformed data (x > 0 or y > 0 as each needs), with the coefficients and r² of the fit |

`T` is a table or `X, Y`. A report has no value of its own: to use a coefficient in a formula use `slope`, `intercept`, `corr`.

## Conventions (stated so that the tests and the answers agree)

- **Sample versus population.** `variance` and `stdev` divide by n − 1 (what a sample is for), `varp` and `stdevp` by n.
- **Quartiles** by the median of the halves: sort, split at the median, and when n is odd leave the median out of both halves; Q₁ and Q₃
  are the medians of the lower and the upper half. For n = 1 all three are the value. This is the usual textbook rule and the one a
  scientific calculator uses; spreadsheets and statistics packages differ (several conventions exist), so `percentile` is the one that
  interpolates: `percentile(D, p)` is the value at position 1 + (n − 1) p/100 of the sorted data, between neighbours linearly. They
  disagree on purpose (`percentile(D, 25)` need not equal `quartile(D, 1)`); the documentation says so next to the functions.
- **Mode.** The values with the highest frequency, ascending. With one distinct value that value is the mode; when every distinct value
  has the same frequency there is no mode (an error for `mode`, left out of `stats`).
- **Regression** is ordinary least squares in the stated coordinates; r is signed like the slope; r² of the transformed fit for `expreg`,
  `powreg` and `logreg` (what the other calculators report), and R² = 1 − SS_res/SS_tot for the polynomial.
- **Rounding** never happens inside the exact value; the digits setting only shortens the decimal that is shown.

## Exactness

Everything above with rational data is rational or a root of a rational (`stdev`, `corr`), computed with `Rational` and `Expr`, no `Double`.
The exponential, power and logarithmic regressions are exact expressions in `ln` and `exp` of the data, shown as a decimal first (the
exact form has a term for every datum; it is behind the exact/decimal switch like any long answer) and checked at 50 digits.

## Distributions

`pdf` is the density (or the probability of exactly k for a discrete one), `cdf` is P(X ≤ x), `inv` is the value q such that
P(X ≤ q) = p (for a discrete one, the smallest such whole number). The probability between a and b is `cdf(b) − cdf(a)` (a convention
chosen over a four-argument form, to keep the arguments in one order).

| Family | Functions | Exact? |
|---|---|---|
| binomial | `binompdf(n, p, k)`, `binomcdf(n, p, k)`, `binominv(n, p, q)` | yes, a fraction |
| Poisson | `poissonpdf(λ, k)`, `poissoncdf(λ, k)`, `poissoninv(λ, q)` | yes, e^−λ times a fraction |
| geometric | `geompdf(p, k)`, `geomcdf(p, k)`, `geominv(p, q)` | yes |
| hypergeometric | `hyperpdf(N, K, n, k)`, `hypercdf(N, K, n, k)` | yes, a fraction |
| uniform (continuous) | `uniformpdf(x, a, b)`, `uniformcdf`, `uniforminv(p, a, b)` | yes |
| exponential | `exponentialpdf(x, λ)`, `exponentialcdf`, `exponentialinv` | yes, with `exp` |
| normal | `normalpdf(x, μ, σ)`, `normalcdf(x, μ, σ)`, `normalinv(p, μ, σ)`; μ and σ may be left out (0 and 1) | pdf yes; cdf and inv through `erf` and `erfinv` (a closed form that is not a number, with its decimal) |
| Student's t | `tpdf(x, ν)`, `tcdf(x, ν)`, `tinv(p, ν)` | decimal; exact for the degrees of freedom whose cdf is a finite expression, where it is recognised |
| χ² | `chisqpdf(x, k)`, `chisqcdf(x, k)`, `chisqinv(p, k)` | decimal; exact for even k (a finite sum with `exp`) |
| F | `fpdf(x, d₁, d₂)`, `fcdf`, `finv(p, d₁, d₂)` | decimal; exact when d₁ and d₂ are even |

Discrete cdfs are sums of exact terms and are exact; the work is bounded (n, k and N at most 1000, beyond that "too large").

**Special functions behind them**, added to the engine as functions of `Expr` (they are useful on their own, and the other functions are
written with them): `erf`, `erfc`, `erfinv`, `gamma` (Γ, so that `x!` for a non-integer is Γ(x + 1)), `beta`, the regularised incomplete
gamma `gammainc(a, x)` and incomplete beta `betainc(x, a, b)`, and the inverses of these two. Each has its exact values (`erf(0)`, `Γ(n)`,
`Γ(n + ½)`, `betainc` with whole parameters is a finite sum) and a decimal value at the working precision, by series and continued
fractions with an error bound that is checked, not assumed, and gives up ("not supported yet") where it cannot be shown to be met.

## What an answer looks like

A single value (`mean(…)`, `binompdf(…)`) is an ordinary answer card. A **report** is a table of rows, a label and a value, each value
exact with its decimal as everywhere else (and following the exact/decimal switch); the labels are in the String Catalog, and copying
copies the lines as text (`mean = 5`). A **column** (`sort`, `mode` with several modes) is a vector.

## Graphs

A regression is drawn: the data as points and the fit as a curve (`PlotContent` gets points as well as curves; the tap-to-graph journey is
the same). `scatter(T)` draws the points alone. Histograms and box plots are the next step after this note's slices and are listed in
`docs/roadmap.md` under graphs.

## Errors it says in words

Fewer values than a function needs ("needs at least 2 values"), data of different lengths, a frequency that is not a whole number, no
mode, all x equal (a vertical line has no slope), a parameter out of range (p outside [0, 1], σ ≤ 0, k > n), too much data ("at most 200
values"). Input that contains a letter is "not supported yet".

## Checking

Oracles are independent of the Swift code: Python's `fractions.Fraction` for the exact statistics (written from the definitions, with
`statistics.mean`, `median`, `variance`, `pvariance`, `correlation` and `linear_regression` as a second opinion where they use the same
convention), `decimal` at 80 digits for the roots, logarithms and regressions, `math.comb` for the binomial family, `statistics.NormalDist`
(about 15 digits) and an own `decimal` implementation by a different method for `erf`, Γ and the incomplete functions; for whole degrees of
freedom the t, χ² and F cdfs have closed forms in exact fractions (sums of binomial and Poisson terms), which are the oracle for them.
Reference vectors are generated by `tools/gen_statistics_vectors.py` (fixed seed, byte-for-byte rerun, as for the other vectors). Beyond the
vectors: identities (cdf of `inv` is p, the cdfs rise from 0 to 1, pdf is the derivative of cdf by differences, a shifted and scaled data set
shifts and scales mean and standard deviation), the random-input tests (`RandomInputTests`) extended to the new functions, and the
sanitizers.

## What was built (branch `feat/statistics`, for 1.1.0)

| Slice | Delivered | Checked against |
|---|---|---|
| Descriptive statistics, the data editor | every function of the table above except `scatter`; `stats`; data as numbers, a vector, a table, or values and frequencies; matrices of up to 200 rows; the report answer card; the **Stats** keyboard page | Python `fractions` (54 one-variable and 24 two-variable data sets, each written in every form), by hand |
| Regression | `linreg`, `polyreg` (degree 1 to 6, exact), `expreg`, `powreg`, `logreg` (60 digits, decimals); the points and the fit drawn | `fractions` (the residual of a polynomial fit is exactly orthogonal to every power of x) and `decimal` at 100 digits |
| Exact distributions | binomial, Poisson, geometric, hypergeometric, uniform, exponential: `pdf`, `cdf`, `inv`; the **Probability** keyboard page | `fractions`, and `decimal` for the Poisson and exponential values; the discrete inverses against a brute-force search |
| Normal distribution | `erf`, `erfc`, `probit` as functions of the expression engine, to any number of digits, `normalpdf`, `normalcdf`, `normalinv`; they differentiate (d/dx `normalcdf(x)` is `normalpdf(x)`) and are drawn | an independent Taylor series in `decimal` (up to 800 digits), 45 digits, `erf` from 0.001 to 27.5, the quantile from 10⁻¹⁰⁰ to 1 − 10⁻¹² |
| t, χ² and F | `tpdf`/`tcdf`/`tinv`, `chisqpdf`/`chisqcdf`/`chisqinv`, `fpdf`/`fcdf`/`finv` with any positive degrees of freedom, on `gamma`, `beta`, `gammainc`, `gammaincinv`, `betainc` and `betaincinv` (Stirling's series with exact Bernoulli numbers, series and continued fractions on the side where each keeps its digits, Newton's method for the inverses) | Spouge's approximation of Γ, the power series of the incomplete functions summed termwise in `decimal`, and for whole degrees of freedom Abramowitz and Stegun 26.7.3 and 26.7.4; 40 to 45 digits |

How the design changed while it was built:

- **Exact only where exactness is not paid for in digits.** The cdf of χ² with even degrees of freedom is a finite sum, 1 − e^(−x/2)(1 + x/2 + …), and is given as one where P is not tiny; where P is tiny the
  difference of nearly equal numbers would lose as many digits as P has zeros (P(15, 0.0005) is 2·10⁻⁶²), so the call `gammainc(a, x)` is kept and worked out without the loss. The
  same holds for the beta function with a whole first parameter. A letter in the argument keeps the call, which is also what is drawn and differentiated.
- **The tail of the normal distribution** is written with `erfc` (the lower half as ½ erfc(−z/√2)), so that Φ(−30) has all its digits.
- **Limits that were set:** 200 rows and 10 columns in a matrix (a row of data holds 10), 100 numbers written out one by one, 2000 terms in an exact discrete sum, `gamma` of 100 000 at most,
  `erf` up to ±300, 1 000 000 terms of a series (then "too large").
- **Not built:** `scatter` (a plot of points alone), random numbers, hypothesis tests and confidence intervals, histograms and box plots, a typed list `{…}`. They stay on the list below.
- **Found on the way:** the inequality `exp(e^7!) ≤ 0.5` took over a minute to give up (it computed a logarithm to thousands of digits before the exponential turned out too large); the size
  of y ln b is now looked at first. The random-input test writes statistics and distributions now.

## Still to do in this line

Random numbers (they need an answer that stays the same when a history entry is opened again), hypothesis tests and confidence intervals (z, t and χ², one and two samples), histograms and
box plots (graph types), `scatter`, a typed list `{…}` and lists as values (`docs/roadmap.md` 1.5).
