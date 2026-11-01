const test = require("node:test");
const assert = require("node:assert/strict");
const R = require("../WebExtension/rules/validate.js");

test("siteKey gộp subdomain và hiểu đuôi 2 cấp", () => {
  assert.equal(R.siteKey("www.example.com"), "example.com");
  assert.equal(R.siteKey("m.news.example.com.vn"), "example.com.vn");
  assert.equal(R.siteKey("localhost"), "localhost");
  assert.equal(R.siteKey("192.168.1.10"), "192.168.1.10");
});

test("normalizeDomain chuẩn hoá và loại giá trị rác", () => {
  assert.equal(R.normalizeDomain("https://*.Ads.Example.com:443/x?y"), "ads.example.com");
  assert.equal(R.normalizeDomain("||popads.net^"), "popads.net");
  assert.equal(R.normalizeDomain("not a domain"), null);
  assert.equal(R.normalizeDomain("-bad.com"), null);
  assert.equal(R.normalizeDomain(42), null);
});

test("isSensitiveHost: danh sách mặc định, đuôi domain và chữ bank", () => {
  assert.ok(R.isSensitiveHost("ebanking.vietcombank.com.vn"));
  assert.ok(R.isSensitiveHost("mybank.example"));
  assert.ok(R.isSensitiveHost("mail.google.com"));
  assert.ok(!R.isSensitiveHost("news.example.com"));
  assert.ok(R.isSensitiveHost("intranet.corp.vn", ["corp.vn"]));
});

test("selectorProblem chặn selector quá chung", () => {
  for (const s of ["div", "body > div", "main section", "*", "a, iframe", "html"]) {
    assert.ok(R.selectorProblem(s), s);
  }
  for (const s of ["#ad-top", "div.banner-ad", "iframe[src*=\"doubleclick.net\"]", "body > div.sponsor > a"]) {
    assert.equal(R.selectorProblem(s), null, s);
  }
  assert.ok(R.selectorProblem("div{color:red}"));
  assert.ok(R.selectorProblem(""));
});

const candidates = new Map([[1, { selector: "#c1" }], [2, { selector: "div.ad-box" }]]);

test("validateRules: hide dùng selector AI nếu đo trên trang hợp lệ, không thì fallback selector ứng viên", () => {
  const measure = (selector) => ({
    "div.sponsored": { valid: true, count: 2, areaRatio: 0.05, includesCandidate: true },
    "div.wide": { valid: true, count: 1, areaRatio: 0.6, includesCandidate: true },
    "#c1": { valid: true, count: 1, areaRatio: 0.02, includesCandidate: true },
  })[selector] || { valid: false };

  const { accepted, rejected } = R.validateRules([
    { type: "hide", candidateId: 1, selector: "div.sponsored", reason: "quảng cáo", confidence: 0.9 },
    { type: "hide", candidateId: 1, selector: "div.wide", reason: "rộng", confidence: 0.9 },
    { type: "hide", candidateId: 9, reason: "không tồn tại", confidence: 0.9 },
  ], { pageHost: "news.example.com", candidates, measure });

  assert.deepEqual(accepted.map((r) => r.selector), ["div.sponsored", "#c1"]);
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].reason, "không rõ phần tử");
});

test("validateRules: hide bị loại khi mọi selector đều ẩn quá nhiều", () => {
  const measure = () => ({ valid: true, count: 1, areaRatio: 0.9, includesCandidate: true });
  const { accepted, rejected } = R.validateRules(
    [{ type: "hide", candidateId: 2, reason: "x", confidence: 1 }],
    { pageHost: "example.com", candidates, measure });
  assert.equal(accepted.length, 0);
  assert.equal(rejected[0].reason, "ẩn quá nhiều nội dung trang");
});

test("validateRules: domain — loại domain của chính trang, CDN dùng chung, độ tin cậy thấp; khử trùng lặp", () => {
  const { accepted, rejected } = R.validateRules([
    { type: "block_domain", domain: "https://ads.badnet.io/x", reason: "a", confidence: 0.9 },
    { type: "block_domain", domain: "ads.badnet.io", reason: "trùng", confidence: 0.9 },
    { type: "block_popup_domain", domain: "cdn.example.com", reason: "b", confidence: 0.9 },
    { type: "block_domain", domain: "fonts.gstatic.com", reason: "c", confidence: 0.9 },
    { type: "block_domain", domain: "maybe.ads.net", reason: "d", confidence: 0.3 },
    { type: "delete_everything", reason: "e", confidence: 1 },
    null,
  ], { pageHost: "www.example.com", candidates });

  assert.deepEqual(accepted, [{ type: "block_domain", domain: "ads.badnet.io", scope: "global", reason: "a", confidence: 0.9 }]);
  assert.deepEqual(rejected.map((r) => r.reason), [
    "domain của chính trang",
    "domain dùng chung, chặn sẽ hỏng trang",
    "độ tin cậy thấp",
    "loại rule không hỗ trợ",
    "rule không hợp lệ",
  ]);
});

test("sourceDomains: chỉ giữ domain bên thứ ba chặn được, khử trùng", () => {
  assert.deepEqual(R.sourceDomains([
    "https://ads.adnet.io/creative.png",
    "//ads.adnet.io/frame",
    "https://cdn.example.com/logo.png",
    "https://fonts.gstatic.com/x.woff",
    "/relative/path.png",
    "data:image/png;base64,AAA",
    "https://tracker.badclick.net/go?u=1",
  ], "www.example.com"), ["ads.adnet.io", "tracker.badclick.net"]);
});

test("validateRules chịu được đầu vào không phải mảng", () => {
  assert.deepEqual(R.validateRules(undefined, { pageHost: "a.com", candidates }), { accepted: [], rejected: [] });
});

test("globalScopeProblem: chỉ cho áp mọi trang khi selector có dấu hiệu quảng cáo", () => {
  for (const ok of ["a.ads-banner", "div.sponsor-box", "#adSlot", "iframe[src*=\"mplmncb.com\"]", "[data-ad-slot]",
    "a[href*='//click.adnet.io']", ".quang-cao"]) {
    assert.equal(R.globalScopeProblem(ok), null, ok);
  }
  assert.match(R.globalScopeProblem("div.w-overlay"), /không có dấu hiệu quảng cáo/);
  assert.match(R.globalScopeProblem("div.w-backdrop, a.ads-banner"), /không có dấu hiệu quảng cáo/);
  assert.match(R.globalScopeProblem("body > div:nth-of-type(3)"), /theo vị trí/);
  assert.match(R.globalScopeProblem("div.ad-box:nth-child(2)"), /theo vị trí/);
  assert.equal(R.globalScopeProblem("div"), "selector quá chung");
});

test("validateRules: scope global bị hạ về site khi selector không đủ điều kiện", () => {
  const cands = new Map([[1, { selector: "#c1" }]]);
  const { accepted } = R.validateRules([
    { type: "hide", candidateId: 1, selector: "div.w-overlay", scope: "global", reason: "x", confidence: 0.9 },
    { type: "hide", candidateId: 1, selector: "a.ads-banner", scope: "global", reason: "y", confidence: 0.9 },
    { type: "hide", candidateId: 1, selector: "div.promo-x", reason: "z", confidence: 0.9 },
  ], { pageHost: "a.com", candidates: cands });
  assert.deepEqual(accepted.map((r) => [r.selector, r.scope]), [["div.w-overlay", "site"], ["a.ads-banner", "global"], ["div.promo-x", "site"]]);
  assert.match(accepted[0].scopeNote, /Chỉ áp trang này/);
});

test("linkSite/unlinkSite: trỏ thẳng tới gốc, chuyển cả site phụ, chống vòng", () => {
  let aliases = R.linkSite({}, "truyenqqto.com", "truyenqqko.com");
  assert.deepEqual(aliases, { "truyenqqto.com": "truyenqqko.com" });
  // Liên kết vào site đang là phụ → trỏ thẳng tới gốc.
  aliases = R.linkSite(aliases, "truyenqqvn.com", "truyenqqto.com");
  assert.equal(aliases["truyenqqvn.com"], "truyenqqko.com");
  // Gốc cũ chuyển sang dùng chung với site mới → mọi site phụ đi theo.
  aliases = R.linkSite(aliases, "truyenqqko.com", "truyenqqmoi.com");
  assert.deepEqual(aliases, {
    "truyenqqto.com": "truyenqqmoi.com", "truyenqqvn.com": "truyenqqmoi.com", "truyenqqko.com": "truyenqqmoi.com",
  });
  assert.throws(() => R.linkSite(aliases, "truyenqqmoi.com", "truyenqqto.com"), /đang dùng chung/);
  assert.equal(R.resolveSite("truyenqqto.com", aliases), "truyenqqmoi.com");
  assert.equal(R.resolveSite("other.com", aliases), "other.com");
  assert.deepEqual(R.unlinkSite(aliases, "truyenqqto.com")["truyenqqto.com"], undefined);
});

test("similarSites: gợi ý tên miền đổi đuôi, không gợi ý tên chỉ giống chút ít", () => {
  const known = ["truyenqqko.com", "truyenfull.vn", "google.com", "example.com.vn", "nettruyen.com"];
  assert.deepEqual(R.similarSites("truyenqqto.com", known), ["truyenqqko.com"]);
  assert.deepEqual(R.similarSites("truyenqqko.net", known), ["truyenqqko.com"]);
  assert.deepEqual(R.similarSites("goo.gl", known), []);
  assert.deepEqual(R.similarSites("example.vn", known), ["example.com.vn"]);
  assert.deepEqual(R.similarSites("truyenfull.com", known), ["truyenfull.vn"]);
});

test("cleanUrl: xoá tham số theo dõi, giữ tham số chức năng; si chỉ xoá trên Spotify/YouTube", () => {
  const cases = [
    ["https://shop.vn/p/1?utm_source=fb&utm_campaign=x&color=red&fbclid=abc", "https://shop.vn/p/1?color=red"],
    ["https://a.com/?gclid=1&UTM_Medium=2", "https://a.com/"],
    ["https://a.com/search?q=utm_source", "https://a.com/search?q=utm_source"],
    ["https://open.spotify.com/track/1?si=abc", "https://open.spotify.com/track/1"],
    ["https://shop.com/?si=size-m", "https://shop.com/?si=size-m"],
    ["https://www.youtube.com/watch?v=x&si=y", "https://www.youtube.com/watch?v=x"],
    ["not a url", "not a url"],
    ["https://a.com/#utm_source=x", "https://a.com/#utm_source=x"],
  ];
  for (const [input, expected] of cases) assert.equal(R.cleanUrl(input), expected, input);
});

test("unwrapLink: gỡ link bọc chuyển hướng về trang đích (đã làm sạch), link thường giữ nguyên", () => {
  const cases = [
    ["https://www.google.com/url?q=https://news.vn/a%3Futm_source%3Dg&sa=U", "https://news.vn/a"],
    ["https://www.google.com.vn/url?url=https://x.com/b&rct=j", "https://x.com/b"],
    ["https://l.facebook.com/l.php?u=https%3A%2F%2Fshop.vn%2Fp%3Ffbclid%3D1&h=AT0", "https://shop.vn/p"],
    ["https://out.reddit.com/t3_abc?url=https%3A%2F%2Fblog.com%2Fpost&token=x", "https://blog.com/post"],
    ["https://www.youtube.com/redirect?event=video&q=https%3A%2F%2Fsite.com%2F", "https://site.com/"],
    ["https://vk.com/away.php?to=https%3A%2F%2Fa.ru%2F", "https://a.ru/"],
    ["https://www.google.com/url?q=javascript:alert(1)", "https://www.google.com/url?q=javascript:alert(1)"],
    ["https://www.google.com/search?q=https://a.com", "https://www.google.com/search?q=https://a.com"],
  ];
  for (const [input, expected] of cases) assert.equal(R.unwrapLink(input), expected, input);
});
