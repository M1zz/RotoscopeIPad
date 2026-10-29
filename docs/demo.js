// 팔랑북 웹 데모: 앱의 '빈 종이 플립북' 을 브라우저에서 그대로 해 본다.
// 규칙은 앱과 같다 — 종이 4:3 (RotoProject.blankCanvasSize), 재생 8장/초 (blankFPS),
// 앞 장이 흐리게 비친다 (showOnionSkin), 붓 굵기 M = 종이 폭의 0.016, 색은 앱 팔레트,
// 무료 빈 종이 플립북은 10장까지 (freeLimits.blankPage).
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text);
  const FPS = 8, MAX_PAGES = 10, WIDTH = 0.016;
  const PALETTE = ["000000", "FF3B30", "FF9500", "FFCC00", "34C759", "00C7BE", "007AFF", "AF52DE", "FF2D55"];
  const icon = d => `<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path fill="currentColor" d="${d}"/></svg>`;
  const ICONS = {
    prev: "M15.4 5.4a1 1 0 0 1 0 1.4L10.2 12l5.2 5.2a1 1 0 1 1-1.4 1.4l-5.9-5.9a1 1 0 0 1 0-1.4l5.9-5.9a1 1 0 0 1 1.4 0Z",
    next: "M8.6 5.4a1 1 0 0 1 1.4 0l5.9 5.9a1 1 0 0 1 0 1.4L10 18.6a1 1 0 1 1-1.4-1.4l5.2-5.2-5.2-5.2a1 1 0 0 1 0-1.4Z",
    play: "M8 5.1v13.8a1 1 0 0 0 1.5.9l11-6.9a1 1 0 0 0 0-1.8l-11-6.9A1 1 0 0 0 8 5.1Z",
    stop: "M7 6h3.5v12H7zM13.5 6H17v12h-3.5z",
    undo: "M9.7 4.3a1 1 0 0 1 0 1.4L7.4 8H14a6 6 0 1 1 0 12h-3a1 1 0 1 1 0-2h3a4 4 0 1 0 0-8H7.4l2.3 2.3a1 1 0 1 1-1.4 1.4l-4-4a1 1 0 0 1 0-1.4l4-4a1 1 0 0 1 1.4 0Z",
    clear: "M9 3h6a1 1 0 0 1 1 1v1h4a1 1 0 1 1 0 2h-1l-1 13a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 7H4a1 1 0 0 1 0-2h4V4a1 1 0 0 1 1-1Zm-2 4 1 13h8l1-13H7Z"
  };
  const btn = (k, cls = "") => `<button type="button" class="fb-btn ${cls}" data-act="${k}" aria-label="${T[k]}" title="${T[k]}">${icon(ICONS[k])}</button>`;

  root.innerHTML = `
    <div class="fb-bar">
      ${btn("undo")}${btn("clear", "danger")}
      <div class="fb-colors" role="radiogroup" aria-label="${T.colors}">
        ${PALETTE.map((c, i) => `<button type="button" role="radio" class="fb-color" data-color="${c}" style="--c:#${c}"
          aria-checked="${i ? "false" : "true"}" aria-label="#${c}"></button>`).join("")}
      </div>
      ${btn("play", "primary")}
    </div>
    <div class="fb-paper">
      <canvas width="1200" height="900" aria-label="${T.canvas}"></canvas>
      <p class="fb-hint" aria-hidden="true">${T.hint}</p>
    </div>
    <div class="fb-nav">
      ${btn("prev")}
      <span class="fb-page" aria-live="polite"></span>
      ${btn("next", "accent")}
    </div>
    <p class="muted small fb-note">${T.note}</p>`;

  const $ = s => root.querySelector(s);
  const canvas = $("canvas"), ctx = canvas.getContext("2d"), W = canvas.width, H = canvas.height;
  const state = { pages: [[]], page: 0, color: PALETTE[0], playing: false, live: null };

  function drawStroke(s, alpha = 1) {
    const p = s.points.map(([x, y]) => [x * W, y * H]);
    ctx.globalAlpha = alpha;
    ctx.strokeStyle = ctx.fillStyle = "#" + s.color;
    ctx.lineWidth = WIDTH * W; ctx.lineCap = ctx.lineJoin = "round";
    ctx.beginPath();
    if (p.length === 1) { ctx.arc(p[0][0], p[0][1], ctx.lineWidth / 2, 0, Math.PI * 2); ctx.fill(); return; }
    ctx.moveTo(...p[0]);
    // 앱처럼 부드럽게: 점 사이의 가운데를 지나는 곡선.
    for (let i = 1; i < p.length - 1; i++)
      ctx.quadraticCurveTo(p[i][0], p[i][1], (p[i][0] + p[i + 1][0]) / 2, (p[i][1] + p[i + 1][1]) / 2);
    ctx.lineTo(...p[p.length - 1]);
    ctx.stroke();
  }

  function render(index = state.page) {
    ctx.globalAlpha = 1; ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, H);
    if (!state.playing && index > 0) state.pages[index - 1].forEach(s => drawStroke(s, 0.22));
    state.pages[index].forEach(s => drawStroke(s));
    if (state.live) drawStroke(state.live);
    ctx.globalAlpha = 1;
    $(".fb-page").textContent = `${index + 1} / ${state.pages.length}`;
    const drawn = state.pages.filter(p => p.length).length;
    $(".fb-hint").hidden = state.playing || state.pages.some(p => p.length);
    $('[data-act="prev"]').disabled = state.playing || state.page === 0;
    $('[data-act="next"]').disabled = state.playing || (state.page === MAX_PAGES - 1);
    $('[data-act="play"]').disabled = !state.playing && (state.pages.length < 2 || drawn < 1);
    $('[data-act="undo"]').disabled = $('[data-act="clear"]').disabled = state.playing || !state.pages[state.page].length;
    $('[data-act="next"]').classList.toggle("hint", !state.playing && state.page === state.pages.length - 1
      && state.pages[state.page].length > 0 && state.pages.length < 3);
  }

  // 재생: 8장/초로 첫 장부터 반복. 앞 장 비침은 끈다.
  let timer, frame = 0;
  function setPlayButton(k) {
    const b = $('[data-act="play"]');
    b.innerHTML = icon(ICONS[k]); b.setAttribute("aria-label", T[k]); b.title = T[k];
  }
  function play() {
    state.playing = true; frame = 0;
    setPlayButton("stop");
    timer = setInterval(() => { render(frame); frame = (frame + 1) % state.pages.length; }, 1000 / FPS);
  }
  function stop() {
    state.playing = false; clearInterval(timer);
    setPlayButton("play");
    render();
  }

  root.addEventListener("click", e => {
    const color = e.target.closest("[data-color]");
    if (color) {
      state.color = color.dataset.color;
      root.querySelectorAll(".fb-color").forEach(b => b.setAttribute("aria-checked", String(b === color)));
      return;
    }
    const act = e.target.closest("[data-act]")?.dataset.act;
    if (!act) return;
    if (act === "play") return state.playing ? stop() : play();
    if (act === "undo") state.pages[state.page].pop();
    if (act === "clear") state.pages[state.page] = [];
    if (act === "prev") state.page--;
    if (act === "next") {
      state.page++;
      if (state.page === state.pages.length) state.pages.push([]);
    }
    render();
  });

  const point = e => {
    const r = canvas.getBoundingClientRect();
    return [Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), Math.min(1, Math.max(0, (e.clientY - r.top) / r.height))];
  };
  canvas.addEventListener("pointerdown", e => {
    if (state.playing) stop();
    canvas.setPointerCapture(e.pointerId);
    state.live = { color: state.color, points: [point(e)] };
    render();
  });
  canvas.addEventListener("pointermove", e => {
    if (!state.live) return;
    state.live.points.push(point(e));
    render();
  });
  const end = () => {
    if (!state.live) return;
    state.pages[state.page].push(state.live);
    state.live = null;
    render();
  };
  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", end);

  render();
})();
