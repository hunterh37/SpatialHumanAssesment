"""Refit KDM parameters as sessions accumulate. Spec: specs/age-model.md, "Learning from sessions".

Every refit starts again from the literature priors (`kdm_params.json`) and adds every eligible person, so
no session is counted twice. Per biomarker, the baseline (`mean25`) and yearly `slope` get a Bayesian linear
regression whose prior is the literature value, and `sd` is pooled with the literature `sd`. The knee and
curvature stay from the literature. With few people the prior dominates; each new person moves the fit
toward what the headset measures.

Fitting uses the first time each participant code produced a biomarker, in any session, so single-game and
duel sessions count. Validation uses the calibration rows (first usable Play-all session per code), so
every held-out person is scored on the same games.

A candidate is adopted only when its leave-one-out error is no worse than the current parameters'.

Run: make kdm-fit, or python -m sha_biomarkers.kdm_fit data/kdm/matrix.csv --out-dir data/kdm
"""

from __future__ import annotations

import argparse
import copy
import csv
import datetime as dt
import json
import math
import pathlib
import sys

from .kdm import DEFAULT_PARAMS, KDM, _missing

#: Pseudo-observations behind the literature `sd` when pooling it with the residual SD.
SD_PRIOR_N = 10
#: Fewer fitting people than this leaves a biomarker at its prior.
MIN_FIT_N = 3
#: Fewer validation people than this cannot adopt a candidate.
MIN_VALIDATION_N = 5


def load_matrix(path) -> list[dict]:
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def _age(row) -> float | None:
    return None if _missing(row.get("age")) else float(row["age"])


def fitting_points(rows: list[dict], name: str, exclude_code: str | None = None) -> list[tuple[float, float]]:
    """(age, value) from the first session per participant code that produced `name`."""
    first: dict[str, tuple[str, float, float]] = {}
    for r in rows:
        code, age, v = r.get("code", ""), _age(r), r.get(name)
        if code == exclude_code or age is None or _missing(v):
            continue
        t = r.get("started_at", "")
        if code not in first or t < first[code][0]:
            first[code] = (t, age, float(v))
    return [(a, v) for _, a, v in first.values()]


def _late(p, a):
    return max(0.0, a - p.get("knee", 50.0)) ** 2


def update_biomarker(p: dict, pts: list[tuple[float, float]]) -> tuple[dict, dict]:
    """Posterior of (mean25, slope) and pooled sd for one biomarker. Returns new entry and fit info."""
    out = copy.deepcopy(p)
    info = {"n": len(pts)}
    if len(pts) < MIN_FIT_N:
        return out, info

    sd0 = p["sd"]
    # The device level is unknown, so the baseline prior is one between-person SD wide. Slopes come from
    # large studies: half the literature slope, with a floor so a flat prior can still move.
    v_m = p.get("prior_sd_mean25", sd0) ** 2
    v_k = p.get("prior_sd_slope", max(0.5 * abs(p["slope"]), sd0 / 200)) ** 2
    m0 = [p["mean25"], p["slope"]]
    accel = p.get("accel", 0.0)

    def solve(m0, v_k, accel):
        sigma2 = sd0 ** 2
        for _ in range(5):
            # Precision P = P0 + Z'Z / sigma^2 with Z = [1, age - 25]; y has the fixed curvature removed.
            a11, a12, a22 = 1 / v_m, 0.0, 1 / v_k
            b1, b2 = m0[0] / v_m, m0[1] / v_k
            for a, x in pts:
                z, y = a - 25, x - accel * _late(p, a)
                a11 += 1 / sigma2; a12 += z / sigma2; a22 += z * z / sigma2
                b1 += y / sigma2; b2 += z * y / sigma2
            det = a11 * a22 - a12 * a12
            mean25 = (a22 * b1 - a12 * b2) / det
            slope = (a11 * b2 - a12 * b1) / det
            ssr = sum((x - accel * _late(p, a) - mean25 - slope * (a - 25)) ** 2 for a, x in pts)
            sigma2 = (SD_PRIOR_N * sd0 ** 2 + ssr) / (SD_PRIOR_N + len(pts))
        return mean25, slope, math.sqrt(sigma2), a22 / det, a11 / det

    mean25, slope, sd, var_m, var_k = solve(m0, v_k, accel)
    if p.get("unit") == "s" and mean25 > 0 and p["mean25"] > 0:
        # Proportional slowing: a slower device baseline scales the whole age curve (Brinley plot), so the
        # slope and curvature priors scale with the baseline before the final pass.
        r = mean25 / p["mean25"]
        m0[1] *= r; accel *= r; v_k *= r * r
        mean25, slope, sd, var_m, var_k = solve(m0, v_k, accel)
        info["baseline_ratio"] = round(r, 3)
    if slope * accel < 0:
        accel = 0.0  # data reversed the literature direction; drop curvature so the curve stays monotone
        info["curvature_dropped"] = True

    out.update(mean25=mean25, slope=slope, sd=sd, accel=accel)
    ages = [a for a, _ in pts]
    info.update(
        data_weight_mean25=round(1 - var_m / v_m, 3),
        data_weight_slope=round(1 - var_k / v_k, 3),
        age_min=min(ages), age_max=max(ages),
    )
    out["fit"] = info
    return out, info


def fit_params(prior: dict, rows: list[dict], exclude_code: str | None = None) -> dict:
    cfg = copy.deepcopy(prior)
    cfg.pop("bias_correction", None)
    cfg.pop("validation", None)
    for name, p in prior["biomarkers"].items():
        cfg["biomarkers"][name], _ = update_biomarker(p, fitting_points(rows, name, exclude_code))
    return cfg


def validation_rows(rows: list[dict]) -> list[dict]:
    return [r for r in rows if r.get("calibration") == "1" and _age(r) is not None]


def _evidence(cfg: dict, row: dict) -> float | None:
    m = KDM.from_dict(cfg)
    names = list(m.biomarkers)
    e = m.predict([[row.get(n) for n in names]], names)[0]
    return e.age if e else None


def _ols(xs, ys):
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return my, 0.0
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return my - b * mx, b


def _pearson(xs, ys):
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    return None if sx == 0 or sy == 0 else sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def leave_one_out(prior: dict, current: dict, rows: list[dict]) -> dict:
    """Held-out error of a refit against the current parameters and the predict-the-mean baseline.

    Each validation person is predicted from parameters fitted without any of their sessions. `current` is
    scored as is; if it was fitted on these people its error is optimistic, which makes the gate stricter.
    """
    val = validation_rows(rows)
    ages, cand, cur, base = [], [], [], []
    for r in val:
        a = _age(r)
        others = [_age(o) for o in val if o["code"] != r["code"]]
        pc = _evidence(fit_params(prior, rows, exclude_code=r["code"]), r)
        pu = _evidence(current, r)
        if pc is None or pu is None or not others:
            continue
        ages.append(a); cand.append(pc); cur.append(pu); base.append(sum(others) / len(others))
    n = len(ages)
    rep = {"n": n}
    if n == 0:
        return rep

    def mae(pred):
        return round(sum(abs(p - a) for p, a in zip(pred, ages)) / n, 2)

    rep.update(mae_candidate=mae(cand), mae_current=mae(cur), mae_predict_mean=mae(base))
    r = _pearson(cand, ages)
    rep["r_candidate"] = None if r is None else round(r, 3)
    if n >= 3:
        alpha, beta = _ols(ages, [p - a for p, a in zip(cand, ages)])
        rep["bias_correction"] = {"alpha": round(alpha, 4), "beta": round(beta, 4), "n": n}
        corrected = [p - (alpha + beta * a) for p, a in zip(cand, ages)]
        rep["mae_candidate_corrected"] = mae(corrected)
    return rep


def should_adopt(rep: dict) -> bool:
    return rep.get("n", 0) >= MIN_VALIDATION_N and rep["mae_candidate"] <= rep["mae_current"]


def coverage(rows: list[dict]) -> dict[str, int]:
    """Validation people per age decade. Thin decades mean the curve there still leans on the literature."""
    out: dict[str, int] = {}
    for r in validation_rows(rows):
        d = int(_age(r) // 10 * 10)
        out[f"{d}s"] = out.get(f"{d}s", 0) + 1
    return dict(sorted(out.items()))


def device_offsets(cfg: dict, rows: list[dict]) -> dict[str, dict]:
    """Mean standardized residual per headset (positive looks older). A large gap means do not pool yet."""
    m = KDM.from_dict(cfg)
    acc: dict[str, list[float]] = {}
    for r in rows:
        dev, a = r.get("device_id") or "unknown", _age(r)
        if a is None:
            continue
        for name, b in m.biomarkers.items():
            if not _missing(r.get(name)):
                acc.setdefault(dev, []).append((float(r[name]) - b.expected(a)) / b.sd * (1 if b.slope >= 0 else -1))
    return {d: {"n": len(z), "mean_z": round(sum(z) / len(z), 3)} for d, z in acc.items() if len(z) >= 3}


def refit(prior: dict, current: dict, rows: list[dict], force: bool = False) -> tuple[dict, dict, bool]:
    """Returns (candidate params, report, adopted)."""
    rep = leave_one_out(prior, current, rows)
    cand = fit_params(prior, rows)
    n_people = len({r["code"] for r in rows if _age(r) is not None})
    cand["version"] = f"fit-{dt.datetime.now():%Y%m%d-%H%M}-n{n_people}"
    cand["based_on"] = prior.get("version", "")
    if "bias_correction" in rep:
        cand["bias_correction"] = rep["bias_correction"]
    cand["validation"] = {k: v for k, v in rep.items() if k != "bias_correction"}
    adopted = force or should_adopt(rep)
    report = {
        "version": cand["version"],
        "adopted": adopted,
        "current_version": current.get("version", ""),
        "people": n_people,
        "validation": rep,
        "coverage": coverage(rows),
        "biomarkers": {n: p.get("fit", {"n": 0}) for n, p in cand["biomarkers"].items()},
        "device_offsets": device_offsets(cand, rows),
    }
    return cand, report, adopted


def main(argv: list[str]):
    ap = argparse.ArgumentParser(prog="python -m sha_biomarkers.kdm_fit")
    ap.add_argument("matrix")
    ap.add_argument("--prior", default=str(DEFAULT_PARAMS), help="literature parameters every refit starts from")
    ap.add_argument("--out-dir", default="data/kdm")
    ap.add_argument("--force", action="store_true", help="adopt even if validation does not improve")
    args = ap.parse_args(argv)

    out = pathlib.Path(args.out_dir)
    current_path = out / "params.json"
    prior = json.loads(pathlib.Path(args.prior).read_text())
    current = json.loads(current_path.read_text()) if current_path.exists() else prior
    cand, report, adopted = refit(prior, current, load_matrix(args.matrix), args.force)

    hist = out / "history"
    hist.mkdir(parents=True, exist_ok=True)
    (hist / f"{cand['version']}.json").write_text(json.dumps(cand, indent=2) + "\n")
    (hist / f"{cand['version']}.report.json").write_text(json.dumps(report, indent=2) + "\n")
    if adopted:
        current_path.write_text(json.dumps(cand, indent=2) + "\n")

    v = report["validation"]
    if v.get("n", 0):
        print(f"{cand['version']}: {v['n']} validation people, LOO MAE {v['mae_candidate']} y "
              f"(current {v['mae_current']}, predict-the-mean {v['mae_predict_mean']})")
    else:
        print(f"{cand['version']}: no validation people yet (need calibration rows with an age)")
    if adopted:
        print(f"adopted -> {current_path}")
    else:
        print(f"kept {current.get('version', '')}; candidate saved in {hist} "
              f"(needs {MIN_VALIDATION_N}+ validation people and no worse MAE, or --force)")


if __name__ == "__main__":
    main(sys.argv[1:])
