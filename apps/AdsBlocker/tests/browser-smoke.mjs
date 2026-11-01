// Smoke test content script trên Chrome headless (không có Safari ở Linux):
//   node tests/browser-smoke.mjs
// main_world.js chạy ở main world, content.js ở isolated world với `browser` giả lập.
// Click bằng CDP Input.dispatchMouseEvent → event.isTrusted = true như người dùng thật.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";

const EXT = new URL("../WebExtension/", import.meta.url).pathname;
const CHROME = process.env.CHROME || "google-chrome";
const read = (p) => readFileSync(join(EXT, p), "utf8");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PAGE = `<!doctype html><html><head><meta name="viewport" content="width=800"></head>
<body style="margin:0;font:16px sans-serif">
  <p id="text" style="padding:20px;height:200px">Nội dung bài viết bình thường.</p>
  <button id="share" style="margin:20px">Chia sẻ</button>
  <a id="link" href="https://other.example/article" target="_blank" style="margin:20px">Link ngoài</a>
  <div class="ad-banner" id="banner" style="width:300px;height:250px;background:#ccc;margin:20px">
    <a href="https://adclick.adnet.io/c" target="_blank"><img id="ad-img" src="https://ads.adnet.io/x.png"
      style="display:block;width:300px;height:250px"></a>
  </div>
  <div class="sponsor-box" id="sp1" style="width:320px;height:100px;background:#eee;margin:20px"><span>Tài trợ 1</span></div>
  <div class="sponsor-box" id="sp2" style="width:320px;height:100px;background:#eee;margin:20px"><span>Tài trợ 2</span></div>
  <div id="overlay" style="position:fixed;inset:0;z-index:99999;background:transparent"></div>
  <div class="list-ad" id="la" style="height:20px"><img alt="" width="10" height="10"
    src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">quảng cáo theo bộ lọc</div>
  <img id="broken" alt="" src="/missing.jpg">
  <img id="lazy" alt="" data-src="https://lazy.cdn.vn/p.jpg" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=">
  <section><span class="tok-ad" id="ta">quảng cáo theo token</span></section>
  <a id="tracked" href="https://dest.example/p?utm_source=x&id=5&fbclid=y">link có tham số theo dõi</a>
  <a id="wrapped" ping="https://track.example/p"
     href="https://www.google.com/url?q=https%3A%2F%2Fdest.example%2Fq%3Futm_medium%3Dz&sa=U">link bọc Google</a>
  <iframe id="fbw" src="https://www.facebook.com/plugins/post.php?href=x" width="300" height="200"></iframe>
  <blockquote class="twitter-tweet" id="tw">nội dung tweet</blockquote>
  <script>
    window.opened = [];
    document.addEventListener("click", (e) => {
      if (e.target.id === "share") window.opened.push(["share", !!window.open("/share", "_blank")]);
      else if (e.target.id === "link") window.opened.push(["link-hijack", !!window.open("https://popads.net/x")]);
      else window.opened.push(["hijack", !!window.open("https://popads.net/x")]);
    });
    // Overlay chèn sau khi tải để thử MutationObserver.
    setTimeout(() => {
      const o = document.createElement("div");
      o.id = "late-overlay";
      o.style.cssText = "position:fixed;inset:0;z-index:99999;";
      document.body.appendChild(o);
    }, 300);
  </script>
</body></html>`;

// Giả lập browser.* cho isolated world.
const BROWSER_STUB = `
  window.__sent = [];
  window.__store = {};
  window.__changeListeners = [];
  window.__messageListeners = [];
  globalThis.browser = {
    storage: {
      local: {
        get: async (keys) => Object.fromEntries([].concat(keys).filter((k) => k in __store).map((k) => [k, __store[k]])),
        set: async (obj) => {
          Object.assign(__store, obj);
          const changes = Object.fromEntries(Object.keys(obj).map((k) => [k, { newValue: obj[k] }]));
          __changeListeners.forEach((l) => l(changes, "local"));
        },
      },
      onChanged: { addListener: (l) => __changeListeners.push(l) },
    },
    runtime: {
      sendMessage: async (m) => { __sent.push(m); return window.__reply(m); },
      onMessage: { addListener: (l) => __messageListeners.push(l) },
    },
  };
  // Giả lập background cho picker: savePicked ghi rule vào storage như saveRules thật.
  window.__aiRules = [];
  window.__reply = (m) => {
    if (m.type === "savePicked") {
      const key = "site:127.0.0.1";
      const site = { hide: [], popupDomains: [], blockDomains: [], ...(__store[key] || {}) };
      site.hide = [...site.hide, ...m.rules.filter((r) => r.type === "hide").map((r, i) => ({ id: "p" + Date.now() + i, ...r }))];
      browser.storage.local.set({ [key]: site });
      return { ok: true, result: null };
    }
    if (m.type === "capture") return { ok: true, result: null };
    if (m.type === "pickAI") return { ok: true, result: window.__aiRules };
    if (m.type === "cosmetic") return { ok: true, result: m.initial ? [".list-ad"] : (m.tokens.includes(".tok-ad") ? [".tok-ad"] : []) };
    // Không cho tải lại trang trong test: trả lỗi để kiểm luồng báo lỗi của ô "Chạm để tải".
    if (m.type === "allowWidget") return { ok: false, error: "thử" };
    return undefined;
  };
  window.__picker = (s) => document.querySelector("[data-adsblocker=picker]")?.shadowRoot.querySelector(s);
  window.__ask = (m) => Promise.all(__messageListeners.map((l) => l(m))).then((r) => r.find((x) => x !== undefined));
`;

class CDP {
  constructor(url) {
    this.ws = new WebSocket(url);
    this.id = 0;
    this.pending = new Map();
    this.events = [];
    this.ws.onmessage = ({ data }) => {
      const msg = JSON.parse(data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
      } else if (msg.method) this.events.push(msg);
    };
  }
  open() { return new Promise((r) => { this.ws.onopen = r; }); }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }
}

const hits = [];
const server = createServer((req, res) => {
  hits.push(req.url);
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(PAGE);
}).listen(0, "127.0.0.1");
await new Promise((r) => server.once("listening", r));
const port = server.address().port;
const pageUrl = `http://127.0.0.1:${port}/?utm_source=news&keep=1`;

const profile = mkdtempSync(join(tmpdir(), "adsblocker-smoke-"));
const chrome = spawn(CHROME, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--window-size=800,600", "about:blank",
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
  await cdp.send("Runtime.enable");

  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: read("content/main_world.js") });
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", {
    worldName: "adsblocker",
    source: BROWSER_STUB + read("rules/validate.js") + read("content/candidates.js") + read("content/content.js") + read("content/privacy.js") + read("content/picker.js"),
  });
  await cdp.send("Page.navigate", { url: pageUrl });
  await sleep(2000);

  const ctx = cdp.events.filter((e) => e.method === "Runtime.executionContextCreated")
    .map((e) => e.params.context).filter((c) => c.name === "adsblocker").pop();
  const evalIn = async (expression, contextId) => {
    const { result, exceptionDetails } = await cdp.send("Runtime.evaluate",
      { expression, awaitPromise: true, returnByValue: true, ...(contextId ? { contextId } : {}) });
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description || exceptionDetails.text);
    return result.value;
  };
  const page = (e) => evalIn(e);
  const iso = (e) => evalIn(e, ctx.id);
  const click = async (selector) => {
    const { x, y } = await page(`(() => { const el = document.querySelector(${JSON.stringify(selector)});
      el.scrollIntoView({ block: "center" });
      const r = el.getBoundingClientRect();
      return { x: r.left + Math.min(r.width / 2, 20), y: r.top + r.height / 2 }; })()`);
    for (const type of ["mousePressed", "mouseReleased"]) {
      await cdp.send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
    }
    await sleep(200);
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

  await check("chỉ 1 listener onMessage (Safari trả undefined khi có nhiều); nạp lại script không chạy lần hai", async () => {
    assert.equal(await iso(`__messageListeners.length`), 1);
    await evalIn(read("content/content.js") + read("content/privacy.js") + read("content/picker.js"), ctx.id);
    assert.equal(await iso(`__messageListeners.length`), 1);
  });

  await check("gỡ lớp phủ trong suốt (có sẵn và chèn sau)", async () => {
    assert.equal(await page(`!!document.getElementById("overlay")`), false);
    assert.equal(await page(`!!document.getElementById("late-overlay")`), false);
    const kinds = await iso(`__sent.filter((m) => m.kind === "overlay").length`);
    assert.ok(kinds >= 2, `overlay reports: ${kinds}`);
  });

  await check("chặn window.open khi bấm vào chữ thường (click-hijack)", async () => {
    await click("#text");
    assert.deepEqual(await page(`window.opened.at(-1)`), ["hijack", false]);
  });

  await check("chặn window.open tới domain khác link được bấm", async () => {
    await click("#link");
    assert.deepEqual(await page(`window.opened.at(-1)`), ["link-hijack", false]);
  });

  await check("cho phép window.open từ nút bấm cùng site", async () => {
    await click("#share");
    assert.deepEqual(await page(`window.opened.at(-1)`), ["share", true]);
  });

  await check("chặn click giả lên <a target=_blank> tách rời", async () => {
    await page(`document.addEventListener("click", (e) => {
      if (e.target.id !== "text") return;
      const a = document.createElement("a"); a.href = "https://ads.bad/x"; a.target = "_blank"; a.click();
    }, { once: true })`);
    const before = await iso(`__sent.filter((m) => m.kind === "popup").length`);
    await click("#text");
    const after = await iso(`__sent.filter((m) => m.kind === "popup").length`);
    assert.ok(after >= before + 2, `${before} → ${after}`);
  });

  await check("ghi log popup kèm lý do", async () => {
    const reasons = await iso(`__sent.filter((m) => m.kind === "popup").map((m) => m.reason)`);
    assert.ok(reasons.includes("bấm vào nội dung thường"), reasons.join(","));
    assert.ok(reasons.includes("khác link được bấm"), reasons.join(","));
  });

  let bannerId;
  await check("snapshot tìm ra banner quảng cáo, vẽ số lên trang", async () => {
    const snap = await iso(`__ask({ type: "snapshot" })`);
    const banner = snap.page.candidates.find((c) => c.selector === "#banner");
    assert.ok(banner, JSON.stringify(snap.page.candidates.map((c) => c.selector)));
    assert.ok(banner.hints.includes("ad-keyword") && banner.hints.includes("banner-size"));
    assert.ok(!/Nội dung/.test(JSON.stringify(snap)), "snapshot không được chứa chữ của trang");
    assert.equal(await page(`!!document.querySelector("[data-adsblocker=marks]")`), true);
    await iso(`__ask({ type: "clearMarks" })`);
    assert.equal(await page(`!!document.querySelector("[data-adsblocker=marks]")`), false);
    bannerId = banner.id;
  });

  await check("validate trên DOM: nhận selector đúng, loại selector quá rộng", async () => {
    const result = await iso(`__ask({ type: "validate", rules: [
      { type: "hide", candidateId: ${bannerId}, selector: "div.ad-banner", reason: "banner", confidence: 0.9 },
      { type: "hide", candidateId: ${bannerId}, selector: "body > p, .ad-banner", reason: "rộng", confidence: 0.9 },
      { type: "block_domain", domain: "fonts.gstatic.com", reason: "CDN", confidence: 0.9 },
    ] })`);
    assert.deepEqual(result.accepted.map((r) => r.selector), ["div.ad-banner", "#banner"]);
    assert.deepEqual(result.rejected.map((r) => r.reason), ["domain dùng chung, chặn sẽ hỏng trang"]);
  });

  await check("áp rule đã lưu: banner bị ẩn ngay khi storage đổi", async () => {
    await iso(`browser.storage.local.set({ "site:127.0.0.1": { hide: [{ id: "1", selector: "div.ad-banner" }] } })`);
    await sleep(200);
    assert.equal(await page(`getComputedStyle(document.getElementById("banner")).display`), "none");
  });

  // ------------------------------------------------------------ chế độ chọn quảng cáo

  const picker = (expr) => iso(`(() => { const $ = window.__picker; return ${expr}; })()`);
  const pressButton = async (act) => {
    await picker(`$("[data-act=${act}]").click()`);
    await sleep(300);
  };
  // Chờ điều kiện (timer của tab headless bị gom về mốc 1 giây nên không chờ cố định được).
  const waitFor = async (expr, ms = 5000) => {
    for (const end = Date.now() + ms; Date.now() < end; await sleep(100)) if (await picker(expr)) return;
    throw new Error(`hết giờ chờ: ${expr}`);
  };

  await check("chế độ chọn: chạm ảnh trong banner → chọn khung #banner, trang không nhận click", async () => {
    await iso(`browser.storage.local.set({ "site:127.0.0.1": {} })`);
    await sleep(200);
    await iso(`__ask({ type: "startPicker" })`);
    const before = await page(`window.opened.length`);
    await click("#ad-img");
    assert.equal(await page(`window.opened.length`), before, "click lọt xuống trang");
    assert.equal(await picker(`$(".sel").textContent`), "#banner");
    assert.equal(await picker(`$(".scope-global").disabled`), false, "#banner có dấu hiệu quảng cáo → được áp mọi trang");
    const domains = await picker(`[...$(".domains").querySelectorAll("input")].map((i) => [i.dataset.type, i.dataset.domain, i.checked])`);
    assert.deepEqual(domains, [["block_domain", "ads.adnet.io", true], ["block_popup_domain", "adclick.adnet.io", false]]);
  });

  await check("Hẹp hơn / Rộng hơn đổi khối được chọn", async () => {
    await pressButton("shrink");
    assert.notEqual(await picker(`$(".sel").textContent`), "#banner");
    await pressButton("grow");
    assert.equal(await picker(`$(".sel").textContent`), "#banner");
  });

  await check("Ẩn (cơ bản): lưu selector + dự phòng + đường dẫn cấu trúc + domain, banner bị ẩn", async () => {
    await pressButton("hide");
    const saved = await iso(`__sent.filter((m) => m.type === "savePicked").at(-1).rules`);
    assert.equal(saved[0].type, "hide");
    assert.equal(saved[0].selector, "#banner");
    assert.ok(saved[0].fallback.includes("div.ad-banner"), JSON.stringify(saved[0]));
    assert.match(saved[0].structural, /^body > div:nth-of-type\(\d+\)$/);
    assert.equal(saved[0].source, "manual");
    assert.equal(saved[0].scope, "site");
    assert.deepEqual(saved.slice(1).map((r) => [r.type, r.domain]), [["block_domain", "ads.adnet.io"]]);
    assert.equal(await page(`!!document.querySelector("[data-adsblocker=picker]")`), false, "picker chưa đóng");
    assert.equal(await page(`getComputedStyle(document.getElementById("banner")).display`), "none");
  });

  await check("trang đổi id/class: đường dẫn cấu trúc vẫn ẩn banner", async () => {
    await page(`(() => { const b = document.getElementById("banner"); b.id = "slot-x"; b.className = "zz";
      document.body.appendChild(document.createElement("i")); })()`);
    // Hẹn giờ 500ms; Chrome headless gom timer của tab nền về mốc 1 giây.
    await sleep(1500);
    assert.equal(await page(`getComputedStyle(document.getElementById("slot-x")).display`), "none");
  });

  await check("Ẩn bằng AI: đề xuất qua validate, lưu cả rule AI → mọi khối cùng loại bị ẩn", async () => {
    await iso(`window.__aiRules = [
      { type: "hide", candidateId: 1, selector: ".sponsor-box", reason: "cùng loại", confidence: 0.9 },
      { type: "block_domain", domain: "fonts.gstatic.com", reason: "CDN", confidence: 0.9 },
    ]`);
    await iso(`__ask({ type: "startPicker" })`);
    await click("#sp1");
    assert.equal(await picker(`$(".sel").textContent`), "#sp1");
    assert.equal(await picker(`$(".scope-global").disabled`), true);
    assert.match(await picker(`$(".scope-note").textContent`), /không có dấu hiệu quảng cáo/);
    await pressButton("ai");
    await waitFor(`$(".ai-result label")`);
    const items = await picker(`[...$(".ai-result").querySelectorAll("label")].map((l) => [l.querySelector("code").textContent, l.querySelector("input").checked])`);
    assert.deepEqual(items, [["#sp1", true], [".sponsor-box", true]]);
    assert.equal(await picker(`$(".save").hidden`), false);
    await pressButton("save");
    const saved = await iso(`__sent.filter((m) => m.type === "savePicked").at(-1).rules`);
    assert.deepEqual(saved.map((r) => [r.selector, r.source]), [["#sp1", "manual"], [".sponsor-box", "ai"]]);
    assert.equal(await page(`getComputedStyle(document.getElementById("sp2")).display`), "none");
  });

  await check("Huỷ thoát chế độ chọn, click lại về trang bình thường", async () => {
    await iso(`__ask({ type: "startPicker" })`);
    await pressButton("cancel");
    assert.equal(await page(`!!document.querySelector("[data-adsblocker=picker]")`), false);
    await click("#share");
    assert.deepEqual(await page(`window.opened.at(-1)`), ["share", true]);
  });
  await check("rule mọi trang (global) và dùng chung rule với tên miền khác (aliases) áp lên trang", async () => {
    const display = (id) => page(`getComputedStyle(document.getElementById(${JSON.stringify(id)})).display`);
    await iso(`browser.storage.local.set({ "site:127.0.0.1": {}, global: { hide: [{ id: "g", selector: "div.sponsor-box" }], popupDomains: [] } })`);
    await sleep(1500);
    assert.equal(await display("sp1"), "none");
    assert.equal(await display("sp2"), "none");
    await iso(`browser.storage.local.set({ global: {}, "site:goc.example": { hide: [{ id: "a", selector: "#sp2" }] }, aliases: { "127.0.0.1": "goc.example" } })`);
    await sleep(1500);
    assert.equal(await display("sp1"), "block");
    assert.equal(await display("sp2"), "none", "rule của site gốc không áp lên tên miền dùng chung");
  });

  await check("domain chặn tab mới lưu ở global áp cho mọi trang", async () => {
    await iso(`browser.storage.local.set({ aliases: {}, global: { hide: [], popupDomains: [{ id: "p", domain: "x.bad-ads.net" }] } })`);
    await sleep(1500);
    await page(`document.getElementById("share").addEventListener("click", () => {
      window.opened.push(["global-popup", !!window.open("https://cdn.x.bad-ads.net/go")]); }, { once: true })`);
    await click("#share");
    assert.deepEqual(await page(`window.opened.find((o) => o[0] === "global-popup")`), ["global-popup", false]);
  });
  // ------------------------------------------------------------ chống theo dõi + bộ lọc

  await check("xoá tham số theo dõi trên thanh địa chỉ, giữ tham số chức năng", async () => {
    assert.equal(await page(`location.search`), "?keep=1");
  });

  await check("link: xoá tham số theo dõi, gỡ link bọc Google, bỏ thuộc tính ping (ngay khi chạm)", async () => {
    await page(`["tracked", "wrapped"].forEach((id) => document.getElementById(id).dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })))`);
    assert.equal(await page(`document.getElementById("tracked").href`), "https://dest.example/p?id=5");
    assert.equal(await page(`document.getElementById("wrapped").href`), "https://dest.example/q");
    assert.equal(await page(`document.getElementById("wrapped").hasAttribute("ping")`), false);
  });

  await check("sendBeacon tới bên thứ ba bị chặn, cùng trang vẫn gửi", async () => {
    await page(`navigator.sendBeacon("http://localhost:${port}/beacon-3p", "x"); navigator.sendBeacon("/beacon-1p", "x")`);
    await sleep(800);
    assert.ok(hits.includes("/beacon-1p"), hits.join(","));
    assert.ok(!hits.includes("/beacon-3p"), "beacon bên thứ ba vẫn gửi đi");
  });

  await check("widget mạng xã hội → ô Chạm để tải; chạm gửi allowWidget, lỗi thì báo trên nút", async () => {
    assert.equal(await page(`!!document.getElementById("fbw")`), false, "iframe Facebook chưa bị thay");
    assert.equal(await page(`document.getElementById("tw").previousElementSibling.dataset.adsblocker`), "widget");
    const button = `document.querySelector("[data-adsblocker=widget]").shadowRoot.querySelector("button")`;
    assert.match(await page(`${button}.textContent`), /Facebook/);
    await page(`${button}.click()`);
    await sleep(300);
    assert.match(await page(`${button}.textContent`), /Lỗi: thử/);
    assert.deepEqual(await iso(`__sent.filter((m) => m.type === "allowWidget").map((m) => m.provider)`), ["facebook"]);
  });

  await check("ẩn phần tử theo bộ lọc: selector theo tên miền ngay từ đầu, selector chung theo token có trên trang", async () => {
    assert.equal(await page(`getComputedStyle(document.getElementById("la")).display`), "none");
    assert.equal(await page(`getComputedStyle(document.getElementById("ta")).display`), "none");
    const asked = await iso(`__sent.filter((m) => m.type === "cosmetic").flatMap((m) => m.tokens)`);
    assert.ok(asked.includes(".tok-ad") && asked.includes("#banner"), asked.slice(0, 10).join(","));
  });

  await check("tắt cả 2 công tắc: không ẩn theo bộ lọc, không chặn popup, không làm sạch link", async () => {
    await iso(`browser.storage.local.set({ features: { ads: false, tracking: false } })`);
    await sleep(1500);
    assert.equal(await page(`getComputedStyle(document.getElementById("la")).display`), "block");
    await click("#text");
    assert.deepEqual(await page(`window.opened.at(-1)`), ["hijack", true]);
    await page(`(() => { const a = document.getElementById("tracked"); a.href = "https://dest.example/p?utm_source=x";
      a.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })); })()`);
    assert.equal(await page(`document.getElementById("tracked").href`), "https://dest.example/p?utm_source=x");
    await iso(`browser.storage.local.set({ features: { ads: true, tracking: true } })`);
    await sleep(1500);
    assert.equal(await page(`getComputedStyle(document.getElementById("la")).display`), "none");
  });
  // ------------------------------------------------------------ chẩn đoán + ngoại lệ

  await check("chẩn đoán: ảnh lỗi, ảnh lazy-load chưa nạp, khối có ảnh bị bộ lọc ẩn", async () => {
    const diag = await iso(`__ask({ type: "diagnostics" })`);
    // Ảnh quảng cáo trong banner (ads.adnet.io, không có mạng trong test) cũng là ảnh lỗi thật.
    assert.deepEqual(diag.brokenImages.map((i) => [i.domain, i.path]), [["ads.adnet.io", "/x.png"], ["127.0.0.1", "/missing.jpg"]]);
    assert.deepEqual(diag.lazyImages.map((i) => i.domain), ["lazy.cdn.vn"]);
    const listAd = diag.hidden.find((h) => h.selector === ".list-ad");
    assert.deepEqual([listAd.source, listAd.count, listAd.media], ["filter", 1, 1]);
    assert.equal(diag.hidden[0].selector, ".list-ad", "khối có ảnh phải xếp đầu");
  });

  await check("ngoại lệ: bỏ ẩn selector, cho mở tab mới, giữ lớp phủ — chỉ trên trang này", async () => {
    await iso(`browser.storage.local.set({ "site:127.0.0.1": { unhide: [{ id: "x", selector: ".list-ad" }], allowPopups: true, keepOverlays: true } })`);
    await sleep(1500);
    assert.equal(await page(`getComputedStyle(document.getElementById("la")).display`), "block");
    await click("#text");
    assert.deepEqual(await page(`window.opened.at(-1)`), ["hijack", true]);
    await page(`(() => { const o = document.createElement("div"); o.id = "keep-overlay";
      o.style.cssText = "position:fixed;inset:0;z-index:99999;"; document.body.appendChild(o); })()`);
    await sleep(1500);
    assert.equal(await page(`!!document.getElementById("keep-overlay")`), true);
    await page(`document.getElementById("keep-overlay").remove()`);
    await iso(`browser.storage.local.set({ "site:127.0.0.1": {} })`);
    await sleep(1500);
    assert.equal(await page(`getComputedStyle(document.getElementById("la")).display`), "none");
  });
} finally {
  chrome.kill();
  server.close();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
