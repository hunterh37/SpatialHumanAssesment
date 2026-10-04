"""Klemera-Doubal biological age (Klemera and Doubal 2006, Mech Ageing Dev 127(3)).

Each biomarker j is modelled as x_j = f_j(age) + e_j with e_j ~ N(0, s_j^2). With linear
f_j = q_j + k_j age the estimate is

    BA_E  = sum (x_j - q_j) k_j / s_j^2 / sum (k_j / s_j)^2
    BA_EC = (sum (x_j - q_j) k_j / s_j^2 + CA / s_BA^2) / (sum (k_j / s_j)^2 + 1 / s_BA^2)

The curves here bend after a knee, so the estimate is the same weighted least squares solved by
Gauss-Newton: each step is the linear KDM formula on the curves' tangents at the current age.

Parameters (f_j, s_j) normally come from a reference sample. `kdm_params.json` holds literature
priors until sessions are collected; `fit` estimates linear parameters from data.

Stdlib only. Run: python -m sha_biomarkers.kdm table.csv
"""

from __future__ import annotations

import csv
import json
import math
import pathlib
import sys
from dataclasses import dataclass

DEFAULT_PARAMS = pathlib.Path(__file__).with_name("kdm_params.json")


@dataclass(frozen=True)
class Biomarker:
    name: str
    mean25: float
    sd: float
    slope: float
    accel: float = 0.0
    knee: float = 50.0

    def expected(self, age: float) -> float:
        late = max(0.0, age - self.knee)
        return self.mean25 + self.slope * (age - 25) + self.accel * late * late

    def rate(self, age: float) -> float:
        """d expected / d age."""
        return self.slope + 2 * self.accel * max(0.0, age - self.knee)


@dataclass(frozen=True)
class Estimate:
    age: float
    """Years. BA_EC when a chronological age was given, else BA_E."""
    se: float
    """Standard error in years, 1 / sqrt(Fisher information)."""
    n: int
    """Biomarkers used."""


def _missing(v) -> bool:
    if v is None or v == "":
        return True
    try:
        return math.isnan(float(v))
    except (TypeError, ValueError):
        return True


class KDM:
    def __init__(self, biomarkers: dict[str, Biomarker], age_range=(18.0, 95.0),
                 prior_sd: float | None = 9.0, version: str = ""):
        for b in biomarkers.values():
            if b.sd <= 0:
                raise ValueError(f"{b.name}: sd must be positive")
            if b.slope * b.accel < 0:
                raise ValueError(f"{b.name}: slope and accel must share a sign so the curve is monotone")
        self.biomarkers = biomarkers
        self.age_range = (float(age_range[0]), float(age_range[1]))
        self.prior_sd = prior_sd
        self.version = version

    @classmethod
    def from_config(cls, path: str | pathlib.Path = DEFAULT_PARAMS) -> "KDM":
        cfg = json.loads(pathlib.Path(path).read_text())
        bms = {
            name: Biomarker(name, p["mean25"], p["sd"], p["slope"], p.get("accel", 0.0), p.get("knee", 50.0))
            for name, p in cfg["biomarkers"].items()
        }
        return cls(bms, cfg.get("age_range", (18, 95)), cfg.get("chronological_prior_sd"), cfg.get("version", ""))

    def predict(self, X, columns: list[str], chronological_age=None) -> list[Estimate | None]:
        """Estimate age for each row of X.

        X is any row-iterable matrix (list of lists, numpy array): rows are people, columns are
        biomarkers named by `columns`. Columns not in the parameters are ignored. Missing values
        (None, NaN, "") are skipped per row. A row with no usable biomarker gives None.
        `chronological_age`, if given, is one age per row (None allowed) and adds the BA_EC prior.
        """
        idx = [(i, self.biomarkers[c]) for i, c in enumerate(columns) if c in self.biomarkers]
        rows = list(X)
        cas = list(chronological_age) if chronological_age is not None else [None] * len(rows)
        if len(cas) != len(rows):
            raise ValueError("chronological_age needs one entry per row")
        out = []
        for row, ca in zip(rows, cas):
            obs = [(b, float(row[i])) for i, b in idx if not _missing(row[i])]
            out.append(self._estimate(obs, None if _missing(ca) else float(ca)))
        return out

    def predict_ages(self, X, columns: list[str], chronological_age=None) -> list[float | None]:
        return [e.age if e else None for e in self.predict(X, columns, chronological_age)]

    def _objective(self, obs, ca, a) -> float:
        s = sum(((x - b.expected(a)) / b.sd) ** 2 for b, x in obs)
        if ca is not None and self.prior_sd:
            s += ((a - ca) / self.prior_sd) ** 2
        return s

    def _estimate(self, obs, ca) -> Estimate | None:
        if not obs:
            return None
        lo, hi = self.age_range
        w0 = 1 / self.prior_sd ** 2 if ca is not None and self.prior_sd else 0.0
        # Coarse grid for a start that avoids the flat pre-knee region, then Gauss-Newton.
        grid = [lo + 0.5 * i for i in range(int((hi - lo) / 0.5) + 1)]
        a = min(grid, key=lambda g: self._objective(obs, ca, g))
        for _ in range(50):
            num = w0 * (ca or 0.0)
            den = w0
            for b, x in obs:
                k, w = b.rate(a), 1 / b.sd ** 2
                q = b.expected(a) - k * a  # tangent intercept
                num += (x - q) * k * w
                den += k * k * w
            if den <= 0:
                break
            new = min(hi, max(lo, num / den))
            if abs(new - a) < 1e-6:
                a = new
                break
            a = new
        info = w0 + sum((b.rate(a) / b.sd) ** 2 for b, _ in obs)
        se = 1 / math.sqrt(info) if info > 0 else math.inf
        return Estimate(round(a, 2), round(se, 2), len(obs))


def fit(X, columns: list[str], ages) -> dict[str, dict]:
    """Linear KDM parameters (accel 0) from a reference sample, by OLS of each biomarker on age.

    Returns entries in the `kdm_params.json` biomarker format. Needs at least 3 non-missing rows
    per biomarker. Small samples give noisy slopes; prefer shrinking toward the literature prior.
    """
    rows, ages = list(X), [float(a) for a in ages]
    out = {}
    for j, name in enumerate(columns):
        pts = [(a, float(r[j])) for r, a in zip(rows, ages) if not _missing(r[j])]
        if len(pts) < 3:
            continue
        ma = sum(a for a, _ in pts) / len(pts)
        mx = sum(x for _, x in pts) / len(pts)
        sxx = sum((a - ma) ** 2 for a, _ in pts)
        if sxx == 0:
            continue
        k = sum((a - ma) * (x - mx) for a, x in pts) / sxx
        resid = [x - (mx + k * (a - ma)) for a, x in pts]
        sd = math.sqrt(sum(r * r for r in resid) / (len(pts) - 2)) if len(pts) > 2 else 0.0
        out[name] = {"mean25": mx + k * (25 - ma), "sd": sd, "slope": k, "accel": 0.0, "knee": 50,
                     "n": len(pts), "source": "fitted"}
    return out


def main(path: str, params: str | None = None):
    """Print one estimate per CSV row. Header names biomarkers; an `age` column adds the prior."""
    model = KDM.from_config(params) if params else KDM.from_config()
    with open(path, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    ca = [r[header.index("age")] for r in rows] if "age" in header else None
    w = csv.writer(sys.stdout)
    w.writerow(["row", "kdm_age", "se", "n_biomarkers"])
    for i, e in enumerate(model.predict(rows, header, ca)):
        w.writerow([i, e.age, e.se, e.n] if e else [i, "", "", 0])


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: python -m sha_biomarkers.kdm table.csv [params.json]")
    main(*sys.argv[1:])
