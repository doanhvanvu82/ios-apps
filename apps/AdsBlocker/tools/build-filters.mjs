#!/usr/bin/env node
// Chuyển bộ lọc Adblock Plus (EasyList, ABPVN, EasyPrivacy) + danh sách tự soạn (tools/lists/) thành
// ruleset declarativeNetRequest + dữ liệu ẩn phần tử + chỉ mục tracker cho extension.
//
//   node tools/build-filters.mjs            → tải bộ lọc (lỗi mạng thì dùng .filters-cache/), ghi WebExtension/filters/
//
// Chỉ nhận rule đơn giản `||domain^$tuỳ-chọn` (chiếm ~90% rule mạng); regex/đường dẫn/$redirect/$csp… bị bỏ qua.
// Domain cùng điều kiện được gộp vào `requestDomains` → vài trăm rule thay vì ~90k (giới hạn rule tĩnh của Safari chưa rõ).
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "WebExtension", "filters");
const CACHE = join(ROOT, ".filters-cache");
const LISTS = join(ROOT, "tools", "lists");

const SOURCES = {
  easylist: { url: "https://easylist.to/easylist/easylist.txt", feature: "ads" },
  abpvn: { url: "https://abpvn.com/filter/abpvn-IPl6HE.txt", feature: "ads" },
  easyprivacy: { url: "https://easylist.to/easylist/easyprivacy.txt", feature: "tracking" },
};

export const DOMAINS_PER_RULE = 1000;
const LIST_BLOCK_PRIORITY = 1;
const LIST_ALLOW_PRIORITY = 2;

// Tuỳ chọn ABP → resourceType của declarativeNetRequest. popup/document = mở/điều hướng tới trang đó (main_frame).
const TYPE_MAP = {
  script: "script", image: "image", stylesheet: "stylesheet", subdocument: "sub_frame", xmlhttprequest: "xmlhttprequest",
  ping: "ping", media: "media", font: "font", websocket: "websocket", object: "object", other: "other",
  popup: "main_frame", document: "main_frame",
};
// Tuỳ chọn không ảnh hưởng việc chặn domain.
const IGNORED_OPTIONS = new Set(["important", "match-case"]);
// Selector dùng cú pháp mở rộng của ABP/uBlock — CSS thường không hiểu.
const EXTENDED_CSS = /:-abp-|:has-text\(|:contains\(|:xpath\(|:style\(|:matches-css|:upward\(|:remove\(|:watch-attr|:min-text-length|:matches-path|:others\(|:if\(|:if-not\(/;

const DOMAIN_RE = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,62}$/;

/**
 * "||ads.example.com^$third-party,script,domain=a.com|~b.com" → { domain, allow, condition } hoặc null nếu không hỗ trợ.
 * condition chỉ chứa các khoá declarativeNetRequest (trừ requestDomains).
 */
export function parseNetworkRule(line) {
  const text = line.trim();
  const allow = text.startsWith("@@");
  const m = /^(?:@@)?\|\|([a-z0-9.-]+)\^(?:\$(.+))?$/i.exec(text);
  if (!m) return null;
  const domain = m[1].toLowerCase();
  if (!DOMAIN_RE.test(domain)) return null;

  const condition = {};
  const types = [];
  const excludedTypes = [];
  for (const raw of (m[2] || "").split(",").filter(Boolean)) {
    const [name, value] = raw.split("=");
    const negated = name.startsWith("~");
    const key = name.replace(/^~/, "");
    if (IGNORED_OPTIONS.has(key)) continue;
    if (key === "third-party" || key === "3p") {
      condition.domainType = negated ? "firstParty" : "thirdParty";
    } else if (key === "first-party" || key === "1p") {
      condition.domainType = negated ? "thirdParty" : "firstParty";
    } else if (key === "domain" && value) {
      const include = [];
      const exclude = [];
      for (const d of value.split("|")) {
        const name = d.replace(/^~/, "").toLowerCase();
        if (!DOMAIN_RE.test(name)) return null;
        (d.startsWith("~") ? exclude : include).push(name);
      }
      if (include.length) condition.initiatorDomains = include.sort();
      if (exclude.length) condition.excludedInitiatorDomains = exclude.sort();
    } else if (TYPE_MAP[key]) {
      (negated ? excludedTypes : types).push(TYPE_MAP[key]);
    } else {
      return null;
    }
  }
  if (types.length) condition.resourceTypes = [...new Set(types)].sort();
  if (excludedTypes.length) condition.excludedResourceTypes = [...new Set(excludedTypes)].sort();
  return { domain, allow, condition };
}

/** Gộp các rule cùng hành động + điều kiện thành rule DNR với requestDomains (≤ DOMAINS_PER_RULE domain/rule). */
export function groupNetworkRules(parsed, firstId = 1) {
  const groups = new Map();
  for (const rule of parsed) {
    const key = JSON.stringify([rule.allow, rule.condition]);
    if (!groups.has(key)) groups.set(key, { allow: rule.allow, condition: rule.condition, domains: new Set() });
    groups.get(key).domains.add(rule.domain);
  }
  const rules = [];
  let id = firstId;
  for (const { allow, condition, domains } of groups.values()) {
    const sorted = [...domains].sort();
    for (let i = 0; i < sorted.length; i += DOMAINS_PER_RULE) {
      rules.push({
        id: id++,
        priority: allow ? LIST_ALLOW_PRIORITY : LIST_BLOCK_PRIORITY,
        action: { type: allow ? "allow" : "block" },
        condition: { ...condition, requestDomains: sorted.slice(i, i + DOMAINS_PER_RULE) },
      });
    }
  }
  return rules;
}

/** Token (#id hoặc .class) phải có trên trang thì selector mới có thể khớp; null nếu không có (luôn áp). */
export function selectorToken(selector) {
  // Bỏ phần trong ngoặc (:not(.x), :has(.y)…): token ở đó không bắt buộc có trên phần tử.
  let s = selector;
  for (let prev = ""; prev !== s;) {
    prev = s;
    s = s.replace(/\([^()]*\)/g, "");
  }
  const m = /([#.])((?:\\.|[\w-])+)/.exec(s);
  return m ? m[1] + m[2] : null;
}

/**
 * Rule ẩn phần tử: "##sel", "a.com,b.com##sel", "~a.com##sel" (chung trừ a.com), "a.com#@#sel" (ngoại lệ).
 * Trả về dữ liệu gọn cho content script: chung theo token, chung luôn áp, theo domain, ngoại lệ theo domain.
 */
export function buildCosmetic(lines) {
  const generic = new Set();
  const genericExceptions = new Set();
  const byDomain = new Map();
  const exceptions = new Map();
  const add = (map, key, value) => {
    if (!map.has(key)) map.set(key, new Set());
    map.get(key).add(value);
  };

  for (const line of lines) {
    const m = /^([^#]*)(##|#@#)(.+)$/.exec(line.trim());
    if (!m || line.startsWith("!")) continue;
    const [, domainPart, sep, selector] = m;
    if (EXTENDED_CSS.test(selector) || selector.startsWith("+js") || /[{}]/.test(selector)) continue;
    const domains = domainPart.split(",").map((d) => d.trim().toLowerCase()).filter(Boolean);
    const include = domains.filter((d) => !d.startsWith("~"));
    const exclude = domains.filter((d) => d.startsWith("~")).map((d) => d.slice(1));
    if (sep === "#@#") {
      if (!include.length) genericExceptions.add(selector);
      include.forEach((d) => add(exceptions, d, selector));
      continue;
    }
    if (include.length) {
      include.forEach((d) => add(byDomain, d, selector));
    } else {
      generic.add(selector);
      exclude.forEach((d) => add(exceptions, d, selector));
    }
  }

  const genericByToken = {};
  const genericAlways = [];
  for (const selector of [...generic].sort()) {
    if (genericExceptions.has(selector)) continue;
    const token = selectorToken(selector);
    if (token) (genericByToken[token] ||= []).push(selector);
    else genericAlways.push(selector);
  }
  const toObject = (map) => Object.fromEntries([...map].sort().map(([k, v]) => [k, [...v].sort()]));
  return { genericByToken, genericAlways, byDomain: toObject(byDomain), exceptions: toObject(exceptions) };
}

/** Dòng danh sách tự soạn: "domain" mỗi dòng, "#" là chú thích. */
export function parseDomainList(text) {
  return text.split("\n").map((l) => l.replace(/#.*/, "").trim().toLowerCase()).filter((l) => DOMAIN_RE.test(l));
}

/**
 * Nhóm → danh sách domain (cho báo cáo trong popup); mỗi domain chỉ thuộc một nhóm, nhóm cụ thể (ghi phiên,
 * fingerprint, mạng xã hội) thắng nhóm chung. Lưu theo nhóm thay vì domain → nhóm để file nhỏ hơn.
 */
export function buildTrackerIndex({ ads, analytics, sessionReplay, fingerprinting, social }) {
  const owner = new Map();
  for (const [category, domains] of [
    ["ads", ads], ["analytics", analytics], ["social", social],
    ["fingerprinting", fingerprinting], ["session_replay", sessionReplay],
  ]) {
    for (const d of domains) owner.set(d, category);
  }
  const index = { ads: [], analytics: [], social: [], fingerprinting: [], session_replay: [] };
  for (const [domain, category] of owner) index[category].push(domain);
  for (const list of Object.values(index)) list.sort();
  return index;
}

// ---------------------------------------------------------------- main

async function fetchList(name, url) {
  const cacheFile = join(CACHE, `${name}.txt`);
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(60000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = await res.text();
    mkdirSync(CACHE, { recursive: true });
    writeFileSync(cacheFile, text);
    return text;
  } catch (error) {
    if (!existsSync(cacheFile)) throw new Error(`Không tải được ${name} (${error.message}) và chưa có cache.`);
    console.warn(`⚠️  Không tải được ${name} (${error.message}) — dùng bản cache.`);
    return readFileSync(cacheFile, "utf8");
  }
}

const networkLines = (text) => text.split("\n").map(parseNetworkRule).filter(Boolean);

async function main() {
  const texts = {};
  for (const [name, { url }] of Object.entries(SOURCES)) texts[name] = await fetchList(name, url);
  const custom = (file) => parseDomainList(readFileSync(join(LISTS, file), "utf8"));
  const sessionReplay = custom("session_replay.txt");
  const fingerprinting = custom("fingerprinting.txt");
  const socialRules = JSON.parse(readFileSync(join(LISTS, "social.json"), "utf8"));

  const adParsed = [...networkLines(texts.easylist), ...networkLines(texts.abpvn)];
  const trackParsed = [
    ...networkLines(texts.easyprivacy),
    ...[...sessionReplay, ...fingerprinting].map((domain) => ({ domain, allow: false, condition: { domainType: "thirdParty" } })),
  ];

  const ads = groupNetworkRules(adParsed);
  const tracking = groupNetworkRules(trackParsed);
  // Ping/beacon tới bên thứ ba: gần như chỉ dùng để thống kê/theo dõi.
  tracking.push({ id: tracking.length + 1, priority: LIST_BLOCK_PRIORITY, action: { type: "block" },
    condition: { resourceTypes: ["ping"], domainType: "thirdParty" } });
  // Widget mạng xã hội: chặn mặc định, content script thay bằng ô "Chạm để tải".
  for (const { urlFilter, resourceTypes } of socialRules.block) {
    tracking.push({ id: tracking.length + 1, priority: LIST_BLOCK_PRIORITY, action: { type: "block" },
      condition: { urlFilter, resourceTypes, domainType: "thirdParty" } });
  }

  const cosmetic = buildCosmetic([...texts.easylist.split("\n"), ...texts.abpvn.split("\n")]);
  const plainBlocked = (parsed) => parsed.filter((r) => !r.allow && !r.condition.initiatorDomains).map((r) => r.domain);
  const trackerIndex = buildTrackerIndex({
    ads: plainBlocked(adParsed),
    analytics: plainBlocked(networkLines(texts.easyprivacy)),
    sessionReplay,
    fingerprinting,
    social: socialRules.domains,
  });

  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, "ads_network.json"), JSON.stringify(ads));
  writeFileSync(join(OUT, "tracking_network.json"), JSON.stringify(tracking));
  writeFileSync(join(OUT, "cosmetic.json"), JSON.stringify(cosmetic));
  writeFileSync(join(OUT, "tracker_index.json"), JSON.stringify(trackerIndex));
  const count = (rules) => rules.reduce((n, r) => n + (r.condition.requestDomains || [1]).length, 0);
  console.log(`✅ Bộ lọc: quảng cáo ${ads.length} rule (${count(ads)} domain), theo dõi ${tracking.length} rule (${count(tracking)} domain), ` +
    `ẩn phần tử ${Object.values(cosmetic.genericByToken).flat().length + cosmetic.genericAlways.length} chung + ` +
    `${Object.keys(cosmetic.byDomain).length} trang, chỉ mục tracker ${Object.values(trackerIndex).flat().length} domain`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`❌ ${error.message}`);
    process.exit(1);
  });
}
