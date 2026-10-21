#!/usr/bin/env python3
"""App Store 크리에이티브 자산(제품 페이지 헤더 · 검색 결과) 생성: HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_creative_assets.py [언어 ...]     (없으면 전부)

자리
  docs/screenshots/creative/<스토어 로케일>/header.png   3840x1646  제품 페이지 맨 위
  docs/screenshots/creative/<스토어 로케일>/search.png   3840x2560  검색 결과 (없으면 스크린샷이 대신 보인다)

⚠️ 안전 영역 밖은 기기에 따라 잘린다. 글은 **반드시** 안전 영역 안에 둔다(배경 · 기기 그림은 넘쳐도 된다).
   수치는 Apple 공식 PSD 템플릿에서 잰 값이다(https://developer.apple.com/app-store/asset-best-practices/).
   아이폰에서 헤더는 가운데만 남고, 검색 결과는 약 385pt 폭으로 줄어 보인다. 그래서 글이 크다.

⚠️ 가격 · 할인 · 주소(URL) · 수상 · 다른 플랫폼 이름은 넣지 않는다(Apple 가이드).
"""
import shutil, subprocess, sys, pathlib, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"   # 스크린샷 원본을 같이 쓴다 (capture_screenshots.sh)
OUT = ROOT / "docs" / "screenshots" / "creative"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


# (가로, 세로, 안전 영역 left, top, right, bottom)
SPEC = {
    "header": (3840, 1646, (1097, 493, 2743, 1154)),
    "search": (3840, 2560, (836, 765, 3004, 1795)),
}

# 팔랑북은 아이패드 전용 앱이다. 기기 그림도 아이패드 모양(3:4, 고른 테두리)으로 그린다.

# 검색 결과 — 스크린샷 1장(따라 그리기 화면: 연한 밑그림 위에 아이가 그린 토끼)과 같은 이야기.
# 눈썹글은 검색어(키워드: 그림판, 아이장난감)다.
SEARCH = {
    "ko": ("아이 그림판", "따라 그리면<br>애니메이션 완성", "선을 따라 한 장씩 그리면 그림이 움직여요"),
    "en-US": ("Kids drawing app", "Trace it,<br>watch it move", "Trace page by page and the drawing moves"),
    "ja": ("お絵かき", "なぞって描けば<br>アニメの完成", "1枚ずつなぞると絵が動きだす"),
    "zh-Hans": ("儿童画画", "照着描<br>动画就完成", "一页一页描，画就动起来"),
    "zh-Hant": ("兒童畫畫", "跟著描<br>動畫就完成", "一頁一頁描，圖畫就動起來"),
    "es-MX": ("Dibujar para niños", "Calca y mira<br>cómo se mueve", "Página por página, el dibujo cobra vida"),
    "de-DE": ("Malen für Kinder", "Nachzeichnen<br>und bewegen", "Seite für Seite, und das Bild bewegt sich"),
    "fr-FR": ("Dessin pour enfants", "On décalque,<br>et ça bouge", "Page après page, le dessin s'anime"),
    "pt-BR": ("Desenhar para crianças", "Contorne e<br>veja se mexer", "Página por página, o desenho ganha vida"),
    "it": ("Disegno per bambini", "Ricalca e<br>guardalo muoversi", "Pagina dopo pagina, il disegno si anima"),
    "en-GB": ("Kids drawing app", "Trace it,<br>watch it move", "Trace page by page and the drawing moves"),
    "ru": ("Детская рисовалка", "Обводи —<br>и рисунок оживёт", "Страница за страницей — и рисунок движется"),
    "th": ("แอปวาดรูปเด็ก", "วาดตามเส้น<br>ภาพก็ขยับ", "วาดตามเส้นทีละหน้า แล้วภาพวาดจะขยับ"),
    "vi": ("Ứng dụng vẽ cho bé", "Vẽ theo nét,<br>xem tranh chuyển động", "Vẽ từng trang và tranh sẽ chuyển động"),
    "cs": ("Kreslení pro děti", "Obkresli a<br>sleduj, jak se hýbe", "Stránku po stránce a kresba ožije"),
    "da": ("Tegneapp til børn", "Tegn efter og<br>se det bevæge sig", "Side for side, og tegningen bevæger sig"),
    "el": ("Ζωγραφική για παιδιά", "Ζωγράφισε πάνω,<br>δες το να κινείται", "Σελίδα σελίδα και το σχέδιο κινείται"),
    "fi": ("Piirtoapp lapsille", "Jäljennä ja<br>katso liikkuvan", "Sivu kerrallaan, ja piirros liikkuu"),
    "id": ("Gambar untuk anak", "Jiplak,<br>lalu lihat bergerak", "Halaman demi halaman, gambar pun bergerak"),
    "nb": ("Tegneapp for barn", "Tegn etter og<br>se det bevege seg", "Side for side, og tegningen beveger seg"),
    "nl": ("Tekenapp voor kinderen", "Overtrekken en<br>laten bewegen", "Pagina voor pagina en de tekening beweegt"),
    "pl": ("Rysowanie dla dzieci", "Obrysuj i zobacz,<br>jak się rusza", "Strona po stronie, a rysunek się rusza"),
    "sv": ("Ritapp för barn", "Rita av och<br>se det röra sig", "Sida för sida, och teckningen rör sig"),
    "tr": ("Çocuk çizim uygulaması", "Üstünden çiz,<br>hareket etsin", "Sayfa sayfa, çizim hareket eder"),
}

# 헤더 — 한 가지 약속: 아이가 그린 그림이 움직인다(부제: 내 아이가 그려주는 애니메이션).
HEADER = {
    "ko": ("아이 그림 애니메이션", "우리 아이 그림이<br>팔랑팔랑 움직여요"),
    "en-US": ("Kids' drawings, animated", "Your child's drawings<br>come to life"),
    "ja": ("子どものお絵かきアニメ", "子どもの絵が<br>パラパラ動きだす"),
    "zh-Hans": ("儿童画画动画", "孩子的画<br>动起来啦"),
    "zh-Hant": ("小朋友畫畫動畫", "孩子的畫<br>動起來囉"),
    "es-MX": ("Dibujos animados para niños", "Los dibujos de tu hijo<br>cobran vida"),
    "de-DE": ("Malen für Kinder", "Kinderbilder<br>werden lebendig"),
    "fr-FR": ("Dessin animé pour enfants", "Les dessins de votre<br>enfant prennent vie"),
    "pt-BR": ("Desenho animado infantil", "Os desenhos do seu filho<br>ganham vida"),
    "it": ("Disegni animati per bambini", "I disegni dei bambini<br>prendono vita"),
    "en-GB": ("Kids' drawings, animated", "Your child's drawings<br>come to life"),
    "ru": ("Детские рисунки оживают", "Рисунки вашего ребёнка<br>оживают"),
    "th": ("ภาพวาดเด็กๆ ขยับได้", "ภาพวาดของลูก<br>ขยับได้"),
    "vi": ("Tranh của bé, hoạt hình", "Tranh của bé<br>biết chuyển động"),
    "cs": ("Dětské kresby v animaci", "Kresby vašeho dítěte<br>ožívají"),
    "da": ("Børns tegninger i animation", "Dit barns tegninger<br>vokser til live"),
    "el": ("Παιδικά σχέδια που κινούνται", "Τα σχέδια του παιδιού σας<br>ζωντανεύουν"),
    "fi": ("Lasten piirrokset animaationa", "Lapsesi piirrokset<br>heräävät eloon"),
    "id": ("Gambar anak jadi animasi", "Gambar si kecil<br>jadi bergerak"),
    "nb": ("Barnas tegninger i animasjon", "Barnets tegninger<br>våkner til liv"),
    "nl": ("Kindertekeningen in animatie", "De tekeningen van je kind<br>komen tot leven"),
    "pl": ("Dziecięce rysunki w ruchu", "Rysunki Twojego dziecka<br>ożywają"),
    "sv": ("Barnens teckningar i rörelse", "Barnets teckningar<br>väcks till liv"),
    "tr": ("Çocuk çizimleri animasyonda", "Çocuğunuzun çizimleri<br>canlanıyor"),
}

# 바탕 · 글자색은 앱 화면과 같다: 하얀 종이, 따라 그리기 카드의 주황 점선, 도장 팔레트 색.
BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#FFF9F1; position:relative;
  font-family:-apple-system, "SF Pro Rounded", "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(170px); pointer-events:none; }
.text { position:absolute; display:flex; flex-direction:column; justify-content:center; }
.eyebrow { font-weight:800; color:#F28A00; letter-spacing:-0.01em; line-height:1.15; }
.headline { font-weight:800; color:#22252B; letter-spacing:-0.03em; line-height:1.14; text-wrap:balance; }
.sub { font-weight:500; color:#7A7570; letter-spacing:-0.01em; line-height:1.35; text-wrap:balance; }
:lang(ko) .headline, :lang(ko) .sub, :lang(ko) .eyebrow { word-break:keep-all; }
.ipad { position:absolute; background:#202226; border:5px solid #d8d4cc; padding:46px; border-radius:110px;
  box-shadow: 0 60px 160px rgba(120,80,20,.20), 0 0 0 2px #2c2e33 inset; }
.ipad img { width:100%%; display:block; border-radius:66px; }
/* 도장 — 앱 그리기 화면 양옆의 도장(하트 · 별 · 동그라미). 안전 영역 밖에만 둔다. */
.stamp { position:absolute; }
"""

# 글이 상자를 넘지 않을 때까지 줄인다. 잘리는 글은 없다 - 끝까지 안 맞으면 표시하고 멈춘다.
FIT_JS = """
<script>
// 문구에 적은 줄(<br>)보다 더 쪼개지면 "Rispondi / con un / tocco" 처럼 읽기가 끊긴다.
// 적은 줄 수를 지킬 때까지 줄인다.
function lines(el) {
  return Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
}
function fit(box, el, max, min) {
  const want = el.querySelectorAll('br').length + 1;
  let size = max;
  el.style.fontSize = size + 'px';
  while (size > min && (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 ||
         lines(el) > want)) {
    size -= 4; el.style.fontSize = size + 'px';
  }
  if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 || lines(el) > want)
    document.body.dataset.overflow = '1';
}
document.fonts.ready.then(() => {
  const box = document.querySelector('.text');
  const h = document.querySelector('.headline');
  fit(box, h, +h.dataset.max, +h.dataset.min);
  document.body.dataset.done = '1';
});
</script>
"""


def ipad(img, left, top, width, rotate=0):
    return (f'<div class="ipad" style="left:{left}px;top:{top}px;width:{width}px;'
            f'transform:rotate({rotate}deg)"><img src="{img}"></div>')


HEART = "M50 88 C20 66 4 50 4 30 C4 14 16 4 30 4 C40 4 47 10 50 18 C53 10 60 4 70 4 C84 4 96 14 96 30 C96 50 80 66 50 88 Z"
STAR = "M50 4 L62 38 L98 38 L69 59 L80 94 L50 73 L20 94 L31 59 L2 38 L38 38 Z"


def stamp(kind, x, y, size, color, rot=0, alpha=.85):
    if kind == "circle":
        shape = '<circle cx="50" cy="50" r="46"/>'
    else:
        shape = f'<path d="{HEART if kind == "heart" else STAR}"/>'
    return (f'<svg class="stamp" viewBox="0 0 100 100" style="left:{x}px;top:{y}px;width:{size}px;height:{size}px;'
            f'transform:rotate({rot}deg);opacity:{alpha}" fill="{color}">{shape}</svg>')


def search_html(lang):
    W, H, (l, t, r, b) = SPEC["search"]
    eyebrow, headline, sub = SEARCH[lang]
    sw, sh = r - l, b - t
    col = int(sw * 0.54)
    pad_w = 1500
    pad_left = l + col + int(sw * 0.05)
    img = (RAW / lang / "01-trace-bunny.png").as_uri()
    stamps = "".join([
        stamp("heart", 180, 210, 300, "#FF4F79", -12),
        stamp("star", 560, 2000, 260, "#FFC21A", 10),
        stamp("circle", 120, 1650, 150, "#2E8CFF", 0, .7),
    ])
    return f"""
<div class="glow" style="left:{pad_left - 200}px;top:500px;width:1800px;height:1800px;background:rgba(255,149,0,.16)"></div>
<div class="glow" style="left:{l - 700}px;top:{t - 500}px;width:1400px;height:1000px;background:rgba(255,79,121,.08)"></div>
{stamps}
{ipad(img, pad_left, t - 420, pad_w, 0)}
<div class="text" style="left:{l}px;top:{t}px;width:{col}px;height:{sh}px">
  <div class="eyebrow" style="font-size:96px">{eyebrow}</div>
  <div class="headline" data-max="230" data-min="130" style="margin-top:36px">{headline}</div>
  <div class="sub" style="font-size:80px;margin-top:52px">{sub}</div>
</div>"""


def header_html(lang):
    W, H, (l, t, r, b) = SPEC["header"]
    eyebrow, headline = HEADER[lang]
    sw, sh = r - l, b - t
    left_img = (RAW / lang / "04-home.png").as_uri()
    right_img = (RAW / lang / "01-trace-bunny.png").as_uri()
    stamps = "".join([
        stamp("heart", 40, 90, 230, "#FF4F79", -14),
        stamp("star", 980, 1300, 200, "#FFC21A", 12),
        stamp("circle", 3560, 120, 150, "#2E8CFF", 0, .7),
        stamp("heart", 2790, 1320, 190, "#B05CF0", 10, .75),
        stamp("star", 3620, 1180, 230, "#34C759", -8, .8),
    ])
    return f"""
<div class="glow" style="left:{l - 200}px;top:{t - 400}px;width:{sw + 400}px;height:{sh + 800}px;background:rgba(255,149,0,.13)"></div>
{stamps}
{ipad(left_img, 120, 300, 900, -7)}
{ipad(right_img, 2830, 300, 900, 7)}
<div class="text" style="left:{l}px;top:{t}px;width:{sw}px;height:{sh}px;align-items:center;text-align:center">
  <div class="eyebrow" style="font-size:76px">{eyebrow}</div>
  <div class="headline" data-max="200" data-min="110" style="margin-top:22px">{headline}</div>
</div>"""


def html_lang(lang):
    return {"zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant"}.get(lang, lang)


def render(lang, kind):
    W, H, _ = SPEC[kind]
    body = search_html(lang) if kind == "search" else header_html(lang)
    page = (f'<!doctype html><html lang="{html_lang(lang)}"><head><meta charset="utf-8"><style>'
            f'{BASE_CSS % {"W": W, "H": H}}</style></head><body>{body}{FIT_JS}</body></html>')
    html_path = pathlib.Path(tempfile.gettempdir()) / f"palangbook-creative-{lang}-{kind}.html"
    html_path.write_text(page, encoding="utf-8")
    # 글이 끝까지 안 맞으면 그림을 만들지 않는다(잘린 글이 스토어에 올라가는 것보다 낫다).
    dom = subprocess.run([CHROME, "--headless=new", "--dump-dom", f"--window-size={W},{H}",
                          "--force-device-scale-factor=1", "--disable-gpu", "--virtual-time-budget=3000",
                          html_path.as_uri()], capture_output=True, text=True, timeout=300).stdout
    if 'data-done="1"' not in dom:
        raise SystemExit(f"글 맞추기가 끝나지 않았다: {lang} {kind}")
    if 'data-overflow="1"' in dom:
        raise SystemExit(f"글이 안전 영역을 넘는다: {lang} {kind} - 문구를 줄일 것")
    out_dir = OUT / lang
    out_dir.mkdir(parents=True, exist_ok=True)
    out_png = out_dir / f"{kind}.png"
    # ⚠️ Chrome 은 가끔 아무것도 안 그리고 끝나거나 멈춘다. 세 번까지 한다.
    for _ in range(3):
        try:
            r = subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                                f"--window-size={W},{H}", "--force-device-scale-factor=1",
                                "--hide-scrollbars", "--disable-gpu", "--virtual-time-budget=3000",
                                "--allow-file-access-from-files", html_path.as_uri()],
                               capture_output=True, timeout=300)
        except subprocess.TimeoutExpired:
            continue
        if r.returncode == 0:
            break
    else:
        raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
    print(f"rendered {out_png}")

if __name__ == "__main__":
    langs = sys.argv[1:] or list(SEARCH)
    for lang in langs:
        if lang not in SEARCH:
            raise SystemExit(f"모르는 언어: {lang} (아는 것: {', '.join(SEARCH)})")
        for kind in ("header", "search"):
            render(lang, kind)
