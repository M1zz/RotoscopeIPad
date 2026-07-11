#!/usr/bin/env python3
"""Generates the bundled "따라 그리기" guide presets.

Each preset is a folder of 20 transparent PNGs (1600x1200) with soft
blue-gray outlines — like the non-photo-blue guides animators trace over.
A kid traces every page with the brush; on playback the guides are hidden,
so only the child's drawing animates (rotoscoping!).

Run from the repo root:
    python3 Tools/generate_presets.py

Output: RotoscopeiPad/Presets/<NN_name>/frame_00.png … frame_19.png
Re-run any time; the folder is rebuilt from scratch.
"""

import math
import os
import shutil

from PIL import Image, ImageDraw

W, H = 1600, 1200          # matches RotoProject.blankCanvasSize
SS = 2                     # supersample factor for smooth lines
FRAMES = 20
LINE = (146, 170, 198, 255)   # soft blue-gray guide color
LW = 16                    # stroke width at final resolution

OUT_ROOT = os.path.join(os.path.dirname(__file__), "..",
                        "RotoscopeiPad", "Presets")


# ---------------------------------------------------------------- helpers

def new_canvas():
    return Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))


def finish(img):
    return img.resize((W, H), Image.LANCZOS)


def s(v):
    """Scale a coordinate/length into supersampled space."""
    return v * SS


def sp(pts):
    return [(x * SS, y * SS) for (x, y) in pts]


def rot(pts, cx, cy, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa,
             cy + (x - cx) * sa + (y - cy) * ca) for (x, y) in pts]


def ellipse_pts(cx, cy, rx, ry, rot_deg=0.0, n=72, start=0.0, end=360.0):
    pts = []
    for i in range(n + 1):
        a = math.radians(start + (end - start) * i / n)
        pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    if rot_deg:
        pts = rot(pts, cx, cy, rot_deg)
    return pts


def stroke(d, pts, width=LW, closed=False):
    if closed:
        pts = list(pts) + [pts[0], pts[1]]
    d.line(sp(pts), fill=LINE, width=int(width * SS), joint="curve")
    # round caps
    r = width * SS / 2
    for (x, y) in (sp([pts[0]])[0], sp([pts[-1]])[0]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=LINE)


def dot(d, cx, cy, r):
    d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=LINE)


def bezier(p0, p1, p2, n=24):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    return pts


def ease(t):
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- presets

def ball(d, t):
    """Bouncing ball with squash & stretch."""
    ground = 1000
    stroke(d, [(220, ground), (1380, ground)])
    r = 150
    h = 560 * 4 * t * (1 - t)                     # parabolic arc
    near = max(0.0, 1 - h / 120)                  # 1 on the ground → squash
    rx = r * (1 + 0.30 * near)
    ry = r * (1 - 0.30 * near)
    if h > 380:                                    # stretch near the top
        rx, ry = r * 0.92, r * 1.10
    cy = ground - ry - h
    stroke(d, ellipse_pts(800, cy, rx, ry), closed=True)
    # a little arc inside so the ball reads as rolling
    stroke(d, ellipse_pts(800, cy, rx * 0.55, ry * 0.55,
                          start=200, end=320), width=LW * 0.75)


def bunny(d, t):
    """Hopping rabbit: body, head, long ears that trail the jump."""
    ground = 1030
    stroke(d, [(200, ground), (1400, ground)])
    # hold the crouch for a few frames so the hop reads clearly
    if t < 0.15 or t > 0.85:
        hop = 0.0
    else:
        u = (t - 0.15) / 0.7
        hop = 380 * 4 * u * (1 - u)
    cx, cy = 780, ground - 250 - hop
    airborne = hop > 40
    tilt = -10 if airborne else 0
    # body
    stroke(d, ellipse_pts(cx, cy, 260, 180, rot_deg=tilt), closed=True)
    # tail
    stroke(d, ellipse_pts(cx - 270, cy - 20, 55, 55), closed=True)
    # head
    hx, hy = cx + 250, cy - 150
    stroke(d, ellipse_pts(hx, hy, 130, 115), closed=True)
    # ears swing back while airborne
    lean = 28 * math.sin(2 * math.pi * t)
    for off in (-45, 35):
        e = ellipse_pts(hx + off, hy - 200, 38, 130,
                        rot_deg=off * 0.25 - lean)
        stroke(d, e, closed=True, width=LW * 0.9)
    dot(d, hx + 55, hy - 20, 13)                  # eye
    stroke(d, ellipse_pts(hx + 128, hy + 28, 26, 20,
                          start=-40, end=200), width=LW * 0.75)  # nose/mouth
    # feet: tucked in the air, planted on the ground
    if airborne:
        stroke(d, bezier((cx - 120, cy + 165), (cx, cy + 240),
                         (cx + 140, cy + 170)), width=LW * 0.9)
    else:
        stroke(d, ellipse_pts(cx + 60, ground - 42, 120, 44), closed=True,
               width=LW * 0.9)
        stroke(d, ellipse_pts(cx - 190, ground - 42, 95, 42), closed=True,
               width=LW * 0.9)


def bird(d, t):
    """Flapping bird, bobbing gently as the wing beats."""
    flap = math.sin(2 * math.pi * t * 2)           # two beats per loop
    cx, cy = 800, 600 - 45 * flap
    # body
    stroke(d, ellipse_pts(cx, cy, 260, 150), closed=True)
    # tail feathers
    stroke(d, [(cx - 250, cy + 40), (cx - 420, cy + 60)])
    stroke(d, [(cx - 245, cy + 75), (cx - 400, cy + 130)])
    # head + beak + eye
    hx, hy = cx + 250, cy - 120
    stroke(d, ellipse_pts(hx, hy, 105, 95), closed=True)
    stroke(d, [(hx + 95, hy - 15), (hx + 190, hy + 10), (hx + 92, hy + 38)],
           closed=True, width=LW * 0.9)
    dot(d, hx + 30, hy - 25, 13)
    # near wing: root at the shoulder, tip sweeping up and down
    ang = -55 * flap
    root = (cx - 20, cy - 80)
    tip = rot([(cx - 150, cy - 360)], root[0], root[1], ang)[0]
    back = rot([(cx - 280, cy - 160)], root[0], root[1], ang)[0]
    wing = (bezier(root, ((root[0] + tip[0]) / 2 + 60,
                          (root[1] + tip[1]) / 2 - 40), tip)
            + bezier(tip, back, (cx - 160, cy - 20)))
    stroke(d, wing)
    # motion puffs under the wing on the downbeat
    if flap < -0.55:
        stroke(d, ellipse_pts(cx - 60, cy + 230, 60, 24, start=180, end=360),
               width=LW * 0.6)


def fish(d, t):
    """Swimming fish with a wagging tail and rising bubbles."""
    wag = math.sin(2 * math.pi * t * 2)
    cx, cy = 760, 620 + 25 * math.sin(2 * math.pi * t)
    stroke(d, ellipse_pts(cx, cy, 300, 175), closed=True)
    # tail rotates around its attach point
    ax, ay = cx - 285, cy
    tail = [(ax, ay), (ax - 200, ay - 150), (ax - 160, ay),
            (ax - 200, ay + 150)]
    stroke(d, rot(tail, ax, ay, 22 * wag), closed=True)
    # fin
    fin = [(cx - 20, cy + 40), (cx - 130, cy + 160), (cx + 60, cy + 130)]
    stroke(d, rot(fin, cx - 20, cy + 40, 12 * wag), closed=True,
           width=LW * 0.9)
    # gill + eye + mouth
    stroke(d, ellipse_pts(cx + 110, cy, 60, 120, start=-60, end=60),
           width=LW * 0.8)
    dot(d, cx + 200, cy - 55, 15)
    stroke(d, ellipse_pts(cx + 300, cy + 30, 28, 22, start=60, end=250),
           width=LW * 0.75)
    # bubbles loop upward
    for k in range(3):
        ph = (t + k / 3) % 1.0
        bx = 1180 + 40 * math.sin(2 * math.pi * (ph + k * 0.3))
        by = 760 - 560 * ph
        br = 18 + 14 * k
        stroke(d, ellipse_pts(bx, by, br, br), closed=True, width=LW * 0.7)


def flower(d, t):
    """A flower grows from the ground and blooms."""
    ground = 1060
    stroke(d, [(300, ground), (1300, ground)])
    for gx in (430, 620, 1050, 1240):
        stroke(d, [(gx, ground), (gx - 18, ground - 55)], width=LW * 0.7)
    grow = ease(min(t / 0.55, 1.0))                # stem 0 → full
    bloom = ease(max(0.0, (t - 0.55) / 0.45))      # petals after that
    top_y = ground - 180 - 560 * grow
    stem = bezier((800, ground), (770 - 60 * grow, (ground + top_y) / 2),
                  (800, top_y))
    stroke(d, stem)
    if grow > 0.55:                                # leaves scale in
        lg = 0.3 + 0.7 * ease(min((grow - 0.55) / 0.35, 1.0))
        ly = ground - 300 * grow
        stroke(d, ellipse_pts(800 - 95 * lg, ly, 95 * lg, 38 * lg,
                              rot_deg=-25), closed=True, width=LW * 0.85)
        stroke(d, ellipse_pts(800 + 95 * lg, ly + 70, 95 * lg, 38 * lg,
                              rot_deg=25), closed=True, width=LW * 0.85)
    if bloom <= 0:                                 # closed bud
        stroke(d, ellipse_pts(800, top_y - 60 * grow, 60 * grow + 20,
                              80 * grow + 24), closed=True)
    else:                                          # petals open around center
        pr = 60 + 130 * bloom
        for i in range(6):
            a = i * 60 + 18 * bloom
            px = 800 + pr * math.cos(math.radians(a))
            py = (top_y - 40) + pr * math.sin(math.radians(a))
            stroke(d, ellipse_pts(px, py, 46 + 46 * bloom, 34 + 30 * bloom,
                                  rot_deg=a), closed=True, width=LW * 0.85)
        stroke(d, ellipse_pts(800, top_y - 40, 55 + 25 * bloom,
                              55 + 25 * bloom), closed=True)


def butterfly(d, t):
    """Butterfly fluttering along a gentle loop."""
    cx = 800 + 260 * math.sin(2 * math.pi * t)
    cy = 560 + 110 * math.sin(4 * math.pi * t)
    flap = abs(math.cos(2 * math.pi * t * 3))      # 3 wingbeats per loop
    wing = max(0.22, flap)
    # wings: big upper + small lower, both sides, squeezing in x
    for side in (-1, 1):
        stroke(d, ellipse_pts(cx + side * 150 * wing, cy - 95,
                              150 * wing, 130, rot_deg=side * 18),
               closed=True)
        stroke(d, ellipse_pts(cx + side * 110 * wing, cy + 95,
                              105 * wing, 95, rot_deg=-side * 12),
               closed=True, width=LW * 0.9)
    # body + antennae
    stroke(d, ellipse_pts(cx, cy, 34, 130), closed=True)
    stroke(d, bezier((cx - 8, cy - 120), (cx - 55, cy - 210),
                     (cx - 95, cy - 235)), width=LW * 0.7)
    stroke(d, bezier((cx + 8, cy - 120), (cx + 55, cy - 210),
                     (cx + 95, cy - 235)), width=LW * 0.7)
    dot(d, cx - 95, cy - 235, 10)
    dot(d, cx + 95, cy - 235, 10)


def car(d, t):
    """Car bouncing along; wheels spin and the road dashes slide."""
    ground = 1010
    stroke(d, [(120, ground), (1480, ground)])
    # sliding road dashes (loop seamlessly)
    period = 260
    off = -t * period
    x = 120 + (off % period)
    while x < 1440:
        stroke(d, [(x, ground + 60), (min(x + 120, 1470), ground + 60)],
               width=LW * 0.8)
        x += period
    bob = 12 * math.sin(2 * math.pi * t * 2)
    by = ground - 210 + bob
    # body silhouette
    body = [(420, by), (420, by - 130), (560, by - 150), (660, by - 280),
            (1010, by - 280), (1120, by - 150), (1240, by - 120),
            (1240, by), ]
    stroke(d, body, closed=True)
    # window split
    stroke(d, [(830, by - 275), (830, by - 155)], width=LW * 0.8)
    stroke(d, [(600, by - 160), (1090, by - 160)], width=LW * 0.8)
    # wheels with spinning spokes (full turn per loop)
    a = 360 * t
    for wx in (600, 1070):
        wy = ground - 95
        stroke(d, ellipse_pts(wx, wy, 95, 95), closed=True)
        for spoke in (a, a + 90):
            p = rot([(wx - 62, wy), (wx + 62, wy)], wx, wy, spoke)
            stroke(d, p, width=LW * 0.8)
    # exhaust puffs behind
    ph = (t * 2) % 1.0
    stroke(d, ellipse_pts(340 - 90 * ph, by - 40 - 60 * ph,
                          34 + 30 * ph, 26 + 22 * ph), closed=True,
           width=LW * 0.7)


def rocket(d, t):
    """Rocket lifting off with a flickering flame."""
    pad = 1070
    stroke(d, [(560, pad), (1040, pad)])
    ry = pad - 60 - 760 * (t ** 1.6)               # accelerates upward
    cx = 800
    # body
    stroke(d, [(cx - 110, ry), (cx - 110, ry - 330), (cx, ry - 500),
               (cx + 110, ry - 330), (cx + 110, ry)], closed=True)
    # fins
    stroke(d, [(cx - 110, ry - 130), (cx - 210, ry + 10), (cx - 110, ry - 10)],
           closed=True, width=LW * 0.9)
    stroke(d, [(cx + 110, ry - 130), (cx + 210, ry + 10), (cx + 110, ry - 10)],
           closed=True, width=LW * 0.9)
    # window
    stroke(d, ellipse_pts(cx, ry - 300, 58, 58), closed=True, width=LW * 0.9)
    # flame flickers frame to frame
    fl = 150 + 90 * (1 if int(t * FRAMES) % 2 == 0 else 0.4) + 160 * t
    stroke(d, [(cx - 70, ry + 6), (cx, ry + fl), (cx + 70, ry + 6)],
           closed=True, width=LW * 0.9)
    stroke(d, [(cx - 28, ry + 6), (cx, ry + fl * 0.55), (cx + 28, ry + 6)],
           closed=True, width=LW * 0.7)
    # smoke puffs hug the pad early in the launch
    if t < 0.45:
        k = t / 0.45
        for sx, r0 in ((640, 55), (960, 55), (520, 40), (1080, 40)):
            stroke(d, ellipse_pts(sx + (sx - 800) * 0.6 * k, pad - 28 - 40 * k,
                                  r0 + 55 * k, (r0 + 55 * k) * 0.7),
                   closed=True, width=LW * 0.7)


def frog(d, t):
    """Frog crouches, leaps, and lands."""
    ground = 1040
    stroke(d, [(200, ground), (1400, ground)])
    # jump envelope: grounded → airborne arc → grounded
    if t < 0.2:
        h, sq = 0.0, 1 - t / 0.2 * 0.0
        squash = 1.25
    elif t < 0.8:
        u = (t - 0.2) / 0.6
        h = 430 * 4 * u * (1 - u)
        squash = 0.85
    else:
        h = 0.0
        squash = 1.25
    cx = 800
    bw, bh = 260 * squash, 190 / squash
    cy = ground - bh - 40 - h
    stroke(d, ellipse_pts(cx, cy, bw, bh), closed=True)
    # eyes on top
    for off in (-110, 110):
        ex, ey = cx + off, cy - bh - 20
        stroke(d, ellipse_pts(ex, ey, 62, 62), closed=True, width=LW * 0.9)
        dot(d, ex, ey + 6, 14)
    # smile
    stroke(d, ellipse_pts(cx, cy - 30, 130, 70, start=20, end=160),
           width=LW * 0.8)
    airborne = h > 30
    if airborne:   # legs stretched back
        stroke(d, bezier((cx - 180, cy + 90), (cx - 340, cy + 190),
                         (cx - 430, cy + 150)))
        stroke(d, bezier((cx + 180, cy + 90), (cx + 300, cy + 230),
                         (cx + 420, cy + 210)))
    else:          # legs folded beside the body
        stroke(d, ellipse_pts(cx - 220, ground - 70, 90, 62), closed=True,
               width=LW * 0.9)
        stroke(d, ellipse_pts(cx + 220, ground - 70, 90, 62), closed=True,
               width=LW * 0.9)


def pinwheel(d, t):
    """Pinwheel spinning on its stick (90° per loop = seamless)."""
    cx, cy = 800, 520
    stroke(d, [(cx, cy + 40), (cx, 1080)])          # stick
    a0 = 90 * t
    for i in range(4):
        a = a0 + i * 90
        blade = [(cx, cy),
                 (cx + 300 * math.cos(math.radians(a)),
                  cy + 300 * math.sin(math.radians(a))),
                 (cx + 260 * math.cos(math.radians(a + 42)),
                  cy + 260 * math.sin(math.radians(a + 42)))]
        stroke(d, blade, closed=True)
    stroke(d, ellipse_pts(cx, cy, 34, 34), closed=True)
    # wind swooshes
    stroke(d, bezier((300, 320), (430, 270), (560, 320)), width=LW * 0.7)
    stroke(d, bezier((1050, 260), (1180, 210), (1310, 260)), width=LW * 0.7)


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
    root = os.path.abspath(OUT_ROOT)
    if os.path.isdir(root):
        shutil.rmtree(root)
    for name, fn in PRESETS:
        folder = os.path.join(root, name)
        os.makedirs(folder)
        for f in range(FRAMES):
            img = new_canvas()
            fn(ImageDraw.Draw(img), f / FRAMES)
            finish(img).save(os.path.join(folder, f"frame_{f:02d}.png"),
                             optimize=True)
        print(f"{name}: {FRAMES} frames")
    print(f"done → {root}")


if __name__ == "__main__":
    main()
