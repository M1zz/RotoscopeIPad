#!/usr/bin/env python3
"""Generates the bundled "따라 그리기" guide presets.

Each preset is a folder of 20 transparent PNGs (1600x1200) with soft
blue-gray outlines — like the non-photo-blue guides animators trace over.
A kid traces every page with the brush; on playback the guides are hidden,
so only the child's drawing animates (rotoscoping!).

How the drawings are made
  * Every character is built from smooth closed curves (Catmull-Rom splines
    through a few control points), so outlines are round and friendly.
  * Shapes are drawn back-to-front and each one first erases what is under
    it, like cut paper — a head in front of a body hides the body's line.
  * Everything is drawn at 3x and downsampled for soft, even lines.

Run from the repo root:
    python3 Tools/generate_presets.py            # all presets
    python3 Tools/generate_presets.py 03_bird    # just one (for tweaking)

Output: RotoscopeiPad/Presets/<NN_name>/frame_00.png … frame_19.png
"""

import math
import os
import shutil
import sys

from PIL import Image, ImageDraw

W, H = 1600, 1200          # matches RotoProject.blankCanvasSize
SS = 3                     # supersample factor for smooth lines
FRAMES = 20
LINE = (146, 170, 198, 255)   # soft blue-gray guide color
CLEAR = (0, 0, 0, 0)
LW = 19                    # main outline width at final resolution
DW = 13                    # detail line width (faces, patterns)

OUT_ROOT = os.path.join(os.path.dirname(__file__), "..",
                        "RotoscopeiPad", "Presets")


# ---------------------------------------------------------------- geometry

def lerp(a, b, u):
    return a + (b - a) * u


def ease(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


def wave(t, cycles=1.0, phase=0.0):
    """Seamless loop helper: sin over the loop."""
    return math.sin(2 * math.pi * (t * cycles + phase))


def rotate(pts, deg, cx=0.0, cy=0.0):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa,
             cy + (x - cx) * sa + (y - cy) * ca) for (x, y) in pts]


def move(pts, dx, dy):
    return [(x + dx, y + dy) for (x, y) in pts]


def scale(pts, sx, sy=None, cx=0.0, cy=0.0):
    sy = sx if sy is None else sy
    return [(cx + (x - cx) * sx, cy + (y - cy) * sy) for (x, y) in pts]


def mirror(pts):
    return [(-x, y) for (x, y) in pts]


def ellipse(cx, cy, rx, ry=None, start=0.0, end=360.0, n=None):
    ry = rx if ry is None else ry
    n = n or max(24, int(abs(end - start) / 360 * (rx + ry) * 0.5))
    return [(cx + rx * math.cos(math.radians(lerp(start, end, i / n))),
             cy + ry * math.sin(math.radians(lerp(start, end, i / n))))
            for i in range(n + 1)]


def spline(ctrl, closed=True, n=14):
    """Catmull-Rom curve through the control points."""
    p = list(ctrl)
    if closed:
        p = [p[-1]] + p + [p[0], p[1]]
    else:
        p = [p[0]] + p + [p[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(n):
            u = k / n
            u2, u3 = u * u, u * u * u
            out.append(tuple(
                0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * u
                       + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u2
                       + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * u3)
                for j in (0, 1)))
    out.append(p[-2])
    return out


def bezier(p0, p1, p2, n=28):
    return [((1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * p1[0] + u * u * p2[0],
             (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * p1[1] + u * u * p2[1])
            for u in (i / n for i in range(n + 1))]


def tube(center, w0, w1=None):
    """Closed outline around a centerline (ears, legs, stems) with round ends."""
    w1 = w0 if w1 is None else w1
    n = len(center)
    left, right = [], []
    for i, (x, y) in enumerate(center):
        a, b = center[max(i - 1, 0)], center[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        r = lerp(w0, w1, i / (n - 1)) / 2
        left.append((x + nx * r, y + ny * r))
        right.append((x - nx * r, y - ny * r))
    # round caps
    def cap(c, r, toward):
        ang = math.degrees(math.atan2(toward[1], toward[0]))
        return ellipse(c[0], c[1], r, r, ang - 90, ang + 90, n=16)[1:-1]
    (x0, y0), (x1, y1) = center[0], center[-1]
    end = cap(center[-1], w1 / 2, (x1 - center[-2][0], y1 - center[-2][1]))
    start = cap(center[0], w0 / 2, (x0 - center[1][0], y0 - center[1][1]))
    return left + end[::-1] + right[::-1] + start[::-1]


def cloud(cx, cy, rx, ry, bumps=7, puff=0.16, phase=0.0):
    """Puffy scalloped outline (smoke, clouds)."""
    pts = []
    n = bumps * 18
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1 + puff * abs(math.sin(bumps / 2 * a + phase))
        pts.append((cx + rx * k * math.cos(a), cy + ry * k * math.sin(a)))
    return pts


# ---------------------------------------------------------------- drawing

class Pen:
    """Draws in 1600x1200 space through an optional transform `self.T`."""

    def __init__(self):
        self.img = Image.new("RGBA", (W * SS, H * SS), CLEAR)
        self.d = ImageDraw.Draw(self.img)
        self.T = None

    def _px(self, pts):
        if self.T:
            pts = self.T(pts)
        return [(x * SS, y * SS) for (x, y) in pts]

    def line(self, pts, w=LW):
        p = self._px(pts)
        self.d.line(p, fill=LINE, width=round(w * SS), joint="curve")
        r = w * SS / 2
        for (x, y) in (p[0], p[-1]):
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=LINE)

    def shape(self, pts, w=LW, erase=True):
        """Closed outline; erases whatever is underneath first."""
        pts = list(pts)
        if erase:
            self.d.polygon(self._px(pts), fill=CLEAR)
        self.line(pts + pts[:2], w)

    def fill(self, pts, color=LINE):
        self.d.polygon(self._px(pts), fill=color)

    def dot(self, cx, cy, r):
        self.fill(ellipse(cx, cy, r))

    def eye(self, cx, cy, rx, ry=None, look=(0.0, 0.0)):
        """Shiny cartoon eye: solid with a little highlight."""
        ry = ry or rx
        self.fill(ellipse(cx, cy, rx, ry))
        hx = cx - rx * 0.35 + look[0]
        hy = cy - ry * 0.38 + look[1]
        self.fill(ellipse(hx, hy, rx * 0.36, ry * 0.36), CLEAR)

    def result(self):
        return self.img.resize((W, H), Image.LANCZOS)


def placed(dx, dy, sx=1.0, sy=1.0, deg=0.0):
    """Transform: scale, rotate, then move local coords to the canvas."""
    def T(pts):
        return move(rotate(scale(pts, sx, sy), deg), dx, dy)
    return T


# ---------------------------------------------------------------- presets

def ball(p, t):
    """Beach ball bouncing in place: squash on the floor, stretch in flight."""
    ground, R, top = 1010, 150, 520
    h = top * (1 - (2 * t - 1) ** 2)               # 0 at t=0, peak at t=.5
    v = abs(2 * t - 1)                             # speed (1 at the floor)
    if t == 0:
        sx, sy = 1.28, 0.74                        # squash on contact
    else:
        sy = 1 + 0.14 * v ** 3                     # stretch when fast
        sx = 1 / sy
    # shadow on the floor shrinks as the ball rises
    k = 1 - 0.55 * h / top
    p.shape(ellipse(800, ground + 6, 150 * k * (1.2 if t == 0 else 1),
                    26 * k), w=DW)
    p.T = placed(800, ground - h, sx, sy)
    p.shape(ellipse(0, -R, R))
    seam = ellipse(0, -R, R * 0.42, R, -90, 90)
    p.line(seam, DW)
    p.line(mirror(seam), DW)
    p.shape(ellipse(0, -R * 1.62, R * 0.2, R * 0.13), w=DW)   # top cap
    # shine
    p.line(ellipse(0, -R, R * 0.74, R * 0.74, 200, 245), DW)
    p.T = None
    if t == 0:                                     # bump marks
        for side in (-1, 1):
            for dy, ln in ((-60, 70), (-10, 90)):
                x0 = 800 + side * 230
                p.line([(x0, ground + dy), (x0 + side * ln, ground + dy - 25)],
                       DW)


def bunny(p, t):
    """Front-facing bunny hopping in place; ears lag behind the jump."""
    ground, top = 1075, 230
    f = t * FRAMES
    # vertical keys: crouch → launch → air → land → settle
    air0, air1 = 3, 17
    if air0 <= f <= air1:
        u = (f - air0) / (air1 - air0)
        h = top * 4 * u * (1 - u)
        vel = 1 - 2 * u                            # +1 up … -1 down
    else:
        h, vel = 0.0, 0.0
    squash = {0: 0.82, 1: 0.84, 2: 0.92, 3: 1.10, 4: 1.06,
              16: 1.06, 17: 0.84, 18: 0.87, 19: 0.92}.get(round(f), 1.0)
    sy, sx = squash, 1 / squash ** 0.7

    k = 1 - 0.5 * h / top
    p.shape(ellipse(800, ground + 26, 165 * k, 18 * k), w=DW)
    p.T = placed(800, ground - h, sx, sy)

    # ears (behind head): swept down while rising, perked when falling
    droop = 30 * vel
    for side in (-1, 1):
        ear = spline([(-38, 0), (-52, -110), (-30, -215), (0, -245),
                      (30, -215), (52, -110), (38, 0)])
        inner = spline([(-16, -30), (-24, -120), (0, -195), (24, -120),
                        (16, -30)])
        bend = lambda pts: [(x + (y / 245) ** 2 * side * droop * 2.2, y)
                            for (x, y) in pts]
        place = lambda pts: move(rotate(bend(pts), side * (10 + droop * 0.3)),
                                 side * 62, -395)
        p.shape(place(ear))
        p.shape(place(inner), w=DW)
    # body
    p.shape(spline([(0, -240), (90, -215), (128, -120), (108, -30), (0, -6),
                    (-108, -30), (-128, -120), (-90, -215)]))
    p.line(ellipse(0, -100, 52, 50, 30, 150), DW)       # tummy
    # paws hug the tummy, feet stand on the ground
    for side in (-1, 1):
        p.shape(ellipse(side * 82, -150, 30, 38))
        p.shape(ellipse(side * 70, -28, 60, 28))
        for dx in (-14, 14):
            p.line([(side * 70 + dx, -44), (side * 70 + dx, -34)], DW * 0.8)
    # head
    p.shape(spline([(0, -440), (115, -425), (178, -350), (170, -270),
                    (100, -222), (0, -212), (-100, -222), (-170, -270),
                    (-178, -350), (-115, -425)]))
    # face
    blink = round(f) == 10
    for side in (-1, 1):
        if blink:
            p.line(ellipse(side * 64, -325, 21, 14, 200, 340), DW)
        else:
            p.eye(side * 64, -327, 19, 23)
        p.shape(ellipse(side * 118, -275, 25, 15), w=DW)     # cheeks
    p.fill(spline([(-17, -295), (17, -295), (0, -277)]))     # nose
    p.line(ellipse(-16, -276, 16, 15, 0, 150), DW)           # mouth "w"
    p.line(ellipse(16, -276, 16, 15, 30, 180), DW)
    p.T = None


def bird(p, t):
    """Round little bird flapping in place, two wingbeats per loop."""
    flap = wave(t, 2, 0.05)       # +1 up, -1 down; never edge-on (0)
    cx, cy = 790, 620 - 40 * flap                  # body rises on downbeat
    p.T = placed(cx, cy, 1.2, 1.2, deg=-3 * flap)

    def wing(deg, hinge=(-20, -25)):
        # rounded leaf-shaped wing pointing back from the hinge
        w = spline([(30, -38), (-80, -62), (-190, -40), (-235, 0),
                    (-180, 38), (-70, 52), (25, 36)])
        return move(rotate(w, deg), *hinge)

    def feathers(deg, hinge=(-20, -25)):
        return [move(rotate(f, deg), *hinge) for f in
                (bezier((-95, -15), (-140, -8), (-175, 2)),
                 bezier((-80, 18), (-120, 24), (-150, 26)))]

    up = 20 + 48 * flap                            # 68° up … -28° down
    # far wing pokes over the back on the upstroke
    if flap > 0.3:
        p.shape(wing(up + 16, (-60, -70)))
    # tail feathers
    for ang in (-24, -2, 20):
        feather = spline([(0, -32), (90, -42), (165, 0), (90, 42), (0, 32)])
        p.shape(move(rotate(feather, 180 + ang), -150, 20))
    # beak
    p.shape(spline([(150, -95), (235, -62), (150, -30)], n=8))
    # body: chubby rounded teardrop, head on top front
    p.shape(spline([(165, -60), (140, -150), (40, -195), (-80, -165),
                    (-175, -60), (-185, 40), (-110, 125), (20, 145),
                    (130, 95), (175, 20)]))
    # belly line + head tuft
    p.line(spline([(125, 55), (55, 100), (-35, 108)], closed=False), DW)
    p.line(spline([(20, -190), (5, -245), (40, -270)], closed=False), DW)
    p.line(spline([(45, -186), (55, -230), (95, -240)], closed=False), DW)
    # face
    p.eye(85, -85, 22, 25)
    p.shape(ellipse(102, -22, 26, 15), w=DW)
    # near wing
    p.shape(wing(up))
    for f in feathers(up):
        p.line(f, DW)
    p.T = None


def fish(p, t):
    """Chubby fish swimming in place; tail wags, bubbles rise."""
    wag = wave(t, 2)
    cx, cy = 760, 600 + 30 * wave(t, 1)
    p.T = placed(cx, cy, deg=4 * wave(t, 1, 0.25))
    # tail (behind body), hinged where it meets the body
    tail = spline([(-150, -40), (-270, -165), (-345, -150), (-300, 0),
                   (-345, 150), (-270, 165), (-150, 40)])
    tail = rotate(scale(tail, 1 - 0.12 * abs(wag), 1, -170, 0), 18 * wag,
                  -170, 0)
    p.shape(tail)
    p.line(rotate([(-205, -40), (-275, -110)], 18 * wag, -170, 0), DW)
    p.line(rotate([(-205, 40), (-275, 110)], 18 * wag, -170, 0), DW)
    # top and bottom fins
    p.shape(spline([(-110, -110), (-60, -215), (40, -235), (90, -200),
                    (80, -120)]))
    p.shape(spline([(-60, 110), (-20, 185), (50, 175), (60, 110)]))
    # body
    p.shape(spline([(250, 10), (210, -110), (60, -165), (-110, -135),
                    (-200, -50), (-205, 40), (-120, 135), (60, 165),
                    (210, 115)]))
    # gill + face
    p.line(spline([(70, -130), (100, -20), (70, 115)], closed=False), DW)
    p.shape(ellipse(160, -45, 40))
    p.eye(170, -45, 22)
    p.line(ellipse(225, 45, 26, 22, 80, 200), DW)
    p.T = None
    # bubbles drift upward and loop
    for k, (bx0, r) in enumerate(((1170, 22), (1110, 32), (1200, 44))):
        ph = (t + k / 3) % 1.0
        bx = bx0 + 30 * wave(ph, 1, k * 0.3)
        by = 700 - 540 * ph
        p.shape(ellipse(bx, by, r), w=DW)
        p.line(ellipse(bx, by, r * 0.55, r * 0.55, 200, 250), DW * 0.8)


def flower(p, t):
    """A sprout grows, the bud opens into a smiling flower, then it sways."""
    ground = 1040
    grow = ease(t / 0.45)                          # stem
    bloom = ease((t - 0.40) / 0.30)                # petals
    sway = 6 * math.sin(2 * math.pi * max(0.0, t - 0.7) / 0.3) * ease(
        (t - 0.7) / 0.1)
    # soil mound and grass
    p.line(spline([(430, ground + 10), (600, ground - 18), (800, ground - 26),
                   (1000, ground - 18), (1170, ground + 10)], closed=False))
    for gx in (520, 1080):
        for dx, ht in ((-22, 50), (0, 72), (22, 50)):
            p.line([(gx, ground - 10), (gx + dx * 1.8, ground - 10 - ht)], DW)

    root = (800, ground - 24)
    height = 120 + 500 * grow
    top = (800 + sway * 6, root[1] - height)
    stem = spline([root, (800 - 40 * grow, root[1] - height * 0.5), top],
                  closed=False, n=20)
    p.line(stem, LW)

    # leaves unfold along the stem
    for side, at, delay in ((-1, 0.38, 0.0), (1, 0.55, 0.15)):
        g = ease((grow - 0.25 - delay) / 0.4)
        if g <= 0:
            continue
        g = 0.35 + 0.65 * g
        sx_, sy_ = stem[int(at * (len(stem) - 1))]
        leaf = spline([(0, 0), (70, -45), (170, -40), (110, 10)], n=10)
        leaf = rotate(scale(leaf, g * side, g), side * -15 + sway * 0.5)
        p.shape(move(leaf, sx_, sy_))
        p.line(move(rotate(scale([(15, -6), (120, -26)], g * side, g),
                           side * -15 + sway * 0.5), sx_, sy_), DW)

    hx, hy = top
    tilt = sway
    if bloom <= 0:
        # seedling bud: a closed teardrop
        bud = scale(spline([(0, 10), (40, -20), (0, -95), (-40, -20)]),
                    0.4 + 0.6 * grow)
        p.shape(move(bud, hx, hy))
        return
    # petals open out from the bud
    n = 8
    pr = lerp(40, 118, bloom)
    for i in range(n):
        a = i * 360 / n + 22.5 * (1 - bloom) + tilt
        petal = spline([(0, -40), (pr * 0.9, -55), (pr + 70, 0),
                        (pr * 0.9, 55), (0, 40)])
        petal = scale(petal, lerp(0.45, 1, bloom))
        p.shape(move(rotate(petal, a), hx, hy))
    # face in the middle
    r = lerp(55, 92, bloom)
    p.shape(ellipse(hx, hy, r))
    if bloom > 0.5:
        p.T = placed(hx, hy, deg=tilt)
        for side in (-1, 1):
            p.line(ellipse(side * 30, -10, 15, 12, 200, 340), DW)  # ^ ^
            p.shape(ellipse(side * 52, 22, 13, 8), w=DW * 0.8)
        p.line(ellipse(0, 18, 22, 18, 20, 160), DW)
        p.T = None


def butterfly(p, t):
    """Butterfly fluttering along a gentle figure-eight."""
    cx = 800 + 230 * wave(t, 1)
    cy = 560 + 90 * wave(t, 2)
    flap = 0.5 + 0.5 * math.cos(2 * math.pi * t * 3)   # 3 beats per loop
    open_ = lerp(0.38, 1.0, flap)
    p.T = placed(cx, cy, deg=8 * wave(t, 1, 0.25))

    upper = spline([(14, -30), (50, -150), (170, -225), (290, -200),
                    (295, -110), (205, -25), (40, 10)])
    lower = spline([(16, 0), (150, 15), (230, 95), (195, 190),
                    (90, 200), (25, 90)])
    for side in (-1, 1):
        def w(pts):
            return [(side * x * open_, y) for (x, y) in pts]
        p.shape(w(lower))
        p.shape(w(ellipse(120, 110, 34, 30)), w=DW)
        p.shape(w(upper))
        p.shape(w(ellipse(180, -125, 50, 44)), w=DW)
    # body, head, antennae
    p.shape(tube(spline([(0, -60), (0, 40), (0, 150)], closed=False, n=8),
                 54, 34))
    for y in (10, 60):
        p.line([(-18, y), (18, y)], DW)
    for side in (-1, 1):
        ant = spline([(side * 14, -110), (side * 40, -190), (side * 95, -235)],
                     closed=False)
        p.line(ant, DW)
        p.shape(ellipse(side * 100, -238, 15), w=DW)
    p.shape(ellipse(0, -100, 52, 48))
    for side in (-1, 1):
        p.eye(side * 20, -106, 10, 12)
    p.line(ellipse(0, -90, 16, 12, 20, 160), DW)
    p.T = None


def car(p, t):
    """Round little car driving along; wheels roll, road slides past."""
    ground = 1000
    R = 92
    roll = 2 * math.pi * R                         # one wheel turn per loop
    # road edge + sliding dashes (one dash period = half a wheel turn)
    p.line([(140, ground), (1460, ground)])
    period = roll / 2
    x = 140 - (t * roll) % period
    while x < 1460:
        a, b = max(x, 160), min(x + period * 0.5, 1440)
        if b > a + 20:
            p.line([(a, ground + 70), (b, ground + 70)], DW)
        x += period
    # speed lines + puff behind
    for y, ln, ph in ((640, 120, 0.0), (720, 170, 0.33), (800, 110, 0.66)):
        sh = 40 * wave(t, 2, ph)
        p.line([(300 + sh, y), (300 + sh + ln, y)], DW)
    ph = (t * 2) % 1.0
    p.shape(cloud(390 - 110 * ph, 905 - 30 * ph, 34 + 30 * ph, 26 + 22 * ph,
                  bumps=5, puff=0.22), w=DW)

    bob = 7 * wave(t, 4)
    p.T = placed(820, ground - R + bob, deg=-1.2 * wave(t, 4, 0.25))
    # body: rounded bubble car, wheel centers at (±230, 0)
    p.shape(spline([(390, -20), (395, -95), (330, -150), (180, -175),
                    (100, -300), (-60, -330), (-230, -300), (-330, -170),
                    (-385, -90), (-375, -15), (-300, 20), (300, 20)], n=16))
    # windows
    p.shape(spline([(-20, -305), (85, -285), (150, -180), (-20, -180)], n=10),
            w=DW)
    p.shape(spline([(-60, -305), (-60, -180), (-275, -180), (-210, -280)],
                   n=10), w=DW)
    # door + handle, lights, bumper
    p.line([(-40, -165), (-40, -10)], DW)
    p.line([(10, -130), (55, -130)], DW)
    p.shape(ellipse(330, -95, 28, 24), w=DW)
    p.shape(spline([(-385, -125), (-355, -125), (-355, -85), (-385, -85)],
                   n=6), w=DW)
    p.T = placed(820, ground - R)
    # wheels with rolling hubs
    spin = 360 * t
    for wx in (-230, 230):
        p.shape(ellipse(wx, 0, R))
        p.shape(ellipse(wx, 0, 46), w=DW)
        for k in range(3):
            a = math.radians(spin + k * 120)
            p.dot(wx + 24 * math.cos(a), 24 * math.sin(a), 9)
    p.T = None


def rocket(p, t):
    """Rocket rumbles on the pad, then blasts off into the stars."""
    pad = 990
    rumble = 1 - ease((t - 0.25) / 0.1)
    lift = ease((t - 0.25) / 0.75) ** 1.4 * 380
    shake = 6 * rumble * (1 if round(t * FRAMES) % 2 else -1)
    # stars twinkle above
    for i, (sx_, sy_, r) in enumerate(((330, 220, 26), (1250, 170, 30),
                                       (1340, 520, 20), (240, 560, 20),
                                       (1080, 90, 16))):
        k = r * (0.75 + 0.25 * wave(t, 2, i * 0.37))
        star = []
        for j in range(8):
            rr = k if j % 2 == 0 else k * 0.35
            a = math.radians(j * 45 - 90)
            star.append((sx_ + rr * math.cos(a), sy_ + rr * math.sin(a)))
        p.shape(spline(star, n=4), w=DW)
    # launch pad
    p.line([(560, pad), (1040, pad)])

    p.T = placed(800 + shake, pad - 220 - lift)
    # flame grows with lift; three tongues flicker
    fl = ease((t - 0.05) / 0.3) * (1 + 0.1 * wave(t, 5))
    if fl > 0.05:
        def grow(pts):
            return [(x, 205 + (y - 205) * fl) for (x, y) in pts]
        p.shape(grow(spline([(-55, 200), (-62, 270), (-40, 370), (-18, 350),
                             (0, 450), (18, 350), (40, 370), (62, 270),
                             (55, 200)], n=8)))
        p.shape(grow(spline([(-26, 205), (-22, 270), (0, 340), (22, 270),
                             (26, 205)], n=8)), w=DW)
    # fins (behind body)
    for side in (-1, 1):
        p.shape([(side * x, y) for (x, y) in
                 spline([(70, 30), (170, 120), (190, 210), (150, 205),
                         (80, 160)], n=10)])
    # nozzle
    p.shape(spline([(-60, 175), (60, 175), (75, 215), (-75, 215)], n=4))
    # body
    p.shape(spline([(0, -330), (75, -250), (112, -90), (108, 80),
                    (80, 185), (-80, 185), (-108, 80), (-112, -90),
                    (-75, -250)], n=16))
    p.line(spline([(-82, -205), (0, -185), (82, -205)], closed=False), DW)
    p.shape(ellipse(0, -40, 58))
    p.shape(ellipse(0, -40, 38), w=DW)
    p.line(ellipse(0, -40, 26, 26, 200, 250), DW * 0.8)
    p.shape(tube([(0, 90), (0, 205)], 34))          # center fin
    p.T = None
    # smoke clouds billow out at liftoff, then drift away
    k = ease(t / 0.45)
    fade = t < 0.8
    if fade:
        for side in (-1, 1):
            for i, (ox, r) in enumerate(((130, 70), (270, 55))):
                x = 800 + side * (ox + 140 * k)
                y = pad - 40 - 30 * k - 25 * i
                rr = r * (0.4 + 0.8 * k) * (1 - ease((t - 0.6) / 0.2) * 0.6)
                p.shape(cloud(x, y, rr * 1.25, rr, bumps=6, puff=0.18,
                              phase=i + side), w=DW)


def frog(p, t):
    """Front-facing frog: crouch, leap with legs out, land."""
    ground = 1060
    f = t * FRAMES
    air0, air1 = 4, 16
    if air0 <= f <= air1:
        u = (f - air0) / (air1 - air0)
        h = 300 * 4 * u * (1 - u)
        reach = ease(min(u / 0.3, (1 - u) / 0.3, 1.0))   # legs out mid-air
    else:
        h, reach = 0.0, 0.0
    squash = {0: 0.84, 1: 0.80, 2: 0.82, 3: 0.92, 4: 1.08, 5: 1.05,
              15: 1.04, 16: 0.86, 17: 0.80, 18: 0.84, 19: 0.86}.get(
                  round(f), 1.0)
    sy, sx = squash, 1 / squash ** 0.6

    k = 1 - 0.5 * h / 300
    p.shape(ellipse(800, ground + 34, 230 * k, 18 * k), w=DW)
    p.T = placed(800, ground - h, sx, sy)
    # back legs: folded bumps on the ground, stretched down in the air
    for side in (-1, 1):
        hip = (side * 120, -110)
        knee = (side * lerp(225, 175, reach), lerp(-80, -30, reach))
        foot = (side * lerp(205, 150, reach), lerp(-26, 70, reach))
        p.shape(tube(spline([hip, knee, foot], closed=False, n=8), 90, 60))
        for dx in (-36, 0, 36):
            p.shape(ellipse(foot[0] + side * dx, foot[1] + 12, 17, 13), w=DW)
        p.shape(ellipse(foot[0], foot[1], 46, 22))
    # eye bumps behind the head
    for side in (-1, 1):
        p.shape(ellipse(side * 105, -325, 66))
    # body + head as one plump bean
    p.shape(spline([(0, -310), (150, -295), (225, -215), (200, -110),
                    (120, -30), (0, -12), (-120, -30), (-200, -110),
                    (-225, -215), (-150, -295)], n=16))
    # front hands: little three-toed mittens
    for side in (-1, 1):
        hx = side * 88
        for dx in (-24, 0, 24):
            p.shape(ellipse(hx + dx, -14, 15, 12), w=DW)
        p.shape(ellipse(hx, -30, 42, 26))
    # face
    for side in (-1, 1):
        p.shape(ellipse(side * 105, -330, 40, 40), w=DW)
        p.eye(side * 105, -328, 22)
        p.shape(ellipse(side * 155, -200, 26, 15), w=DW)
        p.dot(side * 18, -248, 6)
    p.line(spline([(-110, -215), (-55, -178), (0, -170), (55, -178),
                   (110, -215)], closed=False), DW)
    p.T = None


def pinwheel(p, t):
    """Paper pinwheel spinning on its stick while the wind blows by."""
    cx, cy = 800, 500
    # stick (behind the blades)
    p.shape(tube([(cx, cy), (cx + 8, 1090)], 34))
    spin = 180 * t                                 # 4 blades: seamless
    R = 300
    for i in range(4):
        a = spin + i * 90
        blade = spline([(0, 0), (R * 0.45, -14), (R, 0), (R * 0.83, 85),
                        (R * 0.55, 160), (R * 0.22, 110)], n=10)
        p.shape(move(rotate(blade, a), cx, cy))
        fold = spline([(R * 0.12, 18), (R * 0.5, 55), (R * 0.83, 85)],
                      closed=False)
        p.line(move(rotate(fold, a), cx, cy), DW)
    p.shape(ellipse(cx, cy, 34))
    p.dot(cx, cy, 11)
    # wind swooshes breeze in from the left
    for i, (x0, y, ln) in enumerate(((180, 330, 240), (220, 760, 200),
                                     (1180, 860, 180))):
        dx = 50 * wave(t, 1, i / 3)
        x = x0 + dx
        curl = spline([(x, y), (x + ln * 0.5, y - 28), (x + ln * 0.85, y),
                       (x + ln * 0.75, y + 34), (x + ln * 0.6, y + 10)],
                      closed=False, n=10)
        p.line(curl, DW)


PRESETS = [
    ("01_ball", ball),
    ("02_bunny", bunny),
    ("03_bird", bird),
    ("04_fish", fish),
    ("05_flower", flower),
    ("06_butterfly", butterfly),
    ("07_car", car),
    ("08_rocket", rocket),
    ("09_frog", frog),
    ("10_pinwheel", pinwheel),
]


def main():
    only = set(sys.argv[1:])
    root = os.path.abspath(OUT_ROOT)
    for name, fn in PRESETS:
        if only and name not in only:
            continue
        folder = os.path.join(root, name)
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
        for f in range(FRAMES):
            pen = Pen()
            fn(pen, f / FRAMES)
            pen.result().save(os.path.join(folder, f"frame_{f:02d}.png"),
                              optimize=True)
        print(f"{name}: {FRAMES} frames")
    print(f"done → {root}")


if __name__ == "__main__":
    main()
