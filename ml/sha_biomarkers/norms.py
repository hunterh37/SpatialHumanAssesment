"""Age-25 reference values and v0 functional age. All constants are placeholders.

Replace each with a published value and cite the source on the same line.
"""

REFERENCE_AGE = 25.0

# feature: (mean at 25, sd at 25, sign, years per sd)
# sign +1 means higher value = older.
NORMS = {
    "simple_rt_median": (0.32, 0.05, +1, 12.0),  # TODO cite
    "choice_rt_median": (0.45, 0.07, +1, 12.0),  # TODO cite
    "rt_cv":            (0.15, 0.04, +1, 15.0),  # TODO cite
    "corsi_span":       (6.0,  1.0,  -1, 15.0),  # TODO cite
    "ecc_slope":        (0.10, 0.04, +1, 20.0),  # TODO cite
}


def functional_age(features: dict) -> float | None:
    deltas = []
    for name, (mean, sd, sign, years) in NORMS.items():
        value = features.get(name)
        if value is None:
            continue
        deltas.append(sign * (value - mean) / sd * years)
    if not deltas:
        return None
    return round(REFERENCE_AGE + sum(deltas) / len(deltas), 1)
