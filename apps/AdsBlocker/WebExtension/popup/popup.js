"use strict";

const $ = (id) => document.getElementById(id);
const { globalScopeProblem } = globalThis.AdsBlockerRules;
const POLL_MS = 1000;
const PRECHECK_CONFIDENCE = 0.7;
const TOAST_OK_MS = 3000;
const TOAST_ERR_MS = 10000;
// Model preview/thử nghiệm hoặc chuyên dụng (ảnh, giọng nói…) — không tự chọn làm mặc định.
const UNSTABLE_MODEL = /preview|exp|omni|tts|image|audio|live|embedding|thinking/i;
const TYPE_LABEL = {
  hide: "Ẩn phần tử",
  block_domain: "Chặn domain",
  block_popup_domain: "Chặn tab mới tới",
};

let tabId = null;
let state = null;
let pollTimer = 0;
let toastTimer = 0;
// Model lấy từ Google ở lần "Tải danh sách model" gần nhất (null = chưa tải).
let remoteModels = null;
// Kết quả thao tác quét gần nhất (lỗi khi bắt đầu quét, đã áp dụng…), ưu tiên hơn lỗi quét cũ.
let scanFlash = null;

function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children.filter((c) => c !== null && c !== undefined));
  return node;
}

const spinner = () => el("span", { className: "spin" });

async function call(type, extra = {}) {
  const reply = await browser.runtime.sendMessage({ type, ...extra });
  if (!reply || !reply.ok) throw new Error(reply ? reply.error : "Background của extension không phản hồi.");
  return reply.result;
}

// ---------------------------------------------------------------- phản hồi cho người dùng

/** kind: "busy" | "ok" | "err" | "" (thông tin). */
function setStatus(id, kind, text) {
  const node = $(id);
  node.className = `status ${kind}`;
  if (!text) {
    node.replaceChildren();
    return;
  }
  const icon = kind === "busy" ? spinner() : kind === "ok" ? "✓ " : kind === "err" ? "✕ " : "";
  node.replaceChildren(icon, kind === "busy" ? " " : "", text);
}

function toast(kind, text) {
  const node = $("toast");
  clearTimeout(toastTimer);
  node.className = kind;
  node.replaceChildren(kind === "err" ? "✕" : "✓", el("span", { textContent: text }));
  node.hidden = false;
  node.onclick = () => { node.hidden = true; };
  toastTimer = setTimeout(() => { node.hidden = true; }, kind === "err" ? TOAST_ERR_MS : TOAST_OK_MS);
}

/**
 * Chạy một thao tác gắn với nút: nút hiện vòng xoay + `busy`, kết quả (chuỗi trả về) hoặc lỗi hiện ngay dưới nút
 * (`status`) và ở toast đầu màn hình — popup trên iPhone dài, không được để lỗi nằm khuất.
 */
async function run(button, { busy, status }, fn) {
  const label = button.textContent;
  button.disabled = true;
  button.dataset.running = "1";
  button.replaceChildren(spinner(), busy);
  if (status === "scan-status") scanFlash = { kind: "busy", text: busy };
  if (status) setStatus(status, "busy", busy);
  try {
    await currentTab();
    const done = await fn();
    if (status === "scan-status") scanFlash = done ? { kind: "ok", text: done } : null;
    if (status) setStatus(status, done ? "ok" : "", done || "");
    if (done) toast("ok", done);
  } catch (error) {
    const text = error.message || String(error);
    if (status === "scan-status") scanFlash = { kind: "err", text };
    if (status) setStatus(status, "err", text);
    toast("err", text);
    await refresh().catch(() => {});
  } finally {
    delete button.dataset.running;
    button.textContent = label;
    button.disabled = false;
    render();
  }
}

const action = (button, options, fn) => button.addEventListener("click", () => run(button, options, fn));

/**
 * Tab đang mở. Hỏi lại mỗi lần thay vì giữ mã tab lúc mở popup: trên Safari iOS mã tab có thể đổi khi trang
 * điều hướng/tải lại → tabs.get() báo "Tab not found".
 */
async function currentTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab) throw new Error("Không tìm thấy tab đang mở.");
  tabId = tab.id;
  return tab;
}

async function refresh() {
  const tab = await currentTab();
  state = await call("getTabState", { tabId, url: tab.url });
  render();
}

// ---------------------------------------------------------------- render

function ruleText(rule) {
  return rule.type === "hide" || rule.selector ? rule.selector : rule.domain;
}

function render() {
  if (!state) return;
  const { host, stats, log, scan, siteRules, globalRules, sharing, settings, sensitive } = state;

  $("host").textContent = host || "Không phải trang web";
  $("pick").disabled = !host || !state.features.ads;
  const adsOff = "Đang tắt Chặn quảng cáo.";
  if (host && !state.features.ads) setStatus("pick-status", "", adsOff);
  else if ($("pick-status").textContent === adsOff) setStatus("pick-status", "", "");
  if (!host) setStatus("pick-status", "", "Chỉ dùng được trên trang web.");
  $("popups").textContent = stats.popups;
  $("overlays").textContent = stats.overlays;

  $("log").replaceChildren(...(log.length ? log : [null]).map((entry) => entry
    ? el("li", {}, el("div", {},
      el("span", { className: "tag", textContent: entry.kind === "overlay" ? "Lớp phủ" : "Popup" }),
      `${entry.reason} — `, el("code", { textContent: entry.url || "(không có URL)" })))
    : el("li", { textContent: "Chưa chặn gì trên tab này." })));

  renderScan(host, scan, settings, sensitive);
  renderRules(host, siteRules, globalRules);
  renderSharing(host, state.site, sharing);
  renderFeatures(state);
  renderWidgets(host, siteRules);
  renderExceptions(siteRules);
  $("diagnose-box").hidden = !host;
  renderSettings(settings);
  $("reload-banner").hidden = !settings.nativeError;
}

/** Lý do chưa dùng được AI; `needsAds`: thao tác về quảng cáo (quét theo dõi thì không cần bật Chặn quảng cáo). */
function aiBlocker(host, settings, sensitive, { needsAds = true } = {}) {
  if (needsAds && !state.features.ads) return "Đang tắt Chặn quảng cáo.";
  if (!host) return "Chỉ quét được trang web.";
  if (sensitive) return "Trang nhạy cảm — không gửi lên AI.";
  if (settings.nativeError) return settings.nativeError;
  if (!settings.hasKey) return "Chưa có API key — mở Cài đặt AI bên dưới để nhập.";
  if (!settings.model) return "Chưa chọn model — mở Cài đặt AI, bấm Tải danh sách model.";
  return "";
}

function renderScan(host, scan, settings, sensitive) {
  const button = $("scan");
  const running = scan && scan.status === "running";
  const blocker = aiBlocker(host, settings, sensitive);

  if (!button.dataset.running) {
    button.disabled = !!blocker || running;
    button.replaceChildren(...(running ? [spinner(), "Đang quét…"] : ["Quét trang bằng AI"]));
  }
  if (blocker) setStatus("scan-status", "", blocker);
  else if (running) {
    const seconds = Math.round((Date.now() - (scan.startedAt || Date.now())) / 1000);
    setStatus("scan-status", "busy", `Gemini đang phân tích trang… ${seconds} giây (có thể đóng popup, kết quả vẫn giữ)`);
  } else if (scanFlash) setStatus("scan-status", scanFlash.kind, scanFlash.text);
  else if (scan && scan.status === "error") setStatus("scan-status", "err", `Quét lỗi: ${scan.error}`);
  else setStatus("scan-status", "", "");
  if (blocker && host && !sensitive) $("settings").open = true;

  clearTimeout(pollTimer);
  if (running) pollTimer = setTimeout(() => refresh().catch((e) => toast("err", e.message)), POLL_MS);

  const done = scan && scan.status === "done";
  $("scan-result").hidden = !done;
  if (!done) return;

  const kept = $("proposals").dataset.scanKey === String(scan.candidateCount) + scan.accepted.length;
  $("scan-summary").textContent = scan.accepted.length
    ? `AI đề xuất ${scan.accepted.length} rule (đã xét ${scan.candidateCount} khối${scan.usedScreenshot ? ", có ảnh chụp" : ", không có ảnh chụp"}). Chạm vào rule để xem trên trang.`
    : "AI không tìm thấy quảng cáo nào cần chặn thêm.";
  if (!kept) {
    $("proposals").dataset.scanKey = String(scan.candidateCount) + scan.accepted.length;
    proposalScopes = {};
    $("proposals").replaceChildren(...scan.accepted.map((rule, index) => el("li", {},
      el("input", { type: "checkbox", checked: rule.confidence >= PRECHECK_CONFIDENCE, value: String(index), onchange: highlightChosen }),
      el("div", { onclick: () => highlight(rule.type === "hide" ? [rule.selector] : []) },
        el("span", { className: "tag", textContent: TYPE_LABEL[rule.type] }),
        proposalScopeTag(rule, index),
        el("code", { textContent: ruleText(rule) }),
        el("div", { className: "note", textContent: `${rule.reason} · tin cậy ${Math.round(rule.confidence * 100)}%` }),
        rule.scopeNote ? el("div", { className: "note", textContent: rule.scopeNote }) : null))));
  }
  $("apply").hidden = !scan.accepted.length;
  $("rejected-count").textContent = scan.rejected.length;
  $("rejected").replaceChildren(...scan.rejected.map(({ rule, reason }) => el("li", {}, el("div", {},
    el("span", { className: "tag", textContent: reason }),
    el("code", { textContent: rule ? (ruleText(rule) || `#${rule.candidateId}`) : "?" })))));
}

function scopeLabel(scope) {
  return scope === "global" ? "Mọi trang" : "Trang này";
}

/** Nút hành động nhỏ trong danh sách rule: chạy `fn`, báo kết quả bằng toast. */
function smallButton(text, busy, fn) {
  const button = el("button", { className: "small", textContent: text });
  button.addEventListener("click", () => run(button, { busy }, fn));
  return button;
}

function ruleItem(host, rule, scope) {
  const actions = [];
  if (rule.type === "hide") {
    const target = scope === "global" ? "site" : "global";
    const problem = target === "global" ? globalScopeProblem(rule.selector) : null;
    if (!problem) {
      actions.push(smallButton(target === "global" ? "→ Mọi trang" : "→ Trang này", "Đang chuyển…", async () => {
        await call("setRuleScope", { host, ruleId: rule.id, scope: target });
        await refresh();
        return `Đã chuyển rule sang "${scopeLabel(target)}". Tải lại trang để thấy thay đổi.`;
      }));
    }
  }
  actions.push(smallButton("Xoá", "Đang xoá…", async () => {
    await call("deleteRule", { host, ruleId: rule.id });
    await refresh();
    return "Đã xoá rule. Tải lại trang để thấy thay đổi.";
  }));
  return el("li", {},
    el("div", {},
      el("span", { className: "tag", textContent: TYPE_LABEL[rule.type] }),
      el("span", { className: "tag", textContent: rule.source === "manual" ? "Tự chọn" : "AI" }),
      rule.type === "block_domain" ? el("span", { className: "tag scope", textContent: "Mọi trang" }) : null,
      el("code", { textContent: ruleText(rule) }),
      el("div", { className: "note", textContent: rule.reason })),
    el("div", { className: "actions" }, ...actions));
}

function renderRules(host, siteRules, globalRules) {
  const site = [
    ...siteRules.hide.map((r) => ({ ...r, type: "hide" })),
    ...siteRules.blockDomains.map((r) => ({ ...r, type: "block_domain" })),
    ...siteRules.popupDomains.map((r) => ({ ...r, type: "block_popup_domain" })),
  ];
  const global = [
    ...globalRules.hide.map((r) => ({ ...r, type: "hide" })),
    ...globalRules.popupDomains.map((r) => ({ ...r, type: "block_popup_domain" })),
  ];
  $("rule-count").textContent = `${site.length} trang này · ${global.length} mọi trang`;
  $("clear-site").hidden = !site.length;
  $("clear-global").hidden = !global.length;
  $("clear-site").dataset.count = site.length;
  $("clear-global").dataset.count = global.length;
  $("rules").replaceChildren(...(site.length
    ? site.map((r) => ruleItem(host, r, "site"))
    : [el("li", { textContent: "Chưa có rule riêng cho trang này." })]));
  $("global-rules").replaceChildren(...(global.length
    ? global.map((r) => ruleItem(host, r, "global"))
    : [el("li", { textContent: "Chưa có rule áp mọi trang." })]));
}

const CONFIRM_MS = 5000;

/**
 * Nút xoá toàn bộ, xác nhận hai bước ngay trên nút (popup Safari iOS có thể không hiện confirm()):
 * bấm lần 1 → "Bấm lần nữa để xoá N rule" (đỏ); bấm lần 2 trong 5 giây mới xoá; quá hạn thì trở lại.
 */
function clearAllButton(button, scope, label) {
  let timer = 0;
  const disarm = () => {
    clearTimeout(timer);
    delete button.dataset.armed;
    button.classList.remove("armed");
    button.textContent = "Xoá toàn bộ";
  };
  button.addEventListener("click", () => {
    if (button.dataset.running) return;
    if (!button.dataset.armed) {
      button.dataset.armed = "1";
      button.classList.add("armed");
      button.textContent = `Bấm lần nữa để xoá ${button.dataset.count} rule ${label}`;
      timer = setTimeout(disarm, CONFIRM_MS);
      return;
    }
    disarm();
    run(button, { busy: "Đang xoá…" }, async () => {
      const removed = await call("deleteAllRules", { host: state.host, scope });
      await refresh();
      return `Đã xoá ${removed} rule ${label}. Tải lại trang để thấy thay đổi.`;
    });
  });
}

clearAllButton($("clear-site"), "site", "của trang này");
clearAllButton($("clear-global"), "global", "mọi trang");

function renderSharing(host, site, sharing) {
  const { linkedTo, linkedFrom, suggestions, knownSites } = sharing;
  $("share-box").hidden = !host;
  if (!host) return;
  const info = [];
  if (linkedTo) info.push(`${site} đang dùng chung rule của ${linkedTo}.`);
  if (linkedFrom.length) info.push(`Các tên miền dùng chung rule của trang này: ${linkedFrom.join(", ")}.`);
  if (!info.length) info.push("Trang đổi tên miền (vd. truyenqqko → truyenqqto)? Cho tên miền mới dùng chung rule với tên miền cũ.");
  $("share-info").textContent = info.join(" ");

  $("share-suggest").replaceChildren(...suggestions.map((target) => {
    const button = el("button", { className: "primary", textContent: `Trang này giống ${target} — dùng chung rule` });
    button.addEventListener("click", () => run(button, { busy: "Đang liên kết…", status: "share-status" }, () => link(target)));
    return button;
  }));

  const select = $("share-target");
  select.replaceChildren(
    el("option", { value: "", textContent: knownSites.length ? "— Chọn tên miền —" : "— Chưa có tên miền nào khác có rule —" }),
    ...knownSites.map((k) => el("option", { value: k, textContent: k })));
  select.disabled = !knownSites.length || !!linkedTo;
  $("share-link").disabled = !knownSites.length || !!linkedTo;
  $("share-unlink").hidden = !linkedTo;
}

async function link(target) {
  const root = await call("linkSite", { host: state.host, target });
  await refresh();
  return `${state.site} giờ dùng chung rule với ${root}. Tải lại trang để áp dụng.`;
}

function renderSettings(settings) {
  const ready = settings.hasKey && settings.model && !settings.nativeError;
  const badge = $("ai-badge");
  badge.className = `badge ${ready ? "ok" : "err"}`;
  badge.textContent = settings.nativeError ? "Lỗi" : !settings.hasKey ? "Chưa có key" : !settings.model ? "Chưa chọn model" : "Sẵn sàng";

  $("ai-summary").textContent = settings.nativeError
    ? `Không liên lạc được phần native của app: ${settings.nativeError}`
    : `API key: ${settings.hasKey ? "✓ đã lưu trong Keychain" : "✕ chưa có"} · Model: ${settings.model || "chưa chọn"}`;
  $("api-key").placeholder = settings.hasKey ? "Đã lưu (dán key mới để thay)" : "Dán API key (AIza…)";

  const select = $("model");
  const models = remoteModels || (settings.model ? [{ id: settings.model, name: settings.model }] : []);
  const options = models.map((m) => el("option", { value: m.id, textContent: m.name === m.id ? m.id : `${m.name} (${m.id})` }));
  if (!models.some((m) => m.id === settings.model)) {
    options.unshift(el("option", {
      value: "",
      textContent: remoteModels ? "— Chọn model —" : "— Bấm “Tải danh sách model” —",
    }));
  }
  select.replaceChildren(...options);
  select.value = models.some((m) => m.id === settings.model) ? settings.model : "";
  select.disabled = !remoteModels && !settings.model;
  $("load-models").disabled = !settings.hasKey;
  const keyHint = "Lưu API key trước rồi mới tải được danh sách model.";
  if (!settings.hasKey) setStatus("model-status", "", keyHint);
  else if ($("model-status").textContent === keyHint) setStatus("model-status", "", "");
  if (document.activeElement !== $("sensitive")) $("sensitive").value = settings.sensitiveSites.join("\n");
}

// ---------------------------------------------------------------- hành động

// Phạm vi người dùng đổi cho từng đề xuất (index → "site"|"global"), gửi kèm khi áp dụng.
let proposalScopes = {};

function proposalScopeTag(rule, index) {
  const tag = el("span", { className: "tag scope" });
  const problem = rule.type === "hide" ? globalScopeProblem(rule.selector) : "domain luôn áp mọi trang";
  const paint = () => {
    tag.textContent = scopeLabel(proposalScopes[index] || rule.scope);
    tag.title = problem || "Chạm để đổi phạm vi";
  };
  tag.addEventListener("click", (event) => {
    event.stopPropagation();
    if (problem) {
      toast("err", `Không đổi phạm vi được: ${problem}`);
      return;
    }
    proposalScopes[index] = (proposalScopes[index] || rule.scope) === "global" ? "site" : "global";
    paint();
  });
  paint();
  return tag;
}

function highlight(selectors) {
  call("highlight", { tabId, selectors }).catch(() => {});
}

function chosenIndexes() {
  return [...$("proposals").querySelectorAll("input:checked")].map((c) => Number(c.value));
}

function highlightChosen() {
  highlight(chosenIndexes().map((i) => state.scan.accepted[i]).filter((r) => r.type === "hide").map((r) => r.selector));
}

/** Tải model từ Google; model đang chọn không còn trong danh sách thì tự chọn bản "flash" (nhanh, rẻ). */
async function loadModels() {
  const models = await call("listModels");
  if (!models.length) throw new Error("Google trả về 0 model dùng được với API key này.");
  remoteModels = models;
  let chosen = state.settings.model;
  if (!models.some((m) => m.id === chosen)) {
    chosen = (models.find((m) => /flash/i.test(m.id) && !UNSTABLE_MODEL.test(m.id))
      || models.find((m) => /flash/i.test(m.id)) || models[0]).id;
    await call("saveSettings", { model: chosen });
  }
  await refresh();
  return { count: models.length, chosen };
}

async function startScan() {
  scanFlash = null;
  await call("scan", { tabId });
  await refresh();
}

action($("pick"), { busy: "Đang bật chế độ chọn…", status: "pick-status" }, async () => {
  await call("startPicker", { tabId });
  // Không gọi window.close(): trên Safari iOS popup tự đóng xong có thể không mở lại được ở tab đó tới khi tắt hẳn Safari.
  return "Đã bật chế độ chọn. Vuốt đóng popup rồi chạm vào quảng cáo trên trang.";
});

action($("scan"), { busy: "Đang bắt đầu quét…", status: "scan-status" }, async () => {
  if (!state.settings.consentAccepted) {
    $("consent").hidden = false;
    return "";
  }
  await startScan();
  return "";
});

action($("consent-ok"), { busy: "Đang bắt đầu quét…", status: "scan-status" }, async () => {
  await call("saveSettings", { consentAccepted: true });
  $("consent").hidden = true;
  await startScan();
  return "";
});

action($("apply"), { busy: "Đang lưu rule…", status: "scan-status" }, async () => {
  const indexes = chosenIndexes();
  if (!indexes.length) throw new Error("Chưa chọn rule nào.");
  await call("applyRules", { tabId, indexes, scopes: proposalScopes });
  proposalScopes = {};
  await refresh();
  return `Đã lưu ${indexes.length} rule. Tải lại trang để rule chặn domain có hiệu lực.`;
});

action($("dismiss"), { busy: "Đang bỏ qua…", status: "scan-status" }, async () => {
  await call("dismissScan", { tabId });
  await refresh();
  return "";
});

action($("save-key"), { busy: "Đang lưu và kiểm tra key…", status: "key-status" }, async () => {
  const apiKey = $("api-key").value.trim();
  if (!apiKey) throw new Error("Chưa nhập API key.");
  await call("saveSettings", { apiKey });
  $("api-key").value = "";
  await refresh();
  // Thử key ngay để người dùng biết key dùng được hay không.
  try {
    const { count, chosen } = await loadModels();
    setStatus("model-status", "ok", `Đã tải ${count} model · đang dùng ${chosen}`);
    return `Key hợp lệ · ${count} model · đang dùng ${chosen}`;
  } catch (error) {
    throw new Error(`Đã lưu key nhưng gọi Google thất bại: ${error.message}`);
  }
});

action($("clear-key"), { busy: "Đang xoá…", status: "key-status" }, async () => {
  await call("saveSettings", { apiKey: "" });
  remoteModels = null;
  await refresh();
  return "Đã xoá API key khỏi Keychain.";
});

action($("load-models"), { busy: "Đang tải từ Google…", status: "model-status" }, async () => {
  const { count, chosen } = await loadModels();
  return `Đã tải ${count} model · đang dùng ${chosen}`;
});

$("model").addEventListener("change", async (event) => {
  const model = event.target.value;
  if (!model) return;
  setStatus("model-status", "busy", `Đang chọn ${model}…`);
  try {
    await call("saveSettings", { model });
    await refresh();
    setStatus("key-status", "", "");
    setStatus("model-status", "ok", `Đang dùng model ${model}`);
    toast("ok", `Đã chọn model ${model}`);
  } catch (error) {
    setStatus("model-status", "err", error.message);
    toast("err", error.message);
  }
});

// ---------------------------------------------------------------- công tắc tính năng

function renderFeatures({ features, enabledRulesets, nativeParamStrip, skippedRules }) {
  $("feature-ads").checked = features.ads;
  $("feature-tracking").checked = features.tracking;
  $("feature-youtube").checked = features.youtube;
  $("feature-ads").disabled = false;
  $("feature-tracking").disabled = false;
  $("feature-youtube").disabled = false;
  // Ruleset Safari thật sự đang bật lệch với công tắc → Safari không nạp được bộ lọc (thường sau khi cập nhật).
  const missing = Array.isArray(enabledRulesets) ? [
    features.ads && !enabledRulesets.includes("ads") && "quảng cáo",
    features.tracking && !enabledRulesets.includes("tracking") && "theo dõi",
  ].filter(Boolean) : [];
  const warning = "Safari chưa nạp";
  if (missing.length) setStatus("feature-status", "err", `${warning} bộ lọc ${missing.join(", ")} — bấm Tải lại extension ở cuối popup.`);
  else if (skippedRules) setStatus("feature-status", "err", `${warning} ${skippedRules} rule đã lưu (Safari từ chối) — xoá rule lạ trong Rule đã lưu.`);
  else if ($("feature-status").textContent.includes(warning)) setStatus("feature-status", "", "");

  $("privacy-note").textContent = !features.tracking
    ? "Đang tắt Chống theo dõi — tracker trên trang được tải bình thường."
    : nativeParamStrip === false
      ? "Safari không cho xoá tham số theo dõi ở tầng mạng; extension xoá trên link và thanh địa chỉ."
      : "";
  $("tracker-scan").disabled = !features.tracking;
}

for (const [id, name, label] of [["feature-ads", "ads", "Chặn quảng cáo"], ["feature-tracking", "tracking", "Chống theo dõi"], ["feature-youtube", "youtube", "Chặn quảng cáo YouTube"]]) {
  $(id).addEventListener("change", async (event) => {
    const on = event.target.checked;
    event.target.disabled = true;
    setStatus("feature-status", "busy", `Đang ${on ? "bật" : "tắt"} ${label}…`);
    try {
      await call("setFeature", { name, on });
      await refresh();
      const done = `Đã ${on ? "bật" : "tắt"} ${label}. Tải lại trang để áp dụng đầy đủ.`;
      setStatus("feature-status", "ok", done);
      toast("ok", done);
    } catch (error) {
      event.target.checked = !on;
      setStatus("feature-status", "err", error.message);
      toast("err", error.message);
    } finally {
      event.target.disabled = false;
    }
  });
}

// ---------------------------------------------------------------- theo dõi trên trang

const CATEGORY_LABEL = {
  session_replay: "Ghi lại phiên (xem lại thao tác của bạn)",
  fingerprinting: "Lấy dấu vân tay",
  analytics: "Phân tích / thống kê",
  ads: "Quảng cáo",
  social: "Mạng xã hội",
  user: "Rule chặn của bạn",
  null: "Chưa phân loại",
};
const STATUS_LABEL = { blocked: "Đã chặn", loaded: "Đã tải", present: "Có trên trang" };
let trackerProposals = [];

function renderPrivacyReport({ items }) {
  const trackers = items.filter((i) => i.category);
  const badge = $("privacy-badge");
  const loaded = trackers.filter((i) => i.status === "loaded").length;
  badge.className = `badge ${loaded ? "err" : "ok"}`;
  badge.textContent = trackers.length ? `${trackers.length - loaded} chặn · ${loaded} tải` : "Không thấy tracker";
  const groups = Object.keys(CATEGORY_LABEL)
    .map((key) => [key, items.filter((i) => String(i.category) === key)])
    .filter(([, list]) => list.length);
  $("privacy-report").replaceChildren(...(groups.length ? groups.flatMap(([key, list]) => [
    el("h4", { textContent: `${CATEGORY_LABEL[key]} (${list.length})` }),
    el("ul", { className: "list" }, ...list.map((i) => el("li", {}, el("div", {},
      el("span", { className: `tag ${i.status}`, textContent: STATUS_LABEL[i.status] }),
      el("code", { textContent: i.domain }),
      el("div", { className: "note", textContent: `${i.count} lần · ${i.types.join(", ")}` }))))),
  ]) : [el("p", { className: "note", textContent: "Trang này không tải gì từ tên miền khác." })]));
}

async function loadPrivacyReport() {
  const tab = await currentTab();
  renderPrivacyReport(await call("privacyReport", { tabId, url: tab.url }));
}

$("privacy-box").addEventListener("toggle", () => {
  if (!$("privacy-box").open || !state || !state.host) return;
  setStatus("tracker-status", "busy", "Đang kiểm tra trang…");
  loadPrivacyReport()
    .then(() => setStatus("tracker-status", "", ""))
    .catch((error) => setStatus("tracker-status", "err", error.message));
});

action($("privacy-refresh"), { busy: "Đang kiểm tra…", status: "tracker-status" }, async () => {
  await loadPrivacyReport();
  return "";
});

function renderTrackerProposals() {
  $("tracker-proposals").replaceChildren(...trackerProposals.map((rule, index) => el("li", {},
    el("input", { type: "checkbox", checked: rule.confidence >= PRECHECK_CONFIDENCE, value: String(index) }),
    el("div", {},
      el("span", { className: "tag", textContent: CATEGORY_LABEL[rule.category] || rule.category || "Theo dõi" }),
      el("code", { textContent: rule.domain }),
      el("div", { className: "note", textContent: `${rule.reason} · tin cậy ${Math.round(rule.confidence * 100)}%` })))));
  $("tracker-apply").hidden = !trackerProposals.length;
}

action($("tracker-scan"), { busy: "Gemini đang phân loại…", status: "tracker-status" }, async () => {
  const blocker = aiBlocker(state.host, state.settings, state.sensitive, { needsAds: false });
  if (blocker) throw new Error(blocker);
  if (!state.settings.consentAccepted) {
    throw new Error("Cần đồng ý gửi dữ liệu lên Gemini một lần: bấm Quét trang bằng AI để xem và đồng ý.");
  }
  const tab = await currentTab();
  const { accepted } = await call("scanTrackers", { tabId, url: tab.url });
  trackerProposals = accepted;
  renderTrackerProposals();
  return accepted.length ? `AI đề xuất chặn ${accepted.length} domain theo dõi — chọn rồi bấm Chặn.` : "AI không thấy tracker nào chưa bị chặn.";
});

action($("tracker-apply"), { busy: "Đang lưu…", status: "tracker-status" }, async () => {
  const rules = [...$("tracker-proposals").querySelectorAll("input:checked")].map((i) => trackerProposals[Number(i.value)]);
  if (!rules.length) throw new Error("Chưa chọn domain nào.");
  const tab = await currentTab();
  await call("saveTrackerRules", { url: tab.url, rules });
  trackerProposals = [];
  renderTrackerProposals();
  await refresh();
  await loadPrivacyReport();
  return `Đã chặn ${rules.length} domain theo dõi (mọi trang). Tải lại trang để có hiệu lực.`;
});

// ---------------------------------------------------------------- chẩn đoán trang bị lỗi

const FIX_LABEL = {
  allow_domain: "Bỏ chặn domain trên trang này",
  unhide_selector: "Bỏ ẩn trên trang này",
  delete_rule: "Xoá rule của bạn",
  allow_popups: "Cho trang này mở tab mới",
  keep_overlays: "Không gỡ lớp phủ trên trang này",
};
const KIND_LABEL = {
  blocked_domain: "Domain bị chặn",
  failed_domain: "Tải lỗi (không do extension)",
  hidden: "Khối bị ẩn",
  popup_blocked: "Tab mới bị chặn",
  overlay_removed: "Lớp phủ bị gỡ",
};
// Kết quả chẩn đoán gần nhất: { candidates, fixes?, summary? }.
let diagnosis = null;

function candidateText(c) {
  if (c.kind === "hidden") return `${c.selector} — ${c.count} khối${c.media ? `, ${c.media} có ảnh/video` : ""}`;
  if (c.domain) {
    const facts = [
      c.brokenImages && `${c.brokenImages} ảnh lỗi`,
      c.notLoaded.length && `không tải: ${c.notLoaded.join(", ")}`,
      c.lazyImages && `${c.lazyImages} ảnh chờ tải`,
    ].filter(Boolean);
    return `${c.domain}${facts.length ? ` — ${facts.join(" · ")}` : ""}`;
  }
  return `${c.count} lần`;
}

function fixButton(fix, reason) {
  return smallButton(FIX_LABEL[fix.action], "Đang áp dụng…", async () => {
    const tab = await currentTab();
    await call("applyFix", { url: tab.url, fix: { ...fix, reason: reason || FIX_LABEL[fix.action] } });
    await refresh();
    return `Đã áp dụng "${FIX_LABEL[fix.action]}". Tải lại trang để kiểm tra; không đỡ thì huỷ ở mục Ngoại lệ.`;
  });
}

function candidateItem(c, { fixes = c.fixes, note = "" } = {}) {
  return el("li", {},
    el("div", {},
      el("span", { className: "tag", textContent: KIND_LABEL[c.kind] || c.kind }),
      el("code", { textContent: candidateText(c) }),
      el("div", { className: "note", textContent: c.sources.map((s) => s.label).filter(Boolean).join(" · ") || "Không do extension" }),
      note ? el("div", { className: "note", textContent: note }) : null),
    el("div", { className: "actions" }, ...fixes.map((f) => fixButton(f, note))));
}

function renderDiagnosis() {
  const { candidates = [], fixes = null, summary = "" } = diagnosis || {};
  const byId = new Map(candidates.map((c) => [c.id, c]));
  $("diagnose-summary").textContent = summary;
  $("diagnose-fixes").replaceChildren(...(fixes || []).map((f) => candidateItem(byId.get(f.candidateId), {
    fixes: [f], note: `${f.reason} · khả năng ${Math.round(f.confidence * 100)}%`,
  })));
  $("diagnose-all").hidden = !diagnosis;
  $("diagnose-all").open = !!diagnosis && !fixes;
  $("diagnose-count").textContent = candidates.length;
  $("diagnose-candidates").replaceChildren(...(candidates.length
    ? candidates.map((c) => candidateItem(c))
    : [el("li", { textContent: "Không thấy dấu hiệu nào do extension gây ra trên trang này." })]));
}

action($("diagnose-local"), { busy: "Đang xem trang…", status: "diagnose-status" }, async () => {
  const tab = await currentTab();
  diagnosis = { candidates: (await call("diagnostics", { tabId, url: tab.url })).candidates };
  renderDiagnosis();
  const fixable = diagnosis.candidates.filter((c) => c.fixes.length).length;
  return `Tìm thấy ${diagnosis.candidates.length} dấu hiệu, ${fixable} có thể do extension gây ra.`;
});

action($("diagnose-ai"), { busy: "Gemini đang chẩn đoán…", status: "diagnose-status" }, async () => {
  const problem = $("problem").value.trim();
  if (!problem) throw new Error("Nhập mô tả vấn đề trước (vd: ảnh truyện không hiện).");
  const blocker = aiBlocker(state.host, state.settings, state.sensitive, { needsAds: false });
  if (blocker) throw new Error(blocker);
  if (!state.settings.consentAccepted) {
    throw new Error("Cần đồng ý gửi dữ liệu lên Gemini một lần: bấm Quét trang bằng AI để xem và đồng ý.");
  }
  const tab = await currentTab();
  diagnosis = await call("diagnoseAI", { tabId, url: tab.url, problem });
  renderDiagnosis();
  return diagnosis.fixes.length
    ? `AI đề xuất ${diagnosis.fixes.length} cách sửa — thử cái đầu tiên rồi tải lại trang.`
    : "AI không thấy rule nào của extension gây ra vấn đề này.";
});

function renderExceptions(siteRules) {
  const items = [
    ...(siteRules.allowDomains || []).map((r) => ({ kind: "allowDomains", id: r.id, text: `Bỏ chặn ${r.domain}`, note: r.reason })),
    ...(siteRules.unhide || []).map((r) => ({ kind: "unhide", id: r.id, text: `Bỏ ẩn ${r.selector}`, note: r.reason })),
    ...(siteRules.allowPopups ? [{ kind: "allowPopups", text: "Cho mở tab mới" }] : []),
    ...(siteRules.keepOverlays ? [{ kind: "keepOverlays", text: "Không gỡ lớp phủ" }] : []),
  ];
  $("exceptions").replaceChildren(...(items.length ? items.map((item) => el("li", {},
    el("div", {}, el("code", { textContent: item.text }), item.note ? el("div", { className: "note", textContent: item.note }) : null),
    smallButton("Huỷ", "Đang huỷ…", async () => {
      const tab = await currentTab();
      await call("removeException", { url: tab.url, kind: item.kind, id: item.id });
      await refresh();
      return `Đã huỷ ngoại lệ "${item.text}". Tải lại trang để áp dụng.`;
    }))) : [el("li", { textContent: "Chưa có ngoại lệ." })]));
}

const WIDGET_NAME = { facebook: "Facebook", twitter: "X (Twitter)", instagram: "Instagram", tiktok: "TikTok" };

function renderWidgets(host, siteRules) {
  const allowed = siteRules.allowWidgets || [];
  $("widgets").replaceChildren(...(allowed.length ? allowed.map((provider) => el("li", {},
    el("div", {}, el("code", { textContent: WIDGET_NAME[provider] || provider })),
    smallButton("Chặn lại", "Đang chặn…", async () => {
      await call("disallowWidget", { host, provider });
      await refresh();
      return `Đã chặn lại ${WIDGET_NAME[provider] || provider}. Tải lại trang để áp dụng.`;
    }))) : [el("li", { textContent: "Chưa cho phép widget nào (chạm “Chạm để tải” trên trang để cho phép)." })]));
}

action($("share-link"), { busy: "Đang liên kết…", status: "share-status" }, async () => {
  const target = $("share-target").value;
  if (!target) throw new Error("Chọn tên miền muốn dùng chung rule.");
  return link(target);
});

action($("share-unlink"), { busy: "Đang bỏ dùng chung…", status: "share-status" }, async () => {
  const linkedTo = state.sharing.linkedTo;
  await call("unlinkSite", { host: state.host });
  await refresh();
  return `Đã bỏ dùng chung với ${linkedTo}. Rule đã gộp vẫn ở ${linkedTo}.`;
});

// Nạp lại toàn bộ extension (background + phần native ở lần gọi sau). Popup sẽ đóng theo.
for (const id of ["reload-ext", "reload-ext-footer"]) {
  $(id).addEventListener("click", () => {
    toast("ok", "Đang tải lại extension… mở lại popup sau vài giây.");
    setTimeout(() => browser.runtime.reload(), 300);
  });
}

action($("save-sensitive"), { busy: "Đang lưu…", status: "sensitive-status" }, async () => {
  const sensitiveSites = $("sensitive").value.split(/\s+/).map((s) => s.trim().toLowerCase()).filter(Boolean);
  await call("saveSettings", { sensitiveSites });
  await refresh();
  return `Đã lưu ${sensitiveSites.length} domain nhạy cảm.`;
});

(async () => {
  try {
    await refresh();
  } catch (error) {
    $("host").textContent = "✕ Không tải được trạng thái";
    $("reload-banner").hidden = false;
    toast("err", `Không tải được trạng thái extension: ${error.message || error}`);
  }
})();
