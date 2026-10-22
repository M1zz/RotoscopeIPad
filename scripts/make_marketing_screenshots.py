#!/usr/bin/env python3
"""아이패드 마케팅 스크린샷: HTML → 헤드리스 Chrome (2064x2752).

사용법: python3 scripts/make_marketing_screenshots.py [언어 ...]   (없으면 전부)

원본   docs/screenshots/raw/<로케일>/NN-….png       시뮬레이터(iPad Pro 13") 캡처 2064x2752
       (scripts/capture_screenshots.sh 가 언어마다 찍는다)
제출본 docs/screenshots/marketing/<로케일>/NN-….png  스토어에 그대로 올라간다

팔랑북은 아이패드 전용이다. 바탕 · 글자색 · 도장은 제품 페이지 헤더(make_creative_assets.py)와 같다.
"""
import pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# 따로 쓰는 프로필 — 켜 둔 Chrome 이나 다른 headless 와 프로필을 나눠 쓰면 멈추거나 빈 그림이 나온다.
PROFILE = tempfile.mkdtemp(prefix="palangbook-chrome-")
W, H = 2064, 2752

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

SHOTS["en-US"] = [
    ("01-trace-bunny.png", "hero", "Trace and animate",
     "Your child's drawings<br>come to life", "Trace soft outlines one page at a time"),
    ("02-trace-rocket.png", "tilt-left", "Page by page",
     "Follow the lines,<br>make a cartoon", "Bunny, rocket, frog and more: 10 sets"),
    ("03-stamps-fish.png", "tilt-right", "Stamp palette",
     "Tap on hearts,<br>stars and flowers", "No reading needed, just tap the pictures"),
    ("04-home.png", "hero", "Your own videos too",
     "Trace over videos<br>you filmed", "Every artwork waits on the home screen"),
]
SHOTS["ja"] = [
    ("01-trace-bunny.png", "hero", "なぞり描き",
     "子どもの絵が<br>パラパラ動きだす", "うすい下絵を1枚ずつなぞるだけ"),
    ("02-trace-rocket.png", "tilt-left", "1枚ずつ、ゆっくり",
     "線をなぞれば<br>アニメの完成", "うさぎ、ロケット、カエルなど10種類"),
    ("03-stamps-fish.png", "tilt-right", "スタンプ",
     "ハートや星を<br>ポンと押して飾ろう", "字が読めなくても絵のボタンでOK"),
    ("04-home.png", "hero", "自分の動画でも",
     "撮った動画の上に<br>なぞって描ける", "作品はホームに並んで、いつでも続きから"),
]
SHOTS["zh-Hans"] = [
    ("01-trace-bunny.png", "hero", "描画",
     "孩子的画<br>动起来啦", "跟着浅浅的底稿，一页一页描"),
    ("02-trace-rocket.png", "tilt-left", "一页一页来",
     "照着线条描<br>动画就完成", "小兔、火箭、青蛙等 10 套底稿"),
    ("03-stamps-fish.png", "tilt-right", "印章",
     "爱心、星星、花朵<br>一按就印上", "不识字也没关系，点图标就行"),
    ("04-home.png", "hero", "也能用自己的视频",
     "在拍好的视频上<br>描着画", "作品都在首页，随时接着画"),
]
SHOTS["zh-Hant"] = [
    ("01-trace-bunny.png", "hero", "描畫",
     "孩子的畫<br>動起來囉", "跟著淡淡的底圖，一頁一頁描"),
    ("02-trace-rocket.png", "tilt-left", "一頁一頁來",
     "跟著線條描<br>動畫就完成", "小兔子、火箭、青蛙等 10 套底圖"),
    ("03-stamps-fish.png", "tilt-right", "印章",
     "愛心、星星、花朵<br>一按就蓋上", "不識字也沒關係，點圖示就好"),
    ("04-home.png", "hero", "也能用自己的影片",
     "在拍好的影片上<br>描著畫", "作品都在首頁，隨時接著畫"),
]
SHOTS["es-MX"] = [
    ("01-trace-bunny.png", "hero", "Calca y anima",
     "Los dibujos de tu hijo<br>cobran vida", "Calca contornos suaves, página por página"),
    ("02-trace-rocket.png", "tilt-left", "Página por página",
     "Sigue las líneas<br>y crea una caricatura", "Conejo, cohete, rana y más: 10 sets"),
    ("03-stamps-fish.png", "tilt-right", "Sellos",
     "Decora con corazones,<br>estrellas y flores", "Sin leer: solo toca los dibujos"),
    ("04-home.png", "hero", "También con tus videos",
     "Calca sobre<br>tus propios videos", "Todas sus obras esperan en el inicio"),
]
SHOTS["de-DE"] = [
    ("01-trace-bunny.png", "hero", "Nachzeichnen",
     "Kinderbilder<br>werden lebendig", "Zarte Vorlagen Seite für Seite nachmalen"),
    ("02-trace-rocket.png", "tilt-left", "Seite für Seite",
     "Linien folgen,<br>Trickfilm fertig", "Hase, Rakete, Frosch und mehr: 10 Sets"),
    ("03-stamps-fish.png", "tilt-right", "Stempel",
     "Herzen, Sterne<br>und Blumen stempeln", "Ohne Lesen: einfach auf Bilder tippen"),
    ("04-home.png", "hero", "Auch mit eigenen Videos",
     "Über eigene<br>Videos malen", "Alle Werke warten auf dem Startbildschirm"),
]
SHOTS["fr-FR"] = [
    ("01-trace-bunny.png", "hero", "Décalquer",
     "Les dessins de votre<br>enfant prennent vie", "On repasse des contours doux, page par page"),
    ("02-trace-rocket.png", "tilt-left", "Page après page",
     "On suit les traits,<br>c'est un dessin animé", "Lapin, fusée, grenouille… 10 séries"),
    ("03-stamps-fish.png", "tilt-right", "Tampons",
     "Des cœurs, des étoiles,<br>des fleurs à tamponner", "Pas besoin de lire : on touche les images"),
    ("04-home.png", "hero", "Avec vos vidéos aussi",
     "Dessiner sur<br>vos propres vidéos", "Toutes les œuvres attendent sur l'accueil"),
]
SHOTS["pt-BR"] = [
    ("01-trace-bunny.png", "hero", "Contorne e anime",
     "Os desenhos do seu filho<br>ganham vida", "Contorne traços suaves, página por página"),
    ("02-trace-rocket.png", "tilt-left", "Página por página",
     "Siga as linhas<br>e vira desenho animado", "Coelho, foguete, sapo e mais: 10 conjuntos"),
    ("03-stamps-fish.png", "tilt-right", "Carimbos",
     "Carimbe corações,<br>estrelas e flores", "Não precisa ler: é só tocar nas figuras"),
    ("04-home.png", "hero", "Com seus vídeos também",
     "Desenhe sobre<br>seus próprios vídeos", "Todas as obras ficam na tela inicial"),
]
SHOTS["it"] = [
    ("01-trace-bunny.png", "hero", "Ricalca e anima",
     "I disegni dei bambini<br>prendono vita", "Ricalca contorni leggeri, pagina dopo pagina"),
    ("02-trace-rocket.png", "tilt-left", "Pagina dopo pagina",
     "Segui le linee,<br>ecco un cartone animato", "Coniglio, razzo, rana e altri: 10 set"),
    ("03-stamps-fish.png", "tilt-right", "Timbri",
     "Cuori, stelle e fiori<br>da timbrare", "Non serve leggere: basta toccare le figure"),
    ("04-home.png", "hero", "Anche con i tuoi video",
     "Disegna sopra<br>i tuoi video", "Tutte le opere restano nella schermata iniziale"),
]
SHOTS["en-GB"] = [
    ("01-trace-bunny.png", "hero", "Trace and animate",
     "Your child's drawings<br>come to life", "Trace soft outlines one page at a time"),
    ("02-trace-rocket.png", "tilt-left", "Page by page",
     "Follow the lines,<br>make a cartoon", "Bunny, rocket, frog and more: 10 sets"),
    ("03-stamps-fish.png", "tilt-right", "Stamp palette",
     "Tap on hearts,<br>stars and flowers", "No reading needed, just tap the pictures"),
    ("04-home.png", "hero", "Your own videos too",
     "Trace over videos<br>you filmed", "Every artwork waits on the home screen"),
]
SHOTS["ru"] = [
    ("01-trace-bunny.png", "hero", "Обводи и оживляй",
     "Рисунки ребёнка<br>оживают", "Обводите бледные контуры страница за страницей"),
    ("02-trace-rocket.png", "tilt-left", "Страница за страницей",
     "Обведи линии —<br>получится мультфильм", "Зайчик, ракета, лягушка и другие: 10 наборов"),
    ("03-stamps-fish.png", "tilt-right", "Палитра штампов",
     "Сердца, звёзды и цветы<br>одним касанием", "Читать не нужно — просто нажимайте на картинки"),
    ("04-home.png", "hero", "И с вашими видео",
     "Рисуйте поверх<br>снятых видео", "Все работы ждут на главном экране"),
]
SHOTS["th"] = [
    ("01-trace-bunny.png", "hero", "วาดตามเส้นแล้วขยับ",
     "ภาพวาดของลูก<br>ขยับได้", "วาดตามเส้นจางๆ ทีละหน้า"),
    ("02-trace-rocket.png", "tilt-left", "ทีละหน้า",
     "วาดตามเส้น<br>ได้การ์ตูนเรื่องเล็ก", "กระต่าย จรวด กบ และอีกมาก: 10 ชุด"),
    ("03-stamps-fish.png", "tilt-right", "จานตราประทับ",
     "ประทับหัวใจ ดาว<br>และดอกไม้", "ไม่ต้องอ่านออกก็ใช้ได้ แค่แตะรูปภาพ"),
    ("04-home.png", "hero", "วิดีโอของคุณเองก็ได้",
     "วาดทับวิดีโอ<br>ที่ถ่ายเอง", "ผลงานทุกชิ้นรออยู่ที่หน้าหลัก"),
]
SHOTS["vi"] = [
    ("01-trace-bunny.png", "hero", "Vẽ theo và chuyển động",
     "Tranh của bé<br>biết chuyển động", "Vẽ theo nét mờ từng trang một"),
    ("02-trace-rocket.png", "tilt-left", "Từng trang một",
     "Vẽ theo nét,<br>thành phim hoạt hình", "Thỏ, tên lửa, ếch và hơn nữa: 10 bộ"),
    ("03-stamps-fish.png", "tilt-right", "Bảng con dấu",
     "Đóng dấu trái tim,<br>ngôi sao và bông hoa", "Không cần biết đọc, chỉ cần chạm vào hình"),
    ("04-home.png", "hero", "Cả video của riêng bạn",
     "Vẽ lên những video<br>bạn tự quay", "Mọi tác phẩm chờ sẵn ở màn hình chính"),
]
SHOTS["cs"] = [
    ("01-trace-bunny.png", "hero", "Obkresli a rozpohybuj",
     "Kresby vašeho dítěte<br>ožívají", "Obkreslujte světlé obrysy stránku po stránce"),
    ("02-trace-rocket.png", "tilt-left", "Stránku po stránce",
     "Sleduj čáry,<br>vznikne kreslený film", "Zajíček, raketa, žába a další: 10 sad"),
    ("03-stamps-fish.png", "tilt-right", "Paleta razítek",
     "Srdce, hvězdy a květy<br>jedním klepnutím", "Číst není třeba, stačí klepat na obrázky"),
    ("04-home.png", "hero", "I s vlastními videi",
     "Kreslete přes videa,<br>která jste natočili", "Všechna díla čekají na hlavní obrazovce"),
]
SHOTS["da"] = [
    ("01-trace-bunny.png", "hero", "Tegn efter og animér",
     "Dit barns tegninger<br>vokser til live", "Tegn efter lyse streger side for side"),
    ("02-trace-rocket.png", "tilt-left", "Side for side",
     "Følg stregerne,<br>lav en tegnefilm", "Kanin, raket, frø og mere: 10 sæt"),
    ("03-stamps-fish.png", "tilt-right", "Stempelpalet",
     "Tryk hjerter, stjerner<br>og blomster på", "Ingen læsning nødvendig, bare tryk på billederne"),
    ("04-home.png", "hero", "Også dine egne videoer",
     "Tegn oven på videoer,<br>du selv har optaget", "Alle værker venter på hjemmeskærmen"),
]
SHOTS["el"] = [
    ("01-trace-bunny.png", "hero", "Ζωγράφισε και κίνησε",
     "Τα σχέδια του παιδιού σας<br>ζωντανεύουν", "Ζωγράφισε πάνω σε αχνά περιγράμματα σελίδα σελίδα"),
    ("02-trace-rocket.png", "tilt-left", "Σελίδα σελίδα",
     "Ακολούθησε τις γραμμές,<br>φτιάξε κινούμενο σχέδιο", "Λαγουδάκι, πύραυλος, βάτραχος και άλλα: 10 σετ"),
    ("03-stamps-fish.png", "tilt-right", "Παλέτα σφραγίδων",
     "Σφράγισε καρδιές,<br>αστέρια και λουλούδια", "Δεν χρειάζεται ανάγνωση, πατάς απλώς τις εικόνες"),
    ("04-home.png", "hero", "Και με δικά σου βίντεο",
     "Ζωγράφισε πάνω στα βίντεο<br>που τράβηξες", "Όλα τα έργα περιμένουν στην αρχική οθόνη"),
]
SHOTS["fi"] = [
    ("01-trace-bunny.png", "hero", "Jäljennä ja animoi",
     "Lapsesi piirrokset<br>heräävät eloon", "Jäljennä vaaleita ääriviivoja sivu kerrallaan"),
    ("02-trace-rocket.png", "tilt-left", "Sivu kerrallaan",
     "Seuraa viivoja,<br>tee piirretty", "Pupu, raketti, sammakko ja muita: 10 sarjaa"),
    ("03-stamps-fish.png", "tilt-right", "Leimapaletti",
     "Leimaa sydämiä,<br>tähtiä ja kukkia", "Lukutaitoa ei tarvita, napauta vain kuvia"),
    ("04-home.png", "hero", "Myös omilla videoilla",
     "Piirrä omien<br>videoidesi päälle", "Kaikki teokset odottavat aloitusnäytössä"),
]
SHOTS["id"] = [
    ("01-trace-bunny.png", "hero", "Jiplak dan animasikan",
     "Gambar si kecil<br>jadi bergerak", "Jiplak garis tipis halaman demi halaman"),
    ("02-trace-rocket.png", "tilt-left", "Halaman demi halaman",
     "Ikuti garisnya,<br>jadi kartun", "Kelinci, roket, katak, dan lainnya: 10 set"),
    ("03-stamps-fish.png", "tilt-right", "Palet stempel",
     "Cap hati, bintang,<br>dan bunga", "Tak perlu bisa membaca, cukup ketuk gambarnya"),
    ("04-home.png", "hero", "Bisa juga dengan videomu",
     "Gambar di atas video<br>yang kamu rekam", "Semua karya menunggu di layar utama"),
]
SHOTS["nb"] = [
    ("01-trace-bunny.png", "hero", "Tegn etter og animer",
     "Barnets tegninger<br>våkner til liv", "Tegn etter lyse streker side for side"),
    ("02-trace-rocket.png", "tilt-left", "Side for side",
     "Følg strekene,<br>lag en tegnefilm", "Kanin, rakett, frosk og mer: 10 sett"),
    ("03-stamps-fish.png", "tilt-right", "Stempelpalett",
     "Trykk på hjerter,<br>stjerner og blomster", "Ingen lesing nødvendig, bare trykk på bildene"),
    ("04-home.png", "hero", "Også dine egne videoer",
     "Tegn oppå videoer<br>du har tatt opp selv", "Alle verkene venter på startskjermen"),
]
SHOTS["nl"] = [
    ("01-trace-bunny.png", "hero", "Overtrekken en animeren",
     "De tekeningen van je kind<br>komen tot leven", "Trek lichte lijntjes pagina voor pagina over"),
    ("02-trace-rocket.png", "tilt-left", "Pagina voor pagina",
     "Volg de lijnen,<br>maak een tekenfilm", "Konijn, raket, kikker en meer: 10 sets"),
    ("03-stamps-fish.png", "tilt-right", "Stempelpalet",
     "Stempel harten,<br>sterren en bloemen", "Lezen hoeft niet, tik gewoon op de plaatjes"),
    ("04-home.png", "hero", "Ook met je eigen video’s",
     "Teken over video’s<br>die je zelf opnam", "Elk kunstwerk wacht op het beginscherm"),
]
SHOTS["pl"] = [
    ("01-trace-bunny.png", "hero", "Obrysuj i animuj",
     "Rysunki Twojego dziecka<br>ożywają", "Obrysowuj jasne kontury strona po stronie"),
    ("02-trace-rocket.png", "tilt-left", "Strona po stronie",
     "Podążaj za liniami,<br>zrób bajkę", "Króliczek, rakieta, żaba i inne: 10 zestawów"),
    ("03-stamps-fish.png", "tilt-right", "Paleta pieczątek",
     "Przybijaj serca,<br>gwiazdki i kwiatki", "Nie trzeba czytać, wystarczy dotykać obrazków"),
    ("04-home.png", "hero", "Także z własnymi filmami",
     "Rysuj po filmach,<br>które sam nagrasz", "Wszystkie prace czekają na ekranie głównym"),
]
SHOTS["sv"] = [
    ("01-trace-bunny.png", "hero", "Rita av och animera",
     "Barnets teckningar<br>väcks till liv", "Rita av ljusa konturer sida för sida"),
    ("02-trace-rocket.png", "tilt-left", "Sida för sida",
     "Följ linjerna,<br>gör en tecknad film", "Kanin, raket, groda och mer: 10 set"),
    ("03-stamps-fish.png", "tilt-right", "Stämpelpalett",
     "Stämpla hjärtan,<br>stjärnor och blommor", "Ingen läsning behövs, bara tryck på bilderna"),
    ("04-home.png", "hero", "Även med dina egna videor",
     "Rita ovanpå videor<br>du spelat in själv", "Alla verk väntar på startskärmen"),
]
SHOTS["tr"] = [
    ("01-trace-bunny.png", "hero", "Üstünden çiz ve canlandır",
     "Çocuğunuzun çizimleri<br>canlanıyor", "Soluk çizgilerin üstünden sayfa sayfa çizin"),
    ("02-trace-rocket.png", "tilt-left", "Sayfa sayfa",
     "Çizgileri izle,<br>çizgi film yap", "Tavşan, roket, kurbağa ve daha fazlası: 10 set"),
    ("03-stamps-fish.png", "tilt-right", "Damga paleti",
     "Kalp, yıldız ve çiçek<br>damgalarını bas", "Okumak gerekmez, resimlere dokunmak yeter"),
    ("04-home.png", "hero", "Kendi videolarınla da",
     "Çektiğin videoların<br>üstüne çiz", "Tüm çalışmalar ana ekranda bekler"),
]

CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#FFF9F1; position:relative;
  font-family:-apple-system, "SF Pro Rounded", "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(170px); }
.text { position:absolute; left:140px; right:140px; top:200px; text-align:center; }
.eyebrow { font-size:76px; font-weight:800; color:#F28A00; letter-spacing:-0.01em; }
.headline { white-space:nowrap; font-size:150px; font-weight:800; color:#22252B; letter-spacing:-0.03em; line-height:1.16; margin-top:26px; }
.sub { white-space:nowrap; font-size:66px; font-weight:500; color:#7A7570; letter-spacing:-0.01em; margin-top:40px; }
:lang(ko) .headline, :lang(ko) .sub { word-break:keep-all; }
.ipad { position:absolute; background:#202226; border:5px solid #d8d4cc; padding:40px; border-radius:100px;
  box-shadow: 0 60px 160px rgba(120,80,20,.22), 0 0 0 2px #2c2e33 inset; }
.ipad img { width:100%%; display:block; border-radius:60px; }
.stamp { position:absolute; }
"""

# 적은 줄(<br>)이 상자 폭을 넘으면 글자를 줄인다 — 더 쪼개지지 않게 nowrap 으로 둔다.
FIT = """<script>
for (const el of document.querySelectorAll('.headline, .sub')) {
  let size = parseFloat(getComputedStyle(el).fontSize);
  while (el.scrollWidth > el.clientWidth + 1 && size > 40) { size -= 2; el.style.fontSize = size + 'px'; }
}
</script>"""

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
{FIT}
</body></html>"""


def render(lang):
    out_dir = OUT / lang
    out_dir.mkdir(parents=True, exist_ok=True)
    for src, layout, eyebrow, headline, sub in SHOTS[lang]:
        html = pathlib.Path(tempfile.gettempdir()) / f"palangbook-mkt-{lang}-{src}.html"
        html.write_text(page(lang, src, layout, eyebrow, headline, sub), encoding="utf-8")
        out = out_dir / src
        # 그림을 다 쓰고 닫다가 죽기도 해서(Teardown watchdog) 끝 코드 대신 새로 쓴 파일로 판단한다.
        out.unlink(missing_ok=True)
        for _ in range(3):
            try:
                r = subprocess.run([CHROME, "--headless=new", f"--user-data-dir={PROFILE}", f"--screenshot={out}", f"--window-size={W},{H}",
                                    "--force-device-scale-factor=1", "--hide-scrollbars", "--disable-gpu",
                                    "--virtual-time-budget=3000", "--allow-file-access-from-files", html.as_uri()],
                                   capture_output=True, timeout=300)
            except subprocess.TimeoutExpired:
                continue
            if out.exists() and out.stat().st_size > 0:
                break
        else:
            raise SystemExit(f"Chrome 이 그리지 못했다: {out}")
        print(f"rendered {out}")


if __name__ == "__main__":
    for lang in sys.argv[1:] or list(SHOTS):
        render(lang)
