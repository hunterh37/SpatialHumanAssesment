"""Build the Spatial Age showcase PDF.

Runs the ScoreKit CLI on a synthetic cohort and a synthetic longitudinal participant, draws every
figure as hand-written SVG from that JSON, assembles doc.html and prints it with headless Chrome.

    make showcase      # or: python3 showcase/src/build.py
"""
import json
import math
import os
import pathlib
import shutil
import statistics
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent
SVG = OUT / "svg"
PKG = ROOT / "packages/ScoreKit"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

INK = "#1b2430"; PAPER = "#f6f4ef"; GRID = "#d9d4c7"; MUTE = "#8a8f99"; SOFT = "#4a5160"
BLUE = "#2f6bff"; ORANGE = "#ff7a3d"; GOLD = "#ffc83d"; TEAL = "#14b8a6"; VIOLET = "#7a4fd6"
SKIN = "#d9b99b"; CLOTH = "#3a4a63"; FLOOR = "#efece4"; WOOD = "#e8d9c0"; WOOD2 = "#d6c3a3"; WOOD3 = "#cbb593"
# Game identity for charts. Validated with the dataviz palette script (all checks pass, contrast WARN
# handled by ink outlines and direct labels).
GAME_COLOR = {"pendulum": "#d9a400", "spark": BLUE, "gate": ORANGE, "constellation": VIOLET, "orbit": TEAL}
GAME_ORDER = ["pendulum", "spark", "gate", "constellation", "orbit"]
DOMAINS = ["speed", "decision", "control", "memory", "consistency"]
FONT = "font-family='Helvetica Neue, Helvetica, Arial, sans-serif'"
C30 = math.cos(math.radians(30))


# ---------------------------------------------------------------- data

def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw).stdout


def collect():
    sh(["swift", "build", "-c", "release"], cwd=PKG)
    cli = pathlib.Path(sh(["swift", "build", "-c", "release", "--show-bin-path"], cwd=PKG).strip()) / "scorekit"
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="showcase-"))
    sh([cli, "synth", "--n", "40", "--out", tmp / "cohort"])
    sh([cli, "history", "--out", tmp / "history"])
    cohort = json.loads(sh([cli, "score", *sorted((tmp / "cohort").glob("*.json"))]))
    hist_files = sorted((tmp / "history").glob("*.json"))
    history = json.loads(sh([cli, "score", *hist_files]))
    pace = json.loads(sh([cli, "pace", *hist_files]))
    norms = json.loads(sh([cli, "norms"]))
    shutil.rmtree(tmp)
    return cohort, history, pace, norms


# ---------------------------------------------------------------- svg primitives

def iso(x, y, z, s, cx, cy):
    return (cx + (x - y) * C30 * s, cy + (x + y) * 0.5 * s - z * s)


def pts(ps):
    return " ".join(f"{a:.1f},{b:.1f}" for a, b in ps)


def poly(ps, fill, stroke=INK, sw=2, extra=""):
    return f"<polygon points='{pts(ps)}' fill='{fill}' stroke='{stroke}' stroke-width='{sw}' stroke-linejoin='round' {extra}/>"


def pline(ps, stroke=INK, sw=2, dash=None, extra=""):
    d = f" stroke-dasharray='{dash}'" if dash else ""
    return f"<polyline points='{pts(ps)}' fill='none' stroke='{stroke}' stroke-width='{sw}' stroke-linecap='round' stroke-linejoin='round'{d} {extra}/>"


def line(a, b, stroke=INK, sw=2, dash=None, extra=""):
    d = f" stroke-dasharray='{dash}'" if dash else ""
    return (f"<line x1='{a[0]:.1f}' y1='{a[1]:.1f}' x2='{b[0]:.1f}' y2='{b[1]:.1f}' stroke='{stroke}' "
            f"stroke-width='{sw}' stroke-linecap='round'{d} {extra}/>")


def circle(c, r, fill, stroke=INK, sw=2, extra=""):
    return f"<circle cx='{c[0]:.1f}' cy='{c[1]:.1f}' r='{r:.1f}' fill='{fill}' stroke='{stroke}' stroke-width='{sw}' {extra}/>"


def text(x, y, t, size=14, fill=INK, weight=400, anchor="start", extra=""):
    t = str(t).replace("&", "&amp;").replace("<", "&lt;")
    return (f"<text x='{x:.1f}' y='{y:.1f}' font-size='{size}' fill='{fill}' font-weight='{weight}' "
            f"text-anchor='{anchor}' {FONT} {extra}>{t}</text>")


def svg(body, w, h, bg="none"):
    rect = f"<rect width='{w}' height='{h}' fill='{bg}'/>" if bg != "none" else ""
    return f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {w} {h}' width='{w}' height='{h}'>{rect}{body}</svg>"


def save(name, s):
    (SVG / name).write_text(s)
    return f"../svg/{name}"


class Scene:
    """Isometric scene in meters."""

    def __init__(self, s, cx, cy):
        self.s, self.cx, self.cy = s, cx, cy

    def P(self, x, y, z):
        return iso(x, y, z, self.s, self.cx, self.cy)

    def floor(self, r=1.5, step=0.5, cx=0.0, cy=0.0):
        n = 72
        ring = [self.P(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n), 0) for i in range(n)]
        o = poly(ring, FLOOR, GRID, 1.5)
        k = int(r / step)
        for i in range(-k, k + 1):
            a = i * step
            h = math.sqrt(max(r * r - a * a, 0))
            o += line(self.P(cx + a, cy - h, 0), self.P(cx + a, cy + h, 0), GRID, 1)
            o += line(self.P(cx - h, cy + a, 0), self.P(cx + h, cy + a, 0), GRID, 1)
        return o

    def box(self, x0, y0, z0, dx, dy, dz, top=WOOD, s1=WOOD2, s2=WOOD3, sw=1.5):
        P = self.P
        x1, y1, z1 = x0 + dx, y0 + dy, z0 + dz
        o = poly([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], top, sw=sw)
        o += poly([P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)], s1, sw=sw)
        o += poly([P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)], s2, sw=sw)
        return o

    def shadow(self, x, y, r):
        c = self.P(x, y, 0)
        return f"<ellipse cx='{c[0]:.1f}' cy='{c[1]:.1f}' rx='{r * self.s * 1.0:.1f}' ry='{r * self.s * 0.5:.1f}' fill='{INK}' opacity='0.12'/>"

    def orb(self, x, y, z, r, color, ring=True, drop=True, glow=1.0):
        c = self.P(x, y, z)
        pr = max(r * self.s, 4)
        o = ""
        if drop:
            o += self.shadow(x, y, r)
            o += line(self.P(x, y, 0), (c[0], c[1] + pr), MUTE, 1.2, "3 5")
        if ring:
            o += circle(c, pr * 1.7, "none", color, 1.5, f"opacity='{0.45 * glow:.2f}'")
        o += circle(c, pr, color)
        o += circle((c[0] - pr * 0.35, c[1] - pr * 0.35), pr * 0.28, "white", "none", 0, "opacity='0.7'")
        return o

    def person(self, x=0.0, y=0.0, hand=None, facing=(1, 0)):
        """Standing participant 1.70 m tall. `hand` is the 3D point the right index tip reaches."""
        P = self.P
        fx, fy = facing
        rx, ry = -fy, fx  # right side when facing (fx, fy)... mirrored so the right hand is toward the viewer
        sw = 0.23 * self.s
        o = self.shadow(x, y, 0.28)
        for side in (-1, 1):
            hip = P(x + rx * 0.09 * side, y + ry * 0.09 * side, 0.88)
            foot = P(x + rx * 0.1 * side, y + ry * 0.1 * side, 0.02)
            o += line(foot, hip, INK, sw * 0.42)
        # torso as a tapered quad
        sl, sr = P(x - rx * 0.19, y - ry * 0.19, 1.42), P(x + rx * 0.19, y + ry * 0.19, 1.42)
        hl, hr = P(x - rx * 0.15, y - ry * 0.15, 0.86), P(x + rx * 0.15, y + ry * 0.15, 0.86)
        o += poly([sl, sr, hr, hl], CLOTH, INK, 2)
        # idle arm
        o += pline([sl, P(x - rx * 0.24, y - ry * 0.24, 1.12), P(x - rx * 0.22 + fx * 0.05, y - ry * 0.22 + fy * 0.05, 0.86)],
                   CLOTH, sw * 0.32)
        # head + headset
        hc = P(x, y, 1.6)
        o += line(P(x, y, 1.44), P(x, y, 1.5), SKIN, sw * 0.3)
        o += circle(hc, 0.1 * self.s, SKIN)
        vis = P(x + fx * 0.07, y + fy * 0.07, 1.62)
        o += f"<rect x='{vis[0] - 0.09 * self.s:.1f}' y='{vis[1] - 0.04 * self.s:.1f}' width='{0.16 * self.s:.1f}' height='{0.07 * self.s:.1f}' rx='{0.035 * self.s:.1f}' fill='{INK}'/>"
        if hand is not None:
            hx, hy, hz = hand
            sx, sy, sz = x + rx * 0.19, y + ry * 0.19, 1.40
            ex, ey, ez = (sx + hx) / 2 + rx * 0.06, (sy + hy) / 2 + ry * 0.06, (sz + hz) / 2 - 0.12
            o += pline([P(sx, sy, sz), P(ex, ey, ez), P(hx, hy, hz)], CLOTH, sw * 0.32)
            o += circle(P(hx, hy, hz), 0.035 * self.s, SKIN, INK, 1.5)
        return o

    def dim(self, a, b, label, off=(0, 0), color=MUTE, size=13, anchor="middle"):
        pa, pb = self.P(*a), self.P(*b)
        o = line(pa, pb, color, 1.2)
        for p in (pa, pb):
            o += circle(p, 2.5, color, "none", 0)
        mx, my = (pa[0] + pb[0]) / 2 + off[0], (pa[1] + pb[1]) / 2 + off[1]
        o += text(mx, my, label, size, SOFT, 600, anchor)
        return o


# ---------------------------------------------------------------- game scenes

def pendulum_scene(w=760, h=600, s=230, cx=300, cy=135, full=True):
    S = Scene(s, cx, cy)
    o = S.floor(1.2, 0.3) if full else ""
    piv = (0.48, 0.0, 1.95)
    L = 0.7
    amp = math.radians(30)
    # support beam
    o += S.box(0.44, -0.55, 1.95, 0.08, 1.1, 0.05, "#c9d3e3", "#b7c3d8", "#aab7cd")
    # ruler behind the swing plane: 0.75 m to 1.95 m
    rx = 0.80
    o += S.box(rx, -0.03, 0.75, 0.015, 0.06, 1.2, "#fbfaf6", "#e9e4d8", "#dcd5c6", 1.2)
    for i in range(0, 121, 5):
        z = 1.95 - i / 100
        a = S.P(rx, -0.03, z)
        ln = 0.035 if i % 10 == 0 else 0.018
        o += line(a, S.P(rx, -0.03 + ln, z), INK, 1 if i % 10 else 1.4)
        if i % 20 == 0 and full:
            o += text(a[0] - 6, a[1] + 4, f"{i}", 10, MUTE, 400, "end")
    # swing arc ghost
    arc = [S.P(piv[0], piv[1] + L * math.sin(t), piv[2] - L * math.cos(t))
           for t in [amp * (k / 30 - 1) for k in range(61)]]
    o += pline(arc, MUTE, 1.2, "2 6")
    # release state: theta = 18 deg moving toward +y
    th = math.radians(-14)
    om = math.sqrt(9.81 / L)
    thd = amp * om * math.sin(math.acos(th / amp))
    rel = (piv[0], piv[1] + L * math.sin(th), piv[2] - L * math.cos(th))
    vel = (0.0, L * math.cos(th) * thd, L * math.sin(th) * thd)
    # snapped cord fragment, fading
    o += line(S.P(*piv), S.P(piv[0], piv[1] + 0.55 * L * math.sin(th - 0.05), piv[2] - 0.55 * L * math.cos(th - 0.05)),
              INK, 2, None, "opacity='0.85'")
    o += line(S.P(piv[0], piv[1] + 0.62 * L * math.sin(th + 0.08), piv[2] - 0.62 * L * math.cos(th + 0.08)),
              S.P(*rel), INK, 1.5, "3 4", "opacity='0.35'")
    o += circle(S.P(*piv), 5, INK, "none", 0)
    # ballistic path, ghosts every 50 ms
    lat = 0.21
    path = []
    for k in range(0, 31):
        t = lat * 1.25 * k / 30
        path.append((rel[0], rel[1] + vel[1] * t, rel[2] + vel[2] * t - 4.905 * t * t))
    o += pline([S.P(*p) for p in path], GOLD, 2, "1 6")
    for k, t in enumerate([0.05, 0.10, 0.15]):
        p = (rel[0], rel[1] + vel[1] * t, rel[2] + vel[2] * t - 4.905 * t * t)
        o += S.orb(*p, 0.04, GOLD, ring=False, drop=False).replace("<circle", "<circle opacity='0.35'", 3)
    o += S.orb(*rel, 0.04, GOLD, ring=False, drop=False)
    cat = (rel[0], rel[1] + vel[1] * lat, rel[2] + vel[2] * lat - 4.905 * lat * lat)
    if full:
        o += S.person(0, 0, hand=(cat[0] - 0.02, cat[1] + 0.03, cat[2] - 0.02))
    o += S.orb(*cat, 0.04, GOLD, ring=True, drop=False)
    # catch tick on ruler
    tick = S.P(rx, -0.03, cat[2])
    o += line(S.P(*cat), tick, GOLD, 1.5, "2 4")
    o += line((tick[0] - 2, tick[1]), (tick[0] + 26, tick[1] - 6), "#d9a400", 4)
    drop_cm = (rel[2] - cat[2]) * 100
    if full:
        o += text(tick[0] + 32, tick[1] - 2, f"{drop_cm:.0f} cm", 16, INK, 700)
        o += text(tick[0] + 32, tick[1] + 16, "d = g t² / 2", 12, MUTE)
        o += S.dim((0.48, -0.75, 0), (0.48, -0.75, 1.95), "1.95 m", (-30, 0))
        o += S.dim((0, -0.75, 0), (0.48, -0.75, 0), "0.48 m", (-24, 14))
        mid = S.P(piv[0], piv[1] + 0.5 * L * math.sin(-amp), piv[2] - 0.5 * L * math.cos(-amp))
        o += text(mid[0] - 14, mid[1], "cord 0.55–0.85 m", 12, SOFT, 600, "end")
        a = S.P(piv[0], piv[1] + L * math.sin(amp), piv[2] - L * math.cos(amp))
        o += text(a[0] + 14, a[1] + 4, "±22–34°", 12, SOFT, 600)
        r = S.P(*rel)
        o += text(r[0] + 16, r[1] - 10, "release", 12, SOFT, 600)
    return svg(o, w, h)


def spark_scene(w=760, h=560):
    S = Scene(250, 380, 120)
    o = S.floor(1.1, 0.3)
    sh_z = 1.4
    # eccentricity bins as an annulus band at shoulder height, facing +x
    for b, col in enumerate(["#dfe8ff", "#e8eeff", "#dfe8ff", "#e8eeff"]):
        for side in (-1, 1):
            a0, a1 = math.radians(b * 30) * side, math.radians(b * 30 + 30) * side
            outer = [S.P(0.65 * math.cos(a0 + (a1 - a0) * k / 12), 0.65 * math.sin(a0 + (a1 - a0) * k / 12), sh_z) for k in range(13)]
            inner = [S.P(0.35 * math.cos(a1 - (a1 - a0) * k / 12), 0.35 * math.sin(a1 - (a1 - a0) * k / 12), sh_z) for k in range(13)]
            o += poly(outer + inner, col, GRID, 1)
    for b in range(5):
        for side in (-1, 1):
            a = math.radians(b * 30) * side
            p = S.P(0.69 * math.cos(a), 0.69 * math.sin(a), sh_z)
            if side == 1 or b == 0:
                o += text(p[0], p[1] + 4, f"{b * 30}°", 11, MUTE, 600, "middle")
    o += S.person(0, 0, hand=(0.4, 0.32, 1.28), facing=(1, 0))
    tgt = (0.47, 0.36, 1.3)
    o += S.orb(*tgt, 0.06, BLUE)
    o += S.dim((0, 0, sh_z + 0.32), (0.35, 0, sh_z + 0.32), "0.35 m", (0, -8))
    o += S.dim((0, -0.05, sh_z + 0.42), (0.65, -0.05, sh_z + 0.42), "0.65 m", (0, -8))
    t = S.P(*tgt)
    o += text(t[0] + 36, t[1] + 4, "r 6 cm", 12, SOFT, 600)
    return svg(o, w, h)


def gate_scene(w=760, h=560):
    S = Scene(250, 380, 120)
    o = S.floor(1.1, 0.3)
    blue = (0.5, 0.25, 1.32)
    orange = (0.45, -0.12, 1.18)
    o += S.person(0, 0, hand=(0.44, 0.22, 1.3), facing=(1, 0))
    o += S.orb(*orange, 0.06, ORANGE)
    o += S.orb(*blue, 0.06, BLUE)
    o += S.dim((orange[0], orange[1], orange[2] + 0.12), (blue[0], blue[1], blue[2] + 0.12), "≥ 0.25 m", (0, -10))
    b, r = S.P(*blue), S.P(*orange)
    o += text(b[0] + 36, b[1] + 4, "touch", 13, INK, 700)
    o += text(r[0] + 36, r[1] + 4, "leave", 13, INK, 700)
    return svg(o, w, h)


STAR_NODES = [(0.9, -0.7, 0.76), (1.0, -0.2, 0.76), (0.85, 0.35, 0.76), (0.6, 0.85, 1.25), (0.2, 1.0, 1.25),
              (1.1, 0.6, 0.02), (0.55, -1.0, 1.55), (1.05, 0.15, 1.7), (0.35, -0.9, 0.02)]


def constellation_scene(w=760, h=560, seq=(6, 1, 3, 5)):
    S = Scene(200, 360, 150)
    o = S.floor(1.4, 0.35)
    o += S.box(0.7, -0.85, 0, 0.5, 1.4, 0.72)          # table
    o += S.box(0.3, 0.75, 1.15, 0.5, 0.35, 0.06)        # shelf
    o += S.person(0, 0, hand=None, facing=(1, 0))
    # azimuth fan 140 deg
    fan = [S.P(1.3 * math.cos(math.radians(a)), 1.3 * math.sin(math.radians(a)), 0) for a in range(-70, 71, 5)]
    o += pline(fan, MUTE, 1.2, "2 5")
    o += text(fan[-1][0] - 8, fan[-1][1] + 18, "140°", 12, SOFT, 600)
    path = [S.P(*STAR_NODES[i]) for i in seq]
    o += pline(path, BLUE, 1.5, "3 5")
    for i, n in enumerate(STAR_NODES):
        lit = i in seq
        o += S.orb(*n, 0.04, BLUE if lit else "#c9ced8", ring=lit, drop=True)
        if lit:
            c = S.P(*n)
            o += text(c[0], c[1] - 18, seq.index(i) + 1, 13, INK, 700, "middle")
    return svg(o, w, h)


def lissajous(t, ph=(0.4, 1.3, 2.1)):
    return (0.45 + 0.08 * math.sin(2 * math.pi * 0.13 * t + ph[2]),
            0.20 * math.sin(2 * math.pi * 0.21 * t + ph[0]),
            1.32 + 0.12 * math.sin(2 * math.pi * 0.29 * t + ph[1]))


def orbit_scene(w=760, h=560):
    S = Scene(330, 330, 70)
    o = S.floor(0.9, 0.3)
    path = [S.P(*lissajous(k * 0.05)) for k in range(0, 241)]
    o += pline(path, TEAL, 1.2, None, "opacity='0.35'")
    t0 = 7.3
    trail = [S.P(*lissajous(t0 + k * 0.01)) for k in range(0, 31)]
    o += pline(trail, TEAL, 6, None, "opacity='0.18'")
    cur = lissajous(t0)
    fin = lissajous(t0 - 0.13)
    o += S.person(0, -0.05, hand=(fin[0] - 0.01, fin[1] + 0.01, fin[2] - 0.01), facing=(1, 0))
    o += S.orb(*cur, 0.04, TEAL, ring=True, drop=True)
    c, f = S.P(*cur), S.P(*fin)
    o += line(c, f, INK, 1.2, "2 3")
    o += text((c[0] + f[0]) / 2 + 10, (c[1] + f[1]) / 2 + 20, "error", 12, SOFT, 600)
    o += S.dim((0.45, -0.2, 1.62), (0.45, 0.2, 1.62), "0.40 m", (0, -10))
    o += S.dim((0.75, 0.22, 1.2), (0.75, 0.22, 1.44), "0.24 m", (34, 4))
    return svg(o, w, h)


def icon(game, size=150):
    """Small object-only icon for catalog cards."""
    if game == "pendulum":
        S = Scene(95, 60, 8)
        o = line(S.P(0.48, 0, 1.0), S.P(0.48, 0.25, 0.6), INK, 2)
        o += circle(S.P(0.48, 0, 1.0), 3, INK, "none", 0)
        o += pline([S.P(0.48, 0.25 - 0.02 * k, 0.6 - 0.006 * k * k) for k in range(12)], GOLD, 2, "1 5")
        o += S.orb(0.48, 0.25, 0.6, 0.08, GOLD, ring=False, drop=False)
        o += S.orb(0.48, 0.08, 0.15, 0.08, GOLD, ring=True, drop=False)
    elif game == "spark":
        S = Scene(110, 75, 120)
        o = S.orb(0.1, 0.1, 0.6, 0.12, BLUE)
    elif game == "gate":
        S = Scene(110, 75, 120)
        o = S.orb(0.35, -0.2, 0.5, 0.1, ORANGE) + S.orb(0.0, 0.25, 0.65, 0.1, BLUE)
    elif game == "constellation":
        S = Scene(60, 75, 100)
        nodes = [(0.6, -0.9, 0.9), (0.2, 0.3, 1.4), (1.0, 0.2, 0.5), (-0.4, 0.6, 0.8), (0.9, -0.2, 1.6)]
        o = pline([S.P(*n) for n in nodes[:4]], BLUE, 1.5, "3 4")
        for i, n in enumerate(nodes):
            o += S.orb(*n, 0.09, BLUE if i < 4 else "#c9ced8", ring=False, drop=False)
    else:
        S = Scene(170, 75, -150)
        o = pline([S.P(*[lissajous(k * 0.06)[0] - 0.45, lissajous(k * 0.06)[1], lissajous(k * 0.06)[2] - 1.32 + 1.2][0:3])
                   for k in range(200)], TEAL, 1.5, None, "opacity='0.5'")
        p = lissajous(3.0)
        o += S.orb(p[0] - 0.45, p[1], p[2] - 1.32 + 1.2, 0.05, TEAL, ring=True, drop=False)
    return svg(o, size, size)


# ---------------------------------------------------------------- charts

def axis_ticks(lo, hi, n=5):
    step = (hi - lo) / n
    mag = 10 ** math.floor(math.log10(step))
    for m in (1, 2, 2.5, 5, 10):
        if m * mag >= step:
            step = m * mag
            break
    v = math.ceil(lo / step) * step
    out = []
    while v <= hi + 1e-9:
        out.append(round(v, 10))
        v += step
    return out


class Plot:
    def __init__(self, x, y, w, h, xr, yr):
        self.x, self.y, self.w, self.h, self.xr, self.yr = x, y, w, h, xr, yr

    def X(self, v):
        return self.x + (v - self.xr[0]) / (self.xr[1] - self.xr[0]) * self.w

    def Y(self, v):
        return self.y + self.h - (v - self.yr[0]) / (self.yr[1] - self.yr[0]) * self.h

    def frame(self, xt, yt, xlabel="", ylabel="", fmt=lambda v: f"{v:g}", grid=True):
        o = ""
        for v in yt:
            y = self.Y(v)
            if grid:
                o += line((self.x, y), (self.x + self.w, y), GRID, 1)
            o += text(self.x - 8, y + 4, fmt(v), 11, MUTE, 400, "end")
        for v in xt:
            o += text(self.X(v), self.y + self.h + 18, fmt(v), 11, MUTE, 400, "middle")
        o += line((self.x, self.y + self.h), (self.x + self.w, self.y + self.h), INK, 1.2)
        if xlabel:
            o += text(self.x + self.w, self.y + self.h + 38, xlabel, 12, SOFT, 600, "end")
        if ylabel:
            o += text(self.x, self.y - 12, ylabel, 12, SOFT, 600)
        return o


def scatter_chart(cohort):
    xs = [r["chronological_age"] for r in cohort]
    ys = [r["evidence_age"] for r in cohort]
    r = statistics.correlation(xs, ys)
    mae = statistics.fmean(abs(a - b) for a, b in zip(xs, ys))
    base = statistics.fmean(abs(statistics.fmean(xs) - a) for a in xs)
    W, H = 600, 470
    p = Plot(60, 40, 500, 360, (15, 85), (15, 85))
    o = p.frame(axis_ticks(15, 85, 7), axis_ticks(15, 85, 7), "Chronological age", "Evidence age (before prior)")
    o += line((p.X(15), p.Y(15)), (p.X(85), p.Y(85)), MUTE, 1.2, "4 5")
    o += text(p.X(80), p.Y(83) - 6, "identity", 11, MUTE, 400, "end")
    for a, b in zip(xs, ys):
        o += circle((p.X(a), p.Y(b)), 5, BLUE, PAPER, 2)
    o += text(p.x + 12, p.y + 22, f"r = {r:.2f}", 20, INK, 700)
    o += text(p.x + 12, p.y + 42, f"MAE {mae:.1f} y, mean baseline {base:.1f} y", 12, SOFT)
    return svg(o, W, H), r, mae, base


def domain_multiples(cohort):
    W, H = 1000, 230
    o = ""
    pw = 168
    for i, d in enumerate(DOMAINS):
        p = Plot(40 + i * (pw + 30), 30, pw, 150, (15, 85), (0, 100))
        o += p.frame([20, 50, 80], [0, 50, 100] if i == 0 else [], "", "", grid=True)
        if i:
            for v in [0, 50, 100]:
                o += line((p.x, p.Y(v)), (p.x + p.w, p.Y(v)), GRID, 1)
        o += text(p.x, 18, d.capitalize(), 13, INK, 700)
        pts_ = [(r["chronological_age"], next((x["score"] for x in r["domains"] if x["domain"] == d), None)) for r in cohort]
        pts_ = [(a, b) for a, b in pts_ if b is not None]
        for a, b in pts_:
            o += circle((p.X(a), p.Y(b)), 3.5, BLUE, PAPER, 1.5)
        rr = statistics.correlation([a for a, _ in pts_], [b for _, b in pts_])
        o += text(p.x + p.w, 18, f"r {rr:+.2f}", 11, SOFT, 600, "end")
    o += text(40, H - 4, "x: chronological age   y: domain score, 0 to 100 against the age-25 reference", 11, MUTE)
    return svg(o, W, H)


def metric_bars(cohort):
    ids = [m["id"] for m in cohort[0]["metrics"] if m.get("metric_age") is not None]
    rows = []
    for mid in ids:
        pairs = [(r["chronological_age"], m["metric_age"]) for r in cohort for m in r["metrics"]
                 if m["id"] == mid and m.get("metric_age") is not None]
        if len(pairs) > 5 and len({b for _, b in pairs}) > 1:
            m0 = next(m for m in cohort[0]["metrics"] if m["id"] == mid)
            rows.append((m0["label"], m0["game"], statistics.correlation(*zip(*pairs))))
    rows.sort(key=lambda r: (GAME_ORDER.index(r[1]), -r[2]))
    W, H = 380, 26 + 19 * len(rows)
    x0, bw = 150, 200
    o = text(x0, 14, "r, metric age vs chronological age", 11, MUTE)
    for v in (0, 0.5, 1):
        xx = x0 + v * bw
        o += line((xx, 22), (xx, H - 4), GRID, 1)
    for i, (label, game, rr) in enumerate(rows):
        y = 26 + i * 19
        o += text(x0 - 8, y + 11, label, 11, INK, 400, "end")
        o += f"<rect x='{x0}' y='{y + 2}' width='{max(rr, 0) * bw:.1f}' height='12' rx='3' fill='{GAME_COLOR[game]}' stroke='{INK}' stroke-width='1'/>"
        o += text(x0 + max(rr, 0) * bw + 6, y + 12, f"{rr:.2f}", 10, SOFT)
    return svg(o, W, H)


def pace_chart(history, pace):
    pts_ = pace["points"]
    from datetime import datetime
    d0 = datetime.fromisoformat(pts_[0]["date"].replace("Z", "+00:00"))
    days = [(datetime.fromisoformat(p["date"].replace("Z", "+00:00")) - d0).days for p in pts_]
    sa = [p["spatial_age"] for p in pts_]
    sd = [p["sd"] for p in pts_]
    chrono = [r["chronological_age"] for r in sorted(history, key=lambda r: r["started_at"])]
    lo = min(min(a - 1.2816 * s for a, s in zip(sa, sd)), min(chrono)) - 2
    hi = max(max(a + 1.2816 * s for a, s in zip(sa, sd)), max(chrono)) + 2
    W, H = 760, 400
    p = Plot(60, 30, 660, 300, (0, max(days)), (lo, hi))
    o = p.frame(axis_ticks(0, max(days), 6), axis_ticks(lo, hi, 5), "Days since first session", "Age, years",
                fmt=lambda v: f"{v:.0f}")
    band = [(p.X(d), p.Y(a + 1.2816 * s)) for d, a, s in zip(days, sa, sd)] + \
           [(p.X(d), p.Y(a - 1.2816 * s)) for d, a, s in reversed(list(zip(days, sa, sd)))]
    o += f"<polygon points='{pts(band)}' fill='{BLUE}' opacity='0.10'/>"
    o += pline([(p.X(d), p.Y(c)) for d, c in zip(days, chrono)], INK, 2, "6 5")
    o += pline([(p.X(d), p.Y(a)) for d, a in zip(days, sa)], BLUE, 2)
    for d, a in zip(days, sa):
        o += circle((p.X(d), p.Y(a)), 5.5, BLUE, PAPER, 2)
    o += text(p.X(days[-1]) - 6, p.Y(chrono[-1]) - 10, "chronological", 12, INK, 600, "end")
    o += text(p.X(days[-1]) - 6, p.Y(sa[-1]) + 22, "Spatial Age, 80% band", 12, BLUE, 600, "end")
    return svg(o, W, H)


def report_card(r):
    W, H = 980, 520
    o = ""
    o += text(0, 22, f"PARTICIPANT {r['participant_code']}", 12, MUTE, 700, extra="letter-spacing='3'")
    o += text(0, 150, f"{r['spatial_age']:.0f}", 150, INK, 700, extra="letter-spacing='-6'")
    o += text(4, 182, "Spatial Age", 18, SOFT, 600)
    gap = r["age_gap"]
    o += text(250, 70, f"{r['chronological_age']:.0f}", 34, INK, 700)
    o += text(250, 92, "chronological", 12, MUTE)
    o += text(250, 140, f"{gap:+.1f}", 34, BLUE if gap < 0 else ORANGE, 700)
    o += text(250, 162, "years gap", 12, MUTE)
    # interval bar
    lo, hi = r["spatial_age_low"], r["spatial_age_high"]
    p = Plot(0, 230, 360, 10, (15, 85), (0, 1))
    o += line((p.X(15), 240), (p.X(85), 240), GRID, 6)
    o += line((p.X(lo), 240), (p.X(hi), 240), BLUE, 6, None, "opacity='0.35'")
    o += circle((p.X(r["spatial_age"]), 240), 7, BLUE, PAPER, 2)
    o += line((p.X(r["chronological_age"]), 226), (p.X(r["chronological_age"]), 254), INK, 2)
    for v in (20, 40, 60, 80):
        o += text(p.X(v), 274, v, 11, MUTE, 400, "middle")
    o += text(0, 300, f"80% interval {lo:.0f} to {hi:.0f}. Evidence alone {r['evidence_age']:.0f}.", 12, SOFT)
    # domains
    x0 = 470
    o += text(x0, 22, "DOMAINS", 12, MUTE, 700, extra="letter-spacing='3'")
    for i, d in enumerate(r["domains"]):
        y = 50 + i * 46
        o += text(x0, y + 4, d["title"], 15, INK, 600)
        o += f"<rect x='{x0 + 130}' y='{y - 8}' width='300' height='14' rx='7' fill='{GRID}'/>"
        o += f"<rect x='{x0 + 130}' y='{y - 8}' width='{3 * d['score']:.1f}' height='14' rx='7' fill='{INK}'/>"
        o += text(x0 + 444, y + 5, f"{d['score']:.0f}", 15, INK, 700)
        if d.get("age") is not None:
            o += text(x0 + 130, y + 24, f"age {d['age']:.0f} ± {d['age_sd']:.0f}", 10, MUTE)
    # games
    y0 = 340
    o += text(0, y0, "GAMES", 12, MUTE, 700, extra="letter-spacing='3'")
    head = {m["id"]: m for m in r["metrics"]}
    for i, g in enumerate(r["games"]):
        x = i * 196
        col = GAME_COLOR[g["game"]]
        o += f"<rect x='{x}' y='{y0 + 16}' width='180' height='150' rx='14' fill='white' stroke='{GRID}' stroke-width='1.5'/>"
        o += circle((x + 22, y0 + 40), 7, col, INK, 1.5)
        o += text(x + 36, y0 + 45, g["title"], 14, INK, 700)
        o += text(x + 16, y0 + 102, f"{g['score']:.0f}" if g.get("score") is not None else "-", 44, INK, 700)
        o += text(x + 16, y0 + 122, "score", 11, MUTE)
        m = head.get(g["headline"])
        if m:
            unit = {"s": " s", "cm": " cm", "": ""}.get(m["unit"], " " + m["unit"])
            val = f"{m['value']:.0f}" if m["unit"] in ("", "cm") and m["value"] > 5 else (
                f"{m['value'] * 1000:.0f} ms" if m["unit"] == "s" else f"{m['value']:.1f}{unit}")
            if m["unit"] == "cm":
                val = f"{m['value']:.1f} cm"
            o += text(x + 16, y0 + 150, f"{m['label']} {val}", 11, SOFT)
    return svg(o, W, H)


def architecture():
    W, H = 1000, 470
    o = ""

    def node(x, y, w, h, title, sub="", fill="white", stroke=INK, tsize=15):
        s = f"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='12' fill='{fill}' stroke='{stroke}' stroke-width='1.8'/>"
        s += text(x + 16, y + 26, title, tsize, INK, 700)
        if sub:
            for i, ln in enumerate(sub.split("\n")):
                s += text(x + 16, y + 46 + i * 16, ln, 11, SOFT)
        return s

    def arrow(a, b):
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        h1 = (b[0] - 9 * math.cos(ang - 0.4), b[1] - 9 * math.sin(ang - 0.4))
        h2 = (b[0] - 9 * math.cos(ang + 0.4), b[1] - 9 * math.sin(ang + 0.4))
        return line(a, b, INK, 1.6) + poly([b, h1, h2], INK, INK, 1)

    o += node(0, 40, 160, 120, "Vision Pro", "5 minigames\nhand + head tracking\nSessionRecorder")
    o += node(0, 260, 160, 100, "Session JSON", "schema 0.2.0\none file per session")
    o += arrow((80, 160), (80, 258))
    # ScoreKit frame
    o += f"<rect x='220' y='0' width='560' height='460' rx='18' fill='#eef2fb' stroke='{BLUE}' stroke-width='1.5' stroke-dasharray='5 5'/>"
    o += text(240, 30, "packages/ScoreKit", 15, BLUE, 700)
    o += text(762, 30, "pure Swift, no UI", 11, SOFT, 400, "end")
    o += node(245, 50, 240, 78, "Signal", "Signal/Kinematics.swift\nSignal/Stats.swift")
    o += node(515, 50, 240, 78, "Metrics", "Metrics/<Game>Metrics.swift\none extractor per game")
    o += node(245, 160, 240, 78, "Norms", "Norms/NormTable.swift\nversioned, swappable")
    o += node(515, 160, 240, 78, "SpatialAgeModel", "Age/SpatialAgeModel.swift\nmetric → domain → age")
    o += node(515, 270, 240, 78, "ScoreEngine", "ScoreEngine.swift\nsession → ScoreReport")
    o += node(245, 270, 240, 78, "PaceOfAging", "Age/PaceOfAging.swift\nacross sessions")
    o += node(245, 375, 510, 60, "scorekit CLI", "score · pace · synth · history · norms")
    o += arrow((485, 89), (513, 89))
    o += arrow((635, 128), (635, 158))
    o += arrow((485, 199), (513, 199))
    o += arrow((635, 238), (635, 268))
    o += arrow((513, 309), (487, 309))
    o += arrow((162, 310), (243, 89))
    for i, (t, s) in enumerate([("App results", "on-device report"), ("Ingest", "services/ingest"), ("Dashboard", "apps/dashboard")]):
        y = 60 + i * 120
        o += node(840, y, 160, 80, t, s)
        o += arrow((757, 309), (838, y + 40))
    return svg(o, W, H)


PRIMITIVES = [
    ("Breathe", "Live targets pulse 1.00 to 1.03 at 0.5 Hz.", "breathe"),
    ("Proximity glow", "Emissive ramps as the fingertip closes from 30 cm.", "glow"),
    ("Contact pop", "90 ms scale 1 → 1.25 → 0. Ring grows to 3× radius over 240 ms. Tick pitch follows speed.", "pop"),
    ("Miss sink", "250 ms desaturate, drop 3 cm, fade.", "sink"),
    ("Release snap", "Cord flicks and fades in 120 ms with a low tock.", "snap"),
]


def primitive_svg(kind, w=180, h=150):
    c = (w / 2, h / 2 + 4)
    o = ""
    if kind == "breathe":
        o += circle(c, 34, "none", BLUE, 1.2, "stroke-dasharray='3 4'")
        o += circle(c, 33, BLUE)
        o += circle(c, 30, "none", "white", 1, "opacity='0.6'")
    elif kind == "glow":
        for i, r in enumerate([52, 44, 36]):
            o += circle(c, r, BLUE, "none", 0, f"opacity='{0.08 + 0.06 * i:.2f}'")
        o += circle(c, 28, BLUE)
        o += circle((c[0] + 64, c[1] + 26), 7, SKIN, INK, 1.5)
        o += line((c[0] + 58, c[1] + 22), (c[0] + 34, c[1] + 12), MUTE, 1.2, "2 4")
    elif kind == "pop":
        o += circle(c, 60, "none", BLUE, 1.5, "opacity='0.25'")
        o += circle(c, 44, "none", BLUE, 2, "opacity='0.5'")
        o += circle(c, 25, BLUE)
        for a in range(0, 360, 45):
            ra = math.radians(a)
            o += line((c[0] + 30 * math.cos(ra), c[1] + 30 * math.sin(ra)), (c[0] + 38 * math.cos(ra), c[1] + 38 * math.sin(ra)), INK, 1.5)
    elif kind == "sink":
        o += circle((c[0], c[1] - 14), 26, BLUE, INK, 1.2, "opacity='0.25'")
        o += circle((c[0], c[1] + 10), 26, "#9aa6bf")
        o += line((c[0] + 40, c[1] - 18), (c[0] + 40, c[1] + 12), MUTE, 1.5)
        o += poly([(c[0] + 40, c[1] + 18), (c[0] + 35, c[1] + 9), (c[0] + 45, c[1] + 9)], MUTE, MUTE, 1)
    else:
        o += circle((c[0], 18), 4, INK, "none", 0)
        o += line((c[0], 18), (c[0] + 6, 52), INK, 2)
        o += line((c[0] + 9, 62), (c[0] + 18, 88), INK, 1.5, "3 4", "opacity='0.4'")
        o += circle((c[0] + 22, c[1] + 30), 20, GOLD)
    return svg(o, w, h)


# ---------------------------------------------------------------- document

def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


GAMES = {
    "pendulum": dict(
        title="Pendulum", n=(12, 3),
        instruction="Catch the weight when the cord lets go.",
        measures="Catch latency and drop distance",
        mechanic=["A gold bob, 8 cm, swings on a 0.55 to 0.85 m cord from a pivot 1.95 m high, 0.48 m ahead.",
                  "Swing amplitude 22 to 34°. The cord releases at a random time, 1.5 to 4 s into the swing.",
                  "The bob falls ballistically at 9.81 m/s² from its release position and velocity. Catch when the thumb-index midpoint is within 6 cm of the bob.",
                  "A life-size cm ruler stands behind the swing plane. A gold tick marks the catch height."],
        fields="length_m, amplitude_deg, release_t, release_angle_deg, release_position, release_velocity, catch_t, catch_position, hand, outcome, aperture_release_m, aperture_catch_m, tracking_gap_ms, trace",
        metrics=[("Catch latency", "catch_t − release_t, median of catches"),
                 ("Drop distance", "vertical fall at catch, cm. The ruler drop test, d = g t²/2"),
                 ("Catch rate", "catches / attempts"),
                 ("Anticipation", "grasp under 100 ms after release, excluded")],
        micro="Release snap on the cord. Contact pop on catch, with the bob frozen in the hand. Miss sink when it passes the floor.",
        scene=pendulum_scene),
    "spark": dict(
        title="Spark", n=(20, 5),
        instruction="Touch each light as it appears.",
        measures="Reaction, movement and reach kinematics",
        mechanic=["One blue sphere, radius 6 cm, 0.35 to 0.65 m from the shoulder.",
                  "Eccentricity 0 to 120° from head forward, balanced over 4 bins.",
                  "Random foreperiod 0.8 to 2.0 s. Trial ends on fingertip contact or a 3 s timeout."],
        fields="kind, spawn_t, move_t, contact_t, position, eccentricity_deg, outcome, hand, endpoint_error_m, tracking_gap_ms, trace (fingertip path, 90 Hz)",
        metrics=[("Reaction time", "trace onset − spawn"), ("Movement time", "contact − onset"),
                 ("RT tail", "ex-Gaussian tau"), ("RT variability", "SD / mean, trimmed"),
                 ("Eccentricity cost", "slope of reach time per 90°"), ("Peak speed", "fingertip, m/s"),
                 ("Path efficiency", "straight line / path length"), ("Smoothness", "log dimensionless jerk")],
        micro="Breathe while live. Proximity glow on approach. Contact pop with a tick pitched by speed. Miss sink on timeout.",
        scene=spark_scene),
    "gate": dict(
        title="Gate", n=(30, 5),
        instruction="Touch blue. Leave orange.",
        measures="Decision time and inhibition",
        mechanic=["Go trials, 70%: blue and orange appear together, at least 25 cm apart. Touch blue.",
                  "No-go trials, 30%: orange alone. Hold still.",
                  "Response window 2.0 s. Placement and timing as Spark."],
        fields="As Spark. kind is go or nogo. outcome is hit, miss, false_alarm or correct_reject.",
        metrics=[("Choice RT", "median, go hits"), ("Decision time", "choice RT − Spark RT"),
                 ("Commission", "false alarms / trials"), ("Omission", "misses / go trials"),
                 ("Sensitivity d'", "z(hit) − z(false alarm), log-linear")],
        micro="Orange never glows on approach. A correct hold dissolves orange quietly. Touching it plays miss sink.",
        scene=gate_scene),
    "constellation": dict(
        title="Constellation", n=(14, 1),
        instruction="Watch the stars light, then touch them in order.",
        measures="Spatial working memory span",
        mechanic=["9 star nodes, 8 cm, anchored on room surfaces across 140° of azimuth. Some need a head turn.",
                  "A sequence lights, 0.8 s on, 0.2 s gap. Touch it back in order.",
                  "Staircase from span 2: two correct steps up, two fails stop. Cap at span 9."],
        fields="span, sequence, response, correct, start_t, end_t, tap_t, seed",
        metrics=[("Corsi span", "longest span with a correct sequence"),
                 ("Total score", "span × correct sequences (Kessels)"),
                 ("Tap interval", "median gap between response touches")],
        micro="Nodes breathe while waiting. Each touch flashes white and pops. A wrong touch sinks the whole set.",
        scene=constellation_scene),
    "orbit": dict(
        title="Orbit", n=(3, 1),
        instruction="Keep your fingertip inside the moving light.",
        measures="Visuomotor tracking error and lag",
        mechanic=["A teal orb, 4 cm, follows a 3D Lissajous path centered 1.32 m high, 0.45 m ahead.",
                  "Amplitude 0.20, 0.12, 0.08 m at 0.21, 0.29, 0.13 Hz.",
                  "3 trials of 12 s. The first second is acquisition and is not scored. A faint 0.3 s trail leads the orb."],
        fields="start_t, duration_s, path (center, amplitude, frequency_hz, phase), t, target, finger (null while untracked), hand, tracking_gap_ms",
        metrics=[("Tracking error", "RMS fingertip to orb, cm"), ("Lag", "path shift that best fits the fingertip, ms"),
                 ("Time on target", "share of samples within 4 cm"), ("Velocity gain", "fingertip velocity projected on orb velocity")],
        micro="Proximity glow holds while the fingertip is inside. It dims the moment the finger leaves.",
        scene=orbit_scene),
}


CSS = """
@page{size:11in 8.5in;margin:0}
*{box-sizing:border-box}
body{margin:0;font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;color:#1b2430;background:#f6f4ef;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.page{width:11in;height:8.5in;page-break-after:always;position:relative;overflow:hidden;background:#f6f4ef;padding:.55in .6in}
.page:last-child{page-break-after:auto}
.k{font-size:10px;letter-spacing:3px;font-weight:700;color:#8a8f99;text-transform:uppercase}
h1{font-size:64px;line-height:1;margin:.16in 0 .14in;letter-spacing:-1.5px}
h2{font-size:30px;line-height:1.1;margin:.08in 0 .06in;letter-spacing:-.4px}
p{font-size:13px;line-height:1.5;color:#3a4150;margin:0 0 .1in}
.num{position:absolute;right:.6in;top:.55in;font-size:10px;color:#8a8f99;letter-spacing:2px}
.syn{position:absolute;left:.6in;bottom:.4in;font-size:10px;letter-spacing:2px;color:#ff7a3d;font-weight:700}
.foot{position:absolute;right:.6in;bottom:.4in;font-size:10px;color:#8a8f99}
.lede{font-size:15px;color:#4a5160;max-width:4.6in}
.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:.16in;margin-top:.35in}
.card{background:#fff;border-radius:16px;padding:.16in;border:1.5px solid #d9d4c7;height:5.4in;position:relative}
.card img{width:100%;height:1.5in;object-fit:contain}
.card h3{font-size:19px;margin:.1in 0 .06in}
.card .i{font-size:13px;line-height:1.4;color:#1b2430;min-height:.6in}
.card .m{font-size:11.5px;line-height:1.4;color:#4a5160;margin-top:.12in}
.card .t{position:absolute;left:.16in;bottom:.16in;font-size:10px;color:#8a8f99;letter-spacing:1px}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;border:1.5px solid #1b2430;margin-right:6px;vertical-align:1px}
.game{display:grid;grid-template-columns:6.1in 3.6in;gap:.1in}
.game img{width:6.1in;height:auto;margin-top:.05in}
.side .sec{margin-top:.17in}
.side ul{margin:0;padding-left:0;list-style:none}
.side li{font-size:11.5px;line-height:1.45;color:#3a4150;margin-bottom:.06in}
.side li b{color:#1b2430}
.side .f{font-family:Menlo,monospace;font-size:9.5px;line-height:1.55;color:#4a5160}
.prims{display:grid;grid-template-columns:repeat(5,1fr);gap:.16in;margin-top:.4in}
.prim img{width:100%;background:#fff;border-radius:16px;border:1.5px solid #d9d4c7}
.prim h3{font-size:16px;margin:.12in 0 .04in}
.prim p{font-size:12px}
.env{margin-top:.35in;display:grid;grid-template-columns:repeat(3,1fr);gap:.3in}
.env div{border-top:1.5px solid #d9d4c7;padding-top:.1in;font-size:12.5px;line-height:1.45;color:#3a4150}
.env b{display:block;font-size:10px;letter-spacing:2px;color:#8a8f99;margin-bottom:3px}
.algo{display:grid;grid-template-columns:1fr 1fr;gap:.18in .4in;margin-top:.25in}
.algo div{border-top:1.5px solid #d9d4c7;padding-top:.08in}
.algo h3{font-size:14px;margin:0 0 .04in}
.algo p{font-size:11.5px;line-height:1.45;margin:0 0 .04in}
.eq{font-family:Menlo,monospace;font-size:11px;color:#1b2430;background:#fff;border-radius:8px;padding:.06in .1in;display:inline-block;margin:.02in 0}
table{border-collapse:collapse;width:100%}
td,th{font-size:9.5px;line-height:1.35;text-align:left;padding:3px 6px 3px 0;border-bottom:1px solid #e3ded2;vertical-align:top}
th{font-size:9px;letter-spacing:1.5px;color:#8a8f99;text-transform:uppercase;font-weight:700}
td.c{font-family:Menlo,monospace;font-size:9px;color:#1b2430;white-space:nowrap}
.dd{display:grid;grid-template-columns:1fr 1fr;gap:.12in .35in;margin-top:.18in}
.dd h3{font-size:13px;margin:0 0 .03in}
.two{display:grid;grid-template-columns:6.2in 3.5in;gap:.1in;margin-top:.15in}
.stat{display:flex;gap:.45in;margin-top:.25in}
.stat div{font-size:12px;color:#4a5160}
.stat b{display:block;font-size:34px;color:#1b2430;letter-spacing:-.5px}
"""


def page(n, total, kicker, title, body, synthetic=False, foot=""):
    return (f"<section class='page'><div class='k'>{esc(kicker)}</div><div class='num'>{n:02d} / {total:02d}</div>"
            f"{f'<h2>{esc(title)}</h2>' if title else ''}{body}"
            f"{'<div class=syn>SYNTHETIC DATA. NOT A MEASUREMENT OF ANY PERSON.</div>' if synthetic else ''}"
            f"{f'<div class=foot>{esc(foot)}</div>' if foot else ''}</section>")


def build_doc(cohort, history, pace, norms):
    SVG.mkdir(parents=True, exist_ok=True)
    total = 15
    pages = []

    # 1 cover
    cover = save("cover.svg", pendulum_scene(w=760, h=640, s=250, cx=310, cy=150))
    pages.append(
        f"<section class='page'><img src='{cover}' style='position:absolute;right:.1in;top:.7in;width:7.4in'>"
        f"<div style='position:absolute;left:.7in;top:1.35in;width:3.6in'><div class='k'>Spatial Human Assessment</div>"
        f"<h1>Spatial Age</h1><p class='lede'>Five reaction minigames for Apple Vision Pro. Life scale, fully immersive, "
        f"scored on device into one functional age.</p>"
        f"<p style='margin-top:.3in;font-size:11px;color:#8a8f99'>ScoreKit {cohort[0]['engine_version']} · norms "
        f"{cohort[0]['norms_version']} · schema 0.2.0</p></div></section>")

    # 2 catalog
    cards = ""
    for g in GAME_ORDER:
        G = GAMES[g]
        img = save(f"icon_{g}.svg", icon(g))
        cards += (f"<div class='card'><img src='{img}'><h3><span class='dot' style='background:{GAME_COLOR[g]}'></span>"
                  f"{G['title']}</h3><div class='i'>{esc(G['instruction'])}</div><div class='m'>{esc(G['measures'])}</div>"
                  f"<div class='t'>{G['n'][0]} SCORED · {G['n'][1]} PRACTICE</div></div>")
    pages.append(page(2, total, "Catalog", "Five games, one score",
                      "<p class='lede'>Each game runs a short unscored practice round, then its scored trials. "
                      "About six minutes end to end.</p>" f"<div class='cards'>{cards}</div>"))

    # 3 micro-interactions
    prims = ""
    for name, desc, kind in PRIMITIVES:
        img = save(f"prim_{kind}.svg", primitive_svg(kind))
        prims += f"<div class='prim'><img src='{img}'><h3>{esc(name)}</h3><p>{esc(desc)}</p></div>"
    pages.append(page(3, total, "Micro-interactions", "Five primitives",
                      "<p class='lede'>Every game is built from the same five motions. Feedback confirms contact. "
                      "It never reveals timing or score.</p>"
                      f"<div class='prims'>{prims}</div><div class='env'>"
                      "<div><b>SPACE</b>Full immersion. Ink sky dome and a 6 m floor grid disc. Nothing else in view.</div>"
                      "<div><b>SCALE</b>Every object at true size and distance, in meters from the participant.</div>"
                      "<div><b>SCORE</b>Hidden during play. Shown once, after the last game.</div></div>"))

    # 4-8 games
    for i, g in enumerate(GAME_ORDER):
        G = GAMES[g]
        img = save(f"scene_{g}.svg", G["scene"]())
        mech = "".join(f"<li>{esc(m)}</li>" for m in G["mechanic"])
        mets = "".join(f"<li><b>{esc(a)}</b> {esc(b)}</li>" for a, b in G["metrics"])
        body = (f"<div class='game'><div><img src='{img}'></div><div class='side'>"
                f"<p style='font-size:15px;color:#1b2430;margin-top:.05in'>{esc(G['instruction'])}</p>"
                f"<div class='sec'><div class='k'>Mechanic</div><ul>{mech}</ul></div>"
                f"<div class='sec'><div class='k'>Micro-interactions</div><p style='font-size:11.5px'>{esc(G['micro'])}</p></div>"
                f"<div class='sec'><div class='k'>Captured per trial</div><div class='f'>{esc(G['fields'])}</div></div>"
                f"<div class='sec'><div class='k'>Metrics</div><ul>{mets}</ul></div></div></div>")
        pages.append(page(4 + i, total, f"Game {i + 1} of 5 · {G['n'][0]} scored trials",
                          G["title"], body, foot="Dimensions in meters, life scale"))

    # 9 architecture
    arch = save("architecture.svg", architecture())
    pages.append(page(9, total, "Score architecture", "ScoreKit",
                      "<p class='lede'>Scoring lives in one Swift package with no UI or ARKit dependency. "
                      "The app, the CLI and the tests link the same code.</p>"
                      f"<img src='{arch}' style='width:9.8in;margin-top:.2in'>"))

    # 10 algorithms
    algo = [
        ("Movement onset", "Trace resampled to 90 Hz, Gaussian smoothed (σ 2 samples). Onset fires when speed stays "
         "above 0.15 m/s for 50 ms, then walks back to where speed last fell under 5% of peak.",
         "RT = onset − spawn_t,  MT = contact_t − onset"),
        ("Smoothness", "Log dimensionless jerk on the velocity vector between onset and contact "
         "(Balasubramanian 2015). Closer to zero is smoother.",
         "LDLJ = −ln( T³ / v_peak² · ∫ |d²v/dt²|² dt )"),
        ("RT distribution", "Ex-Gaussian by method of moments on untrimmed RTs (0.10 to 1.50 s). "
         "Tau is the slow tail. Medians use 3-MAD trimming.",
         "τ = s·(γ/2)^⅓,  μ = mean − τ"),
        ("Inhibition", "Signal detection on Gate with the log-linear correction (Hautus 1995).",
         "d' = Φ⁻¹((H+.5)/(G+1)) − Φ⁻¹((F+.5)/(N+1))"),
        ("Metric age", "Each norm is a curve m(a) = m₂₅ + β(a−25) + γ·max(0,a−50)². "
         "A value inverts to an age by bisection over 18 to 95. Its SD combines measurement and model error.",
         "sd = √( (sem / |m'(a)|)² + τ² )"),
        ("Fusion", "Inverse-variance weights into 5 domains, then across domains. Correlated inputs inflate the "
         "variance by the design effect, ρ 0.5 within a domain and 0.3 between.",
         "var = (1 + (k−1)ρ) / Σ wᵢ"),
        ("Spatial Age", "Evidence combines with a prior centered on chronological age, SD 9 years. "
         "Thin evidence stays near the calendar. Reported with an 80% interval.",
         "age = (e·w_e + c·w_p) / (w_e + w_p)"),
        ("Pace of aging", "Weighted least squares of Spatial Age on time, at least 3 sessions over 28 days, "
         "shrunk toward 1.0 with prior SD 0.5.",
         "pace = (1·w₀ + b·w_b) / (w₀ + w_b)"),
    ]
    cells = "".join(f"<div><h3>{esc(t)}</h3><p>{esc(d)}</p><span class='eq'>{esc(e)}</span></div>" for t, d, e in algo)
    pages.append(page(10, total, "Algorithms", "From fingertip to age", f"<div class='algo'>{cells}</div>",
                      foot="Constants from packages/ScoreKit source"))

    # 11 data dictionary
    schema = json.loads((ROOT / "packages/schema/session.schema.json").read_text())
    desc = {
        "index": "trial number in block", "kind": "go or nogo", "hand": "left, right or null", "spawn_t": "target visible",
        "move_t": "device movement onset", "contact_t": "fingertip entered radius", "position": "target center",
        "eccentricity_deg": "head forward to target at spawn", "outcome": "trial result", "tracking_gap_ms": "longest hand gap",
        "endpoint_error_m": "fingertip to center at contact", "trace": "fingertip path {t, p} at 90 Hz",
        "span": "sequence length", "sequence": "node ids shown", "response": "node ids touched", "correct": "response equals sequence",
        "start_t": "trial start", "end_t": "trial end", "tap_t": "time of each touch", "length_m": "cord length",
        "amplitude_deg": "swing amplitude", "release_t": "cord releases", "release_angle_deg": "cord angle at release",
        "release_position": "bob at release", "release_velocity": "bob velocity at release", "catch_t": "grasp closes on bob",
        "catch_position": "bob at catch", "aperture_release_m": "thumb-index gap at release",
        "aperture_catch_m": "thumb-index gap at catch", "duration_s": "trial length", "path": "Lissajous parameters",
        "t": "sample times", "target": "orb positions", "finger": "fingertip, null when untracked",
    }
    blocks = ""
    for name, key in [("Spark and Gate · reaction trial", "reactionTrial"), ("Pendulum trial", "pendulumTrial"),
                      ("Constellation · Corsi trial", "corsiTrial"), ("Orbit · pursuit trial", "pursuitTrial")]:
        d = schema["$defs"][key]
        req = set(d.get("required", []))
        rows = "".join(f"<tr><td class='c'>{k}{'' if k in req else ' ?'}</td><td>{esc(desc.get(k, ''))}</td></tr>"
                       for k in d["properties"])
        blocks += f"<div><h3>{esc(name)}</h3><table>{rows}</table></div>"
    pages.append(page(11, total, "Data dictionary", "Everything we capture",
                      "<p class='lede' style='max-width:none'>One JSON file per session: participant code, age, sex, "
                      "handedness, device, then one block per game. Times in seconds from session start, positions in "
                      "meters, y up. <span style='font-family:Menlo;font-size:11px'>?</span> marks optional fields.</p>"
                      f"<div class='dd'>{blocks}</div>", foot="packages/schema/session.schema.json"))

    # 12 report card
    usable = [r for r in cohort if r["quality"]["usable"] and 45 <= r["chronological_age"] <= 62]
    pick = min(usable, key=lambda r: r["age_gap"])
    card = save("report_card.svg", report_card(pick))
    pages.append(page(12, total, "Report", "One session, one number",
                      f"<img src='{card}' style='width:9.6in;margin-top:.3in'>", synthetic=True,
                      foot="Domain and game scores: percentile against the age-25 reference"))

    # 13 cohort
    sc, r, mae, base = scatter_chart(cohort)
    sc_img = save("cohort_scatter.svg", sc)
    bars = save("cohort_metrics.svg", metric_bars(cohort))
    dm = save("cohort_domains.svg", domain_multiples(cohort))
    pages.append(page(13, total, f"Cohort · n = {len(cohort)}", "Does it track age",
                      f"<div class='two'><img src='{sc_img}' style='width:5.4in'><img src='{bars}' style='width:3.5in'></div>"
                      f"<img src='{dm}' style='width:9.8in;margin-top:.05in'>", synthetic=True,
                      foot="Synthetic r says the pipeline works, not that the biomarker does"))

    # 14 pace
    pc = save("pace.svg", pace_chart(history, pace))
    P = pace["pace"]
    stat = (f"<div class='stat'><div><b>{P['pace']:.2f}×</b>pace of aging</div>"
            f"<div><b>± {P['sd']:.2f}</b>posterior SD</div><div><b>{P['sessions']}</b>sessions</div>"
            f"<div><b>{P['window_days']:.0f}</b>days</div><div><b>{P['raw_slope']:.1f}</b>raw slope, years per year</div></div>")
    pages.append(page(14, total, "Longitudinal", "Pace of aging",
                      "<p class='lede' style='max-width:6in'>One synthetic participant, 52 at the start, whose latent age "
                      "advances 0.8 years per calendar year. Session noise dwarfs 8 months of change, so the shrunk pace "
                      "stays near 1.0. A pace claim needs a longer window or more sessions.</p>"
                      f"{stat}<img src='{pc}' style='width:7.6in;margin-top:.15in'>", synthetic=True))

    # 15 norms + limits
    rows = ""
    for n in norms["norms"]:
        model = n.get("domain") is not None and n["tau_years"] < 50
        rows += (f"<tr><td class='c'>{n['id']}</td><td>{n.get('domain') or 'display'}</td><td>{n['mean25']:g}</td>"
                 f"<td>{n['sd25']:g}</td><td>{n['slope']:+g}</td><td>{n['tau_years'] if model else '–'}</td>"
                 f"<td>{esc(n['source'])}</td></tr>")
    table = ("<table><tr><th>Metric</th><th>Domain</th><th>Mean 25</th><th>SD 25</th><th>Per year</th>"
             f"<th>τ years</th><th>Shape source</th></tr>{rows}</table>")
    limits = ("<div class='env' style='grid-template-columns:1fr;gap:.12in;margin-top:0'>"
              "<div><b>PRIORS</b>Every norm is provisional. The cited studies set curve shape. None used a headset "
              "reach task, so values need refitting on collected sessions (specs/age-model.md v1).</div>"
              "<div><b>VALIDATION</b>Ridge model with leave-one-out CV. Report MAE next to the predict-the-mean "
              "baseline, and gap-age correlation for regression to the mean.</div>"
              "<div><b>RELIABILITY</b>Test-retest on 5 participants. Practice effects held by the fixed practice round.</div>"
              "<div><b>SCOPE</b>Functional age for research and demos. No clinical claim or diagnosis.</div></div>")
    pages.append(page(15, total, f"Norm table {norms['version']}", "Priors and limits",
                      f"<div style='display:grid;grid-template-columns:6.6in 3.0in;gap:.25in;margin-top:.15in'>"
                      f"<div>{table}</div>{limits}</div>"))

    assert len(pages) == total
    html = (f"<!doctype html><html><head><meta charset='utf-8'><title>Spatial Age</title><style>{CSS}</style>"
            f"</head><body>{''.join(pages)}</body></html>")
    (HERE / "doc.html").write_text(html)


def render():
    pdf = OUT / "SpatialAge_Minigames.pdf"
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--allow-file-access-from-files",
                    f"--print-to-pdf={pdf}", (HERE / "doc.html").as_uri()], check=True, capture_output=True)
    return pdf


def main():
    cohort, history, pace, norms = collect()
    build_doc(cohort, history, pace, norms)
    pdf = render()
    print(f"{pdf.relative_to(ROOT)}  ({pdf.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    sys.exit(main())
