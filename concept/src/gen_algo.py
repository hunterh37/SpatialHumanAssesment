"""Builds concept/SpatialAge_Algorithms.pdf from live ScoreKit output.

    make concept-algo

Inputs (written by the make target into concept/build/):
    norms.json    scorekit norms
    reports.json  scorekit score over a synthetic cohort
    pace.json     scorekit pace over one synthetic participant history
"""
import html, json, math, os, subprocess, sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
BUILD = os.path.join(ROOT, "build")
OUT_HTML = os.path.join(BUILD, "algorithms.html")
OUT_PDF = os.path.join(ROOT, "SpatialAge_Algorithms.pdf")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

INK = "#1b2430"; PAPER = "#f6f4ef"; GRID = "#d9d4c7"; MUTE = "#8a8f99"; SOFT = "#4a5160"
BLUE = "#2f6bff"; ORANGE = "#ff7a3d"; TEAL = "#14b8a6"; GOLD = "#e0a400"; PLUM = "#8b5cf6"
FONT = "Helvetica Neue, Helvetica, Arial, sans-serif"
DOMAIN_COLOR = {"speed": BLUE, "decision": ORANGE, "control": TEAL, "memory": PLUM, "consistency": GOLD}
DOMAINS = ["speed", "decision", "control", "memory", "consistency"]
GAMES = ["pendulum", "spark", "gate", "constellation", "orbit"]


def load(name):
    return json.load(open(os.path.join(BUILD, name)))


NORMS = {n["id"]: n for n in load("norms.json")["norms"]}
REPORTS = load("reports.json")
PACE = load("pace.json")
DEMO = next(r for r in REPORTS if r["participant_code"] == "SYN024")


# ---------- svg primitives ----------
def esc(s): return html.escape(str(s))
def svg(w, h, body): return f"<svg viewBox='0 0 {w} {h}' width='{w}' height='{h}' xmlns='http://www.w3.org/2000/svg' font-family='{FONT}'>{body}</svg>"
def ln(x1, y1, x2, y2, c=INK, w=1.5, dash=None, op=1):
    d = f" stroke-dasharray='{dash}'" if dash else ""
    return f"<line x1='{x1:.1f}' y1='{y1:.1f}' x2='{x2:.1f}' y2='{y2:.1f}' stroke='{c}' stroke-width='{w}' stroke-linecap='round' opacity='{op}'{d}/>"
def tx(x, y, s, size=11, c=INK, wt=400, anchor="start", ls=0):
    return f"<text x='{x:.1f}' y='{y:.1f}' font-size='{size}' fill='{c}' font-weight='{wt}' text-anchor='{anchor}' letter-spacing='{ls}'>{esc(s)}</text>"
def dot(x, y, r, fill, stroke=None, sw=1.5):
    s = f" stroke='{stroke}' stroke-width='{sw}'" if stroke else ""
    return f"<circle cx='{x:.1f}' cy='{y:.1f}' r='{r}' fill='{fill}'{s}/>"
def path(pts, c=INK, w=2, fill="none", op=1, dash=None):
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    da = f" stroke-dasharray='{dash}'" if dash else ""
    return f"<path d='{d}' stroke='{c}' stroke-width='{w}' fill='{fill}' opacity='{op}' stroke-linejoin='round' stroke-linecap='round'{da}/>"
def rect(x, y, w, h, fill, op=1, rx=0):
    return f"<rect x='{x:.1f}' y='{y:.1f}' width='{w:.1f}' height='{h:.1f}' fill='{fill}' opacity='{op}' rx='{rx}'/>"
def diamond(x, y, r, fill):
    return f"<polygon points='{x-r:.1f},{y:.1f} {x:.1f},{y-r*0.7:.1f} {x+r:.1f},{y:.1f} {x:.1f},{y+r*0.7:.1f}' fill='{fill}'/>"


class Axis:
    def __init__(self, x0, x1, y0, y1, X, Y):
        self.x0, self.x1, self.y0, self.y1, self.X, self.Y = x0, x1, y0, y1, X, Y
    def x(self, v): return self.X[0] + (v - self.x0) / (self.x1 - self.x0) * (self.X[1] - self.X[0])
    def y(self, v): return self.Y[0] + (v - self.y0) / (self.y1 - self.y0) * (self.Y[1] - self.Y[0])
    def frame(self, xt, yt, xl="", yl="", fx=lambda v: f"{v:g}", fy=lambda v: f"{v:g}"):
        o = ""
        for v in yt:
            o += ln(self.X[0], self.y(v), self.X[1], self.y(v), GRID, 1)
            o += tx(self.X[0] - 8, self.y(v) + 4, fy(v), 10, MUTE, anchor="end")
        for v in xt:
            o += tx(self.x(v), self.Y[0] + 16, fx(v), 10, MUTE, anchor="middle")
        o += ln(self.X[0], self.Y[0], self.X[1], self.Y[0], INK, 1.2)
        if xl: o += tx(self.X[1], self.Y[0] + 32, xl, 10, MUTE, 700, "end", 1.5)
        if yl: o += tx(self.X[0] - 40, self.Y[1] - 14, yl, 10, MUTE, 700, "start", 1.5)
        return o


# ---------- figures ----------
def fig_funnel():
    """Games -> metrics -> domains -> Spatial Age."""
    W, H = 640, 560
    modeled = [m for m, n in NORMS.items() if n.get("domain") and n["tau_years"] <= 50]
    game_of = {m["id"]: m["game"] for m in DEMO["metrics"]}
    modeled.sort(key=lambda m: (DOMAINS.index(NORMS[m]["domain"]), GAMES.index(game_of.get(m, "orbit"))))
    cols = [110, 290, 480, 610]
    gy = {g: 70 + i * 105 for i, g in enumerate(GAMES)}
    my = {m: 30 + i * (500 / (len(modeled) - 1)) for i, m in enumerate(modeled)}
    dy = {d: 90 + i * 95 for i, d in enumerate(DOMAINS)}
    ay = 280
    o = ""
    for m in modeled:
        g, d = game_of.get(m), NORMS[m]["domain"]
        if g: o += path([(cols[0], gy[g]), ((cols[0] + cols[1]) / 2, gy[g]), ((cols[0] + cols[1]) / 2, my[m]), (cols[1], my[m])], GRID, 1.2)
        o += path([(cols[1], my[m]), (cols[2] - 60, my[m]), (cols[2] - 30, dy[d]), (cols[2], dy[d])], DOMAIN_COLOR[d], 1.2, op=0.55)
    for d in DOMAINS:
        o += path([(cols[2], dy[d]), (cols[3] - 40, dy[d]), (cols[3] - 20, ay), (cols[3], ay)], DOMAIN_COLOR[d], 2, op=0.8)
    for g in GAMES:
        o += dot(cols[0], gy[g], 6, INK) + tx(cols[0] - 14, gy[g] + 4, g.title(), 12, INK, 600, "end")
    for m in modeled:
        o += dot(cols[1], my[m], 3.2, PAPER, INK, 1.4) + tx(cols[1] + 8, my[m] + 3.5, m.replace("_", " "), 9.5, SOFT)
    for d in DOMAINS:
        o += dot(cols[2], dy[d], 7, DOMAIN_COLOR[d]) + tx(cols[2] - 12, dy[d] - 11, d.title(), 11, INK, 600, "end")
    o += dot(cols[3], ay, 13, INK) + dot(cols[3], ay, 5, PAPER)
    o += tx(cols[3], ay + 34, "Spatial Age", 12, INK, 700, "middle")
    for x, label in zip(cols, ["5 GAMES", f"{len(modeled)} METRICS", "5 DOMAINS", "1 AGE"]):
        o += tx(x, 548, label, 9.5, MUTE, 700, "middle", 1.8)
    return svg(W, H, o)


def min_jerk(t, t0, dur, amp):
    s = np.clip((t - t0) / dur, 0, 1)
    return amp * (10 * s**3 - 15 * s**4 + 6 * s**5)


def fig_kinematics():
    """Synthetic reach through the ScoreKit onset pipeline (Kinematics.swift)."""
    rng = np.random.default_rng(3)
    raw_t = np.cumsum(rng.uniform(0.008, 0.014, 130))
    raw_t -= raw_t[0]
    pos = np.stack([min_jerk(raw_t, 0.33, 0.50, 0.42), min_jerk(raw_t, 0.36, 0.46, 0.12), min_jerk(raw_t, 0.33, 0.52, -0.06)], 1)
    pos += rng.normal(0, 0.0012, pos.shape)
    t = np.arange(0, raw_t[-1], 1 / 90)
    p = np.stack([np.interp(t, raw_t, pos[:, k]) for k in range(3)], 1)
    k = np.exp(-np.arange(-6, 7) ** 2 / 8.0)
    ps = np.stack([np.convolve(np.pad(p[:, i], 6, mode="edge"), k / k.sum(), "valid") for i in range(3)], 1)
    v = np.gradient(ps, t, axis=0)
    sp = np.linalg.norm(v, axis=1)
    contact = 0.86
    need = math.ceil(0.05 * 90)
    run, first = 0, None
    for i, s in enumerate(sp):
        run = run + 1 if s > 0.15 else 0
        if run >= need: first = i - need + 1; break
    stop = int(contact * 90)
    pk = first + int(np.argmax(sp[first:stop]))
    i = first
    while i > 0 and sp[i - 1] > sp[pk] * 0.05: i -= 1
    onset = t[i]

    W, H = 640, 340
    a = Axis(0, 1.0, 0, 2.0, (60, 610), (290, 50))
    o = a.frame([0, .2, .4, .6, .8, 1.0], [0, .5, 1.0, 1.5, 2.0], "TIME AFTER SPAWN (S)", "SPEED (M/S)",
                fx=lambda v: f"{v:.1f}", fy=lambda v: f"{v:.1f}")
    o += rect(a.x(0), 50, a.x(onset) - a.x(0), 240, BLUE, 0.06)
    o += rect(a.x(onset), 50, a.x(contact) - a.x(onset), 240, TEAL, 0.07)
    o += ln(a.x(0), a.y(0.15), a.X[1], a.y(0.15), ORANGE, 1.2, "4 4")
    o += tx(a.x(0.02), a.y(0.15) - 6, "0.15 m/s for 50 ms", 9.5, ORANGE, 600)
    o += path([(a.x(x), a.y(y)) for x, y in zip(t, sp) if x <= 1.0], INK, 2.2)
    o += ln(a.x(t[first]), a.y(0.15), a.x(onset), a.y(0.15), ORANGE, 2)
    o += dot(a.x(onset), a.y(sp[i]), 4.5, BLUE)
    o += tx(a.x(onset) - 6, a.y(0.42), "onset, walked back", 9.5, BLUE, 600, "end")
    o += tx(a.x(onset) - 6, a.y(0.42) + 12, "to 5% of peak", 9.5, BLUE, 400, "end")
    o += dot(a.x(t[pk]), a.y(sp[pk]), 4.5, INK) + tx(a.x(t[pk]) + 8, a.y(sp[pk]) + 4, f"peak {sp[pk]:.2f} m/s", 10, INK, 600)
    o += ln(a.x(contact), 50, a.x(contact), 290, INK, 1.2, "2 4")
    o += tx(a.x(contact) + 6, 64, "contact", 9.5, INK, 600)
    o += tx((a.x(0) + a.x(onset)) / 2, a.y(1.15), f"RT {onset*1000:.0f} ms", 12, BLUE, 700, "middle")
    o += tx((a.x(onset) + a.x(contact)) / 2, a.y(1.15) + 18, f"MT {(contact-onset)*1000:.0f} ms", 12, TEAL, 700, "middle")
    o += tx(a.x(0) + 4, 64, "spawn", 9.5, MUTE, 600)
    return svg(W, H, o)


def fig_norm():
    m = next(x for x in DEMO["metrics"] if x["id"] == "reach_rt")
    n = NORMS["reach_rt"]
    f = lambda age: n["mean25"] + n["slope"] * (age - 25) + n["accel"] * max(0, age - 50) ** 2
    W, H = 620, 440
    a = Axis(18, 95, 0.24, 0.52, (64, 600), (380, 30))
    o = a.frame([20, 30, 40, 50, 60, 70, 80, 90], [0.25, 0.30, 0.35, 0.40, 0.45, 0.50], "AGE (YEARS)", "REACH RT (S)",
                fy=lambda v: f"{v:.2f}")
    ages = np.linspace(18, 95, 200)
    up = [(a.x(x), a.y(f(x) + n["sd25"])) for x in ages]
    lo = [(a.x(x), a.y(f(x) - n["sd25"])) for x in ages[::-1]]
    o += f"<polygon points='{' '.join(f'{x:.1f},{y:.1f}' for x, y in up + lo)}' fill='{BLUE}' opacity='0.07'/>"
    o += path([(a.x(x), a.y(f(x))) for x in ages], BLUE, 2.4)
    age, sd = m["metric_age"], m["metric_age_sd"]
    o += rect(a.x(max(18, age - sd)), 376, a.x(min(95, age + sd)) - a.x(max(18, age - sd)), 8, ORANGE, 0.35, 3)
    o += ln(a.X[0], a.y(m["value"]), a.x(age), a.y(m["value"]), ORANGE, 1.4, "4 4")
    o += ln(a.x(age), a.y(m["value"]), a.x(age), a.Y[0], ORANGE, 1.4, "4 4")
    o += dot(a.x(age), a.y(m["value"]), 6, ORANGE, PAPER, 2)
    o += tx(a.X[0] + 8, a.y(m["value"]) - 8, f"measured {m['value']*1000:.0f} ms", 10.5, ORANGE, 700)
    o += tx(a.x(age) + 10, a.y(m["value"]) + 22, f"metric age {age:.1f} ± {sd:.1f} y", 10.5, ORANGE, 700)
    o += tx(a.x(88), a.y(f(88)) - 16, "expected", 10, BLUE, 700, "end")
    o += tx(a.x(80), a.y(f(80) - n["sd25"]) + 18, "±1 SD at 25", 9.5, BLUE, 400)
    o += ln(a.x(50), 30, a.x(50), 380, GRID, 1, "2 4") + tx(a.x(50) + 5, 42, "quadratic term starts", 9, MUTE)
    return svg(W, H, o)


def fig_forest():
    r = DEMO
    W = 980
    rows = []
    for d in DOMAINS:
        ms = [m for m in r["metrics"] if m.get("domain") == d and m.get("metric_age") is not None]
        rows.append(("domain", d, next(x for x in r["domains"] if x["domain"] == d)))
        for m in ms: rows.append(("metric", d, m))
    rows.append(("gap", None, None))
    rows.append(("evidence", None, None))
    rows.append(("prior", None, None))
    rows.append(("posterior", None, None))
    RH = 15.5
    H = 50 + len(rows) * RH + 30
    a = Axis(18, 95, 0, 1, (330, 940), (H - 30, 0))
    o = ""
    for v in [20, 30, 40, 50, 60, 70, 80, 90]:
        o += ln(a.x(v), 34, a.x(v), H - 34, GRID, 1)
        o += tx(a.x(v), H - 14, f"{v}", 10, MUTE, anchor="middle")
    chrono = r["chronological_age"]
    o += ln(a.x(chrono), 34, a.x(chrono), H - 34, INK, 1, "3 3")
    o += tx(a.x(chrono), 24, f"chronological {chrono:.0f}", 9.5, INK, 700, "middle")
    o += tx(20, 24, "METRIC", 9.5, MUTE, 700, ls=1.8) + tx(250, 24, "VALUE", 9.5, MUTE, 700, "end", 1.8)
    o += tx(318, 24, "AGE ± SD", 9.5, MUTE, 700, "end", 1.8)
    y = 46
    clip = lambda v: min(max(v, 18), 95)
    for kind, d, x in rows:
        if kind == "gap":
            o += ln(20, y - 4, 940, y - 4, GRID, 1); y += RH * 0.4; continue
        if kind == "domain":
            c = DOMAIN_COLOR[d]
            o += ln(a.x(clip(x["age"] - x["age_sd"])), y, a.x(clip(x["age"] + x["age_sd"])), y, c, 3, op=0.9)
            o += diamond(a.x(x["age"]), y, 8, c)
            o += tx(20, y + 4, f"{d.title()}  ·  {x['score']:.0f}/100", 11, INK, 700)
            o += tx(318, y + 4, f"{x['age']:.1f} ± {x['age_sd']:.1f}", 10.5, INK, 700, "end")
        elif kind == "metric":
            c = DOMAIN_COLOR[d]
            o += ln(a.x(clip(x["metric_age"] - x["metric_age_sd"])), y, a.x(clip(x["metric_age"] + x["metric_age_sd"])), y, c, 1.2, op=0.6)
            o += dot(a.x(x["metric_age"]), y, 3.2, PAPER, c, 1.5)
            unit = x["unit"]
            val = f"{x['value']*1000:.0f} ms" if unit == "s" else (f"{x['value']:.2f} {unit}" if unit not in ("", "ratio") else f"{x['value']:.2f}")
            o += tx(34, y + 3.5, x["label"], 10, SOFT) + tx(250, y + 3.5, val, 10, SOFT, anchor="end")
            o += tx(318, y + 3.5, f"{x['metric_age']:.1f} ± {x['metric_age_sd']:.1f}", 10, SOFT, anchor="end")
        else:
            if kind == "evidence":
                age, sd, c, label = r["evidence_age"], evidence_sd(r), MUTE, "Evidence (domains fused)"
            elif kind == "prior":
                age, sd, c, label = chrono, 9.0, GRID, "Prior (chronological, SD 9)"
            else:
                age, sd, c, label = r["spatial_age"], r["spatial_age_sd"], INK, "Spatial Age (posterior)"
            o += ln(a.x(clip(age - sd)), y, a.x(clip(age + sd)), y, c, 4)
            o += diamond(a.x(age), y, 10, c if kind != "prior" else MUTE)
            o += tx(20, y + 4, label, 11, INK, 700)
            o += tx(318, y + 4, f"{age:.1f} ± {sd:.1f}", 10.5, INK, 700, "end")
        y += RH
    return svg(W, int(H), o)


def evidence_sd(r):
    # Posterior precision = evidence precision + prior precision (SpatialAgeModel.swift).
    return (1 / (1 / r["spatial_age_sd"] ** 2 - 1 / 81)) ** 0.5


def fig_cohort():
    xs = [r["chronological_age"] for r in REPORTS]
    ys = [r["evidence_age"] for r in REPORTS]
    W, H = 440, 400
    a = Axis(15, 85, 15, 85, (56, 420), (350, 20))
    o = a.frame([20, 40, 60, 80], [20, 40, 60, 80], "CHRONOLOGICAL AGE", "EVIDENCE AGE")
    o += ln(a.x(15), a.y(15), a.x(85), a.y(85), INK, 1, "3 4")
    b = np.polyfit(xs, ys, 1)
    o += ln(a.x(18), a.y(np.polyval(b, 18)), a.x(80), a.y(np.polyval(b, 80)), BLUE, 1.6, op=0.7)
    for x, y in zip(xs, ys): o += dot(a.x(x), a.y(y), 4.2, BLUE, PAPER, 1.2)
    o += tx(a.x(83), a.y(83) - 8, "identity", 9.5, MUTE, 600, "end")
    o += tx(a.x(84), a.y(np.polyval(b, 80)) + 52, f"fit slope {b[0]:.2f}", 9.5, BLUE, 700, "end")
    return svg(W, H, o), b[0]


def fig_pace():
    pts = PACE["points"]
    import datetime as dt
    d0 = dt.datetime.fromisoformat(pts[0]["date"].replace("Z", "+00:00"))
    days = [(dt.datetime.fromisoformat(p["date"].replace("Z", "+00:00")) - d0).days for p in pts]
    ages = [p["spatial_age"] for p in pts]
    sds = [p["sd"] for p in pts]
    W, H = 440, 400
    a = Axis(-10, 250, 34, 66, (56, 420), (350, 20))
    o = a.frame([0, 60, 120, 180, 240], [35, 45, 55, 65], "DAYS", "SPATIAL AGE")
    for x, y, s in zip(days, ages, sds):
        o += ln(a.x(x), a.y(y - s), a.x(x), a.y(y + s), ORANGE, 1.2, op=0.35)
        o += dot(a.x(x), a.y(y), 4.2, ORANGE, PAPER, 1.2)
    w = [1 / s**2 for s in sds]
    mx = sum(d * wi for d, wi in zip(days, w)) / sum(w); my = sum(y * wi for y, wi in zip(ages, w)) / sum(w)
    raw = PACE["pace"]["raw_slope"]; pace = PACE["pace"]["pace"]
    f = lambda d, s: my + s * (d - mx) / 365.25
    o += ln(a.x(0), a.y(f(0, raw)), a.x(240), a.y(f(240, raw)), ORANGE, 1.6, "5 4")
    o += ln(a.x(0), a.y(f(0, pace)), a.x(240), a.y(f(240, pace)), INK, 2.2)
    o += tx(a.x(240), a.y(f(240, raw)) - 22, f"raw WLS {raw:.1f} y/y", 9.5, ORANGE, 700, "end")
    o += tx(a.x(240), a.y(f(240, pace)) + 18, f"shrunk {pace:.2f} y/y", 9.5, INK, 700, "end")
    return svg(W, H, o)


# ---------- page content ----------
def metric_rows():
    ESTIMATOR = {
        "catch_latency": ("Robust median of grasp time minus release; < 100 ms dropped as anticipation", "1.2533·s/√n"),
        "catch_drop_cm": ("Robust median of fall distance at grasp; ruler-drop d = g t² / 2", "display"),
        "catch_rate": ("Catches / attempts", "Agresti-Coull"),
        "reach_rt": ("Robust median, trace onset minus spawn, 100 to 1500 ms kept", "1.2533·s/√n"),
        "reach_mt": ("Robust median, contact minus onset", "1.2533·s/√n"),
        "rt_tau": ("Ex-Gaussian τ by method of moments, untrimmed RTs, n ≥ 8", "default"),
        "rt_cv": ("SD / mean of MAD-trimmed RTs", "default"),
        "ecc_slope": ("OLS of RT + MT on eccentricity / 90°", "OLS slope SE"),
        "peak_speed": ("Robust median of per-reach peak speed", "1.2533·s/√n"),
        "path_efficiency": ("Straight distance / path length", "1.2533·s/√n"),
        "smoothness": ("LDLJ = −ln(D³ / v²peak · ∫|jerk|² dt)", "1.2533·s/√n"),
        "choice_rt": ("Robust median RT on Gate hits", "1.2533·s/√n"),
        "decision_time": ("Choice RT minus Spark RT", "√(SE₁² + SE₂²)"),
        "commission_rate": ("False alarms / kept trials", "Agresti-Coull"),
        "omission_rate": ("Misses / go trials", "flag only"),
        "d_prime": ("Φ⁻¹(H) − Φ⁻¹(F), log-linear correction (Hautus 1995)", "default"),
        "corsi_span": ("Longest sequence recalled in order", "fixed 0.5"),
        "corsi_total": ("Span × correct sequences (Kessels 2008)", "default"),
        "corsi_tap_interval": ("Robust median gap between recall taps", "display"),
        "pursuit_rms_cm": ("RMS fingertip-to-target distance after 1 s acquisition", "SD / √trials"),
        "pursuit_lag_ms": ("Grid search 0 to 500 ms, 5 ms step, min summed distance", "SD / √trials"),
        "pursuit_on_target": ("Share of samples within 4 cm", "display"),
        "pursuit_gain": ("Fingertip velocity projected on lag-aligned target velocity", "display"),
    }
    rows = ""
    last = None
    for m in DEMO["metrics"]:
        n = NORMS[m["id"]]
        g = m["game"].title() if m["game"] != last else ""
        last = m["game"]
        d = n.get("domain") if n["tau_years"] <= 50 else None
        chip = f"<span class='chip' style='background:{DOMAIN_COLOR[d]}'></span>{d}" if d else "<span class='mute'>display</span>"
        est, se = ESTIMATOR[m["id"]]
        rows += (f"<tr class='{'gs' if g else ''}'><td class='g'>{g}</td><td class='mid'>{esc(m['id'])}</td><td>{esc(est)}</td>"
                 f"<td class='mute'>{esc(se)}</td><td>{chip}</td><td class='num'>{n['tau_years'] if d else ''}</td></tr>")
    return rows


def games_cards():
    G = [
        ("pendulum", "Catch the weight when the cord lets go.", "3 + 12", "Catch latency, drop distance, catch rate"),
        ("spark", "Touch each light as it appears.", "5 + 20", "Reaction, movement, reach kinematics"),
        ("gate", "Touch blue. Leave orange.", "5 + 30", "Decision time, inhibition, d′"),
        ("constellation", "Watch the stars light, then touch them in order.", "1 + 14", "Spatial working memory span"),
        ("orbit", "Keep your fingertip inside the moving light.", "1 + 3", "Tracking error, lag, velocity gain"),
    ]
    out = ""
    for i, (g, ins, trials, meas) in enumerate(G, 1):
        gr = next(x for x in DEMO["games"] if x["game"] == g)
        head = next(m for m in DEMO["metrics"] if m["id"] == gr["headline"])
        unit = head["unit"]
        v = f"{head['value']*1000:.0f}<small>ms</small>" if unit == "s" else f"{head['value']:.1f}<small>{unit}</small>"
        out += (f"<div class='card'><div class='idx'>0{i}</div><h3>{g.title()}</h3><p class='ins'>{esc(ins)}</p>"
                f"<div class='kv'><b>TRIALS</b>{trials}</div><div class='kv'><b>MEASURES</b>{esc(meas)}</div>"
                f"<div class='big'>{v}</div><div class='mute s'>{esc(head['label'])}, SYN024</div></div>")
    return out


def page(n, body, cls=""):
    return f"<section class='page {cls}'>{body}<div class='foot'>SPATIAL AGE · SCOREKIT 0.2.0 · {n:02d} / 08</div></section>"


def build():
    cohort_svg, fit_slope = fig_cohort()
    xs = [r["chronological_age"] for r in REPORTS]; ev = [r["evidence_age"] for r in REPORTS]
    mae = sum(abs(a - b) for a, b in zip(ev, xs)) / len(xs)
    base = sum(abs(np.mean(xs) - b) for b in xs) / len(xs)
    r = float(np.corrcoef(xs, ev)[0, 1])
    usable = sum(1 for x in REPORTS if x["quality"]["usable"])
    ev_sd = float(np.mean([evidence_sd(x) for x in REPORTS]))
    P = PACE["pace"]
    raw_se = (1 / (1 / P["sd"] ** 2 - 1 / 0.25)) ** 0.5
    D = DEMO

    pages = []
    pages.append(page(1, f"""
<div class='cover-l'>
  <div class='k'>Concept 04 · Algorithms</div>
  <h1>Spatial Age</h1>
  <p class='lede'>Five Vision Pro minigames, played with a bare fingertip in the user's own room, produce {sum(1 for m,n in NORMS.items() if n.get('domain') and n['tau_years']<=50)} measurements of speed, decision, control, memory and consistency. ScoreKit turns them into one functional age with an uncertainty interval.</p>
  <div class='stats'>
    <div><b>{len(NORMS)}</b><span>metrics extracted</span></div>
    <div><b>5</b><span>domains fused</span></div>
    <div><b>6 min</b><span>session</span></div>
  </div>
  <p class='note'>Every number in this document is produced by ScoreKit {D['engine_version']} with norm table {D['norms_version']} on synthetic sessions from ScoreKitSynth. No participant data yet.</p>
</div>
<div class='cover-r'>{fig_funnel()}</div>""", "cover"))

    pages.append(page(2, f"""
<div class='head'><div class='k'>01 · Input</div><h2>Five minigames, one session file</h2>
<p>Each game opens with unscored familiarization trials. Every scored trial logs a 90 Hz fingertip trace, timestamps and a per-trial hand tracking gap. Reach trials with a gap over 100 ms are dropped; Orbit masks gaps up to 300 ms.</p></div>
<div class='cards'>{games_cards()}</div>"""))

    pages.append(page(3, f"""
<div class='head'><div class='k'>02 · Signal</div><h2>From fingertip trace to reaction and movement time</h2></div>
<div class='split'>
<div class='figw'>{fig_kinematics()}<div class='cap'>Synthetic minimum-jerk reach run through the same pipeline as <code>Kinematics.swift</code>.</div></div>
<ol class='steps'>
<li><b>Resample</b>Linear interpolation onto a uniform 90 Hz grid.</li>
<li><b>Smooth</b>Gaussian kernel, σ = 2 samples (22 ms).</li>
<li><b>Differentiate</b>Central difference velocity, speed = |v|.</li>
<li><b>Onset</b>First run of speed above 0.15 m/s held for 50 ms, then walked back to where speed last fell below 5% of peak. Device <code>move_t</code> is a fallback.</li>
<li><b>Gate</b>RT under 100 ms is an anticipation, over 1500 ms a lapse. Both drop from timing stats.</li>
<li><b>Reach shape</b>Peak speed, path efficiency, log dimensionless jerk (LDLJ) and submovement count between onset and contact.</li>
</ol></div>"""))

    pages.append(page(4, f"""
<div class='head'><div class='k'>03 · Metrics</div><h2>{len(NORMS)} metrics, each with a standard error</h2>
<p>Medians are taken after dropping values more than 3 scaled MADs from the median. The standard error feeds the age model, so a game played with few clean trials carries less weight. τ is the norm's residual error as an age predictor, in years.</p></div>
<table class='mt'><thead><tr><th>Game</th><th>Metric</th><th>Estimator</th><th>SE</th><th>Domain</th><th class='num tau'>τ (y)</th></tr></thead>
<tbody>{metric_rows()}</tbody></table>"""))

    n = NORMS["reach_rt"]
    pages.append(page(5, f"""
<div class='head'><div class='k'>04 · Norms</div><h2>Each metric is inverted through an age curve</h2></div>
<div class='split'>
<div class='figw'>{fig_norm()}<div class='cap'>Reach RT for SYN024 against the provisional norm (Der and Deary 2006 shape).</div></div>
<div class='eq'>
<div class='f'>E[x | a] = μ<sub>25</sub> + β (a − 25) + γ · max(0, a − 50)²</div>
<p>Linear decline from 25 with an extra quadratic term after 50, the shape reported for processing speed and Corsi span.</p>
<div class='f'>â = E⁻¹(x)</div>
<p>Bisection on the monotone curve, 60 iterations, clamped to 18 to 95.</p>
<div class='f'>σ<sub>â</sub> = √( (SE / |E′(â)|)² + τ² )</div>
<p>Measurement error converted to years through the local slope, plus the metric's residual error τ. Where the curve is steep a small difference in milliseconds maps to few years, so older ages get tighter estimates.</p>
<div class='f mute'>reach_rt: μ<sub>25</sub> {n['mean25']} s · β {n['slope']} s/y · γ {n['accel']:.5f} · τ {n['tau_years']} y</div>
</div></div>"""))

    pages.append(page(6, f"""
<div class='head row'><div><div class='k'>05 · Fusion</div><h2>Metrics fuse into domains, domains into one age</h2></div>
<div class='rule'>Inverse-variance mean, variance × (1 + (k − 1) ρ). ρ = 0.5 inside a domain, 0.3 between domains. A chronological prior with SD 9 y pulls thin evidence toward the calendar. Interval is 80%.</div></div>
<div class='forest'>{fig_forest()}</div>
<div class='result'><span>SYN024 · age {D['chronological_age']:.0f}</span><b>{D['spatial_age']:.1f}</b><span>80% interval {D['spatial_age_low']:.1f} to {D['spatial_age_high']:.1f} · gap {D['age_gap']:+.1f} y · valid trials {D['quality']['valid_trial_rate']*100:.0f}%</span></div>"""))

    pages.append(page(7, f"""
<div class='head'><div class='k'>06 · Validation (synthetic)</div><h2>Cohort accuracy and pace of aging</h2></div>
<div class='two'>
<div>{cohort_svg}
<div class='kpis'><div><b>{mae:.1f} y</b><span>evidence MAE</span></div><div><b>{base:.1f} y</b><span>predict-the-mean</span></div><div><b>{r:.2f}</b><span>Pearson r</span></div></div>
<p class='s'>n = {len(REPORTS)}, ages {min(xs):.0f} to {max(xs):.0f}, {usable} usable. Evidence age excludes the chronological prior; the posterior is not an accuracy measure because it already contains the answer. Synthetic biological age = chronological + N(0, 6), so part of the error is real signal. Fit slope {fit_slope:.2f} shows regression toward the cohort middle.</p></div>
<div>{fig_pace()}
<div class='kpis'><div><b>{P['pace']:.2f}</b><span>pace, y per y</span></div><div><b>± {P['sd']:.2f}</b><span>posterior SD</span></div><div><b>0.80</b><span>simulated truth</span></div></div>
<p class='s'>One participant, {P['sessions']} sessions over {P['window_days']:.0f} days. WLS slope of Spatial Age on time, weights 1/SD², shrunk toward 1.0 with prior SD 0.5. Raw slope {P['raw_slope']:.1f} ± {raw_se:.0f} y/y, so the estimate stays at the prior. Session SD needs to fall well under 7 y before pace is measurable inside a year.</p></div>
</div>"""))

    pages.append(page(8, f"""
<div class='head'><div class='k'>07 · Status</div><h2>Built, in progress, open</h2></div>
<table class='st'>
<tr><td class='tag done'>Built</td><td><b>ScoreKit 0.2.0</b>Swift package, pure function session → report. 5 extractors, kinematics, robust stats, age model, pace of aging, CLI (<code>score</code>, <code>pace</code>, <code>synth</code>, <code>history</code>, <code>norms</code>). 15 tests pass.</td></tr>
<tr><td class='tag done'>Built</td><td><b>Session schema 0.2.0</b>One JSON contract shared by the app, ingest, ML and dashboard. Report JSON uses snake_case and is versioned by engine and norm table.</td></tr>
<tr><td class='tag prog'>In progress</td><td><b>Norm table prior-0.2</b>Curve shapes come from published reaction time, reach and Corsi studies. None of them used a fingertip reach in a headset, so every μ, β, γ and τ is provisional until refit.</td></tr>
<tr><td class='tag prog'>In progress</td><td><b>Calibration of uncertainty</b>Mean evidence SD is {ev_sd:.1f} y, which predicts an MAE near {0.798*ev_sd:.1f} y. Observed MAE is {mae:.1f} y, so intervals are wider than the error. The refit should estimate τ from data.</td></tr>
<tr><td class='tag prog'>In progress</td><td><b>Age model v1</b>Ridge regression with leave-one-out CV on event sessions, reported against the predict-the-mean baseline, with linear bias correction for the age gap.</td></tr>
<tr><td class='tag open'>Open</td><td><b>Assumed constants</b>ρ = 0.5 / 0.3 are assumed, not estimated. τ-only metrics without a trial SE (rt_tau, rt_cv, d′, corsi_total) default to SD₂₅ / 3. Corsi span SE is fixed at 0.5. Constellation does not yet apply the tracking gap filter.</td></tr>
<tr><td class='tag open'>Open</td><td><b>Reliability</b>Test-retest on 5 participants, practice effect size across repeat sessions, and the session count needed for a usable pace estimate.</td></tr>
</table>
<p class='s mute'>Not a clinical or diagnostic tool. Raw gaze is not used; visionOS does not expose it to apps.</p>"""))

    css = open(os.path.join(HERE, "algo.css")).read()
    doc = f"<!doctype html><html><head><meta charset='utf-8'><title>Spatial Age algorithms</title><style>{css}</style></head><body>{''.join(pages)}</body></html>"
    os.makedirs(BUILD, exist_ok=True)
    open(OUT_HTML, "w").write(doc)
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--run-all-compositor-stages-before-draw",
                    f"--print-to-pdf={OUT_PDF}", "file://" + OUT_HTML], check=True, capture_output=True)
    print(OUT_PDF)


if __name__ == "__main__":
    build()
