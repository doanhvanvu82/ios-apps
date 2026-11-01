// background.js chạy trong node:vm với browser.* giả lập (storage, DNR, tabs, native messaging).
const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const vm = require("node:vm");

const EXT = join(__dirname, "..", "WebExtension");
const PAGE = "https://www.truyenqqto.com/truyen/1";

// Dữ liệu bộ lọc giả (thay filters/*.json sinh lúc build).
const FILTERS = {
  cosmetic: {
    genericByToken: { ".ad-box": [".ad-box"], "#top-ad": ["#top-ad"], ".safe-ad": [".safe-ad"] },
    genericAlways: ["a[href*=\"adclick\"]"],
    byDomain: { "truyenqqto.com": [".qq-ads"], "other.com": [".x"] },
    exceptions: { "truyenqqto.com": [".safe-ad"] },
  },
  tracker_index: { ads: ["doubleclick.net"], analytics: ["google-analytics.com"], session_replay: ["hotjar.com"], fingerprinting: [], social: ["connect.facebook.net"] },
  ads_network: [{ id: 1, action: { type: "block" }, condition: { requestDomains: ["manga-cdn.io", "adnet.io"] } }],
  tracking_network: [{ id: 1, action: { type: "block" }, condition: { requestDomains: ["hotjar.com"] } }],
  ad_domains: [{ id: 1, action: { type: "block" }, condition: { urlFilter: "||popads.net^" } }],
};

// Dấu hiệu trang truyện hỏng: ảnh từ CDN bị bộ lọc chặn, script quảng cáo bị rule của người dùng chặn, ảnh lỗi do trang.
const DIAG = {
  url: "https://www.truyenqqto.com/truyen/1", title: "Chương 1", totalImages: 30, timingFull: false,
  brokenImages: [{ domain: "img.manga-cdn.io", path: "/c1/1.jpg" }, { domain: "img.manga-cdn.io", path: "/c1/2.jpg" }, { domain: "i.site.vn", path: "/x.png" }],
  lazyImages: [{ domain: "lazy.cdn.vn", path: "/p.jpg" }],
  notLoaded: [{ domain: "ads.adnet.io", path: "/ad.js", type: "script" }],
  hidden: [
    { selector: ".reader-box", source: "filter", count: 1, media: 20 },
    { selector: "div.w-overlay", source: "site", ruleId: "u2", origin: "ai", count: 1, media: 0 },
  ],
};

function loadBackground({ nativeReplies = [], tabGone = false, rejectRedirect = false, thirdParties = [], rejectDomain = null, pageScripts = true } = {}) {
  const store = {};
  // Tab mở trước khi cài/cập nhật extension: Safari không chạy content script, sendMessage trả undefined.
  let pageAlive = pageScripts;
  const injected = [];
  let dnr = [];
  let enabledRulesets = new Set(["ads_custom", "ads", "tracking"]);
  // Mỗi lệnh updateDynamicRules = Safari biên dịch lại bộ rule (chậm) → test đếm số lệnh.
  const dnrCalls = [];
  const listeners = [];
  const nativeCalls = [];
  const clone = (v) => structuredClone(v);
  const browser = {
    storage: {
      local: {
        get: async (keys) => {
          if (keys === null) return clone(store);
          return Object.fromEntries([].concat(keys).filter((k) => k in store).map((k) => [k, clone(store[k])]));
        },
        set: async (items) => { Object.assign(store, clone(items)); },
        remove: async (keys) => { [].concat(keys).forEach((k) => delete store[k]); },
      },
    },
    declarativeNetRequest: {
      getDynamicRules: async () => clone(dnr),
      // Như Safari: kiểm tra tham số và NÉM LỖI NGAY LÚC GỌI (không trả promise bị từ chối); một rule hỏng → từ chối cả lệnh.
      updateDynamicRules: ({ addRules = [], removeRuleIds = [] }) => {
        dnrCalls.push({ add: addRules.length, remove: removeRuleIds.length });
        if (rejectRedirect && addRules.some((r) => r.action.type === "redirect")) throw new Error("Invalid rule action type: redirect");
        const bad = addRules.findIndex((r) => (r.condition.requestDomains || []).some((d) => !d || /[^\x00-\x7f]/.test(d) || d === rejectDomain));
        if (bad >= 0) throw new Error(`Rule at index ${bad}: requestDomains must be non-empty and cannot contain non-ASCII characters.`);
        const badRegex = addRules.findIndex((r) => /[|(]/.test(r.condition.regexFilter || ""));
        if (badRegex >= 0) throw new Error(`Rule at index ${badRegex}: regexFilter is not a supported regular expression.`);
        dnr = dnr.filter((r) => !removeRuleIds.includes(r.id)).concat(clone(addRules));
        return Promise.resolve();
      },
      getEnabledRulesets: async () => [...enabledRulesets].sort(),
      updateEnabledRulesets: async ({ enableRulesetIds = [], disableRulesetIds = [] }) => {
        enableRulesetIds.forEach((id) => enabledRulesets.add(id));
        disableRulesetIds.forEach((id) => enabledRulesets.delete(id));
      },
    },
    tabs: {
      get: async (id) => {
        if (tabGone) throw new Error("Invalid call to tabs.get(). Tab not found.");
        return { id, url: PAGE, windowId: 1 };
      },
      sendMessage: async (_tabId, message) => (!pageAlive ? undefined
        : message.type === "thirdParties" ? clone(thirdParties)
        : message.type === "diagnostics" ? clone(DIAG) : undefined),
      onRemoved: { addListener() {} },
    },
    scripting: {
      executeScript: async ({ target, files }) => { injected.push({ target, files }); pageAlive = true; },
    },
    runtime: {
      getManifest: () => JSON.parse(readFileSync(join(EXT, "manifest.json"), "utf8")),
      onStartup: { addListener() {} },
      onMessage: { addListener: (l) => listeners.push(l) },
      getURL: (path) => `ext://${path}`,
      sendNativeMessage: async (_app, payload) => {
        nativeCalls.push(payload.action);
        const next = nativeReplies.length ? nativeReplies.shift() : { ok: true, hasKey: true, model: "m" };
        if (next instanceof Error) throw next;
        return next;
      },
    },
    action: { setBadgeText: async () => {} },
  };
  const fetch = async (url) => ({ json: async () => clone(FILTERS[/(\w+)\.json$/.exec(url)[1]]) });
  const context = vm.createContext({ browser, console, setTimeout, clearTimeout, crypto, URL, structuredClone, fetch });
  for (const file of ["rules/validate.js", "background.js"]) {
    vm.runInContext(readFileSync(join(EXT, file), "utf8"), context, { filename: file });
  }
  const send = async (message, url = PAGE) => {
    const reply = await listeners[0](message, { tab: { id: 1, url, windowId: 1 } });
    if (!reply.ok) throw new Error(reply.error);
    // Như message thật: dữ liệu được tuần tự hoá (cũng bỏ prototype của realm vm để so sánh được).
    return reply.result === undefined ? undefined : JSON.parse(JSON.stringify(reply.result));
  };
  // Rule người dùng (bỏ rule xoá tham số theo dõi): [hành động, domain, điều kiện phụ].
  const userRules = () => dnr.filter((r) => r.action.type !== "redirect")
    .map((r) => [r.action.type, r.condition.requestDomains.join(","), r.condition.domainType || (r.condition.resourceTypes || []).join() || (r.condition.initiatorDomains || []).join()]);
  return { store, dnr: () => dnr, userRules, rulesets: () => [...enabledRulesets].sort(), send, nativeCalls, context, dnrCalls, injected };
}

test("savePicked: lưu theo phạm vi; 'Mọi trang' chỉ khi selector đủ điều kiện, bỏ đường dẫn cấu trúc", async () => {
  const bg = loadBackground();
  await bg.send({ type: "savePicked", rules: [
    { type: "hide", selector: "a.ads-banner", fallback: ["div.w-x", "iframe[src*=\"adnet.io\"]"], structural: "body > a:nth-of-type(2)", scope: "global", source: "manual" },
    { type: "hide", selector: "div.w-overlay", structural: "body > div:nth-of-type(3)", scope: "global", source: "manual" },
    { type: "block_domain", domain: "ads.adnet.io", source: "manual" },
    { type: "block_popup_domain", domain: "click.adnet.io", source: "manual" },
  ] });
  const site = bg.store["site:truyenqqto.com"];
  const global = bg.store.global;
  assert.deepEqual(global.hide.map((r) => [r.selector, r.structural, r.fallback]), [["a.ads-banner", undefined, ["iframe[src*=\"adnet.io\"]"]]]);
  assert.deepEqual(site.hide.map((r) => [r.selector, r.structural]), [["div.w-overlay", "body > div:nth-of-type(3)"]]);
  assert.deepEqual(site.blockDomains.map((r) => r.domain), ["ads.adnet.io"]);
  assert.deepEqual(global.popupDomains.map((r) => r.domain), ["click.adnet.io"]);
  assert.deepEqual(bg.userRules(), [["block", "ads.adnet.io", "thirdParty"], ["block", "click.adnet.io", "main_frame,sub_frame"]]);
  assert.ok(bg.dnr().every((r) => r.priority === 3));
});

test("setRuleScope: chuyển qua lại, từ chối selector tên tự đặt; deleteRule xoá cả rule global + DNR", async () => {
  const bg = loadBackground();
  await bg.send({ type: "savePicked", rules: [
    { type: "hide", selector: "a.ads-banner" }, { type: "hide", selector: "div.w-overlay" },
    { type: "block_popup_domain", domain: "click.adnet.io" },
  ] });
  const [banner, overlay] = bg.store["site:truyenqqto.com"].hide;
  await assert.rejects(bg.send({ type: "setRuleScope", host: "www.truyenqqto.com", ruleId: overlay.id, scope: "global" }), /không có dấu hiệu quảng cáo/);
  await bg.send({ type: "setRuleScope", host: "www.truyenqqto.com", ruleId: banner.id, scope: "global" });
  assert.deepEqual(bg.store.global.hide.map((r) => r.selector), ["a.ads-banner"]);
  assert.deepEqual(bg.store["site:truyenqqto.com"].hide.map((r) => r.selector), ["div.w-overlay"]);
  await bg.send({ type: "setRuleScope", host: "www.truyenqqto.com", ruleId: banner.id, scope: "site" });
  assert.deepEqual(bg.store.global.hide, []);

  const popup = bg.store.global.popupDomains[0];
  await bg.send({ type: "deleteRule", host: "www.truyenqqto.com", ruleId: popup.id });
  assert.deepEqual(bg.store.global.popupDomains, []);
  assert.deepEqual(bg.userRules(), []);
});

test("linkSite: gộp rule sang site gốc, trang phụ đọc rule của gốc; gợi ý tên miền giống; unlinkSite", async () => {
  const bg = loadBackground();
  bg.store["site:truyenqqko.com"] = { hide: [{ id: "1", selector: "#ad-top" }], popupDomains: [], blockDomains: [] };
  await bg.send({ type: "savePicked", rules: [{ type: "hide", selector: "div.w-overlay" }, { type: "hide", selector: "#ad-top" }] });

  let state = await bg.send({ type: "getTabState", tabId: 1 });
  assert.deepEqual(state.sharing.suggestions, ["truyenqqko.com"]);
  assert.equal(state.sharing.linkedTo, null);

  assert.equal(await bg.send({ type: "linkSite", host: "www.truyenqqto.com", target: "truyenqqko.com" }), "truyenqqko.com");
  assert.deepEqual(bg.store.aliases, { "truyenqqto.com": "truyenqqko.com" });
  assert.equal(bg.store["site:truyenqqto.com"], undefined);
  assert.deepEqual(bg.store["site:truyenqqko.com"].hide.map((r) => r.selector), ["#ad-top", "div.w-overlay"]);

  state = await bg.send({ type: "getTabState", tabId: 1 });
  assert.equal(state.sharing.linkedTo, "truyenqqko.com");
  assert.deepEqual(state.siteRules.hide.map((r) => r.selector), ["#ad-top", "div.w-overlay"]);
  // Rule mới trên trang phụ lưu vào site gốc.
  await bg.send({ type: "savePicked", rules: [{ type: "hide", selector: "div.promo-x" }] });
  assert.equal(bg.store["site:truyenqqko.com"].hide.length, 3);

  await bg.send({ type: "unlinkSite", host: "www.truyenqqto.com" });
  assert.deepEqual(bg.store.aliases, {});
});

test("native: lỗi khởi chạy sau khi cập nhật app → tự thử lại 1 lần; lỗi khác báo ngay", async () => {
  const launch = new Error("Invalid call to runtime.sendNativeMessage(). RBSLaunchRequest error trying to launch plugin: Launch failed.");
  let bg = loadBackground({ nativeReplies: [launch, { ok: true, hasKey: true, model: "gemini-x-flash" }] });
  let state = await bg.send({ type: "getTabState", tabId: 1 });
  assert.equal(state.settings.nativeError, null);
  assert.equal(state.settings.model, "gemini-x-flash");
  assert.deepEqual(bg.nativeCalls, ["getSettings", "getSettings"]);

  bg = loadBackground({ nativeReplies: [new Error("something else")] });
  state = await bg.send({ type: "getTabState", tabId: 1 });
  assert.match(state.settings.nativeError, /something else/);
  assert.deepEqual(bg.nativeCalls, ["getSettings"]);
});

test("getTabState: Safari không còn tìm thấy tab theo mã (mã tab đổi) → dùng URL popup gửi kèm", async () => {
  const bg = loadBackground({ tabGone: true });
  bg.store["site:truyenqqto.com"] = { hide: [{ id: "1", selector: "a.ads-banner" }], popupDomains: [], blockDomains: [] };
  const state = await bg.send({ type: "getTabState", tabId: 99, url: PAGE });
  assert.equal(state.host, "www.truyenqqto.com");
  assert.deepEqual(state.siteRules.hide.map((r) => r.selector), ["a.ads-banner"]);
});

test("công tắc tính năng: bật/tắt ruleset tĩnh + dựng lại rule động theo tính năng", async () => {
  const bg = loadBackground();
  await bg.send({ type: "savePicked", rules: [
    { type: "block_domain", domain: "ads.adnet.io" },
    { type: "block_domain", domain: "metrics.spy.io", feature: "tracking" },
    { type: "block_popup_domain", domain: "click.adnet.io" },
  ] });
  const redirect = () => bg.dnr().filter((r) => r.action.type === "redirect");
  const params = bg.context.AdsBlockerRules.TRACKING_PARAMS;
  // Mỗi tham số 2 rule urlFilter ("?key=", "&key="), không regex (Safari không hỗ trợ (a|b)).
  assert.equal(redirect().length, params.length * 2);
  assert.deepEqual(redirect().slice(0, 2).map((r) => r.condition.urlFilter), ["?utm_source=", "&utm_source="]);
  assert.ok(redirect().every((r) => !r.condition.regexFilter));
  assert.deepEqual(redirect()[0].action.redirect.transform.queryTransform.removeParams.slice(0, 2), ["utm_source", "utm_medium"]);

  await bg.send({ type: "setFeature", name: "ads", on: false });
  assert.deepEqual(bg.rulesets(), ["tracking"]);
  assert.deepEqual(bg.userRules(), [["block", "metrics.spy.io", "thirdParty"]]);
  assert.equal(redirect().length, params.length * 2);

  await bg.send({ type: "setFeature", name: "tracking", on: false });
  assert.deepEqual(bg.rulesets(), []);
  assert.deepEqual(bg.dnr(), []);

  await bg.send({ type: "setFeature", name: "ads", on: true });
  assert.deepEqual(bg.rulesets(), ["ads", "ads_custom"]);
  assert.deepEqual(bg.userRules(), [["block", "ads.adnet.io", "thirdParty"], ["block", "click.adnet.io", "main_frame,sub_frame"]]);
  assert.equal(redirect().length, 0);

  const state = await bg.send({ type: "getTabState", tabId: 1, url: PAGE });
  assert.deepEqual(state.features, { ads: true, tracking: false, youtube: true });
  assert.deepEqual(state.enabledRulesets, ["ads", "ads_custom"]);
  await assert.rejects(bg.send({ type: "setFeature", name: "bogus", on: true }), /không hợp lệ/);
});

test("Safari từ chối rule redirect xoá tham số → vẫn cài các rule còn lại, báo nativeParamStrip=false", async () => {
  const bg = loadBackground({ rejectRedirect: true });
  await bg.send({ type: "savePicked", rules: [{ type: "block_domain", domain: "ads.adnet.io" }] });
  assert.deepEqual(bg.userRules(), [["block", "ads.adnet.io", "thirdParty"]]);
  assert.equal((await bg.send({ type: "getTabState", tabId: 1, url: PAGE })).nativeParamStrip, false);
});

test("cho phép widget theo trang: rule allow cho domain widget, áp cả tên miền dùng chung", async () => {
  const bg = loadBackground();
  bg.store.aliases = { "truyenqqto.com": "truyenqqko.com" };
  bg.store["site:truyenqqko.com"] = { hide: [], popupDomains: [], blockDomains: [], allowWidgets: ["facebook", "bogus"] };
  await bg.send({ type: "setFeature", name: "tracking", on: true });
  assert.deepEqual(bg.userRules(), [["allow", "facebook.com,facebook.net", "truyenqqko.com,truyenqqto.com"]]);
});

test("cosmetic: lần đầu có selector theo tên miền (cả tên miền cha) + chung luôn áp; sau đó chỉ token; trừ ngoại lệ", async () => {
  const bg = loadBackground();
  const first = await bg.send({ type: "cosmetic", url: "https://m.truyenqqto.com/x", tokens: [".ad-box", ".safe-ad", ".nothing"], initial: true });
  assert.deepEqual(first, ["a[href*=\"adclick\"]", ".qq-ads", ".ad-box"]);
  assert.deepEqual(await bg.send({ type: "cosmetic", url: "https://m.truyenqqto.com/x", tokens: ["#top-ad"] }), ["#top-ad"]);
});

test("privacyReport: phân nhóm theo chỉ mục tracker (khớp tên miền con) + rule riêng; trạng thái đã chặn/đã tải", async () => {
  const bg = loadBackground({ thirdParties: [
    { domain: "www.google-analytics.com", count: 3, types: ["script"], loaded: true },
    { domain: "static.hotjar.com", count: 1, types: ["script"], loaded: false },
    { domain: "spy.example.io", count: 1, types: ["img"], loaded: false },
    { domain: "cdn.fonts.net", count: 2, types: ["css"], loaded: true },
  ] });
  await bg.send({ type: "savePicked", rules: [{ type: "block_domain", domain: "spy.example.io", feature: "tracking" }] });
  const report = await bg.send({ type: "privacyReport", tabId: 1, url: PAGE });
  assert.deepEqual(report.items.map((i) => [i.domain, i.category, i.status]), [
    ["www.google-analytics.com", "analytics", "loaded"],
    ["static.hotjar.com", "session_replay", "blocked"],
    ["spy.example.io", "user", "blocked"],
    ["cdn.fonts.net", null, "loaded"],
  ]);
  await bg.send({ type: "setFeature", name: "tracking", on: false });
  const off = await bg.send({ type: "privacyReport", tabId: 1, url: PAGE });
  assert.equal(off.items.find((i) => i.domain === "static.hotjar.com").status, "present");
});

test("trang chưa có content script (tab mở trước khi cài/cập nhật) → nạp script isolated vào frame chính rồi hỏi lại", async () => {
  const bg = loadBackground({ pageScripts: false, thirdParties: [{ domain: "cdn.fonts.net", count: 1, types: ["css"], loaded: true }] });
  const report = await bg.send({ type: "privacyReport", tabId: 1, url: PAGE });
  assert.deepEqual(report.items.map((i) => i.domain), ["cdn.fonts.net"]);
  assert.equal(bg.injected.length, 1);
  assert.equal(JSON.stringify(bg.injected[0].target), JSON.stringify({ tabId: 1, frameIds: [0] }));
  assert.ok(bg.injected[0].files.includes("content/content.js"));
  assert.ok(!bg.injected[0].files.includes("content/main_world.js"));
  await bg.send({ type: "privacyReport", tabId: 1, url: PAGE });
  assert.equal(bg.injected.length, 1);
});

test("scanTrackers: chỉ gửi danh sách domain, lọc kết quả, bỏ domain đã có trong bộ lọc; saveTrackerRules lưu feature tracking", async () => {
  const bg = loadBackground({
    thirdParties: [
      { domain: "www.google-analytics.com", count: 3, types: ["script"], loaded: true },
      { domain: "metrics.newspy.io", count: 2, types: ["xmlhttprequest"], loaded: true },
    ],
    nativeReplies: [{ ok: true, rules: [
      { type: "block_domain", domain: "metrics.newspy.io", category: "analytics", reason: "thống kê", confidence: 0.9 },
      { type: "block_domain", domain: "www.google-analytics.com", reason: "đã biết", confidence: 0.9 },
      { type: "block_domain", domain: "fonts.gstatic.com", reason: "cdn", confidence: 0.9 },
    ] }],
  });
  bg.store.consentAccepted = true;
  const result = await bg.send({ type: "scanTrackers", tabId: 1, url: PAGE });
  assert.deepEqual(result.accepted.map((r) => [r.domain, r.category]), [["metrics.newspy.io", "analytics"]]);
  assert.deepEqual(result.rejected.map((r) => r.reason), ["domain dùng chung, chặn sẽ hỏng trang"]);
  assert.deepEqual(bg.nativeCalls, ["analyze"]);

  await bg.send({ type: "saveTrackerRules", url: PAGE, rules: result.accepted });
  assert.deepEqual(bg.store["site:truyenqqto.com"].blockDomains.map((r) => [r.domain, r.feature]), [["metrics.newspy.io", "tracking"]]);
  await bg.send({ type: "setFeature", name: "ads", on: false });
  assert.deepEqual(bg.userRules(), [["block", "metrics.newspy.io", "thirdParty"]]);
});

test("allowWidget/disallowWidget: lưu theo trang, dựng rule allow, từ chối nhà cung cấp lạ", async () => {
  const bg = loadBackground();
  await bg.send({ type: "allowWidget", url: PAGE, provider: "twitter" });
  assert.deepEqual(bg.store["site:truyenqqto.com"].allowWidgets, ["twitter"]);
  assert.deepEqual(bg.userRules(), [["allow", "twitter.com,x.com,twimg.com", "truyenqqto.com"]]);
  await bg.send({ type: "disallowWidget", host: "www.truyenqqto.com", provider: "twitter" });
  assert.deepEqual(bg.userRules(), []);
  await assert.rejects(bg.send({ type: "allowWidget", url: PAGE, provider: "myspace" }), /không hợp lệ/);
});

test("chẩn đoán: dựng ứng viên với nguồn rule + cách sửa hợp lệ; domain không do extension chặn không có cách sửa", async () => {
  const bg = loadBackground();
  bg.store["site:truyenqqto.com"] = {
    hide: [{ id: "u2", selector: "div.w-overlay", source: "ai" }], popupDomains: [], allowDomains: [],
    blockDomains: [{ id: "u1", domain: "adnet.io", source: "ai", feature: "ads" }],
  };
  bg.store["tab:1"] = { popups: 1, overlays: 0, log: [{ kind: "popup", url: "https://pop.ads/x", reason: "bấm vào nội dung thường" }], scan: null };
  const { candidates } = await bg.send({ type: "diagnostics", tabId: 1, url: PAGE });
  const view = candidates.map((c) => [c.id, c.kind, c.domain || c.selector || "", c.sources.map((s) => s.ruleset || s.type).join("+"), c.fixes.map((f) => f.action).join("+")]);
  assert.deepEqual(view, [
    ["c1", "blocked_domain", "img.manga-cdn.io", "ads", "allow_domain"],
    ["c2", "failed_domain", "i.site.vn", "", ""],
    ["c3", "blocked_domain", "ads.adnet.io", "ads+user_rule", "allow_domain+delete_rule"],
    ["c4", "hidden", ".reader-box", "filter", "unhide_selector"],
    ["c5", "hidden", "div.w-overlay", "site", "unhide_selector+delete_rule"],
    ["c6", "popup_blocked", "", "popup_guard", "allow_popups"],
  ]);
  assert.equal(candidates[0].brokenImages, 2);
  // Tắt Chặn quảng cáo → bộ lọc quảng cáo không còn là nguồn.
  await bg.send({ type: "setFeature", name: "ads", on: false });
  const off = await bg.send({ type: "diagnostics", tabId: 1, url: PAGE });
  assert.equal(off.candidates[0].kind, "failed_domain");
});

test("chẩn đoán bằng AI: gửi vấn đề + ứng viên (không ảnh/HTML), chỉ giữ đề xuất trỏ ứng viên có thật & cách sửa hợp lệ", async () => {
  const bg = loadBackground({ nativeReplies: [{ ok: true, summary: "Ảnh truyện từ manga-cdn.io bị bộ lọc chặn.", fixes: [
    { candidateId: "c1", action: "allow_domain", reason: "CDN ảnh truyện", confidence: 0.95 },
    { candidateId: "c4", action: "unhide_selector", reason: "khung đọc bị ẩn", confidence: 0.7 },
    { candidateId: "c1", action: "delete_rule", reason: "không hợp lệ", confidence: 0.9 },
    { candidateId: "c99", action: "allow_domain", reason: "không tồn tại", confidence: 1 },
  ] }] });
  bg.store.consentAccepted = true;
  await assert.rejects(bg.send({ type: "diagnoseAI", tabId: 1, url: PAGE, problem: "  " }), /Mô tả vấn đề/);
  const result = await bg.send({ type: "diagnoseAI", tabId: 1, url: PAGE, problem: "ảnh truyện không hiện" });
  assert.match(result.summary, /manga-cdn/);
  assert.deepEqual(result.fixes.map((f) => [f.candidateId, f.action, f.domain || f.selector]),
    [["c1", "allow_domain", "img.manga-cdn.io"], ["c4", "unhide_selector", ".reader-box"]]);
  assert.deepEqual(bg.nativeCalls, ["diagnose"]);
});

test("ngoại lệ: allow_domain sinh rule allow priority 4 cho trang (cả tên miền dùng chung); unhide/allowPopups lưu & huỷ được", async () => {
  const bg = loadBackground();
  bg.store.aliases = { "truyenqqvn.com": "truyenqqto.com" };
  await bg.send({ type: "applyFix", url: PAGE, fix: { action: "allow_domain", domain: "img.manga-cdn.io", reason: "CDN ảnh" } });
  const allow = bg.dnr().find((r) => r.action.type === "allow");
  assert.deepEqual([allow.priority, allow.condition.requestDomains, allow.condition.initiatorDomains],
    [4, ["img.manga-cdn.io"], ["truyenqqto.com", "truyenqqvn.com"]]);
  await bg.send({ type: "applyFix", url: PAGE, fix: { action: "unhide_selector", selector: ".reader-box" } });
  await bg.send({ type: "applyFix", url: PAGE, fix: { action: "allow_popups" } });
  const site = bg.store["site:truyenqqto.com"];
  assert.deepEqual([site.unhide.map((r) => r.selector), site.allowPopups], [[".reader-box"], true]);

  await bg.send({ type: "removeException", url: PAGE, kind: "allowDomains", id: site.allowDomains[0].id });
  await bg.send({ type: "removeException", url: PAGE, kind: "allowPopups" });
  assert.equal(bg.dnr().some((r) => r.action.type === "allow"), false);
  assert.equal(bg.store["site:truyenqqto.com"].allowPopups, undefined);
  await assert.rejects(bg.send({ type: "applyFix", url: PAGE, fix: { action: "rm_rf" } }), /không hỗ trợ/);
});

test("dữ liệu rule cũ hỏng (domain rỗng/có dấu) không làm hỏng các rule khác; xoá tham số vẫn bật", async () => {
  const bg = loadBackground();
  bg.store["site:truyenqqto.com"] = { hide: [], popupDomains: [{ id: "p", domain: "" }], blockDomains: [
    { id: "1", domain: undefined }, { id: "2", domain: "quảngcáo.vn" }, { id: "3", domain: "ads.ok.io" }, { id: "4", domain: "có dấu cách" },
  ] };
  await bg.send({ type: "setFeature", name: "tracking", on: true });
  assert.deepEqual(bg.userRules(), [["block", "xn--qungco-tta4502d.vn", "thirdParty"], ["block", "ads.ok.io", "thirdParty"]]);
  const state = await bg.send({ type: "getTabState", tabId: 1, url: PAGE });
  assert.equal(state.nativeParamStrip, true);
  assert.equal(state.skippedRules, 0);
  assert.ok(bg.dnr().filter((r) => r.action.type === "redirect").length > 0);
});

test("Safari vẫn từ chối một rule → thêm từng rule, chỉ bỏ rule đó, báo skippedRules", async () => {
  const bg = loadBackground({ rejectDomain: "bad.io" });
  bg.store["site:truyenqqto.com"] = { hide: [], popupDomains: [], blockDomains: [{ id: "1", domain: "bad.io" }, { id: "2", domain: "good.io" }] };
  await bg.send({ type: "setFeature", name: "ads", on: true });
  assert.deepEqual(bg.userRules(), [["block", "good.io", "thirdParty"]]);
  const state = await bg.send({ type: "getTabState", tabId: 1, url: PAGE });
  assert.deepEqual([state.skippedRules, state.nativeParamStrip], [1, true]);
});

test("chỉ gửi phần thay đổi cho Safari: xoá rule ẩn → 0 lệnh; xoá rule domain → 1 lệnh gỡ đúng 1 rule", async () => {
  const bg = loadBackground();
  await bg.send({ type: "savePicked", rules: [
    { type: "hide", selector: "a.ads-banner" },
    { type: "block_domain", domain: "ads.one.io" }, { type: "block_domain", domain: "ads.two.io" },
  ] });
  const hide = bg.store["site:truyenqqto.com"].hide[0];
  const domain = bg.store["site:truyenqqto.com"].blockDomains[0];
  const total = bg.dnr().length;

  bg.dnrCalls.length = 0;
  await bg.send({ type: "deleteRule", host: "www.truyenqqto.com", ruleId: hide.id });
  assert.deepEqual(bg.dnrCalls, []);

  await bg.send({ type: "deleteRule", host: "www.truyenqqto.com", ruleId: domain.id });
  assert.deepEqual(bg.dnrCalls, [{ add: 0, remove: 1 }]);
  assert.equal(bg.dnr().length, total - 1);
  assert.deepEqual(bg.userRules(), [["block", "ads.two.io", "thirdParty"]]);
});

test("rule hỏng: tìm bằng chia đôi (không thử từng rule), ghi nhớ để lần sau không thử lại", async () => {
  const bg = loadBackground({ rejectDomain: "bad.io" });
  bg.store["site:truyenqqto.com"] = { hide: [], popupDomains: [], blockDomains:
    ["a", "b", "c", "bad", "d", "e", "f", "g"].map((n, i) => ({ id: String(i), domain: `${n}.io` })) };
  await bg.send({ type: "setFeature", name: "tracking", on: false });
  assert.equal(bg.userRules().length, 7);
  assert.ok(bg.dnrCalls.length <= 8, `${bg.dnrCalls.length} lệnh`);
  assert.equal((await bg.send({ type: "getTabState", tabId: 1, url: PAGE })).skippedRules, 1);

  bg.dnrCalls.length = 0;
  await bg.send({ type: "savePicked", rules: [{ type: "block_domain", domain: "new.io" }] });
  assert.deepEqual(bg.dnrCalls, [{ add: 1, remove: 0 }]);
});

test("Safari không hỗ trợ xoá tham số ở tầng mạng → ghi nhớ, không thử lại ở các lần sau", async () => {
  const bg = loadBackground({ rejectRedirect: true });
  await bg.send({ type: "savePicked", rules: [{ type: "block_domain", domain: "ads.one.io" }] });
  assert.equal(bg.store.dnrState.paramStrip, "unsupported");
  bg.dnrCalls.length = 0;
  await bg.send({ type: "setFeature", name: "tracking", on: true });
  assert.deepEqual(bg.dnrCalls, []);
});

test("cài đặt AI: chỉ hỏi phần Swift một lần, hỏi lại sau khi đổi cài đặt; lỗi thì không nhớ", async () => {
  const bg = loadBackground({ nativeReplies: [
    new Error("tạm lỗi"), new Error("tạm lỗi"),
    { ok: true, hasKey: false, model: "" }, { ok: true }, { ok: true, hasKey: true, model: "m2" },
  ] });
  assert.match((await bg.send({ type: "getTabState", tabId: 1, url: PAGE })).settings.nativeError, /tạm lỗi/);
  assert.equal((await bg.send({ type: "getTabState", tabId: 1, url: PAGE })).settings.hasKey, false);
  assert.equal((await bg.send({ type: "getTabState", tabId: 1, url: PAGE })).settings.hasKey, false);
  await bg.send({ type: "saveSettings", apiKey: "k" });
  assert.equal((await bg.send({ type: "getTabState", tabId: 1, url: PAGE })).settings.model, "m2");
  assert.deepEqual(bg.nativeCalls, ["getSettings", "getSettings", "getSettings", "saveSettings", "getSettings"]);
});

test("xoá toàn bộ theo nhóm: trang này / mọi trang; giữ ngoại lệ; gỡ rule DNR tương ứng", async () => {
  const bg = loadBackground();
  await bg.send({ type: "savePicked", rules: [
    { type: "hide", selector: "div.w-overlay" }, { type: "hide", selector: "a.ads-banner", scope: "global" },
    { type: "block_domain", domain: "ads.one.io" }, { type: "block_popup_domain", domain: "pop.one.io" },
  ] });
  await bg.send({ type: "applyFix", url: PAGE, fix: { action: "unhide_selector", selector: ".reader" } });

  assert.equal(await bg.send({ type: "deleteAllRules", host: "www.truyenqqto.com", scope: "site" }), 2);
  const site = bg.store["site:truyenqqto.com"];
  assert.deepEqual([site.hide, site.blockDomains, site.unhide.map((r) => r.selector)], [[], [], [".reader"]]);
  assert.deepEqual(bg.userRules(), [["block", "pop.one.io", "main_frame,sub_frame"]]);

  assert.equal(await bg.send({ type: "deleteAllRules", host: "www.truyenqqto.com", scope: "global" }), 2);
  assert.deepEqual([bg.store.global.hide, bg.store.global.popupDomains, bg.userRules()], [[], [], []]);
  await assert.rejects(bg.send({ type: "deleteAllRules", host: "www.truyenqqto.com", scope: "all" }), /không hợp lệ/);
});
