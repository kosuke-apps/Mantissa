#!/usr/bin/env python3
"""Generate reference vectors for the statistics tests (docs/statistics.md).

Everything is computed with fractions.Fraction, from the definitions, so the numbers are exact and independent of the Swift code. Where
Python's statistics module uses the same convention (mean, median, variance, pvariance) it is asserted to agree, as a second opinion.
The seed is fixed: running this again must reproduce the committed file byte for byte.

    python3 tools/gen_statistics_vectors.py
"""

import json
import math
import random
import statistics
from decimal import Decimal, getcontext
from fractions import Fraction
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Tests" / "MantissaCoreTests" / "Resources"
rng = random.Random(20261115)


def text(value: Fraction) -> str:
    return str(value.numerator) if value.denominator == 1 else f"{value.numerator}/{value.denominator}"


def random_value(kind: str) -> str:
    """A number as the user would type it: a whole number, or a decimal with one or two places."""
    if kind == "int":
        return str(rng.randint(-20, 60))
    if kind == "small":
        return str(rng.randint(0, 6))  # many repeats, so that modes exist
    places = rng.choice([1, 2])
    whole = rng.randint(-5, 40)
    fraction = rng.randint(0, 10**places - 1)
    sign = "-" if whole < 0 or (whole == 0 and rng.random() < 0.2) else ""
    return f"{sign}{abs(whole)}.{fraction:0{places}d}"


def median(sorted_values):
    n = len(sorted_values)
    if n % 2:
        return sorted_values[n // 2]
    return (sorted_values[n // 2 - 1] + sorted_values[n // 2]) / 2


def quartiles(sorted_values):
    """The median of the halves, leaving the middle one out of both when n is odd; a single value is all three."""
    n = len(sorted_values)
    if n == 1:
        return sorted_values[0], sorted_values[0], sorted_values[0]
    lower = sorted_values[: n // 2]
    upper = sorted_values[n - n // 2 :]
    return median(lower), median(sorted_values), median(upper)


def percentile(sorted_values, p: Fraction) -> Fraction:
    """Linear interpolation at position (n - 1) p / 100, counted from zero."""
    n = len(sorted_values)
    position = Fraction(n - 1) * p / 100
    index = int(position // 1)
    fraction = position - index
    if fraction == 0 or index + 1 >= n:
        return sorted_values[index]
    return sorted_values[index] + fraction * (sorted_values[index + 1] - sorted_values[index])


def modes(sorted_values):
    counts = {}
    for value in sorted_values:
        counts[value] = counts.get(value, 0) + 1
    top = max(counts.values())
    winners = sorted(v for v, c in counts.items() if c == top)
    if len(winners) == len(counts) and len(counts) > 1:
        return None
    return winners


def one_variable_case(kind: str, size: int, with_frequencies: bool):
    texts = [random_value(kind) for _ in range(size)]
    frequencies = [rng.randint(0, 4) for _ in range(size)] if with_frequencies else None
    if frequencies is not None and sum(frequencies) == 0:
        frequencies[0] = 1
    values = [Fraction(t) for t in texts]
    expanded = []
    for index, value in enumerate(values):
        expanded += [value] * (frequencies[index] if frequencies else 1)
    expanded.sort()
    n = len(expanded)
    total = sum(expanded)
    mean = total / n
    squares = sum(v * v for v in expanded)
    ss = squares - total * total / n
    q1, q2, q3 = quartiles(expanded)
    assert q2 == median(expanded)
    assert median(expanded) == statistics.median(expanded)
    assert mean == statistics.mean(expanded)
    case = {
        "data": texts,
        "frequencies": frequencies,
        "count": n,
        "total": text(total),
        "sumsq": text(squares),
        "mean": text(mean),
        "median": text(q2),
        "q1": text(q1),
        "q3": text(q3),
        "min": text(expanded[0]),
        "max": text(expanded[-1]),
        "range": text(expanded[-1] - expanded[0]),
        "varp": text(ss / n),
        "modes": None if modes(expanded) is None else [text(m) for m in modes(expanded)],
        "percentiles": [
            {"p": str(p), "value": text(percentile(expanded, Fraction(p)))} for p in rng.sample(range(0, 101), 4)
        ],
    }
    if n >= 2:
        assert ss / (n - 1) == statistics.variance(expanded)
        assert ss / n == statistics.pvariance(expanded)
        case["variance"] = text(ss / (n - 1))
    return case


def two_variable_case(kind: str, size: int):
    while True:
        xs = [random_value(kind) for _ in range(size)]
        ys = [random_value(kind) for _ in range(size)]
        fx = [Fraction(t) for t in xs]
        fy = [Fraction(t) for t in ys]
        n = len(fx)
        mx = sum(fx) / n
        my = sum(fy) / n
        sxx = sum((x - mx) ** 2 for x in fx)
        syy = sum((y - my) ** 2 for y in fy)
        sxy = sum((x - mx) * (y - my) for x, y in zip(fx, fy))
        if sxx != 0 and syy != 0:
            break
    slope = sxy / sxx
    intercept = my - slope * mx
    return {
        "x": xs,
        "y": ys,
        "cov": text(sxy / (n - 1)),
        "covp": text(sxy / n),
        "slope": text(slope),
        "intercept": text(intercept),
        "determination": text(sxy * sxy / (sxx * syy)),
        "correlationSign": 0 if sxy == 0 else (1 if sxy > 0 else -1),
        "sxx": text(sxx),
        "syy": text(syy),
    }


one = []
for kind in ["int", "small", "decimal"]:
    for size in [1, 2, 3, 4, 5, 7, 8, 12, 25]:
        one.append(one_variable_case(kind, size, False))
        one.append(one_variable_case(kind, size, True))
two = []
for kind in ["int", "decimal"]:
    for size in [2, 3, 4, 6, 9, 15]:
        two.append(two_variable_case(kind, size))
        two.append(two_variable_case(kind, size))

def solve(matrix, vector):
    """Gaussian elimination in fractions, written here and not shared with the Swift code (which inverts the matrix)."""
    n = len(vector)
    rows = [list(matrix[i]) + [vector[i]] for i in range(n)]
    for column in range(n):
        pivot = next(r for r in range(column, n) if rows[r][column] != 0)
        rows[column], rows[pivot] = rows[pivot], rows[column]
        rows[column] = [v / rows[column][column] for v in rows[column]]
        for r in range(n):
            if r != column and rows[r][column] != 0:
                factor = rows[r][column]
                rows[r] = [a - factor * b for a, b in zip(rows[r], rows[column])]
    return [rows[i][n] for i in range(n)]


def polynomial_case(degree: int, size: int, kind: str):
    while True:
        xs = [random_value(kind) for _ in range(size)]
        ys = [random_value(kind) for _ in range(size)]
        fx = [Fraction(t) for t in xs]
        fy = [Fraction(t) for t in ys]
        if len(set(fx)) > degree:
            break
    m = degree + 1
    normal = [[sum(x ** (i + j) for x in fx) for j in range(m)] for i in range(m)]
    rhs = [sum(x**i * y for x, y in zip(fx, fy)) for i in range(m)]
    coefficients = solve(normal, rhs)
    # The residual is orthogonal to every power of x: the defining property of the least-squares fit, checked exactly.
    residual = [y - sum(c * x**k for k, c in enumerate(coefficients)) for x, y in zip(fx, fy)]
    for i in range(m):
        assert sum(r * x**i for r, x in zip(residual, fx)) == 0
    my = sum(fy) / len(fy)
    ss_tot = sum((y - my) ** 2 for y in fy)
    determination = None if ss_tot == 0 else 1 - sum(r * r for r in residual) / ss_tot
    return {
        "x": xs,
        "y": ys,
        "degree": degree,
        "coefficients": [text(c) for c in coefficients],
        "determination": None if determination is None else text(determination),
    }


getcontext().prec = 100


def decimal_line(us, vs):
    """The least-squares line in decimals at 100 digits, with its correlation."""
    n = len(us)
    mu = sum(us) / n
    mv = sum(vs) / n
    suu = sum((u - mu) ** 2 for u in us)
    svv = sum((v - mv) ** 2 for v in vs)
    suv = sum((u - mu) * (v - mv) for u, v in zip(us, vs))
    slope = suv / suu
    intercept = mv - slope * mu
    r = suv / (suu * svv).sqrt()
    return slope, intercept, r


def digits(value: Decimal) -> str:
    return format(+value, ".60g")


def transformed_case(kind: str, size: int):
    while True:
        xs = [Fraction(rng.randint(1, 40), rng.choice([1, 2, 4])) for _ in range(size)]
        ys = [Fraction(rng.randint(1, 90), rng.choice([1, 2, 5])) for _ in range(size)]
        if len(set(xs)) >= 2:
            break
    dx = [Decimal(x.numerator) / Decimal(x.denominator) for x in xs]
    dy = [Decimal(y.numerator) / Decimal(y.denominator) for y in ys]
    if kind == "exponential":
        slope, intercept, r = decimal_line(dx, [y.ln() for y in dy])
        a, b = intercept.exp(), slope.exp()
    elif kind == "power":
        slope, intercept, r = decimal_line([x.ln() for x in dx], [y.ln() for y in dy])
        a, b = intercept.exp(), slope
    else:
        slope, intercept, r = decimal_line([x.ln() for x in dx], dy)
        a, b = intercept, slope
    return {
        "kind": kind,
        "x": [text(x) for x in xs],
        "y": [text(y) for y in ys],
        "a": digits(a),
        "b": digits(b),
        "r": digits(r),
        "determination": digits(r * r),
    }


polynomials = []
for degree, size, kind in [(1, 4, "int"), (1, 9, "decimal"), (2, 3, "int"), (2, 6, "int"), (2, 10, "decimal"), (3, 4, "int"),
                           (3, 8, "decimal"), (4, 5, "int"), (4, 9, "int"), (5, 7, "int"), (6, 7, "int"), (6, 12, "decimal")]:
    polynomials.append(polynomial_case(degree, size, kind))
transformed = []
for kind in ["exponential", "power", "logarithmic"]:
    for size in [2, 3, 5, 8, 13]:
        transformed.append(transformed_case(kind, size))

# --- Distributions -------------------------------------------------------------------------------------------------------------


def probability_text() -> str:
    """A probability as it would be typed: a decimal or a fraction."""
    kind = rng.choice(["decimal", "fraction"])
    if kind == "decimal":
        return f"0.{rng.randint(1, 99):02d}".rstrip("0")
    denominator = rng.choice([2, 3, 5, 6, 7, 10, 12])
    return f"{rng.randint(1, denominator - 1)}/{denominator}"


def inverse_discrete(cdf, start: int, stop: int, q):
    """The smallest k whose cdf is at least q, found by looking at every k in turn."""
    for k in range(start, stop + 1):
        if cdf(k) >= q:
            return k
    return stop


binomial = []
for n in [1, 2, 5, 10, 17, 30, 60, 200]:
    for _ in range(2):
        p = probability_text()
        pf = Fraction(p)
        k = rng.randint(0, n)
        pmf = lambda j: Fraction(math.comb(n, j)) * pf**j * (1 - pf) ** (n - j)
        q_text = probability_text()
        q = Fraction(q_text)
        total = sum(pmf(j) for j in range(0, k + 1))
        binomial.append(
            {
                "n": n,
                "p": p,
                "k": k,
                "pdf": text(pmf(k)),
                "cdf": text(total),
                "q": q_text,
                "inv": inverse_discrete(lambda m: sum(pmf(j) for j in range(0, m + 1)), 0, n, q),
            }
        )

poisson = []
for lam in ["0.5", "1", "2.5", "4", "7.25", "12", "30"]:
    lf = Fraction(lam)
    for _ in range(2):
        k = rng.randint(0, int(lf * 3) + 3)
        term = lambda j: lf**j / math.factorial(j)
        s_pdf = term(k)
        s_cdf = sum(term(j) for j in range(0, k + 1))
        lam_decimal = Decimal(lf.numerator) / Decimal(lf.denominator)
        decay = (-lam_decimal).exp()
        q_text = f"0.{rng.randint(1, 999):03d}".rstrip("0")
        q = Decimal(q_text)

        def cdf_decimal(m):
            return decay * sum(Decimal(term(j).numerator) / Decimal(term(j).denominator) for j in range(0, m + 1))

        poisson.append(
            {
                "lambda": lam,
                "k": k,
                "pdfFactor": text(s_pdf),
                "cdfFactor": text(s_cdf),
                "pdf": digits(decay * Decimal(s_pdf.numerator) / Decimal(s_pdf.denominator)),
                "cdf": digits(cdf_decimal(k)),
                "q": q_text,
                "inv": next(m for m in range(0, 10_000) if cdf_decimal(m) >= q),
            }
        )

geometric = []
for p in ["1", "1/2", "0.3", "0.1", "1/7", "0.65", "1/20"]:
    pf = Fraction(p)
    for _ in range(2):
        k = rng.randint(1, 25)
        q_text = rng.choice(["0.5", "0.9", "0.99", "0.25", "0.75", "0.999", "7/8", "0.63"])
        q = Fraction(q_text)
        cdf = lambda m: 1 - (1 - pf) ** m
        geometric.append(
            {
                "p": p,
                "k": k,
                "pdf": text((1 - pf) ** (k - 1) * pf),
                "cdf": text(cdf(k)),
                "q": q_text,
                "inv": next(m for m in range(1, 200_000) if cdf(m) >= q),
            }
        )
geometric.append({"p": "1/2", "k": 3, "pdf": text(Fraction(1, 8)), "cdf": text(Fraction(7, 8)), "q": "7/8", "inv": 3})
geometric.append({"p": "0.1", "k": 2, "pdf": text(Fraction(9, 100)), "cdf": text(Fraction(19, 100)), "q": "0.19", "inv": 2})

hypergeometric = []
for population, successes, drawn in [(10, 4, 3), (20, 7, 5), (52, 13, 5), (100, 30, 10), (49, 6, 6), (15, 15, 4), (12, 0, 5)]:
    for _ in range(2):
        low = max(0, drawn - (population - successes))
        high = min(drawn, successes)
        k = rng.randint(low, high)
        mass = lambda j: Fraction(math.comb(successes, j) * math.comb(population - successes, drawn - j), math.comb(population, drawn)) if low <= j <= high else Fraction(0)
        hypergeometric.append(
            {
                "population": population,
                "successes": successes,
                "drawn": drawn,
                "k": k,
                "pdf": text(mass(k)),
                "cdf": text(sum(mass(j) for j in range(low, k + 1))),
            }
        )

uniform = []
for _ in range(14):
    a = Fraction(rng.randint(-20, 20), rng.choice([1, 2, 4]))
    b = a + Fraction(rng.randint(1, 30), rng.choice([1, 2, 3]))
    x = a + (b - a) * Fraction(rng.randint(-20, 120), 100)
    p = Fraction(rng.randint(0, 100), 100)
    uniform.append(
        {
            "a": text(a),
            "b": text(b),
            "x": text(x),
            "pdf": text(1 / (b - a) if a <= x <= b else Fraction(0)),
            "cdf": text(Fraction(0) if x < a else Fraction(1) if x > b else (x - a) / (b - a)),
            "p": text(p),
            "inv": text(a + p * (b - a)),
        }
    )

exponential = []
for _ in range(14):
    lam = Fraction(rng.randint(1, 30), rng.choice([1, 2, 5, 10]))
    x = Fraction(rng.randint(0, 60), rng.choice([1, 2, 4, 10]))
    p = Fraction(rng.randint(0, 99), 100)
    dl = Decimal(lam.numerator) / Decimal(lam.denominator)
    dx = Decimal(x.numerator) / Decimal(x.denominator)
    dp = Decimal(p.numerator) / Decimal(p.denominator)
    exponential.append(
        {
            "lambda": text(lam),
            "x": text(x),
            "pdf": digits(dl * (-dl * dx).exp()),
            "cdf": digits(1 - (-dl * dx).exp()),
            "p": text(p),
            "inv": digits(-(1 - dp).ln() / dl),
        }
    )

distributions = {
    "binomial": binomial,
    "poisson": poisson,
    "geometric": geometric,
    "hypergeometric": hypergeometric,
    "uniform": uniform,
    "exponential": exponential,
}

# --- The error function and the normal quantile -------------------------------------------------------------------------------


def decimal_pi() -> Decimal:
    """π by Machin's formula, 16 atan(1/5) − 4 atan(1/239), at the current precision."""

    def arctan_inverse(n: int) -> Decimal:
        x = Decimal(1) / n
        total = term = x
        k = 1
        while abs(term) > Decimal(10) ** (-getcontext().prec - 5):
            term = -term * x * x
            k += 2
            total += term / k
        return total

    return 16 * arctan_inverse(5) - 4 * arctan_inverse(239)


def decimal_erf(x: Decimal) -> Decimal:
    """erf(x) by its alternating Taylor series, with enough digits to survive the cancellation (wasteful, and independent of Swift's)."""
    saved = getcontext().prec
    getcontext().prec = saved + int(2 * float(x) ** 2 / 2.302585) + 40
    total = term = x
    n = 0
    while abs(term) > Decimal(10) ** (-getcontext().prec):
        n += 1
        term = -term * x * x / n
        total += term / (2 * n + 1)
    result = 2 / decimal_pi().sqrt() * total
    getcontext().prec = saved
    return +result


def decimal_erfc(x: Decimal) -> Decimal:
    saved = getcontext().prec
    getcontext().prec = saved + int(2 * float(x) ** 2 / 2.302585) + 40
    result = 1 - decimal_erf(x)
    getcontext().prec = saved
    return +result


def decimal_probit(p: Decimal) -> Decimal:
    """The normal quantile by Newton's method in decimals, from the machine number's start."""
    z = Decimal(statistics.NormalDist().inv_cdf(float(p)))
    root2 = Decimal(2).sqrt()
    tau = (2 * decimal_pi()).sqrt()
    for _ in range(8):
        cdf = decimal_erfc(-z / root2) / 2
        density = (-z * z / 2).exp() / tau
        z = z - (cdf - p) / density
    return z


getcontext().prec = 100
erf_points = []
for text_x in ["0.001", "0.1", "1/3", "0.5", "1", "1.5", "2", "2.9", "3", "3.1", "4", "5", "6.5", "8", "10", "20", "27.5", "-0.7", "-3", "-3.5", "-12"]:
    x = Decimal(Fraction(text_x).numerator) / Decimal(Fraction(text_x).denominator)
    erf_points.append({"x": text_x, "erf": digits(decimal_erf(x)), "erfc": digits(decimal_erfc(x))})
probit_points = []
for text_p in ["1e-100", "1e-30", "1e-12", "1e-5", "0.001", "0.01", "0.1", "0.3", "0.5", "0.6", "0.9", "0.975", "0.999", "0.99999", "0.999999999999"]:
    p = Decimal(text_p)
    probit_points.append({"p": text_p, "z": digits(decimal_probit(p))})
normal_points = []
root2 = Decimal(2).sqrt()
tau = (2 * decimal_pi()).sqrt()
for text_x, text_mu, text_sigma in [
    ("0", "0", "1"), ("1", "0", "1"), ("-1.96", "0", "1"), ("1.96", "0", "1"), ("3.5", "0", "1"), ("-7", "0", "1"),
    ("12", "10", "2"), ("85", "100", "15"), ("1.2", "1.5", "0.5"), ("-3", "-2", "0.25"), ("0.001", "0", "1"), ("40", "0", "1"),
    ("101", "100", "15"), ("130", "100", "15"), ("-0.5", "0.5", "3"), ("6", "0", "1"),
]:
    x, mu, sigma = Decimal(text_x), Decimal(text_mu), Decimal(text_sigma)
    z = (x - mu) / sigma
    pe = Decimal(rng.randint(1, 999)) / 1000
    normal_points.append(
        {
            "x": text_x,
            "mu": text_mu,
            "sigma": text_sigma,
            "pdf": digits((-z * z / 2).exp() / (sigma * tau)),
            "cdf": digits(decimal_erfc(-z / root2) / 2),
            "p": str(pe),
            "inv": digits(mu + sigma * decimal_probit(pe)),
        }
    )
# --- Gamma, incomplete gamma and beta, and the t, chi-squared and F distributions ------------------------------------------------


_gamma_cache = {}


def spouge_gamma(z: Decimal) -> Decimal:
    key = (z, getcontext().prec)
    if key not in _gamma_cache:
        _gamma_cache[key] = _spouge_gamma(z)
    return _gamma_cache[key]


def _spouge_gamma(z: Decimal) -> Decimal:
    """Γ(z) for z > 0 by Spouge's approximation, accurate to about the working digits (a method that shares nothing with Stirling's series)."""
    digits_wanted = getcontext().prec
    a = int(digits_wanted * 1.26) + 4
    z = z - 1  # Γ(z + 1) = z Γ(z)
    total = Decimal(2 * decimal_pi()).sqrt()
    factorial = Decimal(1)
    for k in range(1, a):
        if k > 1:
            factorial *= k - 1
        c = ((-1) ** (k - 1)) / factorial * (Decimal(a - k) ** (Decimal(k) - Decimal(1) / 2)) * Decimal(a - k).exp()
        total += c / (z + k)
    return (z + a) ** (z + Decimal(1) / 2) * (-(z + a)).exp() * total


def decimal_gamma_series(a: Decimal, x: Decimal) -> Decimal:
    """P(a, x) by its power series, which has only positive terms and converges for every x."""
    gamma_a1 = spouge_gamma(a + 1)
    total = term = Decimal(1)
    n = 0
    while term > Decimal(10) ** (-getcontext().prec):
        n += 1
        term = term * x / (a + n)
        total += term
    return x**a * (-x).exp() / gamma_a1 * total


def decimal_beta_series(x: Decimal, a: Decimal, b: Decimal) -> Decimal:
    """I_x(a, b) = x^a / (a B(a, b)) · ₂F₁(a, 1 − b; a + 1; x), summed termwise (used for x ≤ 1/2, the other side by symmetry)."""
    beta = spouge_gamma(a) * spouge_gamma(b) / spouge_gamma(a + b)
    total = term = Decimal(1)
    n = 0
    while True:
        # the term ratio of Σ (a)ₙ (1 − b)ₙ / ((a + 1)ₙ n!) xⁿ
        ratio = (a + n) * (1 - b + n) / ((a + 1 + n) * (n + 1)) * x
        term *= ratio
        total += term
        n += 1
        if abs(term) < Decimal(10) ** (-getcontext().prec) and n > 5:
            break
    return x**a / (a * beta) * total


def decimal_beta(x: Decimal, a: Decimal, b: Decimal):
    """(I_x(a, b), 1 − I_x(a, b)), each computed on the side where the series is short and not a difference."""
    if x <= Decimal(1) / 2:
        lower = decimal_beta_series(x, a, b)
        return lower, 1 - lower
    upper = decimal_beta_series(1 - x, b, a)
    return 1 - upper, upper


def decimal_gamma_regularised(a: Decimal, x: Decimal):
    lower = decimal_gamma_series(a, x)
    return lower, 1 - lower


def dec(text_value: str) -> Decimal:
    f = Fraction(text_value)
    return Decimal(f.numerator) / Decimal(f.denominator)


getcontext().prec = 150
gamma_points = []
for text_x in ["0.1", "0.5", "1", "1.5", "2", "3.25", "7", "10.5", "25.75", "50", "100.5", "300"]:
    x = dec(text_x)
    gamma_points.append({"x": text_x, "gamma": digits(spouge_gamma(x)), "lgamma": digits(spouge_gamma(x).ln())})

gammainc_points = []
for text_a, text_x in [("0.5", "0.2"), ("0.5", "3"), ("1", "1"), ("2.5", "1"), ("2.5", "8"), ("5", "2"), ("5", "30"), ("10.25", "9"), ("10.25", "20"), ("50", "40"), ("50", "80"), ("0.1", "0.01"), ("3", "0.001"), ("200", "180")]:
    lower, upper = decimal_gamma_regularised(dec(text_a), dec(text_x))
    gammainc_points.append({"a": text_a, "x": text_x, "p": digits(lower), "q": digits(upper)})

betainc_points = []
for text_x, text_a, text_b in [("0.5", "1", "1"), ("0.3", "2", "3"), ("0.3", "0.5", "0.5"), ("0.9", "2.5", "1.5"), ("0.1", "5", "0.5"), ("0.7", "10", "20"), ("0.01", "3", "40"), ("0.99", "3", "40"), ("0.5", "30", "30"), ("0.25", "0.5", "7.5"), ("0.0001", "2", "2"), ("0.6", "15.5", "4.25")]:
    lower, upper = decimal_beta(dec(text_x), dec(text_a), dec(text_b))
    betainc_points.append({"x": text_x, "a": text_a, "b": text_b, "lower": digits(lower), "upper": digits(upper)})

# The inverses, by Newton's method in decimals on the series of the cdfs.
getcontext().prec = 120
gamma_inverse = []
for text_a, text_p in [("0.5", "0.1"), ("1", "0.5"), ("2.5", "0.95"), ("5", "0.01"), ("10.25", "0.999"), ("30", "0.5"), ("3", "1e-10")]:
    a, p_target = dec(text_a), Decimal(text_p)
    # Bisection to a few digits, then Newton, in decimals.
    low, high = Decimal(0), a + 20 * a.sqrt() + 50
    for _ in range(200):
        mid = (low + high) / 2
        if decimal_gamma_series(a, mid) < p_target:
            low = mid
        else:
            high = mid
    x = (low + high) / 2
    for _ in range(10):
        residual = decimal_gamma_series(a, x) - p_target
        density = x ** (a - 1) * (-x).exp() / spouge_gamma(a)
        x = x - residual / density
    gamma_inverse.append({"a": text_a, "p": text_p, "x": digits(x)})

beta_inverse = []
for text_p, text_a, text_b in [("0.5", "1", "1"), ("0.1", "2", "3"), ("0.975", "5", "0.5"), ("0.001", "0.5", "0.5"), ("0.9", "10", "20"), ("0.5", "3", "40"), ("0.99", "2.5", "1.5")]:
    p_target, a, b = Decimal(text_p), dec(text_a), dec(text_b)
    low, high = Decimal(0), Decimal(1)
    for _ in range(200):
        mid = (low + high) / 2
        if decimal_beta(mid, a, b)[0] < p_target:
            low = mid
        else:
            high = mid
    x = (low + high) / 2
    beta_const = spouge_gamma(a) * spouge_gamma(b) / spouge_gamma(a + b)
    for _ in range(10):
        residual = decimal_beta(x, a, b)[0] - p_target
        density = x ** (a - 1) * (1 - x) ** (b - 1) / beta_const
        x = x - residual / density
    beta_inverse.append({"p": text_p, "a": text_a, "b": text_b, "x": digits(x)})
getcontext().prec = 100

# --- Student's t, chi-squared and F -------------------------------------------------------------------------------------------


def decimal_atan(x: Decimal) -> Decimal:
    """arctan by halving the angle three times and summing the series."""
    reductions = 3
    for _ in range(reductions):
        x = x / (1 + (1 + x * x).sqrt())
    total = term = x
    k = 0
    while abs(term) > Decimal(10) ** (-getcontext().prec - 5):
        k += 1
        term = -term * x * x
        total += term / (2 * k + 1)
    return total * 2**reductions


def student_cdf_closed_form(t: Decimal, nu: int) -> Decimal:
    """Abramowitz and Stegun 26.7.3 and 26.7.4: the t distribution function for whole degrees of freedom."""
    theta = decimal_atan(t / Decimal(nu).sqrt())
    # sin θ and cos θ from tan θ, without a library: θ = arctan(u) gives sin = u/√(1+u²), cos = 1/√(1+u²)
    u = t / Decimal(nu).sqrt()
    c = 1 / (1 + u * u).sqrt()
    sn = u * c
    if nu % 2 == 0:
        total = term = Decimal(1)
        for j in range(1, (nu - 2) // 2 + 1):
            term = term * Decimal(2 * j - 1) / Decimal(2 * j) * c * c
            total += term
        return Decimal(1) / 2 + sn * total / 2
    if nu == 1:
        return Decimal(1) / 2 + theta / decimal_pi()
    total = term = c
    for j in range(1, (nu - 3) // 2 + 1):
        term = term * Decimal(2 * j) / Decimal(2 * j + 1) * c * c
        total += term
    return Decimal(1) / 2 + (theta + sn * total) / decimal_pi()


def student_cdf(t: Decimal, nu: Decimal) -> Decimal:
    lower, _ = decimal_beta(nu / (nu + t * t), nu / 2, Decimal(1) / 2)
    return lower / 2 if t < 0 else 1 - lower / 2


def newton_inverse(cdf, pdf, low: Decimal, high: Decimal, target: Decimal) -> Decimal:
    for _ in range(160):
        mid = (low + high) / 2
        if cdf(mid) < target:
            low = mid
        else:
            high = mid
    x = (low + high) / 2
    for _ in range(8):
        x = x - (cdf(x) - target) / pdf(x)
    return x


getcontext().prec = 110
t_cases = []
for nu_text in ["1", "2", "3", "5", "7.5", "30"]:
    nu = dec(nu_text)
    for x_text in ["0", "-1.3", "2.7", "-6"]:
        x = dec(x_text)
        coefficient = spouge_gamma((nu + 1) / 2) / ((nu * decimal_pi()).sqrt() * spouge_gamma(nu / 2))
        pdf = coefficient * (1 + x * x / nu) ** (-(nu + 1) / 2)
        cdf = student_cdf(x, nu)
        if nu == int(nu) and int(nu) <= 30:
            assert abs(cdf - student_cdf_closed_form(x, int(nu))) < Decimal(10) ** -60, (nu_text, x_text)
        t_cases.append({"nu": nu_text, "x": x_text, "pdf": digits(pdf), "cdf": digits(cdf)})
    for p_text in ["0.5", "0.975", "0.01"]:
        p = Decimal(p_text)
        coefficient = lambda v: spouge_gamma((nu + 1) / 2) / ((nu * decimal_pi()).sqrt() * spouge_gamma(nu / 2)) * (1 + v * v / nu) ** (-(nu + 1) / 2)
        q = newton_inverse(lambda v: student_cdf(v, nu), coefficient, Decimal(-5000), Decimal(5000), p) if p != Decimal("0.5") else Decimal(0)
        t_cases.append({"nu": nu_text, "p": p_text, "inv": digits(q)})

chisq_cases = []
for k_text in ["1", "2", "4", "5", "10.5", "30"]:
    k = dec(k_text)
    for x_text in ["0.2", "3.84", "25"]:
        x = dec(x_text)
        pdf = x ** (k / 2 - 1) * (-x / 2).exp() / (2 ** (k / 2) * spouge_gamma(k / 2))
        chisq_cases.append({"k": k_text, "x": x_text, "pdf": digits(pdf), "cdf": digits(decimal_gamma_series(k / 2, x / 2))})
    for p_text in ["0.05", "0.95"]:
        p = Decimal(p_text)
        pdf_fn = lambda v: v ** (k / 2 - 1) * (-v / 2).exp() / (2 ** (k / 2) * spouge_gamma(k / 2))
        q = newton_inverse(lambda v: decimal_gamma_series(k / 2, v / 2), pdf_fn, Decimal(0), 2 * k + 200, p)
        chisq_cases.append({"k": k_text, "p": p_text, "inv": digits(q)})

f_cases = []
for d1_text, d2_text in [("2", "2"), ("3", "5"), ("4", "6"), ("10", "20"), ("7.5", "12")]:
    d1, d2 = dec(d1_text), dec(d2_text)
    a, b = d1 / 2, d2 / 2
    beta = spouge_gamma(a) * spouge_gamma(b) / spouge_gamma(a + b)
    for x_text in ["0.1", "1", "2.5"]:
        x = dec(x_text)
        pdf = ((d1 * x) ** d1 * d2**d2 / (d1 * x + d2) ** (d1 + d2)).sqrt() / (x * beta)
        cdf = decimal_beta(d1 * x / (d1 * x + d2), a, b)[0]
        f_cases.append({"d1": d1_text, "d2": d2_text, "x": x_text, "pdf": digits(pdf), "cdf": digits(cdf)})
    for p_text in ["0.05", "0.95"]:
        p = Decimal(p_text)
        pdf_fn = lambda v: ((d1 * v) ** d1 * d2**d2 / (d1 * v + d2) ** (d1 + d2)).sqrt() / (v * beta)
        q = newton_inverse(lambda v: decimal_beta(d1 * v / (d1 * v + d2), a, b)[0], pdf_fn, Decimal(0), Decimal(10000), p)
        f_cases.append({"d1": d1_text, "d2": d2_text, "p": p_text, "inv": digits(q)})
getcontext().prec = 100

special = {
    "t": t_cases,
    "chisq": chisq_cases,
    "f": f_cases,
    "erf": erf_points,
    "probit": probit_points,
    "normal": normal_points,
    "gamma": gamma_points,
    "gammainc": gammainc_points,
    "betainc": betainc_points,
    "gammaInverse": gamma_inverse,
    "betaInverse": beta_inverse,
}

(OUT / "statistics-vectors.json").write_text(
    json.dumps(
        {
            "one": one,
            "two": two,
            "polynomials": polynomials,
            "transformed": transformed,
            "distributions": distributions,
            "special": special,
        },
        indent=1,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
print(
    f"{len(one)} one-variable, {len(two)} two-variable, {len(polynomials)} polynomial and {len(transformed)} transformed cases"
)
