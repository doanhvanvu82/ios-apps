const test = require("node:test");
const assert = require("node:assert/strict");

const load = () => import("../tools/build-filters.mjs");

test("parseNetworkRule: rule domain đơn giản + tuỳ chọn → điều kiện DNR", async () => {
  const F = await load();
  assert.deepEqual(F.parseNetworkRule("||ads.example.com^"), { domain: "ads.example.com", allow: false, condition: {} });
  assert.deepEqual(F.parseNetworkRule("||Pop.Example.com^$third-party,popup,script"), {
    domain: "pop.example.com", allow: false,
    condition: { domainType: "thirdParty", resourceTypes: ["main_frame", "script"] },
  });
  assert.deepEqual(F.parseNetworkRule("@@||cdn.example.com^$~third-party,~image,domain=a.com|~b.com|c.com"), {
    domain: "cdn.example.com", allow: true,
    condition: {
      domainType: "firstParty", initiatorDomains: ["a.com", "c.com"], excludedInitiatorDomains: ["b.com"],
      excludedResourceTypes: ["image"],
    },
  });
  assert.deepEqual(F.parseNetworkRule("||x.com^$important,subdocument").condition, { resourceTypes: ["sub_frame"] });
});

test("parseNetworkRule: bỏ qua rule không hỗ trợ (đường dẫn, regex, $redirect, $csp, chú thích, cosmetic)", async () => {
  const F = await load();
  for (const line of ["||x.com/ads/banner.js", "/banner[0-9]+/", "||x.com^$redirect=noopjs", "||x.com^$csp=script-src",
    "! comment", "##.ad-box", "example.com##.ad", "||x.com^$domain=bad_domain", "||x.com^$removeparam=utm"]) {
    assert.equal(F.parseNetworkRule(line), null, line);
  }
});

test("groupNetworkRules: gộp domain cùng điều kiện vào requestDomains, tách khi vượt giới hạn, allow ưu tiên cao hơn", async () => {
  const F = await load();
  const parsed = [
    ...Array.from({ length: F.DOMAINS_PER_RULE + 5 }, (_, i) => ({ domain: `d${i}.com`, allow: false, condition: {} })),
    { domain: "t.com", allow: false, condition: { domainType: "thirdParty" } },
    { domain: "ok.com", allow: true, condition: {} },
    { domain: "d1.com", allow: false, condition: {} },
  ];
  const rules = F.groupNetworkRules(parsed);
  assert.deepEqual(rules.map((r) => [r.id, r.action.type, r.priority, r.condition.requestDomains.length, r.condition.domainType]), [
    [1, "block", 1, F.DOMAINS_PER_RULE, undefined],
    [2, "block", 1, 5, undefined],
    [3, "block", 1, 1, "thirdParty"],
    [4, "allow", 2, 1, undefined],
  ]);
});

test("selectorToken: token bắt buộc có trên trang; trong ngoặc không tính", async () => {
  const F = await load();
  assert.equal(F.selectorToken("#ad-top"), "#ad-top");
  assert.equal(F.selectorToken("div.ad-box > img"), ".ad-box");
  assert.equal(F.selectorToken("div:not(.content) > .sponsor"), ".sponsor");
  assert.equal(F.selectorToken("a[href^=\"https://ads.\"]"), null);
  assert.equal(F.selectorToken("AMP-AD"), null);
});

test("buildCosmetic: chung theo token, theo domain, ngoại lệ, bỏ cú pháp mở rộng", async () => {
  const F = await load();
  const c = F.buildCosmetic([
    "##.ad-box", "##.ad-box2", "#@#.ad-box2", "##a[href*=\"adclick\"]", "~safe.com##.banner-x",
    "news.vn,m.news.vn##.qc", "news.vn#@#.ad-box", "##.x:has-text(Sponsored)", "#?#.y:-abp-has(.z)", "! ##.comment",
  ]);
  assert.deepEqual(c.genericByToken, { ".ad-box": [".ad-box"], ".banner-x": [".banner-x"] });
  assert.deepEqual(c.genericAlways, ["a[href*=\"adclick\"]"]);
  assert.deepEqual(c.byDomain, { "m.news.vn": [".qc"], "news.vn": [".qc"] });
  assert.deepEqual(c.exceptions, { "news.vn": [".ad-box"], "safe.com": [".banner-x"] });
});

test("buildTrackerIndex: mỗi domain một nhóm, nhóm cụ thể thắng nhóm chung", async () => {
  const F = await load();
  const index = F.buildTrackerIndex({
    ads: ["a.com", "x.com"], analytics: ["b.com", "hotjar.com"], sessionReplay: ["hotjar.com"],
    fingerprinting: ["fpjs.io"], social: ["connect.facebook.net"],
  });
  assert.deepEqual(index, {
    ads: ["a.com", "x.com"], analytics: ["b.com"], social: ["connect.facebook.net"],
    fingerprinting: ["fpjs.io"], session_replay: ["hotjar.com"],
  });
});

test("parseDomainList: bỏ chú thích và dòng không phải domain", async () => {
  const F = await load();
  assert.deepEqual(F.parseDomainList("# c\nhotjar.com\n\nClarity.MS  # x\nnot a domain\n"), ["hotjar.com", "clarity.ms"]);
});
