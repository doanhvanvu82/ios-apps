"use strict";

const $ = (id) => document.getElementById(id);
let toastTimer = 0;
let busy = false;

async function call(message) {
  const reply = await browser.runtime.sendMessage(message);
  if (!reply) throw new Error("Background của extension không phản hồi.");
  if (!reply.ok) throw new Error(reply.error || "Lỗi không rõ.");
  return reply.result;
}

function toast(text, isError) {
  const node = $("toast");
  clearTimeout(toastTimer);
  node.textContent = text;
  node.className = isError ? "err" : "";
  node.hidden = false;
  toastTimer = setTimeout(() => { node.hidden = true; }, isError ? 8000 : 3000);
}

function run(button, task) {
  if (busy) return;
  busy = true;
  const label = button.textContent;
  button.disabled = true;
  button.textContent = "…";
  Promise.resolve()
    .then(task)
    .catch((error) => toast(error.message || String(error), true))
    .finally(() => {
      busy = false;
      button.disabled = false;
      button.textContent = label;
    });
}

function ensureModelOption(id) {
  const select = $("model");
  if (!id) return;
  if (![...select.options].some((option) => option.value === id)) {
    select.add(new Option(id, id));
  }
  select.value = id;
}

async function refresh() {
  try {
    const settings = await call({ type: "getSettings" });
    $("key-status").textContent = settings.hasKey ? `Đã lưu key. Model: ${settings.model}` : "Chưa có API key.";
    ensureModelOption(settings.model);
  } catch (error) {
    $("key-status").textContent = `Chưa sẵn sàng: ${error.message || error}`;
  }
}

async function saveKey() {
  const apiKey = $("api-key").value.trim();
  if (!apiKey) throw new Error("Dán API key vào ô trước đã.");
  const settings = await call({ type: "saveSettings", apiKey });
  $("api-key").value = "";
  $("key-status").textContent = `Đã lưu key. Model: ${settings.model}`;
  ensureModelOption(settings.model);
  toast("Đã lưu API key.");
}

async function loadModels() {
  const models = await call({ type: "listModels" });
  if (!models.length) throw new Error("Gemini không trả model nào dùng được.");
  const select = $("model");
  const current = select.value;
  select.replaceChildren(...models.map((model) => new Option(`${model.name} (${model.id})`, model.id)));
  const settings = await call({ type: "getSettings" });
  const chosen = [current, settings.model, models[0].id].find((id) => models.some((model) => model.id === id));
  select.value = chosen;
  await call({ type: "saveSettings", model: chosen });
  $("key-status").textContent = `Đã lưu key. Model: ${chosen}`;
  toast(`Đã tải ${models.length} model.`);
}

async function changeModel() {
  const model = $("model").value;
  if (!model) return;
  const settings = await call({ type: "saveSettings", model });
  $("key-status").textContent = settings.hasKey ? `Đã lưu key. Model: ${settings.model}` : "Chưa có API key.";
}

async function translateTab() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab) throw new Error("Không tìm thấy tab đang mở.");
  await ensureContent(tab.id);
  const reply = await browser.tabs.sendMessage(tab.id, { type: "translateNow" });
  if (!reply || !reply.ok) throw new Error("Trang này không phản hồi. Tải lại trang rồi thử lại.");
  window.close();
}

/** Tab mở trước khi cài/cập nhật extension chưa có content script — nạp rồi thử lại. */
async function ensureContent(tabId) {
  let alive;
  try {
    alive = await browser.tabs.sendMessage(tabId, { type: "ping" });
  } catch {
    alive = undefined;
  }
  if (alive) return;
  await browser.scripting.executeScript({
    target: { tabId, allFrames: true },
    files: ["content/translate-core.js", "content/translate.js"],
  });
}

/** Hiển thị log + chẩn đoán của lần dịch gần nhất do content script lưu trong storage.local. */
async function showDiagnostics() {
  const node = $("diag");
  let data;
  try {
    data = (await browser.storage.local.get("mangalate:lastRun"))["mangalate:lastRun"];
  } catch (error) {
    node.textContent = `Không đọc được chẩn đoán: ${error.message || error}`;
    return;
  }
  if (!data) {
    node.textContent = "Chưa có lần dịch nào.";
    return;
  }
  const parts = [
    `${data.at} · ${data.phase || "?"} · model ${data.model || "?"}`,
    `block: ${data.total} · gửi dịch: ${data.sent} · đã dịch: ${data.translated} · khung theo đường bao: ${data.shaped || 0} (phủ kín chữ: ${data.covered || 0})`,
  ];
  if (data.dropped && data.dropped.length) {
    parts.push("", `Bỏ vì không phải ô hội thoại (${data.dropped.length}):`);
    for (const item of data.dropped) {
      parts.push(`「${item.text}」 fill=${item.fill} ô=${item.enclose} nền=${item.bg}`);
    }
  }
  if (data.missing && data.missing.length) {
    parts.push("", `Gửi nhưng AI không trả bản dịch (${data.missing.length}):`);
    for (const item of data.missing) parts.push(`#${item.id} 「${item.text}」`);
  }
  if (data.kept && data.kept.length) {
    parts.push("", `Đã dịch — fill thấp trước (${data.kept.length}):`);
    for (const item of data.kept) {
      parts.push(`「${item.text}」 fill=${item.fill} ô=${item.enclose} nền=${item.bg}`);
    }
  }
  if (data.lines && data.lines.length) parts.push("", "Log:", ...data.lines);
  node.textContent = parts.join("\n");
}

/** Xoá cache bản dịch (key `mangalate:v<phiên bản>:…` + cache-index), giữ chẩn đoán. */
async function clearCache() {
  const all = await browser.storage.local.get(null);
  const keys = Object.keys(all).filter((key) => /^mangalate:v\d+:/.test(key) || key === "mangalate:cache-index");
  if (!keys.length) {
    toast("Chưa có cache bản dịch nào.");
    return;
  }
  await browser.storage.local.remove(keys);
  toast(`Đã xoá ${keys.length} mục cache. Mở lại truyện rồi bấm Dịch.`);
}

const SITES_KEY = "mangalate:sites";

async function readSites() {
  const data = await browser.storage.local.get(SITES_KEY);
  return Array.isArray(data[SITES_KEY]) ? data[SITES_KEY] : [];
}

async function writeSites(sites) {
  await browser.storage.local.set({ [SITES_KEY]: sites });
}

async function currentHost() {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) return "";
  try {
    return new URL(tab.url).hostname.toLowerCase();
  } catch {
    return "";
  }
}

async function renderSites() {
  const host = await currentHost();
  const sites = await readSites();
  $("site-current").textContent = host
    ? `Đang xem: ${host} — ${allowedFor(host, sites) ? "đã cho phép" : "chưa cho phép"}`
    : "Đang xem: trang không xác định";
  const list = $("site-list");
  if (!sites.length) {
    list.innerHTML = "";
    return;
  }
  list.replaceChildren(...sites.map((site) => {
    const item = document.createElement("li");
    const label = document.createElement("span");
    label.textContent = site;
    const remove = document.createElement("button");
    remove.textContent = "Xoá";
    remove.addEventListener("click", () => {
      removeSite(site).catch((error) => toast(error.message || String(error), true));
    });
    item.append(label, remove);
    return item;
  }));
}

function allowedFor(host, sites) {
  return sites.some((site) => host === site || host.endsWith("." + site));
}

async function addCurrentSite() {
  const host = await currentHost();
  if (!host) throw new Error("Không xác định được trang đang mở.");
  const sites = await readSites();
  if (allowedFor(host, sites)) {
    toast(`${host} đã có trong danh sách.`);
    return;
  }
  // Thêm tên miền gốc (bỏ www.) để dùng được cho cả trang con.
  const base = host.replace(/^www\./, "");
  await writeSites([...sites, base].sort());
  await renderSites();
  toast(`Đã thêm ${base}. Mở lại trang để thấy nút Dịch.`);
}

async function removeSite(site) {
  const sites = await readSites();
  await writeSites(sites.filter((item) => item !== site));
  await renderSites();
  toast(`Đã xoá ${site}.`);
}

$("add-site").addEventListener("click", (event) => run(event.currentTarget, addCurrentSite));
$("save-key").addEventListener("click", (event) => run(event.currentTarget, saveKey));
$("load-models").addEventListener("click", (event) => run(event.currentTarget, loadModels));
$("translate").addEventListener("click", (event) => run(event.currentTarget, translateTab));
$("clear-cache").addEventListener("click", (event) => run(event.currentTarget, clearCache));
$("model").addEventListener("change", () => {
  changeModel().catch((error) => toast(error.message || String(error), true));
});
$("diag-card").addEventListener("toggle", (event) => {
  if (event.currentTarget.open) showDiagnostics();
});

renderSites().catch(() => {});
refresh();
