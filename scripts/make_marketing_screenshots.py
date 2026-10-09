#!/usr/bin/env python3
"""아이패드 마케팅 스크린샷: HTML → 헤드리스 Chrome (2064x2752).

사용법: python3 scripts/make_marketing_screenshots.py [언어 ...]   (없으면 전부)

원본   docs/screenshots/raw/<언어>/NN-….png        시뮬레이터(iPad Pro 13") 캡처 2064x2752
제출본 docs/screenshots/marketing/<로케일>/NN-….png  스토어에 그대로 올라간다

팔랑북은 아이패드 전용이다. 바탕 · 글자색 · 도장은 제품 페이지 헤더(make_creative_assets.py)와 같다.
"""
import pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 2064, 2752

STORE = {"ko": "ko"}

# (원본 파일, 배치, 눈썹글, 헤드라인, 보조 한 줄)
SHOTS = {
    "ko": [
        ("01-trace-bunny.png", "hero", "따라 그리기",
         "우리 아이 그림이<br>팔랑팔랑 움직여요", "연한 밑그림 위를 한 장씩 따라 그려요"),
        ("02-trace-rocket.png", "tilt-left", "한 장씩 차근차근",
         "밑그림만 따라가면<br>애니메이션 완성", "토끼, 로켓, 개구리까지 10가지 밑그림"),
        ("03-stamps-fish.png", "tilt-right", "도장 팔레트",
         "하트, 별, 꽃 도장을<br>콕 찍어 꾸며요", "글을 몰라도 그림 버튼만 누르면 돼요"),
        ("04-home.png", "hero", "내 동영상으로도",
         "찍은 영상 위에<br>따라 그려도 돼요", "그린 작품은 홈에 모여 언제든 이어 그려요"),
    ],
}

CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#FFF9F1; position:relative;
  font-family:-apple-system, "SF Pro Rounded", "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(170px); }
.text { position:absolute; left:140px; right:140px; top:200px; text-align:center; }
.eyebrow { font-size:76px; font-weight:800; color:#F28A00; letter-spacing:-0.01em; }
.headline { font-size:150px; font-weight:800; color:#22252B; letter-spacing:-0.03em; line-height:1.16; margin-top:26px; }
.sub { font-size:66px; font-weight:500; color:#7A7570; letter-spacing:-0.01em; margin-top:40px; }
:lang(ko) .headline, :lang(ko) .sub { word-break:keep-all; }
.ipad { position:absolute; background:#202226; border:5px solid #d8d4cc; padding:40px; border-radius:100px;
  box-shadow: 0 60px 160px rgba(120,80,20,.22), 0 0 0 2px #2c2e33 inset; }
.ipad img { width:100%%; display:block; border-radius:60px; }
.stamp { position:absolute; }
"""

HEART = "M50 88 C20 66 4 50 4 30 C4 14 16 4 30 4 C40 4 47 10 50 18 C53 10 60 4 70 4 C84 4 96 14 96 30 C96 50 80 66 50 88 Z"
STAR = "M50 4 L62 38 L98 38 L69 59 L80 94 L50 73 L20 94 L31 59 L2 38 L38 38 Z"


def stamp(kind, x, y, size, color, rot=0, alpha=.85):
    shape = '<circle cx="50" cy="50" r="46"/>' if kind == "circle" else f'<path d="{HEART if kind == "heart" else STAR}"/>'
    return (f'<svg class="stamp" viewBox="0 0 100 100" style="left:{x}px;top:{y}px;width:{size}px;height:{size}px;'
            f'transform:rotate({rot}deg);opacity:{alpha}" fill="{color}">{shape}</svg>')


# 기기 위치: 글 아래에서 시작해 화면 아래로 넘친다(블리드)
PLACE = {
    "hero": dict(left=232, top=1000, width=1600, rot=0),
    "tilt-left": dict(left=300, top=1010, width=1560, rot=-4),
    "tilt-right": dict(left=210, top=1010, width=1560, rot=4),
}
DECOR = {
    "hero": [("heart", 60, 120, 170, "#FF4F79", -14), ("star", 1840, 140, 160, "#FFC21A", 12)],
    "tilt-left": [("star", 70, 150, 160, "#FFC21A", -10), ("circle", 1880, 220, 110, "#2E8CFF", 0, .7)],
    "tilt-right": [("heart", 1840, 130, 170, "#FF4F79", 12), ("circle", 90, 230, 110, "#34C759", 0, .7)],
}


def page(lang, src, layout, eyebrow, headline, sub):
    p = PLACE[layout]
    img = (RAW / lang / src).as_uri()
    deco = "".join(stamp(*d) for d in DECOR[layout])
    return f"""<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{CSS % {"W": W, "H": H}}</style></head><body>
<div class="glow" style="left:300px;top:1300px;width:1500px;height:1500px;background:rgba(255,149,0,.16)"></div>
{deco}
<div class="text"><div class="eyebrow">{eyebrow}</div><div class="headline">{headline}</div><div class="sub">{sub}</div></div>
<div class="ipad" style="left:{p['left']}px;top:{p['top']}px;width:{p['width']}px;transform:rotate({p['rot']}deg)"><img src="{img}"></div>
</body></html>"""


def render(lang):
    out_dir = OUT / STORE.get(lang, lang)
    out_dir.mkdir(parents=True, exist_ok=True)
    for src, layout, eyebrow, headline, sub in SHOTS[lang]:
        html = pathlib.Path(tempfile.gettempdir()) / f"palangbook-mkt-{lang}-{src}.html"
        html.write_text(page(lang, src, layout, eyebrow, headline, sub), encoding="utf-8")
        out = out_dir / src
        for _ in range(3):
            try:
                r = subprocess.run([CHROME, "--headless=new", f"--screenshot={out}", f"--window-size={W},{H}",
                                    "--force-device-scale-factor=1", "--hide-scrollbars", "--disable-gpu",
                                    "--virtual-time-budget=3000", "--allow-file-access-from-files", html.as_uri()],
                                   capture_output=True, timeout=300)
            except subprocess.TimeoutExpired:
                continue
            if r.returncode == 0 and out.exists():
                break
        else:
            raise SystemExit(f"Chrome 이 그리지 못했다: {out}")
        print(f"rendered {out}")


if __name__ == "__main__":
    for lang in sys.argv[1:] or list(SHOTS):
        render(lang)
