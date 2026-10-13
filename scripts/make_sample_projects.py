#!/usr/bin/env python3
"""스크린샷용 예시 작품 5개를 시뮬레이터 앱 폴더에 만든다.

사용법: python3 scripts/make_sample_projects.py <앱 Documents 폴더>
        (xcrun simctl get_app_container <UDID> com.leeo.RotoscopeiPad data 의 Documents)

아이가 밑그림을 따라 그린 것처럼, 밑그림 선(Tools/generate_presets.py 의 도형)에
색을 입히고 손떨림을 더해 MaskStroke 로 저장한다. 언어가 바뀌어도 같은 그림이 나와야
언어별 스크린샷이 같은 장면이 된다 — 그래서 손으로 그리지 않고 여기서 만든다.

앱은 마지막으로 고친 작품(project.json 수정 시각)을 열고 시작한다. 찍을 장면은
그 파일 시각을 바꿔 고른다(scripts/capture_screenshots.sh).
"""
import json, math, os, random, shutil, sys, uuid, importlib.util, pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("presets", ROOT / "Tools" / "generate_presets.py")
P = importlib.util.module_from_spec(spec)
spec.loader.exec_module(P)
W, H, FRAMES = P.W, P.H, P.FRAMES

# 밑그림 선을 그리지 않고 모은다
_lines = []
P.stroke = lambda d, pts, width=P.LW, closed=False: _lines.append((list(pts), closed))
P.dot = lambda d, cx, cy, r: _lines.append((P.ellipse_pts(cx, cy, r * 0.5, r * 0.5, n=10), True))


def guide_lines(fn, f):
    _lines.clear()
    fn(None, f / FRAMES)
    return list(_lines)


def wobble(pts, rnd, amp=7.0, shift=(0, 0)):
    """아이 손떨림: 느린 흔들림 + 살짝 비껴 그리기."""
    ph1, ph2 = rnd.uniform(0, 6.3), rnd.uniform(0, 6.3)
    out = []
    n = max(len(pts) - 1, 1)
    for i, (x, y) in enumerate(pts):
        u = i / n
        out.append((x + shift[0] + amp * math.sin(u * 7 + ph1),
                    y + shift[1] + amp * math.cos(u * 5 + ph2)))
    return out


def norm(pts):
    return [[round(x / W, 5), round(y / H, 5)] for x, y in pts]


def stroke_json(pts, color, width=0.016, closed=False, smooth=True, opacity=1.0):
    return {"id": str(uuid.uuid4()).upper(), "points": norm(pts), "isAdditive": True,
            "closed": closed, "colorHex": color, "width": width,
            "opacity": opacity, "smooth": smooth}


# 도장 (RotoscopeiPad/Models/Stamps.swift 의 unitPoints 와 같은 모양)
def unit(shape):
    if shape == "heart":
        pts = []
        for i in range(36):
            t = 2 * math.pi * i / 36
            x = 16 * math.sin(t) ** 3
            y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
            pts.append((x / 17, -y / 17))
        return pts, True
    if shape == "star":
        return [((1 if k % 2 == 0 else .42) * math.cos(-math.pi / 2 + k * math.pi / 5),
                 (1 if k % 2 == 0 else .42) * math.sin(-math.pi / 2 + k * math.pi / 5)) for k in range(10)], False
    if shape == "circle":
        return [(math.cos(2 * math.pi * i / 24), math.sin(2 * math.pi * i / 24)) for i in range(24)], True
    if shape == "flower":
        pts = []
        for i in range(60):
            t = 2 * math.pi * i / 60
            r = 0.4 + 0.6 * abs(math.cos(2.5 * t))
            pts.append((math.cos(t) * r, math.sin(t) * r))
        return pts, True
    raise ValueError(shape)


def stamp(shape, cx, cy, size, color):
    """cx, cy 는 캔버스 픽셀. size 는 캔버스 폭에 대한 비율(앱의 S/M/L = .09/.16/.28)."""
    pts, smooth = unit(shape)
    half = size / 2 * W
    return stroke_json([(cx + x * half, cy + y * half) for x, y in pts], color,
                       width=0.004, closed=True, smooth=smooth)


# 작품: 밑그림, 펼쳐 둘 장, 선마다 색(밑그림 선 순서대로), 도장
WORKS = [
    dict(name="bunny", preset="02_bunny", frame=5,
         colors=["34C759", "FF9500", "FF9500", "FF9500", "FF2D55", "FF2D55", "000000", "FF2D55",
                 "FF2D55", "FF2D55", "FF2D55"],
         stamps=[("heart", 260, 230, .09, "FF2D55"), ("star", 1350, 220, .09, "FFCC00"),
                 ("flower", 1300, 820, .07, "AF52DE")]),
    dict(name="rocket", preset="08_rocket", frame=6,
         colors=["007AFF", "FF3B30", "007AFF", "FF9500", "FF9500", "FFCC00", "FF3B30",
                 "FFCC00", "FF2D55", "FF9500", "AF52DE"],
         stamps=[("star", 300, 230, .07, "FFCC00"), ("star", 1310, 350, .05, "FFCC00"),
                 ("circle", 380, 760, .05, "AF52DE")]),
    dict(name="fish", preset="04_fish", frame=4,
         colors=["007AFF", "FF9500", "FF3B30", "000000", "00C7BE", "00C7BE", "007AFF", "007AFF", "00C7BE"],
         stamps=[("heart", 1390, 230, .07, "FF2D55")]),
    dict(name="bird", preset="03_bird", frame=3,
         colors=["AF52DE", "FF9500", "FF9500", "000000", "FFCC00", "000000", "AF52DE", "AF52DE"],
         stamps=[("flower", 230, 900, .05, "FF2D55")]),
    dict(name="frog", preset="09_frog", frame=2,
         colors=["34C759", "34C759", "34C759", "000000", "000000", "000000", "FF3B30", "007AFF", "007AFF"],
         stamps=[]),
]
FN = dict(P.PRESETS)


def build(work, docs):
    rnd = random.Random(work["name"])
    fn = FN[work["preset"]]
    masks = {}
    for f in range(work["frame"] + 1):
        strokes = []
        for i, (pts, closed) in enumerate(guide_lines(fn, f)):
            color = work["colors"][i % len(work["colors"])]
            if closed:
                pts = pts + pts[:2]
            small = len(pts) < 14 and max(abs(pts[0][0] - p[0]) + abs(pts[0][1] - p[1]) for p in pts) < 40
            strokes.append(stroke_json(wobble(pts, rnd, amp=0 if small else 7,
                                              shift=(rnd.uniform(-10, 10), rnd.uniform(-10, 10))),
                                       color, width=0.016 if not small else 0.02))
        if f == work["frame"]:
            strokes += [stamp(*s) for s in work["stamps"]]
        masks[str(f)] = {"strokes": strokes}

    pid = str(uuid.uuid5(uuid.NAMESPACE_URL, "palangbook-sample-" + work["name"])).upper()
    folder = docs / "Projects" / pid
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    data = {"frameStep": 1, "currentFrame": work["frame"], "masks": masks, "isBlank": False,
            "blankPageCount": FRAMES, "presetId": work["preset"], "hideBackground": False}
    (folder / "project.json").write_text(json.dumps(data))
    thumb(work, masks[str(work["frame"])]["strokes"], folder / "thumb.png")
    return folder


def thumb(work, strokes, out):
    """앱의 writeThumbnail 과 같게: 하얀 종이 + 밑그림 60% + 그림. 폭 480."""
    tw, th = 480, 360
    ss = 3
    img = Image.new("RGBA", (tw * ss, th * ss), "white")
    guide = Image.open(ROOT / "RotoscopeiPad" / "Presets" / work["preset"] /
                       f"frame_{work['frame']:02d}.png").convert("RGBA").resize((tw * ss, th * ss))
    guide.putalpha(guide.getchannel("A").point(lambda a: int(a * .6)))
    img.alpha_composite(guide)
    d = ImageDraw.Draw(img)
    for s in strokes:
        pts = [(x * tw * ss, y * th * ss) for x, y in s["points"]]
        rgb = "#" + s["colorHex"]
        if s["width"] < 0.01:            # 도장: 채운 모양
            d.polygon(pts, fill=rgb)
        else:
            w = max(1, int(s["width"] * min(tw, th) * ss))
            d.line(pts, fill=rgb, width=w, joint="curve")
            for x, y in (pts[0], pts[-1]):
                d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=rgb)
    img.resize((tw, th), Image.LANCZOS).convert("RGB").save(out)


if __name__ == "__main__":
    docs = pathlib.Path(sys.argv[1])
    (docs / "Projects").mkdir(parents=True, exist_ok=True)
    for w in WORKS:
        print(w["name"], build(w, docs).name)
