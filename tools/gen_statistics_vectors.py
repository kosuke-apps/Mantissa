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

(OUT / "statistics-vectors.json").write_text(
    json.dumps(
        {
            "one": one,
            "two": two,
            "polynomials": polynomials,
            "transformed": transformed,
            "distributions": distributions,
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
