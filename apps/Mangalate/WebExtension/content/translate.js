// Content script: bóc ảnh truyện → nhờ appex OCR trên máy → gửi text qua background lên Gemini → dán bản dịch
// đè lên đúng vị trí bong bóng. Không bao giờ gửi ảnh cho AI.
(() => {
  "use strict";
  if (globalThis.__mangalateLoaded) return;
  globalThis.__mangalateLoaded = true;

  const core = globalThis.MangalateCore;
  if (!core) return;

  const MAX_IMAGES = 60;
  const MAX_TILE_W = 1400;
  const MAX_TILE_H = 1600;
  const TILE_OVERLAP = 0.08;
  const JPEG_QUALITY = 0.7;
  const MAX_REQUEST_CHARS = 8000;
  const MAX_REQUEST_BLOCKS = 300;
  const MIN_IMG_WIDTH = 280;
  const MIN_IMG_HEIGHT = 180;
  const MAX_LINES_PER_IMAGE = 400;
  const LAZY_WAIT_MS = 1500;
  const PREPARE_BUDGET_MS = 20000;
  const CACHE_INDEX_KEY = "mangalate:cache-index";
  const CACHE_MAX_ENTRIES = 400;
  const MODEL_KEY = "mangalateModel";
  // Chỉ các trang trong danh sách này mới hiện nút Dịch — tránh nút thừa trên trang tiếng Việt.
  const SITES_KEY = "mangalate:sites";

  const state = {
    phase: "idle", // idle | running | cached | showing | hidden
    cancelled: false,
    blocks: [],
    rendered: 0,
    model: "",
    cacheChecked: false,
    renderedSrcs: new Set(),
    ui: null,
    layoutFrame: 0,
  };

  // ---------------------------------------------------------------- UI (shadow DOM)

  function ui() {
    if (state.ui) return state.ui;
    const host = document.createElement("div");
    host.id = "mangalate-ui";
    host.style.cssText = "all:initial;position:absolute!important;left:0!important;top:0!important;width:0!important;height:0!important;z-index:2147483646!important;pointer-events:none!important;";
    const shadow = host.attachShadow({ mode: "open" });
    shadow.innerHTML = `
      <style>
        .layer { position: absolute; left: 0; top: 0; width: 0; height: 0; pointer-events: none; }
        .layer[hidden] { display: none; }
        .backdrops { position: absolute; left: 0; top: 0; width: 0; height: 0; pointer-events: none; }
        .backdrops[hidden] { display: none; }
        .backdrop { position: absolute; border-radius: 4px; }
        .block { position: absolute; display: flex; align-items: center; justify-content: center; box-sizing: border-box; overflow: visible; text-align: center; font-family: -apple-system, "Helvetica Neue", "Segoe UI", sans-serif; line-height: 1.15; font-weight: 600; padding: 1px 3px; pointer-events: auto; -webkit-user-select: text; user-select: text; white-space: normal; overflow-wrap: normal; word-break: normal; hyphens: none; }
        .block > span { display: block; width: 100%; max-width: 100%; position: relative; }

        .fab { position: fixed; right: 14px; bottom: calc(18px + env(safe-area-inset-bottom)); z-index: 3; pointer-events: auto; border: 0; border-radius: 999px; padding: 11px 17px; font: 600 15px/1.2 -apple-system, "Helvetica Neue", sans-serif; color: #fff; background: #4f46e5; box-shadow: 0 4px 16px rgba(0, 0, 0, .35); }
        .fab.running { background: #111827; }
        .fab[hidden] { display: none; }
        .panel { position: fixed; left: 12px; right: 12px; bottom: calc(78px + env(safe-area-inset-bottom)); z-index: 3; padding: 14px 16px; border-radius: 14px; background: #fff; color: #111; box-shadow: 0 8px 30px rgba(0, 0, 0, .35); font: 14px/1.45 -apple-system, "Helvetica Neue", sans-serif; pointer-events: auto; }
        .panel[hidden] { display: none; }
        .panel b { display: block; margin-bottom: 6px; font-size: 15px; }
        .panel p { margin: 0 0 10px; }
        .panel .row { display: flex; gap: 8px; justify-content: flex-end; }
        .panel button { border: 0; border-radius: 10px; padding: 9px 14px; font: 600 14px -apple-system, "Helvetica Neue", sans-serif; }
        .panel .primary { background: #4f46e5; color: #fff; }
        .panel .secondary { background: #eef0f4; color: #111; }
      </style>
      <div class="backdrops"></div>
      <div class="layer"></div>
      <button class="fab" hidden>Dịch</button>
      <div class="panel" hidden></div>
    `;
    document.documentElement.appendChild(host);
    const parts = {
      host,
      backdrops: shadow.querySelector(".backdrops"),
      layer: shadow.querySelector(".layer"),
      fab: shadow.querySelector(".fab"),
      panel: shadow.querySelector(".panel"),
    };
    parts.fab.addEventListener("click", onFab);
    state.ui = parts;
    return parts;
  }

  function showPanel(title, message, actions) {
    const { panel } = ui();
    panel.replaceChildren();
    const heading = document.createElement("b");
    heading.textContent = title;
    panel.appendChild(heading);
    if (message) {
      const text = document.createElement("p");
      text.textContent = message;
      panel.appendChild(text);
    }
    const row = document.createElement("div");
    row.className = "row";
    for (const action of actions || []) {
      const button = document.createElement("button");
      button.className = action.primary ? "primary" : "secondary";
      button.textContent = action.label;
      button.addEventListener("click", () => {
        hidePanel();
        if (action.run) action.run();
      });
      row.appendChild(button);
    }
    panel.appendChild(row);
    panel.hidden = false;
  }

  function hidePanel() {
    if (state.ui) state.ui.panel.hidden = true;
  }

  /** Lỗi không gọi được background/native. Tab cũ sau khi cập nhật app thì cho nút tải lại trang. */
  function showAskError(error) {
    const stale = !!(error && (error.stale || isStaleContextError(error)));
    const actions = [{ label: "Đóng", run: () => {} }];
    if (stale) actions.push({ label: "Tải lại trang", primary: true, run: () => location.reload() });
    showPanel("Không gọi được extension", (error && error.message) || String(error), actions);
  }

  /** Trang hiện tại có nằm trong danh sách được dịch không (khớp cả tên miền con). */
  async function siteAllowed() {
    let sites = [];
    try {
      const data = await browser.storage.local.get(SITES_KEY);
      sites = Array.isArray(data[SITES_KEY]) ? data[SITES_KEY] : [];
    } catch {
      return false;
    }
    const host = location.hostname.toLowerCase();
    return sites.some((site) => {
      const value = String(site || "").trim().toLowerCase();
      return value && (host === value || host.endsWith("." + value));
    });
  }

  function setFab(text, running) {
    const { fab } = ui();
    fab.hidden = !text;
    fab.textContent = text;
    fab.classList.toggle("running", !!running);
  }

  function setLayerVisible(visible) {
    ui().layer.hidden = !visible;
    ui().backdrops.hidden = !visible;
  }

  // ---------------------------------------------------------------- nút nổi

  function onFab() {
    if (state.phase === "running") {
      state.cancelled = true;
      setFab("Đang dừng…", true);
      return;
    }
    if (state.phase === "showing") {
      setLayerVisible(false);
      state.phase = "hidden";
      setFab("Bản dịch", false);
      return;
    }
    if (state.phase === "hidden") {
      setLayerVisible(true);
      state.phase = "showing";
      setFab("Bản gốc", false);
      return;
    }
    start();
  }

  function hasCandidateImages() {
    for (const image of document.images) {
      const rect = image.getBoundingClientRect();
      if (rect.width >= 200 && rect.height >= 120 && rect.width * rect.height >= 20000) return true;
    }
    for (const canvas of document.querySelectorAll("canvas")) {
      if (canvas.width >= MIN_IMG_WIDTH && canvas.height >= MIN_IMG_HEIGHT) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- luồng dịch

  async function start() {
    if (state.phase === "running") return;
    hidePanel();

    const consented = await storageGet("consentAccepted");
    if (!consented) {
      showPanel(
        "Dịch truyện bằng AI",
        "Ảnh truyện chỉ được đọc trên máy. Chỉ phần CHỮ (đã OCR) được gửi lên Google Gemini để dịch, bằng API key của bạn. Ảnh không bao giờ được gửi đi.",
        [
          { label: "Huỷ", run: () => {} },
          {
            label: "Đồng ý và dịch",
            primary: true,
            run: async () => {
              await storageSet("consentAccepted", true);
              start();
            },
          },
        ]
      );
      return;
    }

    let settings;
    try {
      settings = await ask({ type: "getSettings" });
    } catch (error) {
      showAskError(error);
      return;
    }
    if (!settings.hasKey) {
      showPanel(
        "Chưa có Gemini API key",
        "Mở biểu tượng ô ghép hình trên thanh địa chỉ → Mangalate → nhập API key rồi bấm Lưu key.",
        [{ label: "Đã hiểu", run: () => {} }]
      );
      return;
    }

    // Đang hiện bản dịch cache của đúng model → chỉ dịch thêm phần còn thiếu, không xoá overlay cũ.
    const resumed = state.phase === "cached" && state.blocks.length > 0 && state.model === (settings.model || "");
    state.phase = "running";
    state.cancelled = false;
    state.model = settings.model || "";
    if (!resumed) resetLayer();
    setFab("Đang tìm ảnh…", true);
    try {
      await translatePage();
    } catch (error) {
      log(`lỗi dịch: ${error.message || error}`);
      if (!state.cancelled) {
        if (error && error.stale) {
          showAskError(error);
        } else {
          showPanel("Dịch thất bại", error.message || String(error), [{ label: "Đóng", run: () => {} }]);
        }
      }
      state.phase = state.rendered ? "showing" : "idle";
      setFab(state.rendered ? "Bản gốc" : "Dịch", false);
    }
    if (state.cancelled) {
      state.phase = state.rendered ? "showing" : "idle";
      setFab(state.rendered ? "Bản gốc" : "Dịch", false);
    }
  }

  async function translatePage() {
    logLines = [];
    diag = { model: state.model, phase: "chạy", total: 0, sent: 0, translated: 0, shaped: 0, covered: 0, dropped: [], kept: [], missing: [], fromCacheOnly: false };
    const images = await prepareImages();
    if (state.cancelled) return;
    if (!images.length) {
      state.phase = "idle";
      setFab("Dịch", false);
      showPanel("Không thấy ảnh truyện", "Trang này không có ảnh đủ lớn để đọc chữ.", [{ label: "Đóng", run: () => {} }]);
      return;
    }
    log(`bắt đầu: ${images.length} ảnh`);

    // Cache theo URL ảnh + model: ảnh đã dịch thì bỏ qua cả OCR lẫn gọi Gemini.
    const keys = images.map((image) => cacheKeyFor(image, state.model));
    const cached = await Promise.all(keys.map((key) => (key ? cacheGet(key) : null)));
    const results = new Array(images.length);
    cached.forEach((entry, index) => {
      if (entry) results[index] = { cached: entry };
    });
    const ocrTotal = results.filter((result) => !result).length;
    log(`cache: ${images.length - ocrTotal}/${images.length} ảnh có sẵn`);

    // Dán phần đã cache trước để vào chapter thấy ngay bản dịch cũ; OCR phần còn lại sau.
    let blocks = state.blocks;
    const fromCache = [];
    images.forEach((image, index) => {
      const result = results[index];
      if (!result || !result.cached) return;
      if (state.renderedSrcs.has(image.src)) return;
      state.renderedSrcs.add(image.src);
      for (const block of result.cached) {
        const rebuilt = { ...block, id: blocks.length + 1, imageIndex: index, image: image.el, fromCache: true };
        blocks.push(rebuilt);
        fromCache.push(rebuilt);
      }
    });
    if (fromCache.length) {
      state.blocks = blocks;
      core.layoutTextAreas(fromCache);
      for (const block of fromCache) renderBlock(block, block.translation);
    }

    let done = 0;
    let failed = 0;
    let next = 0;
    const workers = Array.from({ length: 2 }, async () => {
      while (!state.cancelled) {
        const index = next++;
        if (index >= images.length) return;
        if (results[index]) continue;
        try {
          results[index] = await readImage(images[index]);
        } catch (error) {
          failed += 1;
          log(`ảnh ${index} lỗi: ${error.message || error}`);
        }
        done += 1;
        if (!state.cancelled) setFab(`Đang đọc chữ ${done}/${ocrTotal}`, true);
      }
    });
    await Promise.all(workers);
    if (state.cancelled) return;

    images.forEach((image, index) => {
      const result = results[index];
      if (!result || result.cached) return;
      if (!result.lines || !result.lines.length) return;
      for (const block of core.groupLines(result.lines, image.width, image.height)) {
        blocks.push({
          ...block,
          id: blocks.length + 1,
          imageIndex: index,
          image: image.el,
        });
      }
    });
    const speech = core.selectSpeechBlocks(blocks);
    diag.total = blocks.length;
    diag.sent = speech.length;
    if (speech.length !== blocks.length) {
      // Log chi tiết vài block bị loại để chỉnh ngưỡng từ log máy (không gửi đi đâu).
      const dropped = blocks.filter((block) => !speech.includes(block));
      const sample = dropped.slice(0, 6).map((block) => `「${block.text.slice(0, 24)}」fill=${block.fill.toFixed(2)} ô=${Number(block.enclose || 0).toFixed(2)} nền=${block.bg}`);
      log(`bỏ ${dropped.length}/${blocks.length} block ngoài ô hội thoại: ${sample.join(" | ")}`);
      diag.dropped = dropped
        .map((block) => ({
          text: block.text.slice(0, 60),
          fill: Number(block.fill || 0).toFixed(2),
          enclose: Number(block.enclose || 0).toFixed(2),
          bg: block.bg,
          light: core.isBubbleBackground(block.bg),
        }))
        // Nền trắng trước: đó mới là ứng viên ô thoại bị bỏ oan, SFX nền màu thì đúng là phải bỏ.
        .sort((a, b) => Number(b.light) - Number(a.light) || Number(b.fill) - Number(a.fill))
        .slice(0, 200);
    }
    // Chữ dịch không được chồng lên nhau: chia vùng đặt chữ giữa các block cùng ảnh.
    core.layoutTextAreas(speech);
    for (const block of speech) {
      if (block.el) placeBlock(block);
    }
    state.blocks = speech;
    blocks = speech;
    log(`OCR xong: ${blocks.length} block (${fromCache.length} từ cache), ${failed} ảnh lỗi`);
    if (!blocks.length) {
      state.phase = "idle";
      setFab("Dịch", false);
      showPanel(
        "Không đọc được chữ",
        "Không nhận ra chữ nào trên các ảnh này (truyện không lời, ảnh mờ hoặc chữ quá cách điệu).",
        [{ label: "Đóng", run: () => {} }]
      );
      return;
    }

    const pending = blocks.filter((block) => !block.fromCache);
    if (!pending.length) {
      diag.fromCacheOnly = true;
      state.phase = "showing";
      setFab("Bản gốc", false);
      log(`dùng cache: ${blocks.length} block (không gọi AI)`);
      return;
    }

    // Lập hồ sơ nhân vật/giới tính/cách xưng hô cho cả chapter (chỉ text) để model dịch nhất quán.
    let context = "";
    try {
      setFab("Đang hiểu ngữ cảnh", true);
      const reply = await ask({
        type: "native",
        payload: { action: "analyze", blocks: pending.map((block) => ({ id: block.id, text: block.text })) },
      });
      context = String(reply.context || "");
      log(`ngữ cảnh chapter: ${context.length} ký tự`);
    } catch (error) {
      log(`phân tích ngữ cảnh lỗi: ${error.message || error}`);
    }
    if (state.cancelled) return;

    // Mỗi ảnh xong đủ block là lưu cache ngay — huỷ giữa chừng vẫn giữ phần đã dịch.
    const stats = new Map();
    for (const block of pending) {
      if (!stats.has(block.imageIndex)) stats.set(block.imageIndex, { total: 0, done: 0 });
      stats.get(block.imageIndex).total += 1;
    }
    const savedImages = new Set();

    async function translateBatch(batch) {
      const payload = batch.filter((block) => !block.translation).map((block) => ({ id: block.id, text: block.text }));
      if (!payload.length) return;
      const reply = await ask({
        type: "native",
        payload: context ? { action: "translate", blocks: payload, context } : { action: "translate", blocks: payload },
      });
      const byId = new Map((reply.translations || []).map((item) => [Number(item.id), String(item.text || "").trim()]));
      for (const block of batch) {
        if (block.translation) continue;
        const translated = byId.get(block.id);
        if (!translated) continue;
        renderBlock(block, translated);
        const stat = stats.get(block.imageIndex);
        stat.done += 1;
        if (stat.done === stat.total && !savedImages.has(block.imageIndex)) {
          savedImages.add(block.imageIndex);
          const key = keys[block.imageIndex];
          if (key) {
            await cacheSet(key, pending.filter((item) => item.imageIndex === block.imageIndex && item.translation));
          }
        }
      }
    }

    // Chapter thường gói gọn 1 request; chỉ chapter rất dài mới chia theo số ký tự.
    const batches = core.batchByChars(pending, MAX_REQUEST_CHARS, MAX_REQUEST_BLOCKS);
    log(`dịch ${pending.length} block trong ${batches.length} request`);
    for (let index = 0; index < batches.length; index++) {
      if (state.cancelled) return;
      setFab(batches.length > 1 ? `Đang dịch ${index + 1}/${batches.length}` : "Đang dịch", true);
      await translateBatch(batches[index]);
    }
    // Model có thể bỏ sót id hoặc cắt JSON → dịch lại phần thiếu. Lần 2 gửi từng block một:
    // request nhỏ khó bị bỏ sót/kiểm duyệt hơn cả loạt.
    for (let attempt = 0; attempt < 2 && !state.cancelled; attempt++) {
      const missing = pending.filter((block) => !block.translation);
      if (!missing.length) break;
      log(`dịch lại ${missing.length} block bị thiếu (lần ${attempt + 1})`);
      if (attempt === 0) {
        await translateBatch(missing);
      } else {
        for (const block of missing) {
          if (state.cancelled) break;
          await translateBatch([block]);
        }
      }
    }
    if (state.cancelled) return;

    diag.translated = pending.filter((block) => block.translation).length;
    diag.shaped = blocks.filter((block) => Array.isArray(block.poly) && block.poly.length >= 6).length;
    // Số block mà đường bao phủ trọn vùng chữ — nếu thấp hơn shaped thì đó là các ô còn lộ chữ gốc.
    diag.covered = blocks.filter((block) => {
      const text = block.textBox;
      const poly = block.poly;
      return Boolean(poly) && Boolean(text)
        && core.polygonCoversBox(poly, text.x, text.y, text.w, text.h);
    }).length;
    // Block được dịch, fill thấp trước — fill thấp là nghi bị nhận nhầm SFX/chữ đè tranh.
    diag.kept = pending
      .slice()
      .sort((a, b) => (a.fill || 0) - (b.fill || 0))
      .slice(0, 120)
      .map((block) => ({
        text: block.text.slice(0, 60),
        fill: Number(block.fill || 0).toFixed(2),
        enclose: Number(block.enclose || 0).toFixed(2),
        bg: block.bg,
      }));
    diag.missing = pending
      .filter((block) => !block.translation)
      .slice(0, 40)
      .map((block) => ({ id: block.id, text: block.text.slice(0, 80) }));
    diag.phase = "xong";

    state.phase = "showing";
    setFab("Bản gốc", false);
    log(`dịch xong ${state.rendered}/${blocks.length} block`);
  }

  // ---------------------------------------------------------------- cache

  function cacheKeyFor(image, model) {
    const src = image.src;
    if (!src || !/^https?:/i.test(src)) return null;
    return core.cacheKey(model, src);
  }

  async function cacheGet(key) {
    try {
      const data = await browser.storage.local.get(key);
      const entry = data[key];
      return entry ? core.decodeCacheBlocks(entry.blocks) : null;
    } catch {
      return null;
    }
  }

  /** Chỉ cache ảnh đã có bản dịch cho mọi block để lần sau dùng lại trọn vẹn. */
  async function cacheSet(key, imageBlocks) {
    try {
      const blocks = core.encodeCacheBlocks(imageBlocks);
      if (!blocks.length) return;
      const at = Date.now();
      await browser.storage.local.set({ [key]: { at, blocks } });

      const data = await browser.storage.local.get(CACHE_INDEX_KEY);
      let index = Array.isArray(data[CACHE_INDEX_KEY]) ? data[CACHE_INDEX_KEY] : [];
      index = index.filter((item) => item && item.key !== key);
      index.push({ key, at });
      let drop = [];
      if (index.length > CACHE_MAX_ENTRIES) {
        index.sort((a, b) => a.at - b.at);
        drop = index.splice(0, index.length - CACHE_MAX_ENTRIES).map((item) => item.key);
      }
      if (drop.length) await browser.storage.local.remove(drop);
      await browser.storage.local.set({ [CACHE_INDEX_KEY]: index });
    } catch {
      // Cache là phụ — lỗi lưu không được làm hỏng bản dịch vừa hiện.
    }
  }

  // ---------------------------------------------------------------- tự dán cache khi vào chapter

  /** Vào chapter: ảnh nào đã có cache cho model hiện tại thì dán luôn, không gọi AI. */
  async function autoApplyCache() {
    if (state.cacheChecked || state.phase !== "idle") return;
    const cacheable = candidateElements().filter((item) => !item.canvas && item.src && /^https?:/i.test(item.src));
    if (!cacheable.length) return;
    state.cacheChecked = true;

    let model = "";
    try {
      const data = await browser.storage.local.get(MODEL_KEY);
      if (typeof data[MODEL_KEY] === "string") model = data[MODEL_KEY];
    } catch {
      model = "";
    }
    // Chưa từng mở popup lần nào → hỏi native đúng model đang dùng (mặc định của app).
    if (!model) {
      try {
        const settings = await ask({ type: "getSettings" });
        model = settings.model || "";
      } catch {
        state.cacheChecked = false;
        return;
      }
    }
    if (!model) return;
    const found = await Promise.all(
      cacheable.map(async (item) => {
        const blocks = await cacheGet(core.cacheKey(model, item.src));
        return blocks && blocks.length ? { item, blocks } : null;
      })
    );
    // Người dùng bấm Dịch trong lúc đang kiểm tra cache → để luồng đó làm việc.
    if (state.phase !== "idle") return;

    const hits = found.filter(Boolean);
    if (!hits.length) {
      log(`cache trống cho ${cacheable.length} ảnh`);
      return;
    }

    state.model = model;
    state.blocks = [];
    state.rendered = 0;
    resetLayer();
    for (const hit of hits) {
      for (const block of hit.blocks) {
        state.blocks.push({ ...block, id: state.blocks.length + 1, imageIndex: 0, image: hit.item.el, fromCache: true });
      }
    }
    core.layoutTextAreas(state.blocks);
    for (const block of state.blocks) renderBlock(block, block.translation);
    const complete = hits.length === cacheable.length;
    state.renderedSrcs = new Set(hits.map((hit) => hit.item.src));
    state.phase = complete ? "showing" : "cached";
    setFab(complete ? "Bản gốc" : "Dịch", false);
    log(`tự dán cache: ${hits.length}/${cacheable.length} ảnh`);
  }

  // ---------------------------------------------------------------- ảnh

  function candidateElements() {
    const result = [];
    const seen = new Set();
    for (const image of document.images) {
      if (result.length >= MAX_IMAGES) break;
      const rect = image.getBoundingClientRect();
      if (rect.width < 200 || rect.height < 120 || rect.width * rect.height < 20000) continue;
      const src = image.currentSrc || image.src;
      if (!src || seen.has(src)) continue;
      seen.add(src);
      result.push({ el: image, src, canvas: false });
    }
    for (const canvas of document.querySelectorAll("canvas")) {
      if (result.length >= MAX_IMAGES) break;
      if (canvas.width < MIN_IMG_WIDTH || canvas.height < MIN_IMG_HEIGHT) continue;
      const rect = canvas.getBoundingClientRect();
      if (rect.width < 200 || rect.height < 120) continue;
      result.push({ el: canvas, canvas: true });
    }
    return result;
  }

  function toImageList(elements) {
    const images = [];
    for (const item of elements) {
      if (item.canvas) {
        if (item.el.width < MIN_IMG_WIDTH || item.el.height < MIN_IMG_HEIGHT) continue;
        images.push({ el: item.el, canvas: true, src: null, width: item.el.width, height: item.el.height });
      } else {
        const image = item.el;
        if (!image.complete || image.naturalWidth === 0) continue;
        if (image.naturalWidth < MIN_IMG_WIDTH || image.naturalHeight < MIN_IMG_HEIGHT) continue;
        images.push({
          el: image,
          canvas: false,
          src: image.currentSrc || image.src,
          width: image.naturalWidth,
          height: image.naturalHeight,
        });
      }
    }
    return images;
  }

  /** Ảnh lazy-load ngoài viewport chưa có pixel: cuộn qua để WebKit tải, cuối cùng trả lại vị trí cũ. */
  async function prepareImages() {
    const elements = candidateElements();
    const missing = elements.filter((item) => !item.canvas && (!item.el.complete || item.el.naturalWidth === 0));
    if (missing.length) {
      const started = Date.now();
      const scrollX = window.scrollX;
      const scrollY = window.scrollY;
      try {
        for (let index = 0; index < missing.length; index++) {
          if (state.cancelled) break;
          if (Date.now() - started > PREPARE_BUDGET_MS) break;
          setFab(`Đang tải ảnh ${index + 1}/${missing.length}`, true);
          const image = missing[index].el;
          image.loading = "eager";
          image.scrollIntoView({ block: "center" });
          await waitForLoad(image, LAZY_WAIT_MS);
        }
      } finally {
        window.scrollTo(scrollX, scrollY);
      }
    }
    return toImageList(candidateElements());
  }

  function waitForLoad(image, timeoutMs) {
    if (image.complete && image.naturalWidth > 0) return Promise.resolve();
    return new Promise((resolve) => {
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        image.removeEventListener("load", finish);
        image.removeEventListener("error", finish);
        clearTimeout(timer);
        resolve();
      };
      const timer = setTimeout(finish, timeoutMs);
      image.addEventListener("load", finish);
      image.addEventListener("error", finish);
    });
  }

  async function readImage(image) {
    if (image.canvas) {
      return ocrDataURL(image.el.toDataURL("image/jpeg", JPEG_QUALITY));
    }
    const src = image.src;
    if (!src) throw new Error("Ảnh không có nguồn.");
    if (src.startsWith("data:") || src.startsWith("blob:")) {
      return ocrDataURL(src);
    }
    try {
      const response = await fetch(src, { credentials: "include", referrer: location.href, cache: "force-cache" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const blob = await response.blob();
      return await ocrBlob(blob);
    } catch (error) {
      log(`fetch ảnh lỗi (${error.message || error}) → nhờ appex tải`);
      const reply = await ask({
        type: "native",
        payload: { action: "ocrUrl", url: src, referer: location.href, cookie: document.cookie },
      });
      return { lines: core.dedupeLines((reply.lines || []).map(toLine)).slice(0, MAX_LINES_PER_IMAGE) };
    }
  }

  async function ocrDataURL(dataURL) {
    const blob = await (await fetch(dataURL)).blob();
    return ocrBlob(blob);
  }

  /** Cắt ảnh thành tile ≤ MAX_TILE_W×MAX_TILE_H, OCR từng tile, ghép lại toạ độ chuẩn hoá của ảnh gốc. */
  async function ocrBlob(blob) {
    const bitmap = await createImageBitmap(blob);
    try {
      const scale = Math.min(1, MAX_TILE_W / bitmap.width);
      const width = Math.max(1, Math.round(bitmap.width * scale));
      const height = Math.max(1, Math.round(bitmap.height * scale));
      const canvas = document.createElement("canvas");
      const context = canvas.getContext("2d");
      const tileHeight = Math.min(MAX_TILE_H, height);
      const step = Math.max(1, Math.round(tileHeight * (1 - TILE_OVERLAP)));
      const lines = [];
      let y = 0;
      while (true) {
        const currentHeight = Math.min(tileHeight, height - y);
        canvas.width = width;
        canvas.height = currentHeight;
        // Ảnh PNG trong suốt → JPEG nền đen làm OCR sai; luôn tô trắng trước.
        context.fillStyle = "#ffffff";
        context.fillRect(0, 0, width, currentHeight);
        context.drawImage(bitmap, 0, -y, width, height);
        const dataURL = canvas.toDataURL("image/jpeg", JPEG_QUALITY);
        const reply = await ask({ type: "native", payload: { action: "ocr", image: dataURL } });
        for (const line of reply.lines || []) {
          lines.push(mapLine(line, y, currentHeight, height));
        }
        if (y + currentHeight >= height) break;
        y += step;
      }
      return { lines: core.dedupeLines(lines).slice(0, MAX_LINES_PER_IMAGE) };
    } finally {
      if (bitmap.close) bitmap.close();
    }
  }

  /** Native trả box dạng mảng [x, y, w, h] (tiết kiệm payload) → object cho groupLines/dedupe. */
  function toLine(line) {
    const box = Array.isArray(line.box) ? line.box : [0, 0, 0, 0];
    const bubble = Array.isArray(line.bub) ? line.bub : null;
    return {
      text: line.text,
      confidence: line.confidence,
      bg: line.bg,
      fill: line.fill,
      enclose: Number(line.enclose) || 0,
      box: { x: box[0], y: box[1], w: box[2], h: box[3] },
      bubble: bubble ? { x: bubble[0], y: bubble[1], w: bubble[2], h: bubble[3] } : null,
      poly: Array.isArray(line.poly) && line.poly.length >= 6 ? line.poly.slice() : null,
    };
  }

  function mapLine(line, tileY, tileHeight, imageHeight) {
    const box = Array.isArray(line.box) ? line.box : [0, 0, 0, 0];
    const normalized = core.mapTileBox(
      { x: box[0], y: box[1], w: box[2], h: box[3] },
      { x: 0, y: tileY / imageHeight, w: 1, h: tileHeight / imageHeight }
    );
    const bubble = Array.isArray(line.bub)
      ? core.mapTileBox(
          { x: line.bub[0], y: line.bub[1], w: line.bub[2], h: line.bub[3] },
          { x: 0, y: tileY / imageHeight, w: 1, h: tileHeight / imageHeight }
        )
      : null;
    const poly = Array.isArray(line.poly) && line.poly.length >= 6
      ? line.poly.map((value, index) =>
          index % 2 === 0 ? value : tileY / imageHeight + value * (tileHeight / imageHeight)
        )
      : null;
    return { text: line.text, confidence: line.confidence, bg: line.bg, fill: line.fill, enclose: Number(line.enclose) || 0, box: normalized, bubble, poly };
  }

  // ---------------------------------------------------------------- dán đè

  function resetLayer() {
    const { layer, backdrops } = ui();
    layer.replaceChildren();
    backdrops.replaceChildren();
    layer.hidden = false;
    backdrops.hidden = false;
    for (const block of state.blocks) block.el = null;
    state.blocks = [];
    state.rendered = 0;
    state.renderedSrcs = new Set();
  }

  function renderBlock(block, text) {
    const { layer, backdrops } = ui();
    const element = document.createElement("div");
    element.className = "block";
    const background = typeof block.bg === "string" && /^#[0-9a-f]{6}$/i.test(block.bg) ? block.bg : "#ffffff";
    // Nền ở lớp riêng phía dưới mọi khung, cắt theo đường bao bong bóng; chữ ở lớp trên.
    // Nhờ vậy nền của khung này không bao giờ che chữ của khung khác, và chữ không bị cắt.
    const backdrop = document.createElement("div");
    backdrop.className = "backdrop";
    backdrop.style.background = background;
    applyClip(block, backdrop);
    backdrops.appendChild(backdrop);
    element.style.color = core.luminance(background) > 0.45 ? "#111111" : "#ffffff";
    const span = document.createElement("span");
    span.textContent = text;
    element.appendChild(span);
    block.translation = text;
    block.el = element;
    block.backdrop = backdrop;
    layer.appendChild(element);
    placeBlock(block);
    state.rendered += 1;
  }

  /** Cắt khung theo đường bao bong bóng (đa giác native trả về), toạ độ % so với khung. */
  function applyClip(block, element) {
    const poly = block.poly;
    const box = block.box;
    if (!Array.isArray(poly) || poly.length < 6 || !box || box.w <= 0 || box.h <= 0) {
      element.style.clipPath = "";
      return;
    }
    const points = [];
    for (let index = 0; index < poly.length; index += 2) {
      const x = ((poly[index] - box.x) / box.w) * 100;
      const y = ((poly[index + 1] - box.y) / box.h) * 100;
      points.push(`${x.toFixed(2)}% ${y.toFixed(2)}%`);
    }
    element.style.clipPath = `polygon(${points.join(", ")})`;
  }

  function placeBlock(block) {
    const element = block.el;
    if (!element) return;
    const rect = block.image.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) {
      element.hidden = true;
      if (block.backdrop) block.backdrop.hidden = true;
      return;
    }
    // Nền phủ theo bong bóng (`box`); chữ đặt trong vùng riêng neo vào chữ gốc (`textArea`).
    setFrame(element, block.textArea || block.box, rect);
    element.hidden = false;
    if (block.backdrop) {
      setFrame(block.backdrop, block.box, rect);
      block.backdrop.hidden = false;
    }
    fitText(element, block, rect);
  }

  function setFrame(element, area, rect) {
    element.style.left = `${rect.left + window.scrollX + area.x * rect.width}px`;
    element.style.top = `${rect.top + window.scrollY + area.y * rect.height}px`;
    element.style.width = `${Math.max(8, area.w * rect.width)}px`;
    element.style.height = `${Math.max(8, area.h * rect.height)}px`;
  }

  /**
   * Bắt đầu ở cỡ gần bằng chữ gốc (chiều cao chữ gốc / số dòng) rồi chỉ thu nhỏ khi chữ dịch
   * không vừa vùng đặt chữ — vùng rộng hơn chữ gốc thì chữ xuống dòng chứ không phóng to.
   */
  function fitText(element, block, rect) {
    const span = element.lastElementChild;
    if (!span) return;
    const maxWidth = element.clientWidth - 6;
    const maxHeight = element.clientHeight - 4;
    if (maxWidth < 4 || maxHeight < 4) return;
    const text = block.textBox || block.box;
    const lineHeight = (text.h * rect.height) / Math.max(1, Number(block.lines) || 1);
    let size = Math.max(7, Math.min(28, Math.round(lineHeight / 1.15)));
    element.style.fontSize = `${size}px`;
    element.style.overflowWrap = "";
    // Chỉ xuống dòng giữa các từ; từ dài hơn dòng làm span tràn ngang (scrollWidth) → thu nhỏ chữ.
    const fits = () => span.scrollWidth <= span.clientWidth + 1 && span.getBoundingClientRect().height <= maxHeight;
    let guard = 0;
    while (size > 6 && guard++ < 30 && !fits()) {
      size -= 1;
      element.style.fontSize = `${size}px`;
    }
    // Cỡ nhỏ nhất vẫn không vừa thì đành bẻ từ, còn hơn chữ tràn ra ngoài bong bóng.
    if (!fits()) element.style.overflowWrap = "anywhere";
  }

  function layoutAll() {
    state.layoutFrame = 0;
    for (const block of state.blocks) placeBlock(block);
  }

  function scheduleLayout() {
    if (state.layoutFrame) return;
    state.layoutFrame = requestAnimationFrame(layoutAll);
  }

  // Ảnh lazy-load có thể chưa có kích thước lúc dán (overlay bị ẩn) — cuộn tới thì dán lại.
  let hiddenFrame = 0;
  function placeHidden() {
    hiddenFrame = 0;
    for (const block of state.blocks) {
      if (block.el && block.el.hidden) placeBlock(block);
    }
  }

  function scheduleHiddenLayout() {
    if (hiddenFrame) return;
    hiddenFrame = requestAnimationFrame(placeHidden);
  }

  window.addEventListener("resize", scheduleLayout);
  window.addEventListener("orientationchange", scheduleLayout);
  window.addEventListener("scroll", scheduleHiddenLayout, { passive: true });

  // ---------------------------------------------------------------- background/storage

  async function ask(message) {
    let reply;
    try {
      reply = IS_TOP ? await browser.runtime.sendMessage(message) : await relayToTop(message);
    } catch (error) {
      const friendly = new Error(messagingErrorText(error));
      friendly.stale = isStaleContextError(error);
      throw friendly;
    }
    if (!reply) throw new Error("Background của extension không phản hồi.");
    if (!reply.ok) {
      const error = new Error(reply.error || "Lỗi không rõ.");
      if (reply.stale) error.stale = true;
      throw error;
    }
    return reply.result;
  }

  // Safari iOS: content script trong iframe không gọi được runtime.sendMessage ("Tab not found")
  // → nhờ khung chính chuyển tiếp. Khung chính cũng có thể gặp lỗi này nếu tab mở từ trước khi cập nhật app.
  const IS_TOP = (() => {
    try {
      return window.top === window;
    } catch {
      return false;
    }
  })();
  const RELAY_TIMEOUT_MS = 130000;
  const RELAY_TYPES = new Set(["native", "getSettings", "log"]);
  const RELAY_ACTIONS = new Set(["ocr", "ocrUrl", "translate", "analyze", "log"]);

  let relaySeq = 0;
  const relayPending = new Map();

  function isStaleContextError(error) {
    return /Tab not found|Invalid call to runtime\.sendMessage|Extension context invalidated/i.test(
      String((error && error.message) || error)
    );
  }

  function messagingErrorText(error) {
    return isStaleContextError(error)
      ? "Extension chưa sẵn sàng cho tab này (thường gặp sau khi cập nhật app, hoặc tab được mở từ trước). Tải lại trang rồi thử lại — hoặc mở popup Mangalate → Dịch trang này."
      : String((error && error.message) || error);
  }

  function relayToTop(message) {
    return new Promise((resolve, reject) => {
      const id = `r${Date.now()}-${++relaySeq}`;
      const timer = setTimeout(() => {
        relayPending.delete(id);
        reject(new Error("Khung chính của trang không phản hồi."));
      }, RELAY_TIMEOUT_MS);
      relayPending.set(id, { resolve, timer });
      try {
        window.top.postMessage({ __mangalate: true, id, message }, "*");
      } catch (error) {
        clearTimeout(timer);
        relayPending.delete(id);
        reject(error);
      }
    });
  }

  window.addEventListener("message", async (event) => {
    const data = event.data;
    if (!data || data.__mangalate !== true) return;

    // Khung con nhận phản hồi từ khung chính.
    if (data.id && data.reply) {
      const pending = relayPending.get(data.id);
      if (!pending) return;
      relayPending.delete(data.id);
      clearTimeout(pending.timer);
      pending.resolve(data.reply);
      return;
    }

    // Khung chính chuyển tiếp yêu cầu. Chỉ nhận đúng các loại message của extension.
    if (!IS_TOP || !data.id || !data.message || !event.source) return;
    const message = data.message;
    if (!RELAY_TYPES.has(message.type)) return;
    if (message.type === "native" && !RELAY_ACTIONS.has(message.payload && message.payload.action)) return;
    let reply;
    try {
      reply = await browser.runtime.sendMessage(message);
    } catch (error) {
      reply = { ok: false, error: messagingErrorText(error), stale: isStaleContextError(error) };
    }
    try {
      event.source.postMessage({ __mangalate: true, id: data.id, reply }, "*");
    } catch {
      // Khung con đã đóng — bỏ qua.
    }
  });

  async function storageGet(key) {
    try {
      const data = await browser.storage.local.get(key);
      return data[key] === true;
    } catch {
      return false;
    }
  }

  async function storageSet(key, value) {
    try {
      await browser.storage.local.set({ [key]: value });
    } catch {
      // Không lưu được cũng không chặn lần dịch này.
    }
  }

  // Log + chẩn đoán của lần dịch gần nhất, lưu trong storage để popup hiển thị (chỉ trên máy).
  const LOG_LIMIT = 250;
  const DIAG_KEY = "mangalate:lastRun";
  let logLines = [];
  let diagTimer = 0;
  let diag = { model: "", phase: "", total: 0, sent: 0, translated: 0, shaped: 0, covered: 0, dropped: [], kept: [], missing: [], fromCacheOnly: false };

  function saveDiag() {
    if (diagTimer) return;
    // Lần chỉ hiện cache không gọi AI — không ghi đè chẩn đoán của lần dịch thật.
    if (diag.fromCacheOnly) return;
    diagTimer = setTimeout(() => {
      diagTimer = 0;
      browser.storage.local
        .set({
          [DIAG_KEY]: {
            at: new Date().toLocaleString("vi-VN"),
            url: location.href,
            model: diag.model,
            phase: diag.phase,
            total: diag.total,
            sent: diag.sent,
            translated: diag.translated,
            shaped: diag.shaped,
            covered: diag.covered,
            dropped: diag.dropped,
            kept: diag.kept,
            missing: diag.missing,
            lines: logLines.slice(-LOG_LIMIT),
          },
        })
        .catch(() => {});
    }, 500);
  }

  function log(text) {
    logLines.push(String(text));
    if (logLines.length > LOG_LIMIT) logLines = logLines.slice(-LOG_LIMIT);
    saveDiag();
    try {
      browser.runtime.sendMessage({ type: "log", text: String(text) }).catch(() => {});
    } catch {
      // Bỏ qua: log không được làm hỏng thao tác chính.
    }
  }

  browser.runtime.onMessage.addListener((message) => {
    if (!message) return undefined;
    if (message.type === "translateNow") {
      return siteAllowed().then((allowed) => {
        if (!allowed) {
          return { ok: false, error: "Trang này chưa nằm trong danh sách được dịch. Mở Mangalate → thêm trang rồi thử lại." };
        }
        if (state.phase === "idle" || state.phase === "cached") {
          start();
        } else if (state.phase === "hidden") {
          setLayerVisible(true);
          state.phase = "showing";
          setFab("Bản gốc", false);
        }
        return { ok: true };
      });
    }
    if (message.type === "ping") return Promise.resolve({ ok: true });
    return undefined;
  });

  async function boot() {
    if (!(await siteAllowed())) {
      setFab("", false);
      return;
    }
    if (state.phase === "idle" && hasCandidateImages()) setFab("Dịch", false);
    autoApplyCache();
  }

  // Thêm/xoá trang trong popup thì cập nhật nút ngay trên tab đang mở.
  browser.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes[SITES_KEY]) boot();
  });

  boot();
  window.addEventListener("load", boot);
  window.addEventListener("load", scheduleLayout);
  setTimeout(boot, 2500);
})();
