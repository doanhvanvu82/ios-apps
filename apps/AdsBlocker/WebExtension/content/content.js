// Content script (isolated world): ẩn quảng cáo theo rule, gỡ lớp phủ bắt click, ghi log popup bị chặn,
// và phục vụ popup khi quét (snapshot ứng viên, đánh số lên trang, đo selector, highlight).
(() => {
  "use strict";

  // background nạp lại script (askPage) khi trang không trả lời → không chạy lần hai.
  if (globalThis.AdsBlockerContent) return;

  const { siteKey, resolveSite, MAX_AREA_RATIO } = globalThis.AdsBlockerRules;
  const { scoreCandidate, isInvisibleOverlay, isRandomToken, hasAdWord } = globalThis.AdsBlockerCandidates;

  const IS_TOP = window === window.top;
  const HOST = location.hostname;
  const OWN_ATTR = "data-adsblocker";
  const HIDDEN_ATTR = "data-adsblocker-hidden";
  const MAX_CANDIDATES = 40;
  const MAX_SCAN_ELEMENTS = 6000;
  const OVERLAY_SWEEP_MS = 30000;

  // Quảng cáo phổ biến, selector đủ đặc thù để ẩn mọi nơi.
  const GENERIC_HIDE = [
    "ins.adsbygoogle", ".adsbygoogle", "[id^='div-gpt-ad']", "[id^='google_ads_iframe']",
    "iframe[src*='doubleclick.net']", "iframe[src*='googlesyndication.com']", "[data-ad-slot]",
    "[id^='taboola-']", ".OUTBRAIN", "iframe[src*='exoclick.com']", "iframe[src*='popads.net']",
  ];

  // Khoá storage chứa rule của trang (site gốc nếu tên miền này dùng chung rule với tên miền khác).
  let siteStorageKey = "site:" + siteKey(HOST);
  let siteRules = { hide: [], popupDomains: [], blockDomains: [] };
  // Rule áp cho mọi trang.
  let globalRules = { hide: [], popupDomains: [] };
  // Công tắc trong popup: Chặn quảng cáo / Chống theo dõi / Chặn quảng cáo YouTube.
  let features = { ads: true, tracking: true, youtube: true };
  // Selector ẩn phần tử lấy từ bộ lọc (EasyList/ABPVN) qua background.
  const listSelectors = new Set();
  const seenTokens = new Set();
  let cosmeticStarted = false;
  let styleEl = null;
  let highlightEl = null;
  let marksEl = null;
  // id → {el, selector} của lần snapshot gần nhất.
  let candidateInfo = new Map();

  // ---------------------------------------------------------------- cấu hình

  async function loadConfig() {
    const { aliases, features: stored } = await browser.storage.local.get(["aliases", "features"]);
    features = { ads: true, tracking: true, youtube: true, ...(stored || {}) };
    siteStorageKey = "site:" + resolveSite(siteKey(HOST), aliases);
    const data = await browser.storage.local.get([siteStorageKey, "global"]);
    siteRules = { hide: [], popupDomains: [], blockDomains: [], ...(data[siteStorageKey] || {}) };
    globalRules = { hide: [], popupDomains: [], ...(data.global || {}) };
    applyConfig();
    startCosmetic();
  }

  const allHideRules = () => [...globalRules.hide, ...siteRules.hide];

  function applyConfig() {
    document.dispatchEvent(new CustomEvent("adsblocker:config", {
      detail: JSON.stringify({
        ads: features.ads,
        allowPopups: !!siteRules.allowPopups,
        tracking: features.tracking,
        youtube: features.youtube,
        popupDomains: [...globalRules.popupDomains, ...siteRules.popupDomains].map((r) => r.domain),
      }),
    }));
    applyStyle();
  }

  function applyStyle() {
    // Ngoại lệ "bỏ ẩn selector trên trang này" (từ chẩn đoán) gỡ selector khỏi mọi nguồn.
    const unhidden = new Set((siteRules.unhide || []).map((r) => r.selector));
    const selectors = features.ads ? [
      ...GENERIC_HIDE, `[${HIDDEN_ATTR}]`, ...listSelectors,
      ...allHideRules().flatMap((r) => [r.selector, ...(r.fallback || [])]),
    ].filter((s) => !unhidden.has(s)) : [];
    // Khối đã ẩn theo đường dẫn cấu trúc mang thuộc tính riêng → gỡ khi selector đó được bỏ ẩn.
    unhidden.forEach((s) => queryAll(s).forEach((n) => n.removeAttribute(HIDDEN_ATTR)));
    if (!styleEl) {
      styleEl = document.createElement("style");
      styleEl.setAttribute(OWN_ATTR, "style");
    }
    // Mỗi selector một khối: một selector hỏng không làm hỏng cả stylesheet.
    styleEl.textContent = selectors.map((s) => `${s} { display: none !important; }`).join("\n");
    if (!styleEl.isConnected) (document.head || document.documentElement).appendChild(styleEl);
    applyStructural();
  }

  function queryAll(selector) {
    try {
      return document.querySelectorAll(selector);
    } catch {
      return [];
    }
  }

  /**
   * Rule tự chọn lưu thêm đường dẫn :nth-of-type — chỉ dùng khi mọi selector CSS của rule không còn trúng
   * (trang đổi class). Đường dẫn cấu trúc dễ trúng nhầm khi bố cục đổi, nên chỉ ẩn khi trúng đúng 1 khối nhỏ.
   */
  function applyStructural() {
    if (!features.ads || !document.body) return;
    for (const rule of allHideRules()) {
      if (!rule.structural || [rule.selector, ...(rule.fallback || [])].some((s) => queryAll(s).length)) continue;
      if ((siteRules.unhide || []).some((r) => r.selector === rule.structural || r.selector === rule.selector)) continue;
      const nodes = queryAll(rule.structural);
      if (nodes.length !== 1 || nodes[0].hasAttribute(HIDDEN_ATTR)) continue;
      const r = nodes[0].getBoundingClientRect();
      if ((r.width * r.height) / pageArea() <= MAX_AREA_RATIO) nodes[0].setAttribute(HIDDEN_ATTR, "");
    }
  }

  let structuralTimer = 0;
  function scheduleStructural() {
    if (structuralTimer || !siteRules.hide.some((r) => r.structural)) return;
    structuralTimer = setTimeout(() => {
      structuralTimer = 0;
      applyStructural();
    }, 500);
  }

  browser.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !(changes[siteStorageKey] || changes.global || changes.aliases || changes.features)) return;
    loadConfig();
  });

  // Trang có thể xoá <style> của mình (anti-adblock) → gắn lại.
  new MutationObserver((records) => {
    if (styleEl && !styleEl.isConnected) applyStyle();
    scheduleOverlaySweep();
    scheduleStructural();
    if (cosmeticStarted) {
      for (const record of records) record.addedNodes.forEach((node) => queueTokens(collectTokens(node)));
    }
  }).observe(document, { childList: true, subtree: true });

  // ---------------------------------------------------------------- ẩn phần tử theo bộ lọc

  /** id/class mới xuất hiện trong `root` (dạng "#id", ".class") — bộ lọc chung chỉ gửi selector khớp các token này. */
  function collectTokens(root) {
    if (!(root instanceof Element)) return [];
    const fresh = [];
    for (const el of [root, ...root.querySelectorAll("[id],[class]")]) {
      const tokens = [...(el.id ? ["#" + el.id] : []), ...[...el.classList].map((c) => "." + c)];
      for (const token of tokens) {
        if (seenTokens.has(token)) continue;
        seenTokens.add(token);
        fresh.push(token);
      }
    }
    return fresh;
  }

  async function requestCosmetic(tokens, initial) {
    if (!features.ads) return;
    try {
      const reply = await browser.runtime.sendMessage({ type: "cosmetic", url: location.href, tokens, initial });
      const before = listSelectors.size;
      for (const selector of (reply && reply.ok && reply.result) || []) listSelectors.add(selector);
      if (listSelectors.size !== before) applyStyle();
    } catch {
      // Extension đang nạp lại/cập nhật — lần đổi DOM sau sẽ thử lại.
    }
  }

  let pendingTokens = [];
  let tokenTimer = 0;
  function queueTokens(tokens) {
    if (!tokens.length) return;
    pendingTokens.push(...tokens);
    if (tokenTimer) return;
    tokenTimer = setTimeout(() => {
      tokenTimer = 0;
      const batch = pendingTokens;
      pendingTokens = [];
      requestCosmetic(batch, false);
    }, 300);
  }

  /** Lần đầu (hoặc khi vừa bật "Chặn quảng cáo"): selector theo tên miền + chung luôn áp, rồi token đang có trên trang. */
  function startCosmetic() {
    if (!features.ads || cosmeticStarted) return;
    cosmeticStarted = true;
    requestCosmetic([], true);
    if (document.readyState !== "loading") queueTokens(collectTokens(document.documentElement));
  }

  // ---------------------------------------------------------------- log chặn

  function reportBlocked(kind, url, reason) {
    // Safari có thể ném lỗi ngay lúc gọi (không phải promise bị từ chối) khi extension đang nạp lại.
    (async () => {
      try {
        await browser.runtime.sendMessage({ type: "blocked", kind, url, reason });
      } catch {
        // Bỏ qua: chỉ là thống kê.
      }
    })();
  }

  document.addEventListener("adsblocker:blocked", (event) => {
    try {
      const { kind, url, reason } = JSON.parse(event.detail);
      reportBlocked(kind, url, reason);
    } catch {
      // detail không phải JSON → event giả từ trang.
    }
  });

  // ---------------------------------------------------------------- đặc trưng phần tử

  function hostOf(url) {
    try {
      return new URL(url, location.href).hostname.toLowerCase();
    } catch {
      return "";
    }
  }

  const isThirdParty = (url) => {
    const host = hostOf(url);
    return !!host && siteKey(host) !== siteKey(HOST);
  };

  function isTransparentColor(color) {
    return color === "transparent" || /rgba\(.*,\s*0(\.0+)?\)$/.test(color);
  }

  function featuresOf(el, rect, style) {
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const visibleW = Math.max(0, Math.min(rect.right, vw) - Math.max(rect.left, 0));
    const visibleH = Math.max(0, Math.min(rect.bottom, vh) - Math.max(rect.top, 0));
    const tag = el.tagName.toLowerCase();
    const fixed = style.position === "fixed";
    const absolute = style.position === "absolute";
    const transparent = Number(style.opacity) < 0.1 ||
      (isTransparentColor(style.backgroundColor) && style.backgroundImage === "none");
    // Nội dung chỉ cần đo khi có thể là lớp phủ (đắt với phần tử lớn).
    const maybeOverlay = (fixed || absolute) && transparent;
    const className = typeof el.className === "string" ? el.className : (el.getAttribute("class") || "");
    return {
      tag,
      idClass: [el.id, className, el.getAttribute("aria-label"), el.getAttribute("src"),
        ...[...el.attributes].map((a) => a.name).filter((n) => n.startsWith("data-ad"))].join(" "),
      thirdPartyFrame: tag === "iframe" && isThirdParty(el.src),
      fixed,
      absolute,
      sticky: style.position === "sticky",
      zIndex: parseInt(style.zIndex, 10) || 0,
      width: rect.width,
      height: rect.height,
      viewportRatio: (visibleW * visibleH) / (vw * vh),
      transparent,
      pointerEventsNone: style.pointerEvents === "none",
      textLength: maybeOverlay ? (el.textContent || "").trim().length : Infinity,
      hasMedia: maybeOverlay ? !!el.querySelector("img,video,canvas,svg,iframe,picture,input,textarea") : true,
      thirdPartyLinks: tag === "a" && el.target === "_blank" && isThirdParty(el.href) ? 1 : 0,
    };
  }

  // ---------------------------------------------------------------- lớp phủ bắt click

  function overlayAt(target) {
    for (let el = target, depth = 0; el && el !== document.body && el !== document.documentElement && depth < 6;
      el = el.parentElement, depth++) {
      if (el.hasAttribute(OWN_ATTR)) return null;
      const f = featuresOf(el, el.getBoundingClientRect(), getComputedStyle(el));
      if (isInvisibleOverlay(f)) return el;
    }
    return null;
  }

  function removeOverlay(el, how) {
    reportBlocked("overlay", el.querySelector("a[href]")?.href || el.getAttribute("href") || "", how);
    el.remove();
  }

  function sweepOverlays() {
    if (!features.ads || siteRules.keepOverlays || !document.body) return;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    for (const fx of [0.25, 0.5, 0.75]) {
      for (const fy of [0.25, 0.5, 0.75]) {
        const el = overlayAt(document.elementFromPoint(vw * fx, vh * fy));
        if (el) removeOverlay(el, "lớp phủ trong suốt");
      }
    }
  }

  let sweepTimer = 0;
  const sweepUntil = performance.now() + OVERLAY_SWEEP_MS;
  function scheduleOverlaySweep() {
    if (sweepTimer || performance.now() > sweepUntil) return;
    sweepTimer = setTimeout(() => {
      sweepTimer = 0;
      sweepOverlays();
    }, 800);
  }

  // Lưới an toàn khi lớp phủ xuất hiện sau thời gian quét: gỡ ngay lúc người dùng chạm vào nó.
  // KHÔNG preventDefault cho pointerdown/touchstart: lớp phủ trong suốt phủ kín màn hình nên mọi cú chạm đều trúng
  // nó trước, mà chặn mặc định ở touchstart/pointerdown thì iOS huỷ luôn thao tác cuộn → trang không vuốt được
  // (chỉ bấm được). Cú chạm đã bị stopImmediatePropagation nên script của trang không thấy; chặn click là đủ để
  // không mở link/tab quảng cáo. Listener cũng phải khai báo passive ở các loại còn lại, nếu không trình duyệt vẫn
  // coi cú chạm là "có thể bị chặn" và hoãn việc cuộn tới khi xử lý xong.
  for (const type of ["pointerdown", "touchstart", "mousedown", "click"]) {
    const cancelClick = type === "click";
    window.addEventListener(type, (event) => {
      if (!features.ads || siteRules.keepOverlays || !event.isTrusted) return;
      const target = event.composedPath()[0];
      const el = overlayAt(target instanceof Element ? target : target?.parentElement);
      if (!el) return;
      if (cancelClick) event.preventDefault();
      event.stopImmediatePropagation();
      removeOverlay(el, "chạm vào lớp phủ trong suốt");
    }, { capture: true, passive: !cancelClick });
  }

  // ---------------------------------------------------------------- snapshot cho AI

  function isUniqueFor(selector, el) {
    try {
      const nodes = document.querySelectorAll(selector);
      return nodes.length === 1 && nodes[0] === el;
    } catch {
      return false;
    }
  }

  /** Selector ưu tiên id/class có nghĩa; hết cách mới dùng :nth-of-type. */
  function stableSelector(el) {
    const parts = [];
    for (let node = el; node && node !== document.documentElement && parts.length < 5; node = node.parentElement) {
      let part = node.tagName.toLowerCase();
      if (node.id && !isRandomToken(node.id) && !/^\d/.test(node.id)) {
        parts.unshift("#" + CSS.escape(node.id));
        const selector = parts.join(" > ");
        if (isUniqueFor(selector, el)) return selector;
        continue;
      }
      const classes = [...node.classList].filter((c) => !isRandomToken(c)).slice(0, 3);
      if (classes.length) part += classes.map((c) => "." + CSS.escape(c)).join("");
      else if (node.tagName === "IFRAME" && hostOf(node.src)) part += `[src*="${hostOf(node.src)}"]`;
      parts.unshift(part);
      const selector = parts.join(" > ");
      if (isUniqueFor(selector, el)) return selector;
    }
    return structuralPath(el);
  }

  /** Đường dẫn :nth-of-type từ body (tối đa 12 cấp) — không phụ thuộc class/id. */
  function structuralPath(el) {
    const path = [];
    let node = el;
    for (; node && node !== document.body && node.parentElement && path.length < 12; node = node.parentElement) {
      const index = [...node.parentElement.children].filter((c) => c.tagName === node.tagName).indexOf(node) + 1;
      path.unshift(`${node.tagName.toLowerCase()}:nth-of-type(${index})`);
    }
    return (node === document.body ? "body > " : "") + path.join(" > ");
  }

  /** outerHTML bỏ chữ (tránh gửi nội dung riêng tư), cắt ngắn thuộc tính. */
  function strippedHtml(el) {
    const clone = el.cloneNode(el.getElementsByTagName("*").length <= 150);
    const walker = document.createTreeWalker(clone, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    const drop = [];
    for (let node = walker.currentNode; node; node = walker.nextNode()) {
      if (node.nodeType === Node.TEXT_NODE) drop.push(node);
      else if (/^(SCRIPT|STYLE|svg|NOSCRIPT)$/.test(node.tagName)) node.replaceChildren();
      if (node.nodeType === Node.ELEMENT_NODE) {
        for (const attr of [...node.attributes]) {
          if (/^(value|placeholder|title|alt)$/.test(attr.name)) node.removeAttribute(attr.name);
          else if (attr.value.length > 100) node.setAttribute(attr.name, attr.value.slice(0, 100) + "…");
        }
      }
    }
    drop.forEach((n) => n.remove());
    return clone.outerHTML.slice(0, 600);
  }

  function sameBox(a, b) {
    return Math.abs(a.left - b.left) < 4 && Math.abs(a.top - b.top) < 4 &&
      Math.abs(a.width - b.width) < 4 && Math.abs(a.height - b.height) < 4;
  }

  function collectCandidates() {
    const found = [];
    const chosen = new Map();
    const all = document.body ? document.body.getElementsByTagName("*") : [];
    for (let i = 0; i < Math.min(all.length, MAX_SCAN_ELEMENTS); i++) {
      const el = all[i];
      if (el.hasAttribute(OWN_ATTR) || /^(SCRIPT|STYLE|LINK|META|NOSCRIPT|BR|TEMPLATE|SOURCE)$/.test(el.tagName)) continue;
      const rect = el.getBoundingClientRect();
      if (rect.width < 20 || rect.height < 20) continue;
      const style = getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden") continue;

      const { score, hints, isCandidate } = scoreCandidate(featuresOf(el, rect, style));
      if (!isCandidate) continue;
      let parent = el.parentElement;
      while (parent && !chosen.has(parent)) parent = parent.parentElement;
      if (parent && sameBox(chosen.get(parent), rect)) continue;
      chosen.set(el, rect);
      found.push({ el, rect, score, hints });
    }
    return found.sort((a, b) => b.score - a.score).slice(0, MAX_CANDIDATES);
  }

  function resourceDomains() {
    const counts = new Map();
    for (const entry of performance.getEntriesByType("resource")) {
      const host = hostOf(entry.name);
      if (!host || !isThirdParty(entry.name)) continue;
      const item = counts.get(host) || { domain: host, count: 0, types: new Set() };
      item.count++;
      item.types.add(entry.initiatorType);
      counts.set(host, item);
    }
    return [...counts.values()]
      .sort((a, b) => b.count - a.count)
      .slice(0, 60)
      .map((d) => ({ domain: d.domain, count: d.count, types: [...d.types], adLike: hasAdWord(d.domain) }));
  }

  // ---------------------------------------------------------------- chẩn đoán trang bị lỗi

  const LAZY_ATTRS = ["data-src", "data-original", "data-lazy-src", "data-srcset", "data-lazy", "data-url"];
  // Mặc định trình duyệt chỉ giữ ~250 mục resource timing → trang nhiều tài nguyên có thể báo "không tải" sai.
  const TIMING_BUFFER = 250;

  function shortUrl(url) {
    try {
      const u = new URL(url, location.href);
      return { domain: u.hostname, path: (u.pathname + u.search).slice(0, 100) };
    } catch {
      return null;
    }
  }

  /** Mọi selector extension đang dùng để ẩn, kèm nguồn — để chẩn đoán biết khối nào bị ẩn bởi rule nào. */
  function appliedSelectors() {
    const fromRules = (rules, source) => rules.flatMap((r) =>
      [r.selector, ...(r.fallback || [])].map((selector) => ({ selector, source, ruleId: r.id, origin: r.source })));
    return [
      ...GENERIC_HIDE.map((selector) => ({ selector, source: "builtin" })),
      ...[...listSelectors].map((selector) => ({ selector, source: "filter" })),
      ...fromRules(siteRules.hide, "site"),
      ...fromRules(globalRules.hide, "global"),
      ...siteRules.hide.filter((r) => r.structural)
        .map((r) => ({ selector: r.structural, source: "structural", ruleId: r.id, origin: r.source })),
    ];
  }

  /** Dấu hiệu trang hỏng: ảnh lỗi, ảnh lazy-load chưa nạp, tài nguyên không tải, khối đang bị extension ẩn. */
  function diagnostics() {
    const entries = performance.getEntriesByType("resource");
    const loaded = new Set(entries.map((e) => e.name));
    const brokenImages = [];
    const lazyImages = [];
    for (const img of document.images) {
      const lazy = LAZY_ATTRS.map((a) => img.getAttribute(a)).find(Boolean);
      const src = img.currentSrc || img.src;
      if (lazy && (!src || src.startsWith("data:") || /placeholder|blank|loading|lazy|spacer/i.test(src))) {
        lazyImages.push(shortUrl(lazy.split(/[\s,]/)[0]));
      } else if (src && !src.startsWith("data:") && img.complete && img.naturalWidth === 0) {
        brokenImages.push(shortUrl(src));
      }
    }
    const notLoaded = [];
    for (const el of document.querySelectorAll("script[src], iframe[src], link[rel=stylesheet][href]")) {
      const url = el.src || el.href;
      if (/^https?:/.test(url) && !loaded.has(url)) notLoaded.push({ ...shortUrl(url), type: el.tagName.toLowerCase() });
    }
    const hidden = [];
    const seen = new Set();
    for (const item of appliedSelectors()) {
      if (seen.has(item.selector)) continue;
      seen.add(item.selector);
      let nodes = [...queryAll(item.selector)];
      if (item.source === "structural") nodes = nodes.filter((n) => n.hasAttribute(HIDDEN_ATTR));
      if (!nodes.length) continue;
      const media = nodes.filter((n) => n.matches("img, video, picture, canvas") || n.querySelector("img, video, picture, canvas")).length;
      hidden.push({ ...item, count: nodes.length, media });
    }
    hidden.sort((a, b) => b.media - a.media || b.count - a.count);
    return {
      url: location.origin + location.pathname,
      title: document.title.slice(0, 120),
      brokenImages: brokenImages.filter(Boolean).slice(0, 20),
      lazyImages: lazyImages.filter(Boolean).slice(0, 20),
      notLoaded: notLoaded.filter((r) => r.domain).slice(0, 40),
      hidden: hidden.slice(0, 40),
      totalImages: document.images.length,
      timingFull: entries.length >= TIMING_BUFFER,
    };
  }

  /**
   * Domain bên thứ ba của trang cho báo cáo theo dõi. `loaded`: có trong resource timing (đã tải được);
   * chỉ có trong DOM (src của script/iframe/img) mà không tải được → nhiều khả năng đã bị chặn.
   */
  function thirdParties() {
    const items = new Map();
    const item = (host) => {
      if (!items.has(host)) items.set(host, { domain: host, count: 0, types: new Set(), loaded: false });
      return items.get(host);
    };
    for (const entry of performance.getEntriesByType("resource")) {
      if (!isThirdParty(entry.name)) continue;
      const it = item(hostOf(entry.name));
      it.count++;
      it.loaded = true;
      it.types.add(entry.initiatorType);
    }
    for (const el of document.querySelectorAll("script[src], iframe[src], img[src]")) {
      if (!isThirdParty(el.src)) continue;
      const it = item(hostOf(el.src));
      it.types.add(el.tagName.toLowerCase());
      if (!it.loaded) it.count++;
    }
    return [...items.values()]
      .sort((a, b) => b.count - a.count)
      .slice(0, 150)
      .map((d) => ({ ...d, types: [...d.types] }));
  }

  function drawMarks(items) {
    clearMarks();
    marksEl = document.createElement("div");
    marksEl.setAttribute(OWN_ATTR, "marks");
    marksEl.style.cssText = "position:fixed;inset:0;z-index:2147483647;pointer-events:none;";
    for (const { id, el } of items) {
      const r = el.getBoundingClientRect();
      if (r.bottom < 0 || r.top > window.innerHeight || r.right < 0 || r.left > window.innerWidth) continue;
      const box = document.createElement("div");
      box.style.cssText = `position:absolute;left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;` +
        "border:2px solid #ff1744;box-sizing:border-box;";
      const label = document.createElement("span");
      label.textContent = String(id);
      label.style.cssText = "position:absolute;left:0;top:0;background:#ff1744;color:#fff;" +
        "font:bold 13px/1.2 -apple-system,sans-serif;padding:1px 4px;";
      box.appendChild(label);
      marksEl.appendChild(box);
    }
    document.documentElement.appendChild(marksEl);
  }

  function clearMarks() {
    marksEl?.remove();
    marksEl = null;
  }

  // Chờ khung số được vẽ trước khi chụp; tab không được render thì rAF không chạy → hết giờ vẫn đi tiếp.
  const nextFrame = () => Promise.race([
    new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
    new Promise((resolve) => setTimeout(resolve, 150)),
  ]);

  async function snapshot() {
    const found = collectCandidates();
    candidateInfo = new Map(found.map((c, i) => [i + 1, { el: c.el, selector: stableSelector(c.el) }]));
    const candidates = found.map((c, i) => ({
      id: i + 1,
      selector: candidateInfo.get(i + 1).selector,
      tag: c.el.tagName.toLowerCase(),
      rect: {
        x: Math.round(c.rect.left + window.scrollX), y: Math.round(c.rect.top + window.scrollY),
        w: Math.round(c.rect.width), h: Math.round(c.rect.height),
      },
      inViewport: c.rect.bottom > 0 && c.rect.top < window.innerHeight,
      hints: c.hints,
      html: strippedHtml(c.el),
    }));
    drawMarks([...candidateInfo].map(([id, { el }]) => ({ id, el })));
    await nextFrame();
    return {
      host: HOST,
      page: {
        url: location.origin + location.pathname,
        title: document.title.slice(0, 120),
        viewport: { w: window.innerWidth, h: window.innerHeight, scrollY: Math.round(window.scrollY) },
        candidates,
        resourceDomains: resourceDomains(),
      },
    };
  }

  // ---------------------------------------------------------------- đo / highlight rule

  function pageArea() {
    const doc = document.documentElement;
    return Math.max(doc.scrollWidth * doc.scrollHeight, window.innerWidth * window.innerHeight);
  }

  function measure(selector, candidateId) {
    return measureFor(selector, candidateInfo.get(candidateId)?.el);
  }

  /** Selector trúng bao nhiêu khối, chiếm bao nhiêu diện tích trang, có trúng `candidate` không. */
  function measureFor(selector, candidate) {
    let nodes;
    try {
      nodes = [...document.querySelectorAll(selector)];
    } catch {
      return { valid: false };
    }
    const area = nodes.reduce((sum, n) => {
      const r = n.getBoundingClientRect();
      return sum + r.width * r.height;
    }, 0);
    return {
      valid: true,
      count: nodes.length,
      areaRatio: area / pageArea(),
      includesCandidate: !!candidate && nodes.some((n) => n === candidate || n.contains(candidate)),
    };
  }

  function validate(rules) {
    return globalThis.AdsBlockerRules.validateRules(rules, { pageHost: HOST, candidates: candidateInfo, measure });
  }

  function highlight(selectors) {
    highlightEl?.remove();
    highlightEl = null;
    if (!selectors.length) return;
    highlightEl = document.createElement("style");
    highlightEl.setAttribute(OWN_ATTR, "highlight");
    highlightEl.textContent = selectors
      .map((s) => `${s} { outline: 3px solid #ff1744 !important; outline-offset: -3px !important; }`)
      .join("\n");
    document.documentElement.appendChild(highlightEl);
    try {
      document.querySelector(selectors[0])?.scrollIntoView({ block: "center", behavior: "smooth" });
    } catch {
      // selector đã được validate; lỗi chỉ khi DOM đổi — bỏ qua cuộn.
    }
  }

  // Listener onMessage DUY NHẤT của content script: khi có nhiều listener, Safari iOS trả về background
  // `undefined` dù listener này đã trả kết quả (picker.js từng có listener riêng → quét/chẩn đoán luôn lỗi).
  if (IS_TOP) {
    browser.runtime.onMessage.addListener((message) => {
      switch (message && message.type) {
        case "snapshot": return snapshot();
        case "clearMarks": clearMarks(); return Promise.resolve(true);
        case "validate": return Promise.resolve(validate(message.rules));
        case "highlight": highlight(message.selectors || []); return Promise.resolve(true);
        case "thirdParties": return Promise.resolve(thirdParties());
        case "diagnostics": return Promise.resolve(diagnostics());
        case "startPicker": globalThis.AdsBlockerPicker.start(); return Promise.resolve(true);
        default: return undefined;
      }
    });
  }

  // Dùng chung cho content/picker.js (cùng isolated world, nạp sau file này).
  globalThis.AdsBlockerContent = {
    OWN_ATTR, HOST, IS_TOP, hostOf, stableSelector, structuralPath, strippedHtml, resourceDomains, measureFor,
  };

  // ---------------------------------------------------------------- khởi động

  loadConfig();
  document.addEventListener("DOMContentLoaded", () => {
    applyConfig();
    sweepOverlays();
    if (cosmeticStarted) queueTokens(collectTokens(document.documentElement));
  });
  window.addEventListener("load", sweepOverlays);
})();
