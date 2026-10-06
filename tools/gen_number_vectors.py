#!/usr/bin/env python3
"""Generate reference vectors for the BigInt and Rational tests.

Python's int and fractions.Fraction are exact, so they act as an independent oracle for the Swift code.
The seed is fixed: running this again must reproduce the committed files byte for byte.

    python3 tools/gen_number_vectors.py
"""

import json
import random
from fractions import Fraction
from math import gcd, isqrt
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "Tests" / "MantissaCoreTests" / "Resources"
rng = random.Random(20261006)


def truncated_divmod(a: int, b: int) -> tuple[int, int]:
    """Quotient rounded toward zero and a remainder with the dividend's sign, as Swift's / and % do."""
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q, a - q * b


def limbs(*digits: int) -> int:
    """An integer from 32-bit limbs, least significant first."""
    return sum(d << (32 * i) for i, d in enumerate(digits))


def random_int(max_bits: int) -> int:
    value = rng.getrandbits(rng.randint(1, max_bits))
    return -value if rng.random() < 0.4 else value


# Operands near limb boundaries and the dividends that force Knuth's "add back" step (from Hacker's Delight).
special = [
    0, 1, -1, 2, 10**9, 10**9 - 1, 2**31, 2**32 - 1, 2**32, 2**32 + 1, 2**63 - 1, 2**63, 2**64 - 1, 2**64,
    -(2**63), -(2**63) - 1, 2**96, 2**96 - 1, 2**128 + 1, 10**18, 10**19,
    limbs(0x00000003, 0x00000000, 0x80000000),
    limbs(0x00000001, 0x00000000, 0x20000000),
    limbs(0x0000FFFE, 0x00000000, 0x80000000),
    limbs(0x0000FFFF, 0x00000000, 0x80000000),
    limbs(0x00000000, 0xFFFFFFFE, 0x80000000),
    limbs(0xFFFFFFFF, 0x80000000),
    limbs(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF),
    limbs(0xFFFFFFFF, 0xFFFFFFFF),
]
operands = special + [random_int(64) for _ in range(40)] + [random_int(700) for _ in range(120)]

pairs = []
for _ in range(400):
    pairs.append((rng.choice(operands), rng.choice(operands)))
pairs += [(a, b) for a in special for b in special]

integer_cases = []
for a, b in pairs:
    case = {"a": str(a), "b": str(b), "sum": str(a + b), "difference": str(a - b), "product": str(a * b),
            "gcd": str(gcd(a, b)), "compare": (a > b) - (a < b), "digits": len(str(abs(a)))}
    if a >= 0:
        case["isqrt"] = str(isqrt(a))
    if b != 0:
        q, r = truncated_divmod(a, b)
        case["quotient"], case["remainder"] = str(q), str(r)
        case["floorQuotient"] = str(a // b)
    integer_cases.append(case)

power_cases = []
for _ in range(40):
    base, exponent = random_int(120), rng.randint(0, 60)
    power_cases.append({"base": str(base), "exponent": exponent, "result": str(base**exponent)})

fractions = [Fraction(random_int(80), rng.choice([1, 2, 3, 7, 12, 1000, rng.getrandbits(60) | 1]))
             for _ in range(60)] + [Fraction(0), Fraction(1), Fraction(-1, 2), Fraction(1, 3)]
fraction_cases = []
for _ in range(300):
    a, b = rng.choice(fractions), rng.choice(fractions)
    case = {"a": f"{a.numerator}/{a.denominator}", "b": f"{b.numerator}/{b.denominator}",
            "sum": str(a + b), "difference": str(a - b), "product": str(a * b), "compare": (a > b) - (a < b)}
    if b != 0:
        case["quotient"] = str(a / b)
    fraction_cases.append(case)

decimal_cases = [
    ("0", "0"), ("12", "12"), ("-12", "-12"), ("+7", "7"), ("1.25", "5/4"), ("-1.25", "-5/4"), (".5", "1/2"),
    ("5.", "5"), ("0.125", "1/8"), ("1e3", "1000"), ("1E3", "1000"), ("2.5e-3", "1/400"), ("-2.5e+2", "-250"),
    ("0.000001", "1/1000000"), ("123456789012345678901234567890.5", "246913578024691357802469135781/2"),
    ("10e-1", "1"), ("0e5", "0"),
]
invalid_decimals = ["", ".", "-", "e5", "1e", "1e+", "1.2.3", "1,5", "abc", "1e10001", "--1", "1 2", "0x10", "٣"]

(OUT / "integer-vectors.json").write_text(json.dumps(
    {"integers": integer_cases, "powers": power_cases}, separators=(",", ":")) + "\n")
(OUT / "rational-vectors.json").write_text(json.dumps(
    {"fractions": fraction_cases,
     "decimals": [{"text": t, "value": v} for t, v in decimal_cases],
     "invalidDecimals": invalid_decimals}, separators=(",", ":")) + "\n")
print(f"integers: {len(integer_cases)}, powers: {len(power_cases)}, fractions: {len(fraction_cases)}")
