// The phone remote. Served as a single page; talks to /api/* on the same server.
let remotePageHTML = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Commentary">
<meta name="theme-color" content="#0d0f12">
<title>Commentary Boost</title>
<style>
  :root {
    --bg: #0d0f12; --panel: #171a1f; --line: #262a31; --text: #f2f3f5; --dim: #8b919c;
    --accent: #e10600; --accent-dim: #4a1210; --ok: #3ccf7a;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; background: var(--bg); color: var(--text);
    font: 16px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  body { padding: max(20px, env(safe-area-inset-top)) 16px max(24px, env(safe-area-inset-bottom));
    min-height: 100dvh; display: flex; flex-direction: column; gap: 16px; user-select: none; -webkit-user-select: none; }
  header { display: flex; align-items: center; justify-content: space-between; }
  h1 { font-size: 17px; font-weight: 650; margin: 0; letter-spacing: .01em; }
  .status { font-size: 13px; color: var(--dim); display: flex; align-items: center; gap: 6px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--dim); }
  .dot.live { background: var(--ok); } .dot.off { background: var(--accent); }
  section { background: var(--panel); border: 1px solid var(--line); border-radius: 18px; padding: 18px; }
  .label { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 14px; }
  .label span:first-child { color: var(--dim); font-size: 14px; }
  #carsValue { font-size: 34px; font-weight: 700; font-variant-numeric: tabular-nums; }
  input[type=range] { -webkit-appearance: none; appearance: none; width: 100%; height: 44px; background: transparent; margin: 0; }
  input[type=range]::-webkit-slider-runnable-track { height: 10px; border-radius: 5px;
    background: linear-gradient(90deg, var(--accent) var(--fill, 20%), var(--line) var(--fill, 20%)); }
  input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; width: 34px; height: 34px; border-radius: 50%;
    background: #fff; margin-top: -12px; box-shadow: 0 2px 8px rgba(0,0,0,.5); }
  .ends { display: flex; justify-content: space-between; font-size: 12px; color: var(--dim); margin-top: 4px; }
  .chips { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; margin-top: 14px; }
  button { font: inherit; color: var(--text); background: #20242b; border: 1px solid var(--line); border-radius: 12px;
    padding: 12px 6px; cursor: pointer; transition: transform .06s, background .15s; }
  button:active { transform: scale(.96); background: #2a2f37; }
  button.on { background: var(--accent-dim); border-color: var(--accent); }
  .transport { display: grid; grid-template-columns: 1fr 1.8fr 1fr; gap: 10px; }
  .transport button { padding: 22px 0; font-size: 17px; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 8px; }
  .transport svg { width: 26px; height: 26px; fill: currentColor; }
  #play { background: var(--accent); border-color: var(--accent); }
  #play:active { background: #b80500; }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .note { font-size: 13px; color: var(--dim); text-align: center; margin: 0; }
  .note.warn { color: #ffb4a8; }
  .spacer { flex: 1; }
</style>
</head>
<body>
  <header>
    <h1>Commentary Boost</h1>
    <div class="status"><span class="dot" id="dot"></span><span id="statusText">Connecting…</span></div>
  </header>

  <section>
    <div class="label"><span>Car sound</span><span id="carsValue">20%</span></div>
    <input type="range" id="cars" min="0" max="100" step="1" value="20" aria-label="Car sound">
    <div class="ends"><span>Commentary only</span><span>Original</span></div>
    <div class="chips">
      <button data-cars="0">0%</button><button data-cars="10">10%</button>
      <button data-cars="20">20%</button><button data-cars="40">40%</button>
    </div>
  </section>

  <div class="transport">
    <button id="back" aria-label="Back a few seconds">
      <svg viewBox="0 0 24 24"><path d="M11 6V2L5 8l6 6V10c3.3 0 6 2.7 6 6s-2.7 6-6 6-6-2.7-6-6H3c0 4.4 3.6 8 8 8s8-3.6 8-8-3.6-8-8-8z" transform="translate(1 -2)"/></svg>
    </button>
    <button id="play" aria-label="Play or pause">
      <svg viewBox="0 0 24 24"><path d="M3 5v14l9-7zM14 5h3v14h-3zM19 5h3v14h-3z"/></svg>Play / Pause
    </button>
    <button id="forward" aria-label="Forward a few seconds">
      <svg viewBox="0 0 24 24" style="transform: scaleX(-1)"><path d="M11 6V2L5 8l6 6V10c3.3 0 6 2.7 6 6s-2.7 6-6 6-6-2.7-6-6H3c0 4.4 3.6 8 8 8s8-3.6 8-8-3.6-8-8-8z" transform="translate(1 -2)"/></svg>
    </button>
  </div>

  <div class="row">
    <button id="bypass">Compare original</button>
    <button id="model">Voice model</button>
  </div>
  <p class="note warn" id="keysNote" hidden>Play/pause needs Accessibility permission for Terminal on the Mac.</p>

  <div class="spacer"></div>
  <p class="note">Play/pause goes to whatever video is playing on the Mac.</p>

<script>
  const key = new URLSearchParams(location.search).get("k") || "";
  const $ = (id) => document.getElementById(id);
  const slider = $("cars");
  let dragging = false, sendTimer = null, lastSent = null;

  async function api(path, params = {}) {
    const q = new URLSearchParams({ k: key, ...params });
    const res = await fetch(`/api/${path}?${q}`, { method: path === "state" ? "GET" : "POST" });
    if (!res.ok) throw new Error(res.status);
    return res.json();
  }

  function render(s) {
    if (!dragging) setSlider(s.cars);
    $("bypass").classList.toggle("on", s.bypassed);
    $("bypass").textContent = s.bypassed ? "Hearing original" : "Compare original";
    $("model").textContent = s.highQuality ? "Model: HQ voice" : "Model: Voice";
    $("keysNote").hidden = s.canControlPlayback;
    document.querySelectorAll("[data-cars]").forEach(b => b.classList.toggle("on", +b.dataset.cars === Math.round(s.cars)));
    $("dot").className = "dot " + (s.active ? "live" : "");
    $("statusText").textContent = s.active ? (s.bypassed ? "Original sound" : "Boosting") : "Waiting for audio";
  }

  function disconnected() {
    $("dot").className = "dot off";
    $("statusText").textContent = "Not connected";
  }

  function setSlider(v) {
    slider.value = v;
    slider.style.setProperty("--fill", v + "%");
    $("carsValue").textContent = Math.round(v) + "%";
  }

  async function refresh() {
    try { render(await api("state")); } catch { disconnected(); }
  }

  function sendCars(v) {
    if (v === lastSent) return;
    lastSent = v;
    api("cars", { v }).then(render).catch(disconnected);
  }

  slider.addEventListener("input", () => {
    dragging = true;
    setSlider(+slider.value);
    clearTimeout(sendTimer);
    sendTimer = setTimeout(() => sendCars(+slider.value), 60);
  });
  slider.addEventListener("change", () => { dragging = false; sendCars(+slider.value); });

  document.querySelectorAll("[data-cars]").forEach(b =>
    b.addEventListener("click", () => { setSlider(+b.dataset.cars); sendCars(+b.dataset.cars); }));

  const press = (id, path) => $(id).addEventListener("click", () => {
    navigator.vibrate?.(10);
    api(path).then(render).catch(disconnected);
  });
  press("play", "playpause");
  press("back", "back");
  press("forward", "forward");
  press("bypass", "bypass");
  press("model", "model");

  refresh();
  setInterval(() => { if (!dragging && !document.hidden) refresh(); }, 1500);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
</script>
</body>
</html>
"""#
