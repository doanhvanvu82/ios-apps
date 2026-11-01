// Chế độ "Chọn quảng cáo để ẩn" (giống Hide Distracting Items của Safari), chỉ ở frame top.
// Chạm vào khối → tự chọn khung chứa → bảng đáy trang: Rộng/Hẹp, domain nguồn, nút "Ẩn" (cơ bản) và "Ẩn bằng AI".
(() => {
  "use strict";

  const C = globalThis.AdsBlockerContent;
  if (!C || !C.IS_TOP || globalThis.AdsBlockerPicker) return;
  const { sourceDomains, selectorProblem, validateRules, globalScopeProblem, MAX_AREA_RATIO } = globalThis.AdsBlockerRules;
  const { slotIndex, isRandomToken, hasAdWord } = globalThis.AdsBlockerCandidates;

  const MAX_MATCHES = 50;
  const PRECHECK_CONFIDENCE = 0.7;
  const MAX_FALLBACKS = 2;
  const TOAST_MS = 3500;
  const BUSY_LABEL = { hide: "Đang lưu…", ai: "Đang hỏi Gemini…", save: "Đang lưu…" };
  const SWALLOWED = ["pointerdown", "pointerup", "mousedown", "mouseup", "touchstart", "touchend",
    "click", "auxclick", "dblclick", "contextmenu"];

  let ui = null;
  let chain = [];
  let level = 0;
  let basic = null;
  let proposals = [];
  let previewEl = null;

  const TEMPLATE = `
    <style>
      :host { all: initial; }
      [hidden] { display: none !important; }
      * { box-sizing: border-box; font: 15px/1.35 -apple-system, system-ui, sans-serif; }
      .shield { position: fixed; inset: 0; pointer-events: auto; cursor: crosshair; background: rgba(0,0,0,.04); }
      .box { position: fixed; display: none; pointer-events: none; border: 3px solid #ff1744;
        background: rgba(255,23,68,.15); border-radius: 4px; }
      .panel { position: fixed; left: 8px; right: 8px; pointer-events: auto; color: #111; background: #fff;
        border-radius: 14px; box-shadow: 0 6px 30px rgba(0,0,0,.35); padding: 10px 12px; max-width: 520px; margin: 0 auto; }
      .bar { top: calc(8px + env(safe-area-inset-top)); display: flex; align-items: center; gap: 8px; }
      .bar span { flex: 1; font-weight: 600; }
      .sheet { bottom: calc(8px + env(safe-area-inset-bottom)); display: none; max-height: 60vh; overflow: auto; }
      .row { display: flex; gap: 8px; margin-top: 8px; }
      .row button { flex: 1; }
      button { border: 0; border-radius: 9px; padding: 9px 10px; background: #e9ecef; color: #111; font-weight: 600; }
      button.primary { background: #15a37a; color: #fff; }
      button.ai { background: #5b5bd6; color: #fff; }
      button:disabled { opacity: .45; }
      code { font: 12px ui-monospace, monospace; word-break: break-all; }
      .muted { color: #666; font-size: 13px; }
      .err { color: #d0302f; font-size: 13px; }
      .ok { color: #15a37a; font-size: 13px; }
      .status:empty { display: none; }
      .status { margin-top: 8px; }
      .spin { display: inline-block; width: 12px; height: 12px; margin-right: 6px; vertical-align: -1px;
        border: 2px solid currentColor; border-right-color: transparent; border-radius: 50%; animation: spin .8s linear infinite; }
      @keyframes spin { to { transform: rotate(360deg); } }
      label { display: flex; gap: 8px; align-items: flex-start; margin-top: 6px; font-size: 13px; }
      label input { width: 18px; height: 18px; flex: none; accent-color: #15a37a; }
      .tag { font-size: 11px; font-weight: 700; padding: 1px 6px; border-radius: 6px; background: #e3f6ef; margin-right: 4px; }
      .tag.scope { background: #e6e6fa; }
      .tag.scope.toggle { text-decoration: underline dotted; }
      @media (prefers-color-scheme: dark) {
        .panel { background: #1c1c1e; color: #f2f2f7; }
        button { background: #3a3a3c; color: #f2f2f7; }
        .muted { color: #a1a1a6; }
        .tag { background: #1f3d33; }
      }
    </style>
    <div class="shield"></div>
    <div class="box"></div>
    <div class="panel bar"><span>Chạm vào quảng cáo cần ẩn</span><button data-act="cancel">Huỷ</button></div>
    <div class="panel sheet">
      <div><b class="what"></b> <span class="muted count"></span></div>
      <code class="sel"></code>
      <label><input type="checkbox" class="scope-global">
        <span>Áp dụng cho mọi trang <span class="muted scope-note"></span></span></label>
      <div class="row">
        <button data-act="grow">▲ Rộng hơn</button>
        <button data-act="shrink">▼ Hẹp hơn</button>
      </div>
      <div class="domains"></div>
      <div class="ai-result"></div>
      <div class="status muted"></div>
      <div class="row actions">
        <button class="primary" data-act="hide">Ẩn</button>
        <button class="ai" data-act="ai">Ẩn bằng AI</button>
      </div>
      <div class="row save" hidden>
        <button class="primary" data-act="save">Lưu rule đã chọn</button>
      </div>
    </div>`;

  // ---------------------------------------------------------------- bật / tắt

  function start() {
    if (ui) return;
    const host = document.createElement("div");
    host.setAttribute(C.OWN_ATTR, "picker");
    host.style.cssText = "position:fixed;inset:0;z-index:2147483647;pointer-events:none;";
    // "open": composedPath() ở window mới thấy được lớp chắn để phân biệt với bảng điều khiển.
    const shadow = host.attachShadow({ mode: "open" });
    shadow.innerHTML = TEMPLATE;
    const $ = (s) => shadow.querySelector(s);
    ui = { host, $, shield: $(".shield"), box: $(".box"), sheet: $(".sheet") };

    shadow.addEventListener("click", onPanelClick);
    // Click trong bảng của mình không được lan ra document (script quảng cáo của trang nghe ở đó).
    for (const type of SWALLOWED) host.addEventListener(type, (e) => e.stopPropagation());
    for (const type of SWALLOWED) window.addEventListener(type, swallow, true);
    window.addEventListener("scroll", placeBox, { passive: true });
    window.addEventListener("resize", placeBox);
    window.addEventListener("keydown", onKey, true);
    document.documentElement.appendChild(host);
  }

  function stop() {
    if (!ui) return;
    for (const type of SWALLOWED) window.removeEventListener(type, swallow, true);
    window.removeEventListener("scroll", placeBox);
    window.removeEventListener("resize", placeBox);
    window.removeEventListener("keydown", onKey, true);
    ui.host.remove();
    preview([]);
    ui = null;
    chain = [];
    basic = null;
    proposals = [];
  }

  function onKey(event) {
    if (event.key === "Escape") stop();
  }

  /** Chặn mọi cú chạm tới trang khi đang chọn: chạm vào quảng cáo không được mở tab/chạy script của trang. */
  function swallow(event) {
    if (!ui || event.composedPath().includes(ui.host) && !event.composedPath().includes(ui.shield)) return;
    event.stopImmediatePropagation();
    // Không preventDefault touchstart/pointerdown để vẫn cuộn được trang khi đang chọn.
    if (/^(click|mousedown|mouseup|auxclick|dblclick|contextmenu)$/.test(event.type)) event.preventDefault();
    if (event.type === "click" && event.isTrusted && ui.sheet.dataset.busy !== "1") pickAt(event.clientX, event.clientY);
  }

  // ---------------------------------------------------------------- chọn khối

  function pickAt(x, y) {
    ui.shield.style.pointerEvents = "none";
    const el = document.elementFromPoint(x, y);
    ui.shield.style.pointerEvents = "";
    if (!el || el === document.body || el === document.documentElement || ui.host.contains(el)) return;
    chain = [];
    for (let node = el; node && node !== document.body && node !== document.documentElement; node = node.parentElement) {
      chain.push(node);
    }
    level = slotIndex(chain.map((n) => n.getBoundingClientRect()));
    proposals = [];
    select();
  }

  const current = () => chain[level];

  function select() {
    const el = current();
    basic = buildBasicRule(el);
    const r = el.getBoundingClientRect();
    ui.$(".what").textContent = `<${el.tagName.toLowerCase()}> ${Math.round(r.width)}×${Math.round(r.height)}`;
    ui.$(".count").textContent = `· sẽ ẩn ${basic.count} khối trên trang`;
    ui.$(".sel").textContent = basic.selector;
    const scopeProblem = globalScopeProblem(basic.selector);
    const scopeBox = ui.$(".scope-global");
    scopeBox.checked = false;
    scopeBox.disabled = !!scopeProblem;
    ui.$(".scope-note").textContent = scopeProblem
      ? `— không được: ${scopeProblem}`
      : "— selector có dấu hiệu quảng cáo, dùng được cho trang khác";
    ui.$("[data-act=grow]").disabled = level >= chain.length - 1;
    ui.$("[data-act=shrink]").disabled = level === 0;
    renderDomains(el);
    renderProposals();
    setStatus("");
    ui.sheet.style.display = "block";
    placeBox();
  }

  function placeBox() {
    if (!ui || !current()) return;
    const r = current().getBoundingClientRect();
    Object.assign(ui.box.style, {
      display: "block", left: `${r.left}px`, top: `${r.top}px`, width: `${r.width}px`, height: `${r.height}px`,
    });
  }

  // ---------------------------------------------------------------- rule cơ bản

  function okSelector(selector, el) {
    if (selectorProblem(selector)) return null;
    const m = C.measureFor(selector, el);
    return m.valid && m.includesCandidate && m.count <= MAX_MATCHES && m.areaRatio <= MAX_AREA_RATIO ? m : null;
  }

  /** Selector chính (có nghĩa, bền khi nội dung quảng cáo đổi) + dự phòng + đường dẫn cấu trúc. */
  function buildBasicRule(el) {
    const tag = el.tagName.toLowerCase();
    const options = [];
    if (el.id && !isRandomToken(el.id) && !/^\d/.test(el.id)) options.push("#" + CSS.escape(el.id));
    const classes = [...el.classList].filter((c) => !isRandomToken(c));
    const adClasses = classes.filter((c) => hasAdWord(c));
    if (adClasses.length) options.push(tag + adClasses.slice(0, 2).map((c) => "." + CSS.escape(c)).join(""));
    const adAttr = [...el.attributes].find((a) => /^data-(ad|dfp|gpt|google-query-id)/i.test(a.name));
    if (adAttr) options.push(`${tag}[${adAttr.name}]`);
    const frame = el.matches("iframe") ? el : el.querySelectorAll("iframe").length === 1 ? el.querySelector("iframe") : null;
    const frameHost = frame && C.hostOf(frame.src);
    if (frameHost && sourceDomains([frame.src], C.HOST).length) options.push(`iframe[src*="${frameHost}"]`);
    if (classes.length) options.push(tag + classes.slice(0, 3).map((c) => "." + CSS.escape(c)).join(""));
    options.push(C.stableSelector(el));

    const good = [...new Set(options)].filter((s) => okSelector(s, el));
    const selector = good[0] || C.stableSelector(el);
    const structural = C.structuralPath(el);
    return {
      type: "hide",
      selector,
      fallback: good.slice(1, 1 + MAX_FALLBACKS),
      structural: structural === selector ? undefined : structural,
      count: C.measureFor(selector, el).count || 1,
    };
  }

  function renderDomains(el) {
    const urls = [el, ...el.querySelectorAll("iframe,img,video,source,embed,object")]
      .flatMap((n) => [n.src, n.currentSrc, n.data].filter(Boolean));
    const links = [el.closest("a[href]"), ...el.querySelectorAll("a[href]")].filter(Boolean).map((a) => a.href);
    const resources = sourceDomains(urls, C.HOST);
    const popups = sourceDomains(links, C.HOST);
    const box = ui.$(".domains");
    box.replaceChildren();
    const add = (type, domain, text) => {
      const label = document.createElement("label");
      const input = Object.assign(document.createElement("input"), { type: "checkbox", checked: hasAdWord(domain) });
      input.dataset.type = type;
      input.dataset.domain = domain;
      const span = document.createElement("span");
      span.append(text, Object.assign(document.createElement("code"), { textContent: domain }));
      label.append(input, span);
      box.append(label);
    };
    resources.forEach((d) => add("block_domain", d, "Chặn luôn domain (mọi trang) "));
    popups.forEach((d) => add("block_popup_domain", d, "Chặn tab mới tới "));
  }

  function checkedDomains() {
    return [...ui.$(".domains").querySelectorAll("input:checked")]
      .map((i) => ({ type: i.dataset.type, domain: i.dataset.domain }));
  }

  // ---------------------------------------------------------------- AI

  function aiPage(el) {
    const r = el.getBoundingClientRect();
    const ancestors = [];
    for (let n = el.parentElement; n && n !== document.body && ancestors.length < 4; n = n.parentElement) {
      ancestors.push({ tag: n.tagName.toLowerCase(), id: n.id || undefined, class: n.getAttribute("class") || undefined });
    }
    const similar = [...(el.parentElement ? el.parentElement.children : [])]
      .filter((n) => n !== el && n.tagName === el.tagName).slice(0, 5).map((n) => C.strippedHtml(n).slice(0, 300));
    return {
      url: location.origin + location.pathname,
      title: document.title.slice(0, 120),
      viewport: { w: window.innerWidth, h: window.innerHeight },
      candidates: [{
        id: 1,
        confirmedAd: true,
        selector: basic.selector,
        tag: el.tagName.toLowerCase(),
        rect: { x: Math.round(r.left), y: Math.round(r.top + window.scrollY), w: Math.round(r.width), h: Math.round(r.height) },
        html: C.strippedHtml(el),
        ancestors,
        similarSiblings: similar,
      }],
      resourceDomains: C.resourceDomains(),
    };
  }

  async function ask(type, extra) {
    const reply = await browser.runtime.sendMessage({ type, ...extra });
    if (!reply || !reply.ok) throw new Error(reply ? reply.error : "Không liên lạc được với extension.");
    return reply.result;
  }

  async function runAI() {
    const el = current();
    const page = aiPage(el);
    // Ẩn bảng khi chụp màn hình: ảnh gửi Gemini chỉ có trang + khung đỏ quanh khối đã chọn.
    ui.$(".bar").style.visibility = "hidden";
    ui.sheet.style.visibility = "hidden";
    let screenshot = null;
    try {
      await new Promise((resolve) => setTimeout(resolve, 60));
      screenshot = await ask("capture", {});
    } finally {
      ui.$(".bar").style.visibility = "";
      ui.sheet.style.visibility = "";
    }
    const startedAt = Date.now();
    const tick = () => setStatus(`Gemini đang phân tích khối này… ${Math.round((Date.now() - startedAt) / 1000)} giây`, "busy");
    tick();
    const timer = setInterval(tick, 1000);
    let rules;
    try {
      rules = await ask("pickAI", { page, screenshot });
    } finally {
      clearInterval(timer);
    }
    const { accepted } = validateRules(rules, {
      pageHost: C.HOST,
      candidates: new Map([[1, { selector: basic.selector }]]),
      measure: (selector) => C.measureFor(selector, el),
    });
    proposals = accepted.filter((p) => !(p.type === "hide" && p.selector === basic.selector));
    renderProposals();
    setStatus(proposals.length
      ? `AI đề xuất thêm ${proposals.length} rule. Tick rule muốn lưu (chạm vào rule để xem trên trang).`
      : "AI không đề xuất thêm rule nào — bấm Lưu để dùng rule cơ bản.", "ok");
    if (!proposals.length) {
      ui.$(".actions").hidden = true;
      ui.$(".save").hidden = false;
    }
  }

  function renderProposals() {
    const box = ui.$(".ai-result");
    box.replaceChildren();
    const aiMode = proposals.length > 0;
    ui.$(".actions").hidden = aiMode;
    ui.$(".save").hidden = !aiMode;
    if (!aiMode) return;
    const items = [
      { ...basic, scope: basicScope(), reason: "Rule cơ bản (khối vừa chọn)", confidence: 1, base: true },
      ...proposals,
    ];
    items.forEach((rule, index) => {
      const label = document.createElement("label");
      const input = Object.assign(document.createElement("input"), {
        type: "checkbox", checked: rule.base || rule.confidence >= PRECHECK_CONFIDENCE, value: String(index),
      });
      const text = document.createElement("span");
      const kind = rule.type === "hide" ? "Ẩn" : rule.type === "block_domain" ? "Chặn domain" : "Chặn tab mới";
      text.append(
        Object.assign(document.createElement("span"), { className: "tag", textContent: kind }),
        scopeTag(rule),
        Object.assign(document.createElement("code"), { textContent: rule.selector || rule.domain }),
        Object.assign(document.createElement("div"), { className: "muted", textContent: rule.reason }));
      text.addEventListener("click", (e) => {
        e.preventDefault();
        preview(rule.type === "hide" ? [rule.selector] : []);
      });
      label.append(input, text);
      box.append(label);
    });
    box.items = items;
  }

  function preview(selectors) {
    previewEl?.remove();
    previewEl = null;
    if (!selectors.length) return;
    previewEl = document.createElement("style");
    previewEl.setAttribute(C.OWN_ATTR, "picker-preview");
    previewEl.textContent = selectors
      .map((s) => `${s} { outline: 3px dashed #5b5bd6 !important; outline-offset: -3px !important; }`).join("\n");
    document.documentElement.appendChild(previewEl);
  }

  // ---------------------------------------------------------------- lưu

  const basicScope = () => (ui.$(".scope-global").checked ? "global" : "site");

  /** Nhãn phạm vi của rule ẩn; chạm để đổi Trang này ↔ Mọi trang (nếu selector đủ điều kiện). */
  function scopeTag(rule) {
    const tag = document.createElement("span");
    if (rule.type !== "hide") {
      Object.assign(tag, { className: "tag scope", textContent: "Mọi trang" });
      return tag;
    }
    const problem = globalScopeProblem(rule.selector);
    const paint = () => {
      tag.className = problem ? "tag scope" : "tag scope toggle";
      tag.textContent = rule.scope === "global" ? "Mọi trang" : "Trang này";
      tag.title = problem || "Chạm để đổi phạm vi";
    };
    tag.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (problem) return setStatus(`Không áp mọi trang được: ${problem}`, "err");
      rule.scope = rule.scope === "global" ? "site" : "global";
      paint();
    });
    paint();
    return tag;
  }

  const forStorage = (rule, source) => rule.type === "hide"
    ? {
      type: "hide", selector: rule.selector, fallback: rule.fallback, structural: rule.structural,
      scope: rule.scope === "global" ? "global" : "site", reason: rule.reason, source,
    }
    : { type: rule.type, domain: rule.domain, reason: rule.reason, source };

  async function save(rules) {
    if (!rules.length) throw new Error("Chưa chọn rule nào.");
    await ask("savePicked", { rules });
    stop();
    const hidden = rules.filter((r) => r.type === "hide").length;
    const domains = rules.length - hidden;
    pageToast(`✓ Đã ẩn ${hidden} rule${domains ? ` · chặn ${domains} domain` : ""}. Xem/xoá trong popup › Rule đã lưu.`);
  }

  /** kind: "busy" | "ok" | "err" | "" (thông tin). */
  function setStatus(text, kind = "") {
    const node = ui.$(".status");
    node.className = `status ${kind === "busy" || !kind ? "muted" : kind}`;
    node.replaceChildren();
    if (!text) return;
    if (kind === "busy") node.append(Object.assign(document.createElement("span"), { className: "spin" }));
    node.append((kind === "err" ? "✕ " : kind === "ok" ? "✓ " : "") + text);
  }

  /** Thông báo nổi ngắn sau khi đóng bảng chọn, để biết thao tác đã có hiệu lực. */
  function pageToast(text) {
    const host = document.createElement("div");
    host.setAttribute(C.OWN_ATTR, "toast");
    host.style.cssText = "position:fixed;left:0;right:0;top:calc(12px + env(safe-area-inset-top));z-index:2147483647;" +
      "display:flex;justify-content:center;pointer-events:none;";
    const box = host.attachShadow({ mode: "open" });
    box.innerHTML = `<div style="all:initial;font:600 15px -apple-system,system-ui,sans-serif;color:#fff;background:#15a37a;
      padding:10px 16px;border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,.3);max-width:90vw"></div>`;
    box.firstElementChild.textContent = text;
    document.documentElement.appendChild(host);
    setTimeout(() => host.remove(), TOAST_MS);
  }

  async function onPanelClick(event) {
    const button = event.target.closest && event.target.closest("button[data-act]");
    if (!button || !ui) return;
    const act = button.dataset.act;
    if (act === "cancel") return stop();
    if (act === "grow" || act === "shrink") {
      level = Math.max(0, Math.min(chain.length - 1, level + (act === "grow" ? 1 : -1)));
      proposals = [];
      return select();
    }

    ui.sheet.dataset.busy = "1";
    ui.sheet.querySelectorAll("button").forEach((b) => { b.disabled = true; });
    const label = button.textContent;
    button.replaceChildren(Object.assign(document.createElement("span"), { className: "spin" }), BUSY_LABEL[act] || "Đang xử lý…");
    try {
      if (act === "hide") {
        const domains = checkedDomains().map((d) => ({ ...d, reason: "Tự chọn" }));
        await save([{ ...basic, scope: basicScope(), reason: "Tự chọn" }, ...domains].map((r) => forStorage(r, "manual")));
      } else if (act === "ai") {
        await runAI();
      } else if (act === "save") {
        // AI không đề xuất thêm thì danh sách trống: lưu rule cơ bản.
        const items = ui.$(".ai-result").items || [{ ...basic, base: true }];
        const chosen = ui.$(".ai-result").items
          ? [...ui.$(".ai-result").querySelectorAll("input:checked")].map((i) => items[Number(i.value)])
          : items;
        const domains = checkedDomains().map((d) => ({ ...d, reason: "Tự chọn" }));
        await save([
          ...chosen.map((r) => forStorage(r.base ? { ...r, reason: "Tự chọn" } : r, r.base ? "manual" : "ai")),
          ...domains.map((r) => forStorage(r, "manual")),
        ]);
      }
    } catch (error) {
      if (ui) setStatus(error.message || String(error), "err");
    } finally {
      button.textContent = label;
      if (ui) {
        delete ui.sheet.dataset.busy;
        ui.sheet.querySelectorAll("button").forEach((b) => { b.disabled = false; });
        ui.$("[data-act=grow]").disabled = level >= chain.length - 1;
        ui.$("[data-act=shrink]").disabled = level === 0;
      }
    }
  }

  // Lệnh "startPicker" đi qua listener duy nhất trong content.js.
  globalThis.AdsBlockerPicker = { start };
})();
