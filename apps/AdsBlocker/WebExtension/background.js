// Background (non-persistent): thống kê chặn theo tab, điều phối "Quét trang" (content → Gemini qua native → validate),
// lưu rule theo site và đồng bộ rule chặn domain vào declarativeNetRequest.
"use strict";

const {
  siteKey, isSensitiveHost, DEFAULT_SENSITIVE_SITES, selectorProblem, normalizeDomain, isSameSite, isProtectedDomain,
  globalScopeProblem, resolveSite, similarSites, linkSite: linkAliases, unlinkSite: unlinkAliases, TRACKING_PARAMS, validateRules,
} = globalThis.AdsBlockerRules;

/**
 * Gọi API trình duyệt, lỗi thì trả `fallback`. Safari ném lỗi kiểm tra tham số ngay lúc gọi ("Invalid call to …")
 * thay vì trả promise bị từ chối → `.catch()` gắn sau lời gọi không bắt được; phải dùng try/await.
 */
async function attempt(fn, fallback) {
  try {
    return await fn();
  } catch {
    return fallback;
  }
}

/**
 * Gửi lệnh tới content script ở frame chính. Safari không chạy content script ở tab mở trước khi extension được
 * cài/cập nhật hoặc tab khôi phục khi Safari mở lại, và khi đó `tabs.sendMessage` trả `undefined` thay vì ném lỗi
 * → nạp script vào trang rồi gửi lại.
 */
async function askPage(tabId, message) {
  const send = () => attempt(() => browser.tabs.sendMessage(tabId, message, { frameId: 0 }));
  let reply = await send();
  if (reply === undefined) {
    // Chỉ script isolated world: đủ để trả lời background.
    const files = browser.runtime.getManifest().content_scripts.filter((cs) => !cs.world).flatMap((cs) => cs.js);
    await attempt(() => browser.scripting.executeScript({ target: { tabId, frameIds: [0] }, files }));
    reply = await send();
  }
  if (reply === undefined) throw new Error("Không đọc được trang. Tải lại trang rồi thử lại.");
  return reply;
}

const MAX_LOG = 30;
const MAX_LOG_URL = 300;
const MAX_REJECTED = 20;
const SCREENSHOT_MAX_SIDE = 1280;
// Background có thể bị Safari dỡ khỏi bộ nhớ giữa chừng → trạng thái tab để trong storage.
// Không dùng storage.session: Safari iOS báo "Exceeded storage quota" dù dữ liệu chỉ vài KB.
// Khoá "tab:*" được dọn khi đóng tab và khi Safari khởi động lại.
const tabStore = browser.storage.local;

// ---------------------------------------------------------------- trạng thái tab

const tabKey = (tabId) => `tab:${tabId}`;
const emptyTab = () => ({ popups: 0, overlays: 0, log: [], scan: null });

async function readTab(tabId) {
  const data = await tabStore.get(tabKey(tabId));
  return { ...emptyTab(), ...(data[tabKey(tabId)] || {}) };
}

// Ghi tuần tự theo tab: nhiều event "blocked" liên tiếp không ghi đè nhau.
const tabQueues = new Map();
function updateTab(tabId, mutate) {
  const run = (tabQueues.get(tabId) || Promise.resolve()).then(async () => {
    const state = await readTab(tabId);
    mutate(state);
    await tabStore.set({ [tabKey(tabId)]: state });
    return state;
  });
  tabQueues.set(tabId, run.catch(() => {}));
  return run;
}

browser.tabs.onRemoved.addListener((tabId) => {
  tabQueues.delete(tabId);
  tabStore.remove(tabKey(tabId));
});

browser.runtime.onStartup?.addListener(async () => {
  const all = await browser.storage.local.get(null);
  await browser.storage.local.remove(Object.keys(all).filter((k) => k.startsWith("tab:")));
});

async function setBadge(tabId, state) {
  const total = state.popups + state.overlays;
  try {
    await browser.action.setBadgeText({ tabId, text: total ? String(total) : "" });
  } catch {
    // Safari iOS có thể không hỗ trợ badge — không ảnh hưởng chức năng.
  }
}

// ---------------------------------------------------------------- native (Swift)

// Gemini có thể mất 10–30 s; các lệnh khác chỉ đọc/ghi Keychain hoặc gọi API nhẹ.
const NATIVE_TIMEOUT_MS = { analyze: 120000, diagnose: 120000, listModels: 30000 };
const NATIVE_DEFAULT_TIMEOUT_MS = 8000;

// Sau khi cập nhật app, Safari còn giữ đường dẫn extension cũ: lần gọi đầu thường hỏng khi khởi chạy phần native.
const NATIVE_LAUNCH_FAILURE = /RBSLaunchRequest|Launch failed|launchd|Invalid call to runtime\.sendNativeMessage/i;
const NATIVE_RETRY_DELAY_MS = 1000;

async function native(payload) {
  try {
    return await nativeOnce(payload);
  } catch (error) {
    if (!NATIVE_LAUNCH_FAILURE.test(error.message)) throw error;
    await new Promise((resolve) => setTimeout(resolve, NATIVE_RETRY_DELAY_MS));
    return nativeOnce(payload);
  }
}

async function nativeOnce(payload) {
  const timeoutMs = NATIVE_TIMEOUT_MS[payload.action] || NATIVE_DEFAULT_TIMEOUT_MS;
  let timer;
  let reply;
  try {
    // Không có hạn chờ thì phần native treo sẽ khoá nút trong popup mãi mãi.
    reply = await Promise.race([
      browser.runtime.sendNativeMessage("application.id", payload),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`không phản hồi sau ${timeoutMs / 1000} giây`)), timeoutMs);
      }),
    ]);
  } catch (error) {
    throw new Error(`Không gọi được phần native của app (${payload.action}): ${error.message || error}`);
  } finally {
    clearTimeout(timer);
  }
  if (!reply || reply.ok !== true) throw new Error((reply && reply.error) || "Phần native không phản hồi.");
  return reply;
}

// ---------------------------------------------------------------- cấu hình

async function localSettings() {
  const data = await browser.storage.local.get(["sensitiveSites", "consentAccepted"]);
  return {
    sensitiveSites: data.sensitiveSites || DEFAULT_SENSITIVE_SITES,
    consentAccepted: data.consentAccepted === true,
  };
}

const emptySite = () => ({ hide: [], popupDomains: [], blockDomains: [] });
const emptyGlobal = () => ({ hide: [], popupDomains: [] });

async function readAliases() {
  return (await browser.storage.local.get("aliases")).aliases || {};
}

/** Rule của trang (site gốc nếu tên miền này dùng chung rule với tên miền khác) + rule mọi trang. */
async function readRules(host) {
  const key = "site:" + resolveSite(siteKey(host), await readAliases());
  const data = await browser.storage.local.get([key, "global"]);
  return {
    key,
    site: { ...emptySite(), ...(data[key] || {}) },
    global: { ...emptyGlobal(), ...(data.global || {}) },
  };
}

const writeRules = ({ key, site, global }) => browser.storage.local.set({ [key]: site, global });

function hostOf(url) {
  try {
    const u = new URL(url);
    return /^https?:$/.test(u.protocol) ? u.hostname : "";
  } catch {
    return "";
  }
}

/** `url` do popup gửi kèm: dùng khi Safari không còn tìm thấy tab theo mã (mã tab đổi sau khi trang điều hướng). */
// Cài đặt AI (có key, model) lấy từ phần Swift — mỗi lần gọi là khởi động tiến trình extension (chậm), nên nhớ trong
// lúc background còn sống; saveSettings xoá để lần sau đọc lại. Lỗi thì không nhớ (lần sau thử lại).
let nativeSettingsCache = null;

async function readNativeSettings() {
  if (!nativeSettingsCache) nativeSettingsCache = await native({ action: "getSettings" });
  return nativeSettingsCache;
}

async function getTabState(tabId, url) {
  const tab = await attempt(() => browser.tabs.get(tabId), null);
  const host = hostOf((tab && tab.url) || url || "");
  const [state, local, all] = await Promise.all([readTab(tabId), localSettings(), browser.storage.local.get(null)]);
  const aliases = all.aliases || {};
  const key = host ? siteKey(host) : "";
  const root = resolveSite(key, aliases);
  const site = { ...emptySite(), ...(all["site:" + root] || {}) };
  const knownSites = Object.keys(all)
    .filter((k) => k.startsWith("site:") && !aliases[k.slice(5)])
    .filter((k) => ["hide", "popupDomains", "blockDomains"].some((list) => (all[k][list] || []).length))
    .map((k) => k.slice(5))
    .filter((k) => k !== root)
    .sort();
  let nativeSettings;
  try {
    nativeSettings = await readNativeSettings();
  } catch (error) {
    nativeSettings = { hasKey: false, model: "", error: error.message };
  }
  return {
    host,
    site: host ? siteKey(host) : "",
    sensitive: host ? isSensitiveHost(host, local.sensitiveSites) : false,
    stats: { popups: state.popups, overlays: state.overlays },
    log: state.log,
    scan: state.scan,
    siteRules: site,
    globalRules: { ...emptyGlobal(), ...(all.global || {}) },
    features: { ...DEFAULT_FEATURES, ...(all.features || {}) },
    // Ruleset tĩnh Safari thực sự đang bật: lệch với công tắc → Safari không nạp được bộ lọc.
    enabledRulesets: await attempt(() => browser.declarativeNetRequest.getEnabledRulesets(), null),
    nativeParamStrip: (all[DNR_STATE_KEY] || {}).paramStrip !== "unsupported",
    skippedRules: (all[DNR_STATE_KEY] || {}).skipped || 0,
    sharing: {
      linkedTo: root !== key ? root : null,
      linkedFrom: Object.keys(aliases).filter((k) => aliases[k] === key).sort(),
      suggestions: key && root === key ? similarSites(key, knownSites) : [],
      knownSites,
    },
    settings: {
      hasKey: !!nativeSettings.hasKey,
      model: nativeSettings.model || "",
      nativeError: nativeSettings.error || null,
      sensitiveSites: local.sensitiveSites,
      consentAccepted: local.consentAccepted,
    },
  };
}

// ---------------------------------------------------------------- quét trang

async function dataUrlFromBlob(blob) {
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return `data:${blob.type};base64,${btoa(binary)}`;
}

/** Thu nhỏ ảnh chụp để gửi Gemini nhanh/rẻ hơn; môi trường thiếu API thì gửi ảnh gốc. */
async function shrinkScreenshot(dataUrl) {
  if (typeof OffscreenCanvas === "undefined" || typeof createImageBitmap === "undefined") return dataUrl;
  const bitmap = await createImageBitmap(await (await fetch(dataUrl)).blob());
  const scale = Math.min(1, SCREENSHOT_MAX_SIDE / Math.max(bitmap.width, bitmap.height));
  const canvas = new OffscreenCanvas(Math.round(bitmap.width * scale), Math.round(bitmap.height * scale));
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  return dataUrlFromBlob(await canvas.convertToBlob({ type: "image/jpeg", quality: 0.7 }));
}

async function captureScreenshot(windowId) {
  try {
    return await shrinkScreenshot(await browser.tabs.captureVisibleTab(windowId, { format: "jpeg", quality: 70 }));
  } catch {
    // Safari không cho chụp → Gemini chỉ dựa vào HTML.
    return null;
  }
}

/** Điều kiện gửi dữ liệu trang lên Gemini (quét trang và "Ẩn bằng AI"). */
async function assertCanSendToAI(host) {
  const local = await localSettings();
  if (!host) throw new Error("Chỉ dùng AI được trên trang web http/https.");
  if (isSensitiveHost(host, local.sensitiveSites)) throw new Error("Trang nhạy cảm (ngân hàng/email…) — không gửi lên AI.");
  if (!local.consentAccepted) {
    throw new Error("Cần đồng ý gửi dữ liệu trang lên Gemini: mở popup AdsBlocker › Quét trang bằng AI một lần để đồng ý.");
  }
}

/** Kiểm tra trước khi quét; lỗi ở đây trả thẳng về popup. */
async function startScan(tabId) {
  const tab = await browser.tabs.get(tabId);
  const host = hostOf(tab.url || "");
  await assertCanSendToAI(host);
  await updateTab(tabId, (s) => { s.scan = { status: "running", host, startedAt: Date.now() }; });
  // Không chờ: popup có thể đóng giữa chừng, kết quả nằm trong trạng thái tab.
  runScan(tab, host);
}

async function runScan(tab, host) {
  const tabId = tab.id;
  try {
    const snap = await askPage(tabId, { type: "snapshot" });
    const screenshot = await captureScreenshot(tab.windowId);
    await attempt(() => browser.tabs.sendMessage(tabId, { type: "clearMarks" }, { frameId: 0 }));

    const state = await readTab(tabId);
    const page = { ...snap.page, popupLog: state.log.slice(0, 15).map(({ kind, url, reason }) => ({ kind, url, reason })) };
    const reply = await native({ action: "analyze", page, screenshot });
    const { accepted, rejected } = await askPage(tabId, { type: "validate", rules: reply.rules });

    await updateTab(tabId, (s) => {
      s.scan = { status: "done", host, accepted, rejected: rejected.slice(0, MAX_REJECTED), candidateCount: snap.page.candidates.length, usedScreenshot: !!screenshot };
    });
  } catch (error) {
    await attempt(() => browser.tabs.sendMessage(tabId, { type: "clearMarks" }, { frameId: 0 }));
    await updateTab(tabId, (s) => { s.scan = { status: "error", host, error: error.message || String(error) }; });
  }
}

// ---------------------------------------------------------------- rule

// ---------------------------------------------------------------- tính năng & rule declarativeNetRequest

// youtube không có ruleset: chạy trong content/main_world.js (cũng được app nạp vào tab YouTube).
const DEFAULT_FEATURES = { ads: true, tracking: true, youtube: true };
// Ruleset tĩnh (manifest) của từng tính năng.
const FEATURE_RULESETS = { ads: ["ads_custom", "ads"], tracking: ["tracking"] };
// Rule của người dùng thắng rule cho phép (@@) của bộ lọc (priority 2) và rule chặn của bộ lọc (priority 1).
const USER_RULE_PRIORITY = 3;
// Ngoại lệ "bỏ chặn domain trên trang này" (từ chẩn đoán) thắng mọi rule chặn, kể cả rule của người dùng.
const EXCEPTION_PRIORITY = 4;
// Widget mạng xã hội được cho phép theo trang (lấy từ tools/lists/social.json).
const WIDGET_DOMAINS = {
  facebook: ["facebook.com", "facebook.net"],
  twitter: ["twitter.com", "x.com", "twimg.com"],
  instagram: ["instagram.com", "cdninstagram.com"],
  tiktok: ["tiktok.com", "tiktokcdn.com"],
};

async function readFeatures() {
  const { features } = await browser.storage.local.get("features");
  return { ...DEFAULT_FEATURES, ...(features || {}) };
}

async function setFeature(name, on) {
  if (!(name in DEFAULT_FEATURES)) throw new Error(`Tính năng không hợp lệ: ${name}`);
  await browser.storage.local.set({ features: { ...(await readFeatures()), [name]: !!on } });
  await applyFeatures();
}

// Trạng thái rule động đã nạp vào Safari, lưu trong storage (background non-persistent):
//   applied: chữ ký nội dung rule → id; rejected: chữ ký rule Safari từ chối (dữ liệu cũ hỏng…) — không thử lại;
//   skipped: số rule đang bị bỏ vì bị từ chối (popup cảnh báo);
//   paramStrip: "unsupported" khi Safari không nhận redirect + queryTransform → chỉ còn content/privacy.js xoá tham số.
const DNR_STATE_KEY = "dnrState";
const ruleSignature = (rule) => JSON.stringify([rule.priority, rule.action, rule.condition]);

/**
 * Tên miền dùng được trong requestDomains/initiatorDomains: Safari đòi ASCII, không rỗng.
 * Tên miền có dấu → punycode (URL làm hộ); rác (rỗng, undefined, có khoảng trắng…) → null.
 */
function ruleDomain(value) {
  const text = String(value ?? "").trim();
  if (!text) return null;
  try {
    const host = new URL(`http://${text}`).hostname;
    return /^[a-z0-9.-]+$/.test(host) && !host.startsWith(".") ? host : null;
  } catch {
    return null;
  }
}

/**
 * Rule xoá tham số theo dõi khi tải trang. Không dùng regexFilter: Safari báo "not a supported regular expression"
 * với nhóm lựa chọn (a|b). Mỗi tham số 2 rule urlFilter "?key=" / "&key=" (không phân biệt hoa thường) — chỉ khớp
 * URL có tham số đó, nên redirect luôn đổi URL, không lặp.
 */
function paramStripRules(firstId) {
  const action = { type: "redirect", redirect: { transform: { queryTransform: { removeParams: TRACKING_PARAMS } } } };
  return TRACKING_PARAMS.flatMap((key) => ["?", "&"].map((sep) => ({ urlFilter: `${sep}${key}=` })))
    .map((condition, i) => ({
      id: firstId + i, priority: USER_RULE_PRIORITY, action, condition: { ...condition, resourceTypes: ["main_frame"] },
    }));
}

/** Rule động = toàn bộ rule người dùng trong storage, theo tính năng đang bật. Dựng lại mỗi khi rule/tính năng đổi. */
async function buildDynamicRules() {
  const all = await browser.storage.local.get(null);
  const features = { ...DEFAULT_FEATURES, ...(all.features || {}) };
  const aliases = all.aliases || {};
  const rules = [];
  const add = (action, condition, priority = USER_RULE_PRIORITY) => rules.push({ id: rules.length + 1, priority, action, condition });
  const popupDomains = [...((all.global && all.global.popupDomains) || [])];

  for (const [key, site] of Object.entries(all)) {
    if (!key.startsWith("site:")) continue;
    const siteDomain = key.slice(5);
    for (const r of site.blockDomains || []) {
      if (features[r.feature === "tracking" ? "tracking" : "ads"]) {
        const domain = ruleDomain(r.domain);
        if (domain) add({ type: "block" }, { requestDomains: [domain], domainType: "thirdParty" });
      }
    }
    popupDomains.push(...(site.popupDomains || []));
    const initiators = [siteDomain, ...Object.keys(aliases).filter((k) => aliases[k] === siteDomain)].map(ruleDomain).filter(Boolean);
    if (!initiators.length) continue;
    // Ngoại lệ áp bất kể công tắc: chỉ nới lỏng, không chặn thêm.
    for (const r of site.allowDomains || []) {
      const domain = ruleDomain(r.domain);
      if (domain) add({ type: "allow" }, { requestDomains: [domain], initiatorDomains: initiators }, EXCEPTION_PRIORITY);
    }
    if (features.tracking) {
      for (const provider of site.allowWidgets || []) {
        if (WIDGET_DOMAINS[provider]) add({ type: "allow" }, { requestDomains: WIDGET_DOMAINS[provider], initiatorDomains: initiators });
      }
    }
  }
  if (features.ads) {
    for (const r of popupDomains) {
      const domain = ruleDomain(r.domain);
      if (domain) add({ type: "block" }, { requestDomains: [domain], resourceTypes: ["main_frame", "sub_frame"] });
    }
  }
  return { rules, features };
}

/**
 * Đồng bộ rule động của Safari với storage, **chỉ gửi phần thay đổi**: mỗi lệnh updateDynamicRules làm Safari biên
 * dịch lại bộ rule (chậm trên iPhone). Xoá rule ẩn phần tử → không lệnh nào; xoá rule chặn domain → gỡ đúng 1 rule.
 */
async function rebuildDynamicRules() {
  const dnr = browser.declarativeNetRequest;
  const update = (options) => attempt(async () => { await dnr.updateDynamicRules(options); return true; }, false);
  const { rules, features } = await buildDynamicRules();
  const stored = (await browser.storage.local.get(DNR_STATE_KEY))[DNR_STATE_KEY] || {};
  const paramStrip = stored.paramStrip;
  const desired = [...rules, ...(features.tracking && paramStrip !== "unsupported" ? paramStripRules(0) : [])];
  const desiredSigs = new Set(desired.map(ruleSignature));
  const rejected = new Set((stored.rejected || []).filter((s) => desiredSigs.has(s)));

  const existingIds = new Set((await dnr.getDynamicRules()).map((r) => r.id));
  const applied = new Map(Object.entries(stored.applied || {}).filter(([, id]) => existingIds.has(id)));
  const usedIds = new Set();
  const nextApplied = {};
  const toAdd = [];
  for (const rule of desired) {
    const sig = ruleSignature(rule);
    if (rejected.has(sig)) continue;
    const id = applied.get(sig);
    if (id !== undefined && !usedIds.has(id)) {
      usedIds.add(id);
      nextApplied[sig] = id;
    } else {
      toAdd.push(rule);
    }
  }
  const removeRuleIds = [...existingIds].filter((id) => !usedIds.has(id));
  let nextId = 1;
  const fresh = toAdd.map((rule) => {
    while (usedIds.has(nextId)) nextId++;
    usedIds.add(nextId);
    return { ...rule, id: nextId };
  });
  const record = (rule) => { nextApplied[ruleSignature(rule)] = rule.id; };
  const isParam = (rule) => rule.action.type === "redirect";
  const userAdds = fresh.filter((r) => !isParam(r));
  const paramAdds = fresh.filter(isParam);

  // Lô bị từ chối (Safari từ chối cả lệnh khi một rule hỏng) → chia đôi tới khi tìm ra rule hỏng: ~log2 N lệnh thay vì N.
  const addBatch = async (batch) => {
    if (!batch.length) return;
    if (await update({ addRules: batch })) {
      batch.forEach(record);
    } else if (batch.length === 1) {
      rejected.add(ruleSignature(batch[0]));
    } else {
      await addBatch(batch.slice(0, batch.length >> 1));
      await addBatch(batch.slice(batch.length >> 1));
    }
  };
  if (removeRuleIds.length || userAdds.length) {
    if (await update({ removeRuleIds, addRules: userAdds })) {
      userAdds.forEach(record);
    } else {
      if (removeRuleIds.length) await dnr.updateDynamicRules({ removeRuleIds });
      await addBatch(userAdds);
    }
  }
  // Thử riêng: lỗi của rule khác không được làm tưởng nhầm Safari không hỗ trợ xoá tham số.
  let nextParamStrip = paramStrip;
  if (paramAdds.length) {
    if (await update({ addRules: paramAdds })) paramAdds.forEach(record);
    else nextParamStrip = "unsupported";
  }
  await browser.storage.local.set({
    [DNR_STATE_KEY]: { applied: nextApplied, rejected: [...rejected], skipped: rejected.size, paramStrip: nextParamStrip },
  });
}

async function applyFeatures() {
  const features = await readFeatures();
  const enableRulesetIds = [];
  const disableRulesetIds = [];
  for (const [name, ids] of Object.entries(FEATURE_RULESETS)) (features[name] ? enableRulesetIds : disableRulesetIds).push(...ids);
  await browser.declarativeNetRequest.updateEnabledRulesets({ enableRulesetIds, disableRulesetIds });
  await rebuildDynamicRules();
}

// ---------------------------------------------------------------- dữ liệu bộ lọc (filters/*.json, sinh lúc build)

const filterCache = new Map();
function loadFilter(name) {
  if (!filterCache.has(name)) {
    filterCache.set(name, fetch(browser.runtime.getURL(`filters/${name}.json`)).then((r) => r.json()).catch((error) => {
      filterCache.delete(name);
      throw error;
    }));
  }
  return filterCache.get(name);
}

/** "m.news.example.com" → ["m.news.example.com", "news.example.com", "example.com"]. */
function hostSuffixes(host) {
  const labels = host.toLowerCase().split(".");
  return labels.slice(0, -1).map((_, i) => labels.slice(i).join("."));
}

/**
 * Selector ẩn phần tử từ bộ lọc cho trang `host`: theo domain + chung khớp token (#id/.class) trang đang có.
 * `initial`: lần đầu của trang → kèm selector theo domain và selector chung luôn áp.
 */
async function cosmeticFor(host, tokens, initial) {
  const data = await loadFilter("cosmetic");
  const suffixes = hostSuffixes(host);
  const excluded = new Set(suffixes.flatMap((d) => data.exceptions[d] || []));
  const selectors = initial ? [...data.genericAlways, ...suffixes.flatMap((d) => data.byDomain[d] || [])] : [];
  for (const token of tokens || []) selectors.push(...(data.genericByToken[token] || []));
  return [...new Set(selectors)].filter((s) => !excluded.has(s));
}

// ---------------------------------------------------------------- báo cáo theo dõi & quét theo dõi bằng AI

const TRACKING_CATEGORIES = ["analytics", "session_replay", "fingerprinting", "social"];
let trackerMap = null;

async function trackerCategory(domain) {
  if (!trackerMap) {
    const index = await loadFilter("tracker_index");
    trackerMap = new Map(Object.entries(index).flatMap(([category, domains]) => domains.map((d) => [d, category])));
  }
  const suffix = hostSuffixes(domain).find((d) => trackerMap.has(d));
  return suffix ? trackerMap.get(suffix) : null;
}

/** Domain bên thứ ba của trang, phân nhóm theo bộ lọc + rule riêng; trạng thái: đã chặn / đã tải. */
async function privacyReport(tabId, url) {
  const domains = await askPage(tabId, { type: "thirdParties" });
  const host = hostOf(url);
  const [features, rules] = await Promise.all([readFeatures(), readRules(host)]);
  const userBlocked = new Set(rules.site.blockDomains.map((r) => r.domain));
  const items = [];
  for (const d of domains || []) {
    const userRule = [...userBlocked].find((b) => d.domain === b || d.domain.endsWith("." + b));
    const category = (await trackerCategory(d.domain)) || (userRule ? "user" : null);
    const featureOn = category === "ads" ? features.ads : TRACKING_CATEGORIES.includes(category) ? features.tracking : true;
    items.push({ ...d, category, status: d.loaded ? "loaded" : category && featureOn ? "blocked" : "present" });
  }
  return { host, features, items };
}

/** Gửi danh sách domain (không ảnh, không HTML) cho Gemini phân loại tracker chưa có trong bộ lọc. */
async function scanTrackers(tabId, url) {
  const host = hostOf(url);
  await assertCanSendToAI(host);
  const { items } = await privacyReport(tabId, url);
  if (!items.length) throw new Error("Trang này không tải gì từ tên miền khác.");
  const page = {
    url: new URL(url).origin,
    domains: items.map(({ domain, count, types, category, loaded }) => ({ domain, count, types, knownCategory: category, loaded })),
  };
  const reply = await native({ action: "analyze", mode: "trackers", page });
  const already = new Set(items.filter((i) => i.category).map((i) => i.domain));
  const { accepted, rejected } = validateRules(reply.rules, { pageHost: host, candidates: new Map() });
  return {
    accepted: accepted.filter((r) => r.type === "block_domain" && !already.has(r.domain)),
    rejected: rejected.slice(0, MAX_REJECTED),
  };
}

// ---------------------------------------------------------------- chẩn đoán trang bị lỗi

const RULESET_LABEL = { ads: "bộ lọc quảng cáo (EasyList/ABPVN)", ads_custom: "danh sách quảng cáo có sẵn", tracking: "bộ lọc theo dõi (EasyPrivacy)" };
let blockIndex = null;

/** domain → các ruleset tĩnh chặn nó (chỉ rule chặn; dựng một lần từ file ruleset trong extension). */
async function rulesetBlockIndex() {
  if (blockIndex) return blockIndex;
  const index = new Map();
  const note = (domain, ruleset) => index.set(domain, [...new Set([...(index.get(domain) || []), ruleset])]);
  const files = { ads: "filters/ads_network.json", tracking: "filters/tracking_network.json", ads_custom: "rules/ad_domains.json" };
  for (const [ruleset, path] of Object.entries(files)) {
    const rules = await fetch(browser.runtime.getURL(path)).then((r) => r.json()).catch(() => []);
    for (const rule of rules) {
      if (rule.action.type !== "block") continue;
      for (const d of rule.condition.requestDomains || []) note(d, ruleset);
      const host = /^\|\|([a-z0-9.-]+)/.exec(rule.condition.urlFilter || "");
      if (host) note(host[1], ruleset);
    }
  }
  blockIndex = index;
  return index;
}

/**
 * Dựng ứng viên gây lỗi từ dấu hiệu trang (thuần — test được).
 * ctx: { lookup(domain) → [ruleset], site, global, log, features }.
 * Mỗi ứng viên: { id, kind, …, sources, fixes } với fixes là các cách sửa hợp lệ cho ứng viên đó.
 */
function buildCandidates(diag, ctx) {
  const candidates = [];
  const push = (c) => candidates.push({ id: `c${candidates.length + 1}`, ...c });
  const matches = (host, domain) => host === domain || host.endsWith("." + domain);
  const allowed = new Set((ctx.site.allowDomains || []).map((r) => r.domain));

  const byDomain = new Map();
  const evidence = (domain) => {
    if (!byDomain.has(domain)) byDomain.set(domain, { brokenImages: 0, lazyImages: 0, notLoaded: [], samples: [] });
    return byDomain.get(domain);
  };
  for (const img of diag.brokenImages) evidence(img.domain).brokenImages++;
  for (const img of diag.lazyImages) evidence(img.domain).lazyImages++;
  for (const r of diag.notLoaded) evidence(r.domain).notLoaded.push(r.type);
  for (const r of [...diag.brokenImages, ...diag.notLoaded]) {
    const e = evidence(r.domain);
    if (e.samples.length < 3) e.samples.push(r.path);
  }

  for (const [domain, e] of byDomain) {
    if (allowed.has(domain)) continue;
    const sources = ctx.lookup(domain).map((ruleset) => ({ type: "ruleset", ruleset, label: RULESET_LABEL[ruleset] || ruleset }));
    const fixes = [];
    for (const r of ctx.site.blockDomains || []) {
      if (!matches(domain, r.domain)) continue;
      sources.push({ type: "user_rule", ruleId: r.id, origin: r.source, label: `rule chặn domain ${r.domain} của bạn` });
      fixes.push({ action: "delete_rule", ruleId: r.id });
    }
    for (const r of [...(ctx.global.popupDomains || []), ...(ctx.site.popupDomains || [])]) {
      if (!matches(domain, r.domain)) continue;
      sources.push({ type: "user_rule", ruleId: r.id, origin: r.source, label: `rule chặn tab mới tới ${r.domain} của bạn` });
      fixes.push({ action: "delete_rule", ruleId: r.id });
    }
    if (sources.length) fixes.unshift({ action: "allow_domain", domain });
    // Domain không do extension chặn vẫn giữ làm ngữ cảnh (lỗi của trang / chặn ảnh hotlink…), không có cách sửa;
    // domain chỉ có ảnh lazy-load chưa nạp (chưa hề tải) thì chỉ đáng kể khi extension đang chặn nó.
    if (sources.length || e.brokenImages || e.notLoaded.length) {
      push({ kind: sources.length ? "blocked_domain" : "failed_domain", domain, ...e, notLoaded: [...new Set(e.notLoaded)], sources, fixes });
    }
  }

  const SOURCE_LABEL = { builtin: "selector quảng cáo có sẵn", filter: "bộ lọc ẩn phần tử (EasyList/ABPVN)", site: "rule ẩn của bạn (trang này)", global: "rule ẩn của bạn (mọi trang)", structural: "rule ẩn theo vị trí của bạn" };
  for (const h of diag.hidden) {
    const fixes = [{ action: "unhide_selector", selector: h.selector }];
    if (h.ruleId) fixes.push({ action: "delete_rule", ruleId: h.ruleId });
    push({ kind: "hidden", selector: h.selector, count: h.count, media: h.media, sources: [{ type: h.source, ruleId: h.ruleId, origin: h.origin, label: SOURCE_LABEL[h.source] }], fixes });
  }

  const popups = ctx.log.filter((l) => l.kind === "popup");
  if (popups.length && !ctx.site.allowPopups) {
    push({ kind: "popup_blocked", count: popups.length, samples: popups.slice(0, 3).map((l) => `${l.reason}: ${String(l.url).slice(0, 80)}`), sources: [{ type: "popup_guard", label: "chặn mở tab mới" }], fixes: [{ action: "allow_popups" }] });
  }
  const overlays = ctx.log.filter((l) => l.kind === "overlay");
  if (overlays.length && !ctx.site.keepOverlays) {
    push({ kind: "overlay_removed", count: overlays.length, sources: [{ type: "overlay_guard", label: "gỡ lớp phủ trong suốt" }], fixes: [{ action: "keep_overlays" }] });
  }
  return candidates;
}

async function collectDiagnosis(tabId, url) {
  const diag = await askPage(tabId, { type: "diagnostics" });
  const host = hostOf(url);
  const [index, rules, tab, features] = await Promise.all([rulesetBlockIndex(), readRules(host), readTab(tabId), readFeatures()]);
  const enabled = new Set(Object.entries(FEATURE_RULESETS).filter(([name]) => features[name]).flatMap(([, ids]) => ids));
  const lookup = (domain) => [...new Set(hostSuffixes(domain).flatMap((d) => index.get(d) || []))].filter((r) => enabled.has(r));
  const candidates = buildCandidates(diag, { lookup, site: rules.site, global: rules.global, log: tab.log, features });
  return { diag, candidates, features };
}

/** Chỉ giữ đề xuất của AI trỏ tới ứng viên có thật và cách sửa hợp lệ của ứng viên đó. */
function checkFixes(rawFixes, candidates) {
  const byId = new Map(candidates.map((c) => [c.id, c]));
  const fixes = [];
  for (const f of Array.isArray(rawFixes) ? rawFixes : []) {
    const candidate = f && byId.get(f.candidateId);
    const fix = candidate && candidate.fixes.find((x) => x.action === f.action);
    if (!fix) continue;
    fixes.push({ candidateId: candidate.id, ...fix, reason: String(f.reason || "").slice(0, 200), confidence: Math.max(0, Math.min(1, Number(f.confidence) || 0)) });
  }
  return fixes.sort((a, b) => b.confidence - a.confidence);
}

async function diagnoseWithAI(tabId, url, problem) {
  const text = String(problem || "").trim().slice(0, 500);
  if (!text) throw new Error("Mô tả vấn đề trước khi chẩn đoán.");
  await assertCanSendToAI(hostOf(url));
  const { diag, candidates, features } = await collectDiagnosis(tabId, url);
  const page = {
    url: diag.url, title: diag.title, features,
    signals: { totalImages: diag.totalImages, brokenImages: diag.brokenImages.length, lazyImagesNotLoaded: diag.lazyImages.length, resourceTimingFull: diag.timingFull },
    candidates: candidates.map(({ fixes, ...c }) => ({ ...c, allowedFixes: fixes.map((f) => f.action) })),
  };
  const reply = await native({ action: "diagnose", problem: text, page });
  return { summary: String(reply.summary || "").slice(0, 600), fixes: checkFixes(reply.fixes, candidates), candidates, diag };
}

// Khởi động/cài đặt/cập nhật: đồng bộ ruleset + rule động với storage (cũng chuyển rule cũ có dnrId sang cách mới).
browser.runtime.onInstalled?.addListener(() => { applyFeatures().catch(() => {}); });
browser.runtime.onStartup?.addListener(() => { applyFeatures().catch(() => {}); });

const asStrings = (value, max) => (Array.isArray(value) ? value : [])
  .filter((s) => typeof s === "string" && !selectorProblem(s)).slice(0, max);

/** Lưu rule (từ quét AI hoặc tự chọn) vào site + rule chặn domain vào declarativeNetRequest. */
async function saveRules(host, rules) {
  const state = await readRules(host);
  const { site, global } = state;

  for (const rule of rules) {
    const base = {
      id: crypto.randomUUID(),
      reason: String(rule.reason || "").slice(0, 120),
      source: rule.source === "manual" ? "manual" : "ai",
      createdAt: Date.now(),
    };
    if (rule.type === "hide") {
      if (typeof rule.selector !== "string" || selectorProblem(rule.selector)) continue;
      if ([...site.hide, ...global.hide].some((r) => r.selector === rule.selector)) continue;
      const hide = { ...base, selector: rule.selector, fallback: asStrings(rule.fallback, 3) };
      if (rule.scope === "global" && !globalScopeProblem(rule.selector)) {
        global.hide.push(toGlobalHide(hide));
        continue;
      }
      if (typeof rule.structural === "string" && rule.structural) hide.structural = rule.structural;
      site.hide.push(hide);
      continue;
    }
    if (rule.type !== "block_domain" && rule.type !== "block_popup_domain") continue;
    const domain = normalizeDomain(rule.domain);
    if (!domain || isSameSite(domain, host) || isProtectedDomain(domain)) continue;
    // Rule DNR chặn domain áp mọi trang; vẫn hiện ở trang tạo ra nó. Domain chặn tab mới lưu ở global để
    // phần chặn window.open (main_world.js) cũng áp mọi trang.
    const list = rule.type === "block_domain" ? site.blockDomains : global.popupDomains;
    const existing = rule.type === "block_domain" ? site.blockDomains : [...global.popupDomains, ...site.popupDomains];
    if (existing.some((r) => r.domain === domain)) continue;
    const entry = { ...base, domain };
    if (rule.type === "block_domain") entry.feature = rule.feature === "tracking" ? "tracking" : "ads";
    list.push(entry);
  }

  await writeRules(state);
  await rebuildDynamicRules();
}

/** Rule mọi trang không mang đường dẫn :nth-of-type hay selector dự phòng chỉ đúng ở trang gốc. */
function toGlobalHide(rule) {
  const { structural, ...rest } = rule;
  return { ...rest, fallback: (rule.fallback || []).filter((s) => !globalScopeProblem(s)) };
}

async function setRuleScope(host, ruleId, scope) {
  const state = await readRules(host);
  const [from, to] = scope === "global" ? [state.site.hide, state.global.hide] : [state.global.hide, state.site.hide];
  const index = from.findIndex((r) => r.id === ruleId);
  if (index < 0) throw new Error("Không tìm thấy rule (có thể đã bị xoá).");
  const rule = from[index];
  if (scope === "global") {
    const problem = globalScopeProblem(rule.selector);
    if (problem) throw new Error(`Không áp mọi trang được: ${problem}`);
  }
  from.splice(index, 1);
  to.push(scope === "global" ? toGlobalHide(rule) : rule);
  await writeRules(state);
}

/** Tên miền của `host` dùng chung rule với site `target`; rule riêng đang có của host được gộp sang site gốc. */
async function linkSite(host, target) {
  const from = siteKey(host);
  const to = siteKey(target);
  if (!to || to === from) throw new Error("Chọn một tên miền khác để dùng chung rule.");
  const aliases = linkAliases(await readAliases(), from, to);
  const root = aliases[from];
  const data = await browser.storage.local.get([`site:${from}`, `site:${root}`]);
  const own = { ...emptySite(), ...(data[`site:${from}`] || {}) };
  const merged = { ...emptySite(), ...(data[`site:${root}`] || {}) };
  for (const list of ["hide", "popupDomains", "blockDomains"]) {
    const keyOf = (r) => r.selector || r.domain;
    const existing = new Set(merged[list].map(keyOf));
    merged[list].push(...own[list].filter((r) => !existing.has(keyOf(r))));
  }
  await browser.storage.local.set({ aliases, [`site:${root}`]: merged });
  await browser.storage.local.remove(`site:${from}`);
  await rebuildDynamicRules();
  return root;
}

/**
 * Ngoại lệ theo trang (từ chẩn đoán hoặc bấm tay), lưu ở site gốc nên áp cả tên miền dùng chung:
 *   allow_domain {domain} · unhide_selector {selector} · allow_popups · keep_overlays · delete_rule {ruleId}
 */
async function applyFix(host, fix) {
  if (fix.action === "delete_rule") return deleteRule(host, fix.ruleId);
  const state = await readRules(host);
  const { site } = state;
  const reason = String(fix.reason || "").slice(0, 120);
  const base = { id: crypto.randomUUID(), reason, createdAt: Date.now() };
  if (fix.action === "allow_domain") {
    const domain = normalizeDomain(fix.domain);
    if (!domain) throw new Error("Domain không hợp lệ.");
    site.allowDomains = (site.allowDomains || []).filter((r) => r.domain !== domain).concat({ ...base, domain });
  } else if (fix.action === "unhide_selector") {
    if (typeof fix.selector !== "string" || !fix.selector.trim()) throw new Error("Selector không hợp lệ.");
    site.unhide = (site.unhide || []).filter((r) => r.selector !== fix.selector).concat({ ...base, selector: fix.selector });
  } else if (fix.action === "allow_popups" || fix.action === "keep_overlays") {
    site[fix.action === "allow_popups" ? "allowPopups" : "keepOverlays"] = true;
  } else {
    throw new Error(`Cách sửa không hỗ trợ: ${fix.action}`);
  }
  await writeRules(state);
  await rebuildDynamicRules();
}

/** Huỷ ngoại lệ: kind = allowDomains | unhide (theo id) | allowPopups | keepOverlays. */
async function removeException(host, kind, id) {
  const state = await readRules(host);
  const { site } = state;
  if (kind === "allowDomains" || kind === "unhide") site[kind] = (site[kind] || []).filter((r) => r.id !== id);
  else if (kind === "allowPopups" || kind === "keepOverlays") delete site[kind];
  else throw new Error(`Loại ngoại lệ không hợp lệ: ${kind}`);
  await writeRules(state);
  await rebuildDynamicRules();
}

/** Cho phép (on) / chặn lại widget mạng xã hội trên trang `host` (lưu ở site gốc, áp cả tên miền dùng chung). */
async function setWidgetAllowed(host, provider, on) {
  if (!WIDGET_DOMAINS[provider]) throw new Error(`Widget không hợp lệ: ${provider}`);
  const state = await readRules(host);
  const allowed = new Set(state.site.allowWidgets || []);
  if (on) allowed.add(provider);
  else allowed.delete(provider);
  state.site.allowWidgets = [...allowed].sort();
  await writeRules(state);
  await rebuildDynamicRules();
}

async function unlinkSite(host) {
  await browser.storage.local.set({ aliases: unlinkAliases(await readAliases(), siteKey(host)) });
  await rebuildDynamicRules();
}

async function applyRules(tabId, indexes, scopes = {}) {
  const state = await readTab(tabId);
  if (!state.scan || state.scan.status !== "done") throw new Error("Không còn kết quả quét để áp dụng.");
  // scopes: phạm vi người dùng đổi trong popup; saveRules vẫn tự kiểm lại điều kiện "Mọi trang".
  const chosen = indexes.map((i) => state.scan.accepted[i] && { ...state.scan.accepted[i], scope: scopes[i] || state.scan.accepted[i].scope })
    .filter(Boolean);
  await saveRules(state.scan.host, chosen.map((r) => ({ ...r, source: "ai" })));
  await updateTab(tabId, (s) => { s.scan = null; });
  await attempt(() => browser.tabs.sendMessage(tabId, { type: "highlight", selectors: [] }, { frameId: 0 }));
}

/**
 * Xoá toàn bộ rule đã lưu của một nhóm: "site" (ẩn, chặn domain, chặn tab mới của trang này — gồm tên miền dùng chung)
 * hoặc "global" (rule mọi trang). Ngoại lệ (bỏ chặn/bỏ ẩn/widget) không thuộc "Rule đã lưu" nên giữ nguyên.
 */
async function deleteAllRules(host, scope) {
  const state = await readRules(host);
  let removed;
  if (scope === "site") {
    removed = state.site.hide.length + state.site.blockDomains.length + state.site.popupDomains.length;
    Object.assign(state.site, { hide: [], blockDomains: [], popupDomains: [] });
  } else if (scope === "global") {
    removed = state.global.hide.length + state.global.popupDomains.length;
    Object.assign(state.global, { hide: [], popupDomains: [] });
  } else {
    throw new Error(`Nhóm rule không hợp lệ: ${scope}`);
  }
  await writeRules(state);
  await rebuildDynamicRules();
  return removed;
}

async function deleteRule(host, ruleId) {
  const state = await readRules(host);
  const { site, global } = state;
  for (const list of [site.hide, site.popupDomains, site.blockDomains, global.hide, global.popupDomains]) {
    const index = list.findIndex((r) => r.id === ruleId);
    if (index >= 0) list.splice(index, 1);
  }
  await writeRules(state);
  await rebuildDynamicRules();
}

async function saveSettings(message) {
  const local = {};
  if (Array.isArray(message.sensitiveSites)) local.sensitiveSites = message.sensitiveSites;
  if (typeof message.consentAccepted === "boolean") local.consentAccepted = message.consentAccepted;
  if (Object.keys(local).length) await browser.storage.local.set(local);

  const nativePayload = { action: "saveSettings" };
  if (typeof message.apiKey === "string") nativePayload.apiKey = message.apiKey;
  if (typeof message.model === "string") nativePayload.model = message.model;
  if (Object.keys(nativePayload).length > 1) {
    nativeSettingsCache = null;
    await native(nativePayload);
  }
}

// ---------------------------------------------------------------- router

async function handle(message, sender) {
  switch (message.type) {
    case "blocked": {
      const tabId = sender.tab && sender.tab.id;
      if (tabId === undefined) return null;
      const state = await updateTab(tabId, (s) => {
        if (message.kind === "overlay") s.overlays++;
        else s.popups++;
        s.log.unshift({ kind: message.kind, url: String(message.url || "").slice(0, MAX_LOG_URL), reason: message.reason, time: Date.now() });
        s.log.length = Math.min(s.log.length, MAX_LOG);
      });
      await setBadge(tabId, state);
      return null;
    }
    
    case "getTabState": return getTabState(message.tabId, message.url);
    case "scan": return startScan(message.tabId);
    case "dismissScan":
      await updateTab(message.tabId, (s) => { s.scan = null; });
      return attempt(() => browser.tabs.sendMessage(message.tabId, { type: "highlight", selectors: [] }, { frameId: 0 }));
    case "highlight":
      return browser.tabs.sendMessage(message.tabId, { type: "highlight", selectors: message.selectors }, { frameId: 0 });
    case "applyRules": return applyRules(message.tabId, message.indexes, message.scopes);
    case "startPicker":
      return askPage(message.tabId, { type: "startPicker" });
    case "savePicked": {
      const host = hostOf((sender.tab && sender.tab.url) || "");
      if (!host) throw new Error("Không xác định được trang.");
      return saveRules(host, Array.isArray(message.rules) ? message.rules : []);
    }
    case "capture": return sender.tab ? captureScreenshot(sender.tab.windowId) : null;
    case "pickAI": {
      await assertCanSendToAI(hostOf((sender.tab && sender.tab.url) || ""));
      const reply = await native({ action: "analyze", mode: "picked", page: message.page, screenshot: message.screenshot });
      return reply.rules;
    }
    case "deleteRule": return deleteRule(message.host, message.ruleId);
    case "deleteAllRules": return deleteAllRules(message.host, message.scope);
    case "setRuleScope": return setRuleScope(message.host, message.ruleId, message.scope);
    case "linkSite": return linkSite(message.host, message.target);
    case "unlinkSite": return unlinkSite(message.host);
    case "setFeature": return setFeature(message.name, message.on);
    case "applyFix": return applyFix(hostOf(message.url || ""), message.fix || {});
    case "diagnostics": return collectDiagnosis(message.tabId, message.url);
    case "diagnoseAI": return diagnoseWithAI(message.tabId, message.url, message.problem);
    case "removeException": return removeException(hostOf(message.url || ""), message.kind, message.id);
    case "allowWidget": return setWidgetAllowed(hostOf(message.url || (sender.tab && sender.tab.url) || ""), message.provider, true);
    case "disallowWidget": return setWidgetAllowed(message.host, message.provider, false);
    case "privacyReport": return privacyReport(message.tabId, message.url);
    case "scanTrackers": return scanTrackers(message.tabId, message.url);
    case "saveTrackerRules":
      return saveRules(hostOf(message.url), (message.rules || []).map((r) => ({ ...r, type: "block_domain", feature: "tracking", source: "ai" })));
    // Theo URL của frame gửi (iframe có tên miền riêng), không theo tab.
    case "cosmetic": return cosmeticFor(hostOf(message.url || ""), message.tokens, message.initial);
    case "saveSettings": return saveSettings(message);
    case "listModels": return (await native({ action: "listModels" })).models;
    default: return null;
  }
}

browser.runtime.onMessage.addListener((message, sender) => {
  if (!message || typeof message.type !== "string") return undefined;
  return handle(message, sender).then(
    (result) => ({ ok: true, result }),
    (error) => ({ ok: false, error: error.message || String(error) }),
  );
});
