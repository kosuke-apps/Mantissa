#!/usr/bin/env python3
"""Generate reference vectors for the BigDecimal tests.

The expected values come from Python's `decimal` module at 300 digits, rounded half away from zero to 110. Python's
exp, ln and sqrt are correctly rounded and independent of the Swift code. Python has no sin, cos or atan, so those are
written here the plain way (Taylor series after exact range reduction, 300 digits of pi) and asin and acos are found
by Newton iteration on that sin; none of this shares an algorithm with the Swift implementation, which uses guard
digits and argument halving. The seed is fixed: rerunning reproduces the committed file byte for byte.

    python3 tools/gen_decimal_vectors.py
"""

import json
import math
import random
from decimal import ROUND_HALF_UP, Decimal as D, getcontext, localcontext
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Tests" / "MantissaCoreTests" / "Resources" / "decimal-vectors.json"
WORK = 300
OUT_DIGITS = 110
rng = random.Random(20261007)
getcontext().prec = WORK
getcontext().rounding = ROUND_HALF_UP
TINY = D(10) ** -(WORK + 10)


def atan_inverse(n: int) -> D:
    """atan(1/n) by its Taylor series."""
    term = D(1) / n
    total, k = term, 0
    while abs(term) > TINY:
        k += 1
        term = -term / (n * n)
        total += term / (2 * k + 1)
    return total


PI = 16 * atan_inverse(5) - 4 * atan_inverse(239)
HALF_PI = PI / 2


def sin_series(r: D) -> D:
    term, total, k = r, r, 0
    while abs(term) > TINY:
        k += 1
        term = -term * r * r / ((2 * k) * (2 * k + 1))
        total += term
    return total


def cos_series(r: D) -> D:
    term, total, k = D(1), D(1), 0
    while abs(term) > TINY:
        k += 1
        term = -term * r * r / ((2 * k - 1) * (2 * k))
        total += term
    return total


def reduce(x: D) -> tuple[int, D]:
    """x = n * pi/2 + r with n the nearest integer; returns n mod 4 and r."""
    n = (x / HALF_PI).to_integral_value()
    return int(n) % 4, x - n * HALF_PI


def sin(x: D) -> D:
    q, r = reduce(x)
    return [sin_series(r), cos_series(r), -sin_series(r), -cos_series(r)][q]


def cos(x: D) -> D:
    q, r = reduce(x)
    return [cos_series(r), -sin_series(r), -cos_series(r), sin_series(r)][q]


def atan(x: D) -> D:
    if x < 0:
        return -atan(-x)
    if x > 1:
        return HALF_PI - atan(1 / x)
    for _ in range(8):  # atan(x) = 2 atan(x / (1 + sqrt(1 + x^2)))
        x = x / (1 + (1 + x * x).sqrt())
    term, total, k = x, x, 0
    while abs(term) > TINY:
        k += 1
        term = -term * x * x
        total += term / (2 * k + 1)
    return total * 256


def asin(x: D) -> D:
    y = D(math.asin(float(x)))
    for _ in range(9):
        y -= (sin(y) - x) / cos(y)
    return y


def acos(x: D) -> D:
    return HALF_PI - asin(x)


def sinh(x: D) -> D:
    return (x.exp() - (-x).exp()) / 2


def cosh(x: D) -> D:
    return (x.exp() + (-x).exp()) / 2


def tanh(x: D) -> D:
    return sinh(x) / cosh(x)


def asinh(x: D) -> D:
    a = abs(x)
    value = (a + (a * a + 1).sqrt()).ln()
    return -value if x < 0 else value


def acosh(x: D) -> D:
    return (x + (x * x - 1).sqrt()).ln()


def atanh(x: D) -> D:
    return ((1 + x) / (1 - x)).ln() / 2


def power(x: D, y: D) -> D:
    if y == y.to_integral_value():
        return x ** int(y)  # exact at this precision for the sizes used here
    return (y * x.ln()).exp()


def log_base(x: D, base: D) -> D:
    return x.ln() / base.ln()


def fmt(value: D, digits: int = OUT_DIGITS) -> str:
    with localcontext() as context:
        context.prec = digits
        context.rounding = ROUND_HALF_UP
        return str(+value)


def random_decimal(max_digits: int, low_exp: int, high_exp: int, signed: bool = True) -> str:
    digits = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, max_digits)))
    digits = str(int(digits) or 1)
    text = digits[0] + "." + digits[1:] if len(digits) > 1 else digits
    text += f"e{rng.randint(low_exp, high_exp)}"
    return ("-" if signed and rng.random() < 0.4 else "") + text


# One-argument functions: (name, oracle, hand-picked inputs, random-input range as (digits, low exp, high exp, signed)).
SINGLE = [
    ("exp", lambda x: x.exp(),
     ["0", "1", "-1", "0.5", "-0.5", "2", "10", "-10", "100", "-100", "1e-30", "-1e-30", "123.456", "-0.0001", "700",
      "-700", "12345.6789", "1e-5", "3.14159265358979323846", "0.693147180559945309417232121458",
      "-23.025850929940456840179914546844", "1e-80", "2.302585092994045684017991454684364", "99999.5"],
     (14, -3, 1, True)),
    ("ln", lambda x: x.ln(),
     ["1.0000000001", "0.9999999999", "1.00000000000000000001", "0.99999999999999999999999999", "2", "10", "0.5",
      "0.1", "0.01", "100", "1e-5", "3.14159", "1e100", "1e-100", "123456789.123456789", "2.718281828459045", "0.8",
      "1.6", "1.5999999", "0.79999999", "7", "9.999999", "1e30", "1.23e-200", "1", "1.0000000000000000000000000000001",
      "1e1000", "5e-1000"],
     (14, -6, 6, False)),
    ("sqrt", lambda x: x.sqrt(),
     ["2", "3", "0.5", "1e-20", "1e20", "12345.6789", "144", "0.0001", "1e-300", "7.25", "2e100", "0", "1", "10",
      "1e-1001", "123456789012345678901234567890"],
     (30, -50, 50, False)),
    ("sin", sin,
     ["0.1", "0.5", "1", "-1", "2", "3", "3.14159265358979", "3.14159265358979323846264338327950288",
      "6.28318530717958647692528676655900577", "1e-10", "1e-60", "10", "100", "1000", "1e10", "1e20", "1e30",
      "-2.5", "1.5707963267949", "1.5707963267948966192313216916397514420985846996875529", "355", "104348",
      "12345.6789", "0.7853981633974483", "1e-3", "57.29577951308232", "-1000000.5", "0", "1e-200"],
     (14, -3, 2, True)),
    ("cos", cos,
     ["0.1", "0.5", "1", "-1", "2", "3", "3.14159265358979", "3.14159265358979323846264338327950288",
      "6.28318530717958647692528676655900577", "1e-10", "1e-60", "10", "100", "1000", "1e10", "1e20", "1e30",
      "-2.5", "1.5707963267949", "1.5707963267948966192313216916397514420985846996875529", "355", "104348",
      "12345.6789", "0.7853981633974483", "1e-3", "57.29577951308232", "-1000000.5", "0", "1e-200"],
     (14, -3, 2, True)),
    ("tan", lambda x: sin(x) / cos(x),
     ["0.1", "0.5", "1", "-1", "2", "3", "3.14159265358979", "1e-10", "1e-60", "10", "100", "1000", "1e10", "1e20",
      "-2.5", "1.5707963267949", "1.5707963267948966192313216916397514420985846996875529", "355", "104348",
      "12345.6789", "0.7853981633974483", "1e-3", "-1000000.5", "0", "1e-200"],
     (14, -3, 2, True)),
    ("atan", atan,
     ["0", "0.5", "1", "-1", "2", "10", "100", "1e10", "1e50", "1e-5", "1e-30", "-0.3", "0.999999", "1.000001",
      "3.14159", "123456789.123456789", "0.0123456789", "1e300", "-1e-100"],
     (14, -5, 5, True)),
    ("asin", asin,
     ["0", "0.5", "-0.5", "0.1", "0.9", "-0.9", "0.999999", "-0.999999", "1e-10", "0.7071067811865476", "0.3",
      "0.123456789012345678901234567890", "1e-100"],
     None),
    ("acos", acos,
     ["0", "0.5", "-0.5", "0.1", "0.9", "-0.9", "0.999999", "-0.999999", "1e-10", "0.7071067811865476", "0.3",
      "0.123456789012345678901234567890", "0.999999999999"],
     None),
    ("sinh", sinh,
     ["0.5", "-0.5", "1", "10", "-10", "1e-5", "1e-30", "100", "-100", "700", "1e3", "0.0123", "25", "50", "123.456"],
     (14, -4, 2, True)),
    ("cosh", cosh,
     ["0", "0.5", "-0.5", "1", "10", "-10", "1e-5", "1e-30", "100", "-100", "700", "1e3", "0.0123", "25", "50",
      "123.456"],
     (14, -4, 2, True)),
    ("tanh", tanh,
     ["0.5", "-0.5", "1", "10", "-10", "1e-5", "1e-30", "100", "-100", "700", "0.0123", "25", "50", "123.456", "3"],
     (14, -4, 2, True)),
    ("asinh", asinh,
     ["0.5", "-0.5", "1", "10", "1e-5", "1e-30", "100", "1e50", "-1e50", "3.7", "123456.789", "1e200"],
     (14, -4, 4, True)),
    ("acosh", acosh,
     ["1.5", "2", "10", "1.0000001", "1.00000000000000000001", "1.000000000000000000000000000000001", "100", "1e50",
      "1e200", "1", "1.00000000000000000000000000000000000000000000000000000000000000001"],
     None),
    ("atanh", atanh,
     ["0.5", "-0.5", "0.1", "0.9999", "1e-5", "1e-30", "0.123456789", "-0.999999999", "0.7", "0.999999999999999"],
     None),
]

# Two-argument functions: (name, oracle, hand-picked pairs).
PAIRS = [
    ("pow", power,
     [("2", "0.5"), ("2", "10"), ("10", "-3"), ("3", "1.5"), ("10", "0.30103"), ("0.5", "2.5"), ("123.456", "7.89"),
      ("1.0001", "10000.5"), ("2", "100.5"), ("9", "0.5"), ("2", "-3"), ("1.5", "20"), ("7", "0"), ("0.1", "30"),
      ("12345.6789", "-2.5"), ("2", "0.001"), ("1e-5", "0.3"), ("1e100", "0.5"), ("5", "-100")]),
    ("log", log_base,
     [("1000", "10"), ("8", "2"), ("0.001", "10"), ("5", "3"), ("123.456", "7"), ("2", "10"), ("1", "10"),
      ("1024", "2"), ("0.5", "2"), ("1e-30", "10"), ("1e100", "1e10"), ("2.718281828459045", "2.718281828459045")]),
]

functions = []
for name, oracle, picked, spec in SINGLE:
    inputs = list(picked)
    if spec is not None:
        inputs += [random_decimal(*spec) for _ in range(12)]
    else:
        # Arguments inside the domain: random values in (0, 1), signed where the domain allows it, or above 1.
        for _ in range(8):
            fraction = rng.randint(1, 10**15)
            if name == "acosh":
                inputs.append(f"{rng.randint(1, 1000)}.{fraction}")
            else:
                inputs.append(f"{'-' if rng.random() < 0.4 else ''}0.{fraction}")
    for text in inputs:
        # tan is skipped where cos is 0 to within 1e-300, which no decimal of this size reaches; keep all.
        functions.append({"fn": name, "x": text, "expected": fmt(oracle(D(text)))})

for name, oracle, pairs in PAIRS:
    for x, y in pairs:
        functions.append({"fn": name, "x": x, "y": y, "expected": fmt(oracle(D(x), D(y)))})

functions.append({"fn": "pi", "expected": fmt(PI)})
functions.append({"fn": "e", "expected": fmt(D(1).exp())})

# Exact arithmetic, rounding and division against Python's decimal.
arithmetic = []
specials = ["0", "1", "-1", "0.1", "0.2", "0.3", "1e-30", "-2.5e20", "123456789.987654321", "1e50", "-3e-7", "9.99"]
for _ in range(250):
    a = rng.choice(specials + [random_decimal(25, -30, 30) for _ in range(6)])
    b = rng.choice(specials + [random_decimal(25, -30, 30) for _ in range(6)])
    da, db = D(a), D(b)
    with localcontext() as exact:
        exact.prec = 2000
        case = {"a": a, "b": b, "sum": str(da + db), "difference": str(da - db), "product": str(da * db),
                "compare": (da > db) - (da < db)}
    if db != 0:
        with localcontext() as context:
            context.prec = 50
            context.rounding = ROUND_HALF_UP
            case["quotient50"] = str(da / db)
        with localcontext() as context:
            context.prec = 7
            context.rounding = ROUND_HALF_UP
            case["quotient7"] = str(da / db)
    arithmetic.append(case)

rounding = []
for _ in range(120):
    text = random_decimal(40, -10, 10)
    digits = rng.randint(1, 30)
    places = rng.randint(-5, 25)
    with localcontext() as context:
        context.prec = digits
        context.rounding = ROUND_HALF_UP
        to_digits = str(+D(text))
    with localcontext() as context:
        context.prec = 2000
        to_places = str(D(text).quantize(D(1).scaleb(-places), rounding=ROUND_HALF_UP))
    rounding.append({"x": text, "digits": digits, "places": places, "toDigits": to_digits, "toPlaces": to_places})

roots = []
for _ in range(60):
    text = random_decimal(30, -40, 40, signed=False)
    precision = rng.choice([1, 5, 20, 50, 80])
    roots.append({"x": text, "precision": precision, "expected": fmt(D(text).sqrt(), precision)})

powers = []
for _ in range(60):
    text = random_decimal(12, -3, 3)
    n = rng.randint(-40, 60)
    precision = rng.choice([5, 20, 50])
    if D(text) == 0 and n <= 0:
        continue
    with localcontext() as exact:
        exact.prec = 20000
        exact_value = D(text) ** n if n >= 0 else 1 / (D(text) ** -n)
    with localcontext() as context:
        context.prec = precision
        context.rounding = ROUND_HALF_UP
        powers.append({"x": text, "n": n, "precision": precision, "expected": str(+exact_value)})

OUT.write_text(json.dumps(
    {"functions": functions, "arithmetic": arithmetic, "rounding": rounding, "roots": roots, "powers": powers},
    separators=(",", ":")) + "\n")
print(f"functions: {len(functions)}, arithmetic: {len(arithmetic)}, rounding: {len(rounding)}, "
      f"roots: {len(roots)}, powers: {len(powers)}")
