// Smoke test popup trên Chrome headless với background giả lập:
//   node tests/popup-smoke.mjs [ảnh-chụp.png]
// Kiểm tra mọi nút đều có phản hồi: đang xử lý (vòng xoay), thành công, lỗi — hiện dưới nút và ở toast.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, existsSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join, extname } from "node:path";
import assert from "node:assert/strict";

const EXT = new URL("../WebExtension/", import.meta.url).pathname;
const CHROME = process.env.CHROME || "google-chrome";
const SHOT = process.argv[2];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".png": "image/png" };

// Background giả: trạng thái AI chỉnh được từ test qua window.__bg.
const BROWSER_STUB = `
  window.__bg = {
    hasKey: false, model: "", listModels: "ok", scan: null, calls: [], nativeError: null, reloaded: false, tabId: 1,
    siteRules: { hide: [], popupDomains: [], blockDomains: [] },
    globalRules: { hide: [], popupDomains: [] },
    sharing: { linkedTo: null, linkedFrom: [], suggestions: [], knownSites: [] },
    features: { ads: true, tracking: true, youtube: true }, enabledRulesets: ["ads", "ads_custom", "tracking"], nativeParamStrip: true,
    candidates: [
      { id: "c1", kind: "blocked_domain", domain: "img.manga-cdn.io", brokenImages: 12, lazyImages: 0, notLoaded: [], samples: [],
        sources: [{ type: "ruleset", label: "bộ lọc quảng cáo (EasyList/ABPVN)" }], fixes: [{ action: "allow_domain", domain: "img.manga-cdn.io" }] },
      { id: "c2", kind: "hidden", selector: ".reader-box", count: 1, media: 20,
        sources: [{ type: "filter", label: "bộ lọc ẩn phần tử (EasyList/ABPVN)" }], fixes: [{ action: "unhide_selector", selector: ".reader-box" }] },
    ],
  };
  const models = [
    { id: "gemini-x-omni-flash-preview", name: "Gemini X Omni Flash Preview" },
    { id: "gemini-x-pro", name: "Gemini X Pro" },
    { id: "gemini-x-flash", name: "Gemini X Flash" },
  ];
  const reply = (result) => ({ ok: true, result });
  globalThis.browser = {
    tabs: { query: async () => [{ id: window.__bg.tabId, url: "https://news.example.com/a" }] },
    runtime: {
      reload: () => { window.__bg.reloaded = true; },
      sendMessage: async (m) => {
        const bg = window.__bg;
        bg.calls.push(m.type);
        await new Promise((r) => setTimeout(r, 50));
        switch (m.type) {
          case "getTabState":
            // Như Safari: mã tab cũ không còn → tabs.get() lỗi (background thật dùng url dự phòng).
            if (m.tabId !== bg.tabId) return { ok: false, error: "Invalid call to tabs.get(). Tab not found." };
            return reply({
            host: "news.example.com", site: "example.com", sensitive: false,
            stats: { popups: 3, overlays: 1 }, log: [], scan: bg.scan,
            siteRules: bg.siteRules, globalRules: bg.globalRules, sharing: bg.sharing,
            features: bg.features, enabledRulesets: bg.enabledRulesets, nativeParamStrip: bg.nativeParamStrip,
            settings: { hasKey: bg.hasKey, model: bg.model, nativeError: bg.nativeError,
              sensitiveSites: ["paypal.com"], consentAccepted: true },
          });
          case "saveSettings":
            if (typeof m.apiKey === "string") bg.hasKey = !!m.apiKey;
            if (typeof m.model === "string") bg.model = m.model;
            return reply(null);
          case "listModels":
            if (bg.listModels === "error") return { ok: false, error: "API key hoặc model không hợp lệ: API key not valid." };
            await new Promise((r) => setTimeout(r, 400));
            return reply(models);
          case "startPicker": return reply(true);
          case "setFeature": bg.features = { ...bg.features, [m.name]: m.on }; return reply(null);
          case "privacyReport": return reply({ items: [
            { domain: "static.hotjar.com", count: 1, types: ["script"], category: "session_replay", status: "blocked" },
            { domain: "www.google-analytics.com", count: 3, types: ["script"], category: "analytics", status: "loaded" },
            { domain: "cdn.fonts.net", count: 2, types: ["css"], category: null, status: "loaded" },
          ] });
          case "scanTrackers": return reply({ accepted: [
            { type: "block_domain", domain: "metrics.newspy.io", category: "analytics", reason: "thống kê", confidence: 0.9 },
            { type: "block_domain", domain: "maybe.io", category: "ads", reason: "?", confidence: 0.6 },
          ], rejected: [] });
          case "saveTrackerRules": bg.savedTrackers = m.rules.map((r) => r.domain); return reply(null);
          case "disallowWidget": bg.siteRules.allowWidgets = []; return reply(null);
          case "diagnostics": return reply({ candidates: bg.candidates });
          case "deleteAllRules": {
            bg.cleared = m.scope;
            const group = m.scope === "site" ? bg.siteRules : bg.globalRules;
            const n = group.hide.length;
            group.hide = [];
            return reply(n);
          }
          case "diagnoseAI": return reply({ summary: "Ảnh truyện từ manga-cdn.io bị bộ lọc chặn.", candidates: bg.candidates,
            fixes: [{ candidateId: "c1", action: "allow_domain", domain: "img.manga-cdn.io", reason: "CDN ảnh truyện", confidence: 0.92 }] });
          case "applyFix":
            bg.applied = m.fix;
            bg.siteRules.allowDomains = [{ id: "e1", domain: m.fix.domain, reason: m.fix.reason }];
            return reply(null);
          case "removeException": bg.removed = m.kind; bg.siteRules.allowDomains = []; return reply(null);
          case "deleteRule":
            bg.siteRules.hide = bg.siteRules.hide.filter((r) => r.id !== m.ruleId);
            bg.globalRules.hide = bg.globalRules.hide.filter((r) => r.id !== m.ruleId);
            return reply(null);
          case "setRuleScope": {
            const [from, to] = m.scope === "global" ? [bg.siteRules.hide, bg.globalRules.hide] : [bg.globalRules.hide, bg.siteRules.hide];
            to.push(...from.splice(from.findIndex((r) => r.id === m.ruleId), 1));
            return reply(null);
          }
          case "linkSite":
            bg.sharing = { linkedTo: m.target, linkedFrom: [], suggestions: [], knownSites: [] };
            return reply(m.target);
          default: return reply(null);
        }
      },
    },
  };
`;

class CDP {
  constructor(url) {
    this.ws = new WebSocket(url);
    this.id = 0;
    this.pending = new Map();
    this.ws.onmessage = ({ data }) => {
      const msg = JSON.parse(data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
      }
    };
  }
  open() { return new Promise((r) => { this.ws.onopen = r; }); }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }
}

const server = createServer((req, res) => {
  const path = join(EXT, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!path.startsWith(EXT) || !existsSync(path)) {
    res.statusCode = 404;
    return res.end();
  }
  res.setHeader("Content-Type", TYPES[extname(path)] || "application/octet-stream");
  res.end(readFileSync(path));
}).listen(0, "127.0.0.1");
await new Promise((r) => server.once("listening", r));

const profile = mkdtempSync(join(tmpdir(), "adsblocker-popup-"));
const chrome = spawn(CHROME, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--window-size=390,1400", "about:blank",
], { stdio: "ignore" });

let failed = false;
try {
  const portFile = join(profile, "DevToolsActivePort");
  for (let i = 0; i < 100 && !existsSync(portFile); i++) await sleep(100);
  const port = readFileSync(portFile, "utf8").split("\n")[0];
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const cdp = new CDP(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await cdp.open();
  await cdp.send("Page.enable");
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: BROWSER_STUB });
  await cdp.send("Page.navigate", { url: `http://127.0.0.1:${server.address().port}/popup/popup.html` });
  await sleep(1500);

  const page = async (expression) => {
    const { result, exceptionDetails } = await cdp.send("Runtime.evaluate",
      { expression, awaitPromise: true, returnByValue: true });
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description || exceptionDetails.text);
    return result.value;
  };
  const text = (id) => page(`document.getElementById(${JSON.stringify(id)}).textContent.trim()`);
  const waitFor = async (expr, ms = 5000) => {
    for (const end = Date.now() + ms; Date.now() < end; await sleep(100)) if (await page(expr)) return;
    throw new Error(`hết giờ chờ: ${expr}`);
  };
  const check = async (name, fn) => {
    try {
      await fn();
      console.log(`✔ ${name}`);
    } catch (error) {
      failed = true;
      console.log(`✖ ${name}\n  ${error.message}`);
    }
  };

  await check("chưa có key: badge, lý do không quét được, nút tải model bị khoá kèm giải thích", async () => {
    assert.equal(await text("host"), "news.example.com");
    assert.equal(await text("ai-badge"), "Chưa có key");
    assert.match(await text("scan-status"), /Chưa có API key/);
    assert.equal(await page(`document.getElementById("load-models").disabled`), true);
    assert.match(await text("model-status"), /Lưu API key trước/);
  });

  await check("lưu key lỗi: nút hiện đang xử lý, rồi lỗi hiện dưới nút và ở toast", async () => {
    await page(`window.__bg.listModels = "error"; document.getElementById("api-key").value = "bad-key"`);
    await page(`document.getElementById("save-key").click()`);
    assert.equal(await page(`!!document.querySelector("#save-key .spin")`), true, "nút không hiện vòng xoay");
    await waitFor(`document.getElementById("key-status").classList.contains("err")`);
    assert.match(await text("key-status"), /Đã lưu key nhưng gọi Google thất bại: API key hoặc model không hợp lệ/);
    assert.equal(await page(`!document.getElementById("toast").hidden && document.getElementById("toast").className`), "err");
    assert.equal(await text("save-key"), "Lưu key");
  });

  await check("lưu key đúng: tự tải model, tự chọn bản flash, badge Sẵn sàng, mở khoá quét", async () => {
    await page(`window.__bg.listModels = "ok"; document.getElementById("api-key").value = "good-key"`);
    await page(`document.getElementById("save-key").click()`);
    await waitFor(`document.getElementById("key-status").classList.contains("ok")`);
    // Bỏ qua bản preview đứng đầu danh sách, chọn bản flash ổn định.
    assert.equal(await text("key-status"), "✓ Key hợp lệ · 3 model · đang dùng gemini-x-flash");
    assert.equal(await page(`document.getElementById("model").value`), "gemini-x-flash");
    assert.equal(await page(`document.getElementById("model").options.length`), 3);
    assert.equal(await text("ai-badge"), "Sẵn sàng");
    assert.equal(await page(`document.getElementById("scan").disabled`), false);
    assert.equal(await page(`document.getElementById("toast").className`), "ok");
  });

  await check("Tải danh sách model: nút báo đang tải, xong báo số model", async () => {
    await page(`document.getElementById("load-models").click()`);
    assert.equal(await text("load-models"), "Đang tải từ Google…");
    assert.match(await text("model-status"), /Đang tải từ Google/);
    await waitFor(`document.getElementById("model-status").classList.contains("ok")`);
    assert.equal(await text("model-status"), "✓ Đã tải 3 model · đang dùng gemini-x-flash");
  });

  await check("đổi model: báo đã chọn", async () => {
    await page(`(() => { const s = document.getElementById("model"); s.value = "gemini-x-pro"; s.dispatchEvent(new Event("change")); })()`);
    await waitFor(`document.getElementById("model-status").textContent.includes("gemini-x-pro") && document.getElementById("model-status").classList.contains("ok")`);
    assert.equal(await page(`window.__bg.model`), "gemini-x-pro");
  });

  await check("quét đang chạy rồi lỗi: nút trở lại bình thường, hiện lỗi", async () => {
    await page(`window.__bg.scan = { status: "running", startedAt: Date.now() }; refresh()`);
    await waitFor(`document.getElementById("scan").textContent.includes("Đang quét")`);
    assert.equal(await page(`document.getElementById("scan").disabled`), true);
    await page(`window.__bg.scan = { status: "error", error: "Model đang quá tải" }`);
    await waitFor(`document.getElementById("scan").textContent === "Quét trang bằng AI"`, 4000);
    assert.equal(await page(`document.getElementById("scan").disabled`), false);
    assert.equal(await page(`!!document.querySelector("#scan .spin")`), false);
    assert.equal(await text("scan-status"), "✕ Quét lỗi: Model đang quá tải");
    await page(`window.__bg.scan = null`);
  });

  await check("Chọn quảng cáo: gọi startPicker, popup không tự đóng được thì hướng dẫn vuốt đóng", async () => {
    await page(`document.getElementById("pick").click()`);
    await waitFor(`document.getElementById("pick-status").classList.contains("ok")`);
    assert.match(await text("pick-status"), /Vuốt đóng popup/);
    assert.ok((await page(`window.__bg.calls`)).includes("startPicker"));
  });

  await check("rule 2 nhóm: chỉ selector có dấu hiệu quảng cáo mới có nút chuyển sang Mọi trang", async () => {
    await page(`window.__bg.siteRules.hide = [
      { id: "1", selector: "a.ads-banner", source: "ai", reason: "banner" },
      { id: "2", selector: "div.w-overlay", source: "manual", reason: "lớp phủ" }]; refresh()`);
    await waitFor(`document.querySelectorAll("#rules li").length === 2`);
    const buttons = await page(`[...document.querySelectorAll("#rules li")].map((li) =>
      [...li.querySelectorAll("button")].map((b) => b.textContent))`);
    assert.deepEqual(buttons, [["→ Mọi trang", "Xoá"], ["Xoá"]]);
    assert.equal(await text("global-rules"), "Chưa có rule áp mọi trang.");
    await page(`document.querySelector("#rules li button").click()`);
    await waitFor(`document.querySelectorAll("#global-rules li button").length === 2`);
    assert.match(await text("global-rules"), /a\.ads-banner/);
    assert.equal(await text("rule-count"), "1 trang này · 1 mọi trang");
  });

  await check("mã tab đổi khi popup đang mở: bấm Xoá vẫn xoá được, không báo lỗi Tab not found", async () => {
    await page(`window.__bg.tabId = 7`);
    await page(`document.querySelector("#rules li button").click()`);
    await waitFor(`!document.getElementById("toast").hidden && document.getElementById("toast").textContent.includes("Đã xoá")`);
    assert.equal(await page(`document.getElementById("toast").className`), "ok");
    assert.equal(await text("rule-count"), "0 trang này · 1 mọi trang");
  });

  await check("gợi ý dùng chung rule với tên miền giống, bấm là liên kết", async () => {
    await page(`window.__bg.sharing = { linkedTo: null, linkedFrom: [], suggestions: ["truyenqqko.com"], knownSites: ["truyenqqko.com"] }; refresh()`);
    await waitFor(`document.querySelector("#share-suggest button")`);
    assert.equal(await page(`document.getElementById("share-unlink").hidden`), true);
    await page(`document.querySelector("#share-suggest button").click()`);
    await waitFor(`document.getElementById("share-status").classList.contains("ok")`);
    assert.match(await text("share-info"), /đang dùng chung rule của truyenqqko\.com/);
    assert.equal(await page(`document.getElementById("share-unlink").hidden`), false);
  });

  await check("phần native lỗi (vd. vừa cập nhật app): hiện banner, bấm Tải lại extension gọi runtime.reload", async () => {
    await page(`window.__bg.nativeError = "Launch failed"; refresh()`);
    await waitFor(`!document.getElementById("reload-banner").hidden`);
    await page(`document.getElementById("reload-ext").click()`);
    await waitFor(`window.__bg.reloaded`, 2000);
    await page(`window.__bg.nativeError = null; refresh()`);
    await waitFor(`document.getElementById("reload-banner").hidden`);
  });

  await check("công tắc: tắt Chặn quảng cáo → gọi setFeature, khoá Chọn/Quét kèm lý do; bật lại mở khoá", async () => {
    assert.equal(await page(`document.getElementById("feature-ads").checked && document.getElementById("feature-tracking").checked`), true);
    await page(`(() => { const c = document.getElementById("feature-ads"); c.checked = false; c.dispatchEvent(new Event("change")); })()`);
    await waitFor(`document.getElementById("feature-status").classList.contains("ok")`);
    assert.equal(await page(`window.__bg.features.ads`), false);
    assert.equal(await page(`document.getElementById("pick").disabled && document.getElementById("scan").disabled`), true);
    assert.equal(await text("scan-status"), "Đang tắt Chặn quảng cáo.");
    await page(`(() => { const c = document.getElementById("feature-ads"); c.checked = true; c.dispatchEvent(new Event("change")); })()`);
    await waitFor(`!document.getElementById("pick").disabled`);
    assert.equal(await text("pick-status"), "");
  });

  await check("Safari không nạp ruleset theo dõi → cảnh báo kèm hướng dẫn tải lại extension", async () => {
    await page(`window.__bg.enabledRulesets = ["ads", "ads_custom"]; refresh()`);
    await waitFor(`document.getElementById("feature-status").textContent.includes("chưa nạp bộ lọc theo dõi")`);
    await page(`window.__bg.enabledRulesets = ["ads", "ads_custom", "tracking"]; refresh()`);
    await waitFor(`!document.getElementById("feature-status").textContent.includes("chưa nạp")`);
  });

  await check("Theo dõi trên trang này: mở mục là có báo cáo theo nhóm + huy hiệu", async () => {
    await page(`document.getElementById("privacy-box").open = true`);
    await waitFor(`document.querySelectorAll("#privacy-report h4").length === 3`);
    assert.deepEqual(await page(`[...document.querySelectorAll("#privacy-report h4")].map((h) => h.textContent)`),
      ["Ghi lại phiên (xem lại thao tác của bạn) (1)", "Phân tích / thống kê (1)", "Chưa phân loại (1)"]);
    assert.equal(await text("privacy-badge"), "1 chặn · 1 tải");
  });

  await check("Quét theo dõi bằng AI: đề xuất (tick sẵn khi tin cậy cao) → Chặn lưu domain đã chọn", async () => {
    await page(`document.getElementById("tracker-scan").click()`);
    await waitFor(`document.querySelectorAll("#tracker-proposals li").length === 2`);
    assert.deepEqual(await page(`[...document.querySelectorAll("#tracker-proposals input")].map((i) => i.checked)`), [true, false]);
    await page(`document.getElementById("tracker-apply").click()`);
    await waitFor(`window.__bg.savedTrackers`);
    assert.deepEqual(await page(`window.__bg.savedTrackers`), ["metrics.newspy.io"]);
    await waitFor(`document.getElementById("tracker-status").classList.contains("ok")`);
  });

  await check("widget đã cho phép: liệt kê và chặn lại được", async () => {
    await page(`window.__bg.siteRules.allowWidgets = ["facebook"]; refresh()`);
    await waitFor(`document.querySelector("#widgets li code")`);
    assert.equal(await page(`document.querySelector("#widgets li code").textContent`), "Facebook");
    await page(`document.querySelector("#widgets li button").click()`);
    await waitFor(`document.querySelector("#widgets li").textContent.includes("Chưa cho phép")`);
  });

  await check("Chỉ xem dấu hiệu: liệt kê nghi phạm kèm nguồn + nút sửa, không cần AI", async () => {
    await page(`document.getElementById("diagnose-box").open = true; document.getElementById("diagnose-local").click()`);
    await waitFor(`document.querySelectorAll("#diagnose-candidates li").length === 2`);
    assert.match(await text("diagnose-candidates"), /img\.manga-cdn\.io — 12 ảnh lỗi/);
    assert.deepEqual(await page(`[...document.querySelectorAll("#diagnose-candidates button")].map((b) => b.textContent)`),
      ["Bỏ chặn domain trên trang này", "Bỏ ẩn trên trang này"]);
    assert.match(await text("diagnose-status"), /2 dấu hiệu, 2 có thể do extension/);
  });

  await check("Chẩn đoán bằng AI: bắt nhập vấn đề; có kết quả → tóm tắt + đề xuất → Áp dụng → hiện ở Ngoại lệ, huỷ được", async () => {
    await page(`document.getElementById("problem").value = ""; document.getElementById("diagnose-ai").click()`);
    await waitFor(`document.getElementById("diagnose-status").classList.contains("err")`);
    assert.match(await text("diagnose-status"), /Nhập mô tả vấn đề/);
    await waitFor(`!document.getElementById("diagnose-ai").disabled`);
    await page(`document.getElementById("problem").value = "ảnh truyện không hiện"; document.getElementById("diagnose-ai").click()`);
    await waitFor(`document.querySelectorAll("#diagnose-fixes li").length === 1`);
    assert.match(await text("diagnose-summary"), /manga-cdn\.io/);
    assert.match(await text("diagnose-fixes"), /CDN ảnh truyện · khả năng 92%/);
    await page(`document.querySelector("#diagnose-fixes button").click()`);
    await waitFor(`window.__bg.applied`);
    assert.deepEqual(await page(`[window.__bg.applied.action, window.__bg.applied.domain]`), ["allow_domain", "img.manga-cdn.io"]);
    await waitFor(`document.getElementById("exceptions").textContent.includes("Bỏ chặn img.manga-cdn.io")`);
    await page(`document.querySelector("#exceptions button").click()`);
    await waitFor(`window.__bg.removed === "allowDomains"`);
    await waitFor(`document.getElementById("exceptions").textContent.includes("Chưa có ngoại lệ")`);
  });

  await check("Xoá toàn bộ: bấm lần 1 chỉ hỏi xác nhận, bấm lần 2 mới xoá; không bấm thì tự trở lại", async () => {
    await page(`window.__bg.siteRules.hide = [{ id: "s1", selector: "div.a" }, { id: "s2", selector: "div.b" }];
      window.__bg.globalRules.hide = [{ id: "g1", selector: "a.ads-x" }]; refresh()`);
    await waitFor(`!document.getElementById("clear-site").hidden && !document.getElementById("clear-global").hidden`);
    await page(`document.getElementById("clear-site").click()`);
    assert.equal(await text("clear-site"), "Bấm lần nữa để xoá 2 rule của trang này");
    assert.equal(await page(`window.__bg.cleared`), undefined);
    await sleep(5500);
    assert.equal(await text("clear-site"), "Xoá toàn bộ", "không tự trở lại sau 5 giây");

    await page(`document.getElementById("clear-global").click()`);
    await page(`document.getElementById("clear-global").click()`);
    await waitFor(`window.__bg.cleared === "global"`);
    await waitFor(`document.getElementById("clear-global").hidden`);
    assert.equal(await page(`window.__bg.siteRules.hide.length`), 2, "nhóm còn lại không được bị xoá");
  });

  if (SHOT) {
    await page(`document.querySelectorAll("details").forEach((d) => { d.open = true; })`);
    const shot = await cdp.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
    writeFileSync(SHOT, Buffer.from(shot.data, "base64"));
  }
} finally {
  chrome.kill();
  server.close();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
