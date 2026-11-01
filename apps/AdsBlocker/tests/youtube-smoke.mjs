// Smoke test YouTube trên Chrome headless: chặn quảng cáo của extension (content/main_world.js) trên trang m.youtube.com.
//   node tests/youtube-smoke.mjs
// Request tới https://m.youtube.com được trả nội dung giả qua CDP Fetch (youtube.com có HSTS preload nên không dùng http local được).
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";

const EXT = new URL("../WebExtension/", import.meta.url).pathname;
const CHROME = process.env.CHROME || "google-chrome";
const read = (p) => readFileSync(join(EXT, p), "utf8");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PAGE = `<!doctype html><html><head>
<script>var ytInitialPlayerResponse = {"adPlacements":[{"x":1}],"playerAds":[{"x":1}],"videoDetails":{"videoId":"v1"}};</script>
</head><body>
  <div id="player-container-id" class="player-container"><div id="player">
    <div id="movie_player" class="html5-video-player"><video id="video"></video>
      <button class="ytp-ad-skip-button" onclick="window.skipped = (window.skipped || 0) + 1">Bỏ qua</button></div>
    <div id="player-overlay" class="ytp-cued-thumbnail-overlay">lớp phủ ngoài #movie_player</div>
  </div></div>
  <ytm-rich-item-renderer id="feed-ad"><ad-slot-renderer>Quảng cáo</ad-slot-renderer></ytm-rich-item-renderer>
  <ytm-rich-item-renderer id="feed-ok"><span>Video thường</span></ytm-rich-item-renderer>
  <video id="pip" disablepictureinpicture></video>
  <script>
    window.visEvents = 0;
    document.addEventListener("visibilitychange", () => window.visEvents++);
  </script>
</body></html>`;

const PLAYER = JSON.stringify({ adPlacements: [{ x: 1 }], adSlots: [{ x: 1 }], streamingData: { formats: [] } });

const BROWSER_STUB = `
  window.__store = {};
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
      sendMessage: async () => ({ ok: true, result: [] }),
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

const profile = mkdtempSync(join(tmpdir(), "adsblocker-yt-"));
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
    const json = new URL(params.request.url).pathname.startsWith("/youtubei/v1/player");
    cdp.send("Fetch.fulfillRequest", {
      requestId: params.requestId, responseCode: 200,
      responseHeaders: [{ name: "Content-Type", value: json ? "application/json" : "text/html; charset=utf-8" }],
      body: Buffer.from(json ? PLAYER : PAGE).toString("base64"),
    });
  });
  await cdp.send("Fetch.enable", { patterns: [{ urlPattern: "https://m.youtube.com/*" }] });

  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: read("content/main_world.js") });
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", {
    worldName: "adsblocker",
    source: BROWSER_STUB + read("rules/validate.js") + read("content/candidates.js") + read("content/content.js"),
  });
  await cdp.send("Page.navigate", { url: "https://m.youtube.com/watch?v=v1" });
  await sleep(1500);

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
  const display = (id) => page(`getComputedStyle(document.getElementById("${id}")).display`);

  const check = async (name, fn) => {
    try {
      await fn();
      console.log(`✔ ${name}`);
    } catch (error) {
      failed = true;
      console.log(`✖ ${name}\n  ${error.message}`);
    }
  };

  await check("ytInitialPlayerResponse inline: bỏ trường quảng cáo, giữ dữ liệu video", async () => {
    assert.deepEqual(await page(`Object.keys(window.ytInitialPlayerResponse)`), ["videoDetails"]);
  });

  await check("fetch youtubei/v1/player → response.json() đã bỏ quảng cáo", async () => {
    assert.deepEqual(await page(`fetch("/youtubei/v1/player").then((r) => r.json()).then(Object.keys)`), ["streamingData"]);
  });

  await check("JSON.parse: player response ở gốc và trong playerResponse của phản hồi điều hướng", async () => {
    assert.deepEqual(await page(`Object.keys(JSON.parse('{"playerAds":[1],"videoDetails":{}}'))`), ["videoDetails"]);
    assert.deepEqual(await page(`Object.keys(JSON.parse('[{"playerResponse":{"adPlacements":[1],"x":1}}]')[0].playerResponse)`), ["x"]);
  });

  await check("ẩn quảng cáo trong feed, giữ video thường", async () => {
    assert.equal(await display("feed-ad"), "none");
    assert.notEqual(await display("feed-ok"), "none");
  });

  await check("quảng cáo lọt: tắt tiếng + bấm Bỏ qua; hết quảng cáo thì trả lại tiếng", async () => {
    await page(`document.getElementById("movie_player").classList.add("ad-showing")`);
    await sleep(700);
    assert.equal(await page(`document.getElementById("video").muted`), true);
    assert.ok(await page(`window.skipped`) >= 1);
    await page(`document.getElementById("movie_player").classList.remove("ad-showing")`);
    await sleep(700);
    assert.equal(await page(`document.getElementById("video").muted`), false);
  });

  await check("tắt công tắc YouTube: không sửa dữ liệu, không ẩn feed, không bấm Bỏ qua", async () => {
    await iso(`browser.storage.local.set({ features: { ads: true, tracking: true, youtube: false } })`);
    await sleep(500);
    assert.deepEqual(await page(`Object.keys(JSON.parse('{"playerAds":[1]}'))`), ["playerAds"]);
    assert.notEqual(await display("feed-ad"), "none");
    const before = await page(`window.skipped`);
    await page(`document.getElementById("movie_player").classList.add("ad-showing")`);
    await sleep(700);
    assert.equal(await page(`window.skipped`), before);
    assert.equal(await page(`document.getElementById("video").muted`), false);
    await page(`document.getElementById("movie_player").classList.remove("ad-showing")`);
  });
} finally {
  chrome.kill();
  await sleep(300);
  rmSync(profile, { recursive: true, force: true });
}
process.exit(failed ? 1 : 0);
