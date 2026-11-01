// Logic thuần (không đụng DOM/browser API) dùng chung cho background, content script và test Node.
(function (root) {
  "use strict";

  const MAX_AREA_RATIO = 0.3;
  const MAX_MATCHES = 50;
  const MIN_CONFIDENCE = 0.5;

  // Đuôi tên miền 2 cấp phổ biến: "example.com.vn" là một site, không phải "com.vn".
  const SECOND_LEVEL_SUFFIXES = new Set([
    "com.vn", "net.vn", "org.vn", "edu.vn", "gov.vn", "info.vn", "biz.vn",
    "co.uk", "org.uk", "ac.uk", "com.au", "net.au", "co.jp", "ne.jp", "or.jp",
    "co.kr", "com.cn", "com.br", "co.in", "com.sg", "com.tw", "com.hk", "co.th", "co.id",
  ]);

  // CDN/dịch vụ dùng chung: chặn sẽ làm hỏng hàng loạt trang.
  const PROTECTED_DOMAINS = [
    "googleapis.com", "gstatic.com", "google.com", "youtube.com", "ytimg.com",
    "cloudflare.com", "cdnjs.cloudflare.com", "jsdelivr.net", "unpkg.com", "jquery.com",
    "bootstrapcdn.com", "fontawesome.com", "akamaihd.net", "cloudfront.net", "fastly.net",
    "apple.com", "icloud.com", "microsoft.com", "github.com", "githubusercontent.com",
  ];

  // Selector chạm tới khung trang: ẩn đi là mất cả trang.
  const STRUCTURAL = /^(html|body|:root|main|header|footer|nav|article|section|div|span|a|p|img|ul|li|iframe|form|\*)$/i;

  const AD_WORD = /(?:^|[^a-z])(ads?|advert\w*|adsense|adslot|adunit|adbox|adzone|banner\w*|sponsor\w*|promo\w*|dfp|gpt|doubleclick|taboola|outbrain|popunder|preroll|quang-?cao)(?:[^a-z]|$)/i;

  // Tên miền "giống nhau" khi đổi đuôi (truyenqqko.com → truyenqqto.com): đủ dài và chung phần lớn tiền tố.
  const MIN_SIMILAR_STEM = 6;
  const SIMILAR_PREFIX_RATIO = 0.7;
  const MAX_SIMILAR_EDITS = 2;

  // Tham số URL chỉ dùng để theo dõi nguồn truy cập/quảng cáo (utm_* xoá theo tiền tố).
  const TRACKING_PARAMS = [
    "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "ttclid", "twclid", "igshid", "igsh",
    "mc_eid", "mc_cid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking", "yclid", "_openstat",
    "vero_id", "vero_conv", "mkt_tok", "oly_anon_id", "oly_enc_id", "rb_clickid", "s_cid", "wickedid", "zanpid",
    "epik", "sc_cid", "_gl", "srsltid",
  ];
  const UTM_PARAMS = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id", "utm_name"];
  // Tham số trùng tên dễ là chức năng ở trang khác → chỉ xoá trên trang biết chắc là theo dõi.
  const SITE_TRACKING_PARAMS = { "open.spotify.com": ["si"], "youtu.be": ["si"], "youtube.com": ["si"], "m.youtube.com": ["si"] };

  // Link bọc chuyển hướng: trang trung gian ghi lại cú bấm rồi mới chuyển tới đích thật nằm trong tham số.
  const LINK_WRAPPERS = [
    { host: /(^|\.)google\.[a-z.]+$/, path: /^\/url$/, params: ["q", "url"] },
    { host: /^(l|lm)\.facebook\.com$/, path: /^\/l\.php$/, params: ["u"] },
    { host: /^l\.messenger\.com$/, path: /^\/l\.php$/, params: ["u"] },
    { host: /^l\.instagram\.com$/, path: /^\/?$/, params: ["u"] },
    { host: /^out\.reddit\.com$/, path: /.*/, params: ["url"] },
    { host: /(^|\.)youtube\.com$/, path: /^\/redirect$/, params: ["q"] },
    { host: /^vk\.com$/, path: /^\/away\.php$/, params: ["to"] },
    { host: /^steamcommunity\.com$/, path: /^\/linkfilter\/?$/, params: ["url", "u"] },
    { host: /(^|\.)linkedin\.com$/, path: /^\/redir\/redirect\/?$/, params: ["url"] },
  ];

  const DEFAULT_SENSITIVE_SITES = [
    "vietcombank.com.vn", "techcombank.com", "mbbank.com.vn", "bidv.com.vn", "vietinbank.vn",
    "tpb.vn", "acb.com.vn", "vpbank.com.vn", "momo.vn", "zalopay.vn", "vnpay.vn",
    "paypal.com", "mail.google.com", "accounts.google.com", "outlook.live.com",
    "outlook.office.com", "mail.yahoo.com", "icloud.com", "appleid.apple.com",
  ];

  function hasAdWord(text) {
    return AD_WORD.test(String(text || "").replace(/([a-z])([A-Z])/g, "$1-$2"));
  }

  function siteKey(host) {
    const h = String(host || "").toLowerCase().replace(/\.$/, "");
    if (/^\d+(\.\d+){3}$/.test(h) || h.includes(":")) return h;
    const labels = h.split(".").filter(Boolean);
    if (labels.length <= 2) return labels.join(".");
    const lastTwo = labels.slice(-2).join(".");
    return SECOND_LEVEL_SUFFIXES.has(lastTwo) ? labels.slice(-3).join(".") : lastTwo;
  }

  /** "https://*.Ads.Example.com:443/x" → "ads.example.com"; không hợp lệ → null. */
  function normalizeDomain(input) {
    if (typeof input !== "string") return null;
    let d = input.trim().toLowerCase()
      .replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
      .replace(/^\|\|/, "")
      .split(/[/?#^]/)[0]
      .replace(/:\d+$/, "")
      .replace(/^\*?\./, "")
      .replace(/\.$/, "");
    const label = "[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?";
    if (d.length > 253 || !new RegExp(`^(?:${label}\\.)+[a-z]{2,63}$`).test(d)) return null;
    return d;
  }

  function matchesDomain(host, domain) {
    return host === domain || host.endsWith("." + domain);
  }

  function isSameSite(domain, pageHost) {
    return siteKey(domain) === siteKey(pageHost);
  }

  function isProtectedDomain(domain) {
    return PROTECTED_DOMAINS.some((p) => matchesDomain(domain, p));
  }

  function isSensitiveHost(host, sites) {
    const h = String(host || "").toLowerCase();
    if (h.split(".").some((label) => label.includes("bank"))) return true;
    return (sites || DEFAULT_SENSITIVE_SITES).some((s) => matchesDomain(h, s));
  }

  function isTrackingParam(key, host) {
    const k = key.toLowerCase();
    if (k.startsWith("utm_") || TRACKING_PARAMS.includes(k)) return true;
    const site = Object.keys(SITE_TRACKING_PARAMS).find((h) => matchesDomain(host, h));
    return !!site && SITE_TRACKING_PARAMS[site].includes(k);
  }

  /** Bỏ tham số theo dõi khỏi URL; không đổi gì thì trả lại nguyên chuỗi. */
  function cleanUrl(url) {
    let u;
    try {
      u = new URL(url);
    } catch {
      return url;
    }
    if (!/^https?:$/.test(u.protocol) || !u.search) return url;
    const host = u.hostname.toLowerCase();
    const keys = [...u.searchParams.keys()].filter((k) => isTrackingParam(k, host));
    if (!keys.length) return url;
    keys.forEach((k) => u.searchParams.delete(k));
    return u.href;
  }

  /** Link bọc chuyển hướng (google.com/url?q=…, l.facebook.com/l.php?u=…) → link đích đã làm sạch; không phải thì trả nguyên. */
  function unwrapLink(url) {
    let u;
    try {
      u = new URL(url);
    } catch {
      return url;
    }
    const host = u.hostname.toLowerCase();
    for (const wrapper of LINK_WRAPPERS) {
      if (!wrapper.host.test(host) || !wrapper.path.test(u.pathname)) continue;
      for (const param of wrapper.params) {
        const target = u.searchParams.get(param);
        if (target && /^https?:\/\//i.test(target)) return cleanUrl(target);
      }
    }
    return url;
  }

  /** Lý do selector không dùng được (chưa xét DOM), hoặc null nếu ổn. */
  function selectorProblem(selector) {
    if (typeof selector !== "string" || !selector.trim()) return "selector rỗng";
    const s = selector.trim();
    if (s.length > 300) return "selector quá dài";
    if (/[{}<]|\/\*/.test(s)) return "selector chứa ký tự không hợp lệ";
    for (const part of s.split(",")) {
      const p = part.trim();
      if (!p) return "selector rỗng";
      // "div", "body > div", "main section": toàn thẻ trần → trúng cả khung trang.
      if (p.split(/\s*[\s>+~]\s*/).every((c) => STRUCTURAL.test(c))) return "selector quá chung";
    }
    return null;
  }

  /**
   * Lý do selector không được áp cho mọi trang, hoặc null. Tên class/id do từng trang tự đặt ("div.w-overlay") áp mọi
   * trang sẽ ẩn nhầm; chỉ cho phép khi selector có dấu hiệu quảng cáo rõ (từ khoá quảng cáo, hoặc src/href trỏ domain).
   */
  function globalScopeProblem(selector) {
    const base = selectorProblem(selector);
    if (base) return base;
    const s = selector.trim();
    if (/:nth-(of-type|child|last-child|last-of-type)/i.test(s)) return "selector theo vị trí chỉ đúng trên trang này";
    for (const part of s.split(",")) {
      const names = [...part.matchAll(/[#.]((?:\\.|[\w-])+)/g)].map((m) => m[1]);
      const attrs = [...part.matchAll(/\[\s*([\w-]+)\s*(?:[~|^$*]?=\s*["']?([^"'\]]*)["']?)?\s*\]/g)]
        .map(([, name, value]) => ({ name, value: value || "" }));
      const adName = names.some(hasAdWord) || attrs.some((a) => hasAdWord(a.name) || hasAdWord(a.value));
      const adSource = attrs.some((a) => /^(src|href)$/i.test(a.name) && normalizeDomain(a.value.replace(/^\/\//, "")));
      if (!adName && !adSource) return "selector không có dấu hiệu quảng cáo, áp mọi trang dễ ẩn nhầm";
    }
    return null;
  }

  // ---------------------------------------------------------------- dùng chung rule giữa tên miền

  /** Site gốc đang giữ rule cho `key` (aliases luôn trỏ thẳng tới gốc). */
  function resolveSite(key, aliases) {
    return (aliases && aliases[key]) || key;
  }

  /** Cho `from` dùng chung rule với `to`; site nào đang trỏ vào `from` cũng chuyển sang gốc mới. */
  function linkSite(aliases, from, to) {
    const root = resolveSite(to, aliases);
    if (root === from) throw new Error(`${to} đang dùng chung rule của ${from}.`);
    const next = {};
    for (const [key, value] of Object.entries(aliases || {})) next[key] = value === from ? root : value;
    next[from] = root;
    return next;
  }

  function unlinkSite(aliases, from) {
    const next = { ...(aliases || {}) };
    delete next[from];
    return next;
  }

  const stemOf = (key) => key.split(".")[0];

  function editDistance(a, b) {
    let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1; i <= a.length; i++) {
      const cur = [i];
      for (let j = 1; j <= b.length; j++) {
        cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /** Site đã có rule mà tên giống site hiện tại (cùng tên khác đuôi, hoặc chỉ khác vài ký tự). */
  function similarSites(key, knownKeys) {
    const stem = stemOf(key);
    return knownKeys.filter((other) => {
      if (other === key) return false;
      const o = stemOf(other);
      if (o === stem) return true;
      const shorter = Math.min(stem.length, o.length);
      if (shorter < MIN_SIMILAR_STEM) return false;
      let prefix = 0;
      while (prefix < shorter && stem[prefix] === o[prefix]) prefix++;
      return prefix >= Math.max(MIN_SIMILAR_STEM, Math.ceil(shorter * SIMILAR_PREFIX_RATIO)) ||
        editDistance(stem, o) <= MAX_SIMILAR_EDITS;
    });
  }

  /**
   * Lọc rule do AI đề xuất.
   *
   * ctx.pageHost: host của trang.
   * ctx.candidates: Map<id, {selector}> từ lần snapshot.
   * ctx.measure(selector, candidateId) → {valid, count, areaRatio, includesCandidate} (content script đo trên DOM);
   *   bỏ trống khi không có DOM (test).
   */
  function validateRules(rawRules, ctx) {
    const accepted = [];
    const rejected = [];
    const seen = new Set();
    const reject = (rule, reason) => rejected.push({ rule, reason });

    for (const rule of Array.isArray(rawRules) ? rawRules : []) {
      if (!rule || typeof rule !== "object") {
        reject(rule, "rule không hợp lệ");
        continue;
      }
      const confidence = Math.max(0, Math.min(1, Number(rule.confidence) || 0));
      const reason = String(rule.reason || "").slice(0, 120);
      if (confidence < MIN_CONFIDENCE) {
        reject(rule, "độ tin cậy thấp");
        continue;
      }

      let normalized;
      if (rule.type === "hide") {
        const candidate = ctx.candidates.get(Number(rule.candidateId));
        if (!candidate) {
          reject(rule, "không rõ phần tử");
          continue;
        }
        let problem = "không có selector";
        const selector = [rule.selector, candidate.selector].find((s) => {
          problem = selectorProblem(s);
          if (problem) return false;
          if (!ctx.measure) return true;
          const m = ctx.measure(s.trim(), Number(rule.candidateId));
          if (!m || !m.valid) problem = "selector sai cú pháp";
          else if (!m.includesCandidate) problem = "selector không trúng phần tử";
          else if (m.count > MAX_MATCHES) problem = `selector trúng quá nhiều phần tử (${m.count})`;
          else if (m.areaRatio > MAX_AREA_RATIO) problem = "ẩn quá nhiều nội dung trang";
          return !problem;
        });
        if (!selector) {
          reject(rule, problem);
          continue;
        }
        normalized = { type: "hide", selector: selector.trim(), candidateId: Number(rule.candidateId), scope: "site" };
        if (rule.scope === "global") {
          const scopeProblem = globalScopeProblem(normalized.selector);
          if (scopeProblem) normalized.scopeNote = `Chỉ áp trang này: ${scopeProblem}`;
          else normalized.scope = "global";
        }
      } else if (rule.type === "block_domain" || rule.type === "block_popup_domain") {
        const domain = normalizeDomain(rule.domain);
        if (!domain) {
          reject(rule, "domain không hợp lệ");
          continue;
        }
        if (isSameSite(domain, ctx.pageHost)) {
          reject(rule, "domain của chính trang");
          continue;
        }
        if (isProtectedDomain(domain)) {
          reject(rule, "domain dùng chung, chặn sẽ hỏng trang");
          continue;
        }
        // Domain quảng cáo là quảng cáo ở mọi trang.
        normalized = { type: rule.type, domain, scope: "global" };
        if (typeof rule.category === "string") normalized.category = rule.category.slice(0, 30);
      } else {
        reject(rule, "loại rule không hỗ trợ");
        continue;
      }

      const key = `${normalized.type}|${normalized.selector || normalized.domain}`;
      if (seen.has(key)) continue;
      seen.add(key);
      accepted.push({ ...normalized, reason, confidence });
    }
    return { accepted, rejected };
  }

  /** Domain bên thứ ba chặn được, lấy từ URL tài nguyên/link của khối người dùng chọn. */
  function sourceDomains(urls, pageHost) {
    const result = new Set();
    for (const url of urls) {
      if (!/^(https?:)?\/\//i.test(String(url || ""))) continue;
      const domain = normalizeDomain(url);
      if (domain && !isSameSite(domain, pageHost) && !isProtectedDomain(domain)) result.add(domain);
    }
    return [...result].sort();
  }

  const api = {
    MAX_AREA_RATIO,
    TRACKING_PARAMS: [...UTM_PARAMS, ...TRACKING_PARAMS],
    cleanUrl,
    unwrapLink,
    sourceDomains,
    hasAdWord,
    globalScopeProblem,
    resolveSite,
    linkSite,
    unlinkSite,
    similarSites,
    DEFAULT_SENSITIVE_SITES,
    siteKey,
    normalizeDomain,
    matchesDomain,
    isSameSite,
    isProtectedDomain,
    isSensitiveHost,
    selectorProblem,
    validateRules,
  };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.AdsBlockerRules = api;
})(globalThis);
