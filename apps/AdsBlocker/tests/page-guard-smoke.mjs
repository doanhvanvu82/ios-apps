// Smoke test trên Chrome headless: chặn tab-under (main_world.js, Navigation API) và mở khoá cuộn sau khi ẩn hộp thoại
// bắt tắt chặn quảng cáo (content.js + main_world.js).
//   node tests/page-guard-smoke.mjs
// Trang giả phục vụ qua CDP Fetch (tên miền .test không cần DNS); click/cuộn bằng Input.* nên là thao tác thật (isTrusted).
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";

const EXT = new URL("../WebExtension/", import.meta.url).pathname;
const CHROME = process.env.CHROME || "google-chrome";
const read = (p) => readFileSync(join(EXT, p), "utf8");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const NEWS = `<!doctype html><html><body style="margin:0">
  <button id="tabunder" style="position:absolute;left:10px;top:10px;width:120px;height:40px"
    onclick="window.open('https://news.test/real'); location.href = 'https://ads.adnet.test/landing'">Đọc tiếp</button>
  <a id="adlink" href="https://ads.adnet.test/l" style="position:absolute;left:10px;top:60px;width:120px;height:40px;display:block"
    onclick="window.open('https://news.test/real')">Chương 2</a>
  <button id="opener" style="position:absolute;left:10px;top:110px;width:120px;height:40px"
    onclick="window.open('https://news.test/real')">Mở tab</button>
  <a id="out" href="https://other.test/" style="position:absolute;left:10px;top:160px;width:120px;height:40px;display:block">Trang khác</a>
  <a id="blanklink" href="https://news.test/real" target="_blank" style="position:absolute;left:10px;top:210px;width:120px;height:40px;display:block"
    onclick="setTimeout(() => { location.href = 'https://ads.adnet.test/landing'; }, 50)">Chương 3</a>
  <script>
    document.addEventListener("adsblocker:blocked", (e) => console.log("adsblocker:blocked", e.detail));
  </script>
</body></html>`;

// Hộp thoại chống chặn quảng cáo: khoá cuộn bằng class (overflow:hidden), lớp nền mờ riêng, chặn wheel/touchmove ở document.
const BLOG = `<!doctype html><html><head><style>
  body.modal-open { overflow: hidden; }
  html.modal-open { overflow: hidden; }
</style></head><body class="modal-open" style="margin:0">
  <div style="height:5000px;background:linear-gradient(#fff,#ccc)">Bài viết dài</div>
  <div class="aab-backdrop" style="position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:998"></div>
  <div class="aab-modal" style="position:fixed;inset:0;z-index:999;display:flex;align-items:center;justify-content:center">
    <p style="background:#fff;padding:20px">Vui lòng tắt trình chặn quảng cáo</p></div>
  <script>
    document.documentElement.classList.add("modal-open");
    document.addEventListener("wheel", (e) => e.preventDefault(), { passive: false });
    document.addEventListener("touchmove", (e) => e.preventDefault(), { passive: false });
  </script>
</body></html>`;

// Script chống chặn quảng cáo hiện hộp thoại + lớp nền mờ MUỘN (sau khi phát hiện bị chặn), rồi ghi lại lớp nền ở
// khung hình đầu tiên được vẽ: còn hiện = màn hình nháy tối.
const LATE = `<!doctype html><html><body style="margin:0">
  <div style="height:3000px">Bài viết</div>
  <script>
    setTimeout(() => {
      const backdrop = Object.assign(document.createElement("div"), { className: "aab-backdrop" });
      backdrop.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:998";
      const modal = Object.assign(document.createElement("div"), { className: "aab-modal", textContent: "Tắt trình chặn quảng cáo" });
      modal.style.cssText = "position:fixed;inset:0;z-index:999";
      document.body.append(backdrop, modal);
      document.body.style.overflow = "hidden";
      requestAnimationFrame(() => { window.__firstFrame = getComputedStyle(backdrop).display; });
    }, 300);
  </script>
</body></html>`;

const PAGES = {
  "https://news.test/a": NEWS, "https://news.test/real": "<p>Nội dung thật</p>",
  "https://ads.adnet.test/landing": "<p>QUẢNG CÁO</p>", "https://ads.adnet.test/l": "<p>QUẢNG CÁO</p>",
  "https://other.test/": "<p>Trang khác</p>", "https://blog.test/b": BLOG, "https://late.test/c": LATE,
  "https://quiz.test/d": BLOG,
};

// Rule đã lưu: ẩn hộp thoại + mở khoá cuộn (như bấm Ẩn trong bảng chọn với ô "Mở khoá cuộn" được tick); rule của
// late.test là rule cũ chưa có selector lớp nền (chỉ còn JS dò lúc chạy). quiz.test chưa có rule (thử bảng chọn).
const BROWSER_STUB = `
  window.__store = {
    "site:blog.test": { hide: [{ id: "1", selector: "div.aab-modal", unlockScroll: true }], popupDomains: [], blockDomains: [] },
    "site:late.test": { hide: [{ id: "2", selector: "div.aab-modal", unlockScroll: true }], popupDomains: [], blockDomains: [] },
  };
  window.__sent = [];
  window.__changeListeners = [];
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
      sendMessage: async (message) => {
        window.__sent.push(message);
        return { ok: true, result: [] };
      },
      onMessage: { addListener: () => {} },
    },
  };
`;

class CDP {
  constructor(url) {
    this.ws = new WebSocket(url);
    this.id = 0;
    this.pending = new Map();
    this.events = [];
    this.listeners = [];
    this.ws.onmessage = ({ data }) => {
      const msg = JSON.parse(data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
      } else if (msg.method) {
        this.events.push(msg);
        this.listeners.forEach((l) => l(msg));
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

const profile = mkdtempSync(join(tmpdir(), "adsblocker-guard-"));
const chrome = spawn(CHROME, [
  "--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
  "--no-first-run", "--window-size=800,600", "about:blank",
], { stdio: "ignore" });

let failed = false;
try {
  const portFile = join(profile, "DevToolsActivePort");
  for (let i = 0; i < 100 && !existsSync(portFile); i++) await sleep(100);
  const devPort = readFileSync(portFile, "utf8").split("\n")[0];
  const targets = await (await fetch(`http://127.0.0.1:${devPort}/json/list`)).json();
  const cdp = new CDP(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await cdp.open();
  await cdp.send("Page.enable");
  await cdp.send("Runtime.enable");
  cdp.listeners.push(({ method, params }) => {
    if (method !== "Fetch.requestPaused") return;
    const url = params.request.url.split("?")[0];
    cdp.send("Fetch.fulfillRequest", {
      requestId: params.requestId, responseCode: 200,
      responseHeaders: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
      body: Buffer.from(PAGES[url] || "<p>404</p>").toString("base64"),
    });
  });
  await cdp.send("Fetch.enable", { patterns: [{ urlPattern: "https://*.test/*" }] });
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: read("content/main_world.js") });
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", {
    worldName: "adsblocker",
    source: BROWSER_STUB + read("rules/validate.js") + read("content/candidates.js") + read("content/content.js") +
      read("content/picker.js"),
  });

  const evaluate = async (expression, contextId) => {
    const { result, exceptionDetails } = await cdp.send("Runtime.evaluate",
      { expression, awaitPromise: true, returnByValue: true, ...(contextId ? { contextId } : {}) });
    if (exceptionDetails) throw new Error(exceptionDetails.exception?.description || exceptionDetails.text);
    return result.value;
  };
  const open = async (url) => {
    // Tab mới do window.open mở chiếm phần hiển thị → tab test không nhận wheel (Input.* treo) nếu không đưa lên trước.
    await cdp.send("Page.bringToFront");
    await cdp.send("Page.navigate", { url });
    await sleep(800);
  };
  const tap = async (selector) => {
    const { x, y } = await evaluate(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
    for (const type of ["mousePressed", "mouseReleased"]) {
      await cdp.send("Input.dispatchMouseEvent", { type, x, y, button: "left", clickCount: 1 });
    }
    await sleep(700);
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

  // Số tab đang mở trang nội dung thật (tab mới do tab-under mở phải bị đóng, nội dung mở ngay tại tab test).
  const realTabs = async () => (await (await fetch(`http://127.0.0.1:${devPort}/json/list`)).json())
    .filter((t) => t.type === "page" && t.url === "https://news.test/real").length;
  const blockedLog = [];
  cdp.listeners.push(({ method, params }) => {
    if (method === "Runtime.consoleAPICalled" && params.args[0]?.value === "adsblocker:blocked") blockedLog.push(params.args[1].value);
  });

  await check("tab-under: window.open rồi location.href sang site khác → đóng tab mới, mở nội dung ngay tại tab này", async () => {
    blockedLog.length = 0;
    await open("https://news.test/a");
    await tap("#tabunder");
    assert.equal(await evaluate("location.href"), "https://news.test/real");
    // Back được về trang cũ.
    assert.equal(await evaluate("navigation.entries().at(-2).url"), "https://news.test/a");
    assert.equal(await realTabs(), 1);
    assert.deepEqual(blockedLog.map((d) => JSON.parse(d)).map((l) => [l.kind, l.url]), [["tabunder", "https://ads.adnet.test/landing"]]);
  });

  await check("tab-under: link quảng cáo tự mở tab nội dung thật trong onclick → không đi theo link, mở nội dung tại tab này", async () => {
    await open("https://news.test/a");
    await tap("#adlink");
    assert.equal(await evaluate("location.href"), "https://news.test/real");
    assert.equal(await realTabs(), 1);
  });

  await check("tab-under: link target=_blank thật rồi tab cũ bị chuyển sang quảng cáo → mở nội dung tại tab này", async () => {
    await open("https://news.test/a");
    await tap("#blanklink");
    await sleep(300);
    assert.equal(await evaluate("location.href"), "https://news.test/real");
  });

  await check("cú chạm mới sau khi mở tab → bấm link sang trang khác vẫn đi bình thường", async () => {
    await open("https://news.test/a");
    await tap("#opener");
    await tap("#out");
    assert.equal(await evaluate("location.href"), "https://other.test/");
  });

  await check("hộp thoại chống chặn quảng cáo: ẩn hộp thoại + lớp nền mờ, gỡ overflow:hidden, cuộn được bằng wheel", async () => {
    await open("https://blog.test/b");
    assert.equal(await evaluate(`getComputedStyle(document.querySelector(".aab-modal")).display`), "none");
    assert.equal(await evaluate(`getComputedStyle(document.querySelector(".aab-backdrop")).display`), "none");
    assert.equal(await evaluate(`getComputedStyle(document.body).overflowY`), "auto");
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseWheel", x: 400, y: 300, deltaX: 0, deltaY: 600 });
    await sleep(600);
    assert.ok(await evaluate("window.scrollY") > 0, "trang phải cuộn được");
  });

  await check("trang khoá lại kiểu iOS (body position:fixed, top âm) → tự gỡ, trả về đúng vị trí đang đọc", async () => {
    await evaluate(`window.scrollTo(0, 0); Object.assign(document.body.style, { position: "fixed", top: "-300px", width: "100%" })`);
    await sleep(500);
    assert.equal(await evaluate(`getComputedStyle(document.body).position`), "static");
    assert.equal(await evaluate("Math.round(window.scrollY)"), 300);
  });

  await check("hộp thoại + lớp nền chèn muộn: lớp nền đã ẩn ngay ở khung hình đầu tiên (không nháy tối)", async () => {
    await open("https://late.test/c");
    await sleep(300);
    assert.equal(await evaluate("window.__firstFrame"), "none");
    assert.equal(await evaluate(`getComputedStyle(document.body).overflowY`), "auto");
  });

  await check("bảng chọn: hộp thoại phủ màn hình → tự tick Mở khoá cuộn, rule lưu kèm selector lớp nền", async () => {
    await open("https://quiz.test/d");
    const iso = cdp.events.filter((e) => e.method === "Runtime.executionContextCreated")
      .map((e) => e.params.context).filter((c) => c.name === "adsblocker").pop().id;
    await evaluate("AdsBlockerPicker.start()", iso);
    await tap(".aab-modal p");
    const shadow = `document.querySelector("[data-adsblocker=picker]").shadowRoot`;
    assert.equal(await evaluate(`${shadow}.querySelector(".unlock").checked`, iso), true);
    await evaluate(`${shadow}.querySelector("[data-act=hide]").click()`, iso);
    await sleep(300);
    const [rule] = await evaluate(`window.__sent.find((m) => m.type === "savePicked").rules`, iso);
    assert.equal(rule.unlockScroll, true);
    assert.equal(rule.fallback[0], "div.aab-backdrop");
  });
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
