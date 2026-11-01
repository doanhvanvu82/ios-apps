const test = require("node:test");
const assert = require("node:assert/strict");
const C = require("../WebExtension/content/candidates.js");

const base = {
  tag: "div", idClass: "", thirdPartyFrame: false, fixed: false, absolute: false, sticky: false,
  zIndex: 0, width: 600, height: 400, viewportRatio: 0.3, transparent: false, pointerEventsNone: false,
  textLength: 200, hasMedia: true, thirdPartyLinks: 0,
};

test("hasAdWord bắt từ khoá quảng cáo nhưng không bắt từ thường", () => {
  assert.ok(C.hasAdWord("top-ad-slot"));
  assert.ok(C.hasAdWord("sponsoredContent"));
  assert.ok(C.hasAdWord("div-gpt-ad-123"));
  assert.ok(!C.hasAdWord("header download address"));
  assert.ok(!C.hasAdWord("shadow badge"));
});

test("isBannerSize theo kích thước IAB có dung sai", () => {
  assert.ok(C.isBannerSize(300, 250));
  assert.ok(C.isBannerSize(726, 92));
  assert.ok(!C.isBannerSize(600, 400));
});

test("isRandomToken nhận class hash, giữ class có nghĩa", () => {
  assert.ok(C.isRandomToken("x1a2b3c"));
  assert.ok(C.isRandomToken("css-1q2w3e4"));
  assert.ok(!C.isRandomToken("ad-banner"));
  assert.ok(!C.isRandomToken("col-md-12"));
  assert.ok(!C.isRandomToken("h1"));
});

test("scoreCandidate: nội dung thường không phải ứng viên", () => {
  assert.equal(C.scoreCandidate(base).isCandidate, false);
});

test("scoreCandidate: iframe bên thứ ba cỡ banner là ứng viên", () => {
  const r = C.scoreCandidate({ ...base, tag: "iframe", thirdPartyFrame: true, width: 300, height: 250 });
  assert.ok(r.isCandidate);
  assert.deepEqual(r.hints, ["third-party-iframe", "banner-size"]);
});

test("slotIndex leo tới khung cùng cỡ, dừng ở khung lớn hơn", () => {
  const box = (left, top, width, height) => ({ left, top, width, height });
  const chain = [box(10, 10, 300, 250), box(10, 10, 300, 250), box(8, 6, 304, 256), box(0, 0, 800, 600), box(8, 6, 304, 256)];
  assert.equal(C.slotIndex(chain), 2);
  assert.equal(C.slotIndex([box(0, 0, 100, 100)]), 0);
  // Khung có padding nhỏ (diện tích ≤ 1.15×) vẫn tính là khung chứa.
  assert.equal(C.slotIndex([box(20, 20, 300, 250), box(10, 10, 320, 260)]), 1);
});

test("isInvisibleOverlay: lớp phủ fixed trong suốt phủ màn hình", () => {
  const overlay = { ...base, fixed: true, transparent: true, viewportRatio: 0.95, textLength: 0, hasMedia: false, zIndex: 9999 };
  assert.ok(C.isInvisibleOverlay(overlay));
  assert.ok(C.scoreCandidate(overlay).hints.includes("invisible-overlay"));
  // Không gỡ: có pointer-events:none, có chữ, có nền (modal backdrop), absolute z-index thấp (stretched link).
  assert.ok(!C.isInvisibleOverlay({ ...overlay, pointerEventsNone: true }));
  assert.ok(!C.isInvisibleOverlay({ ...overlay, textLength: 50 }));
  assert.ok(!C.isInvisibleOverlay({ ...overlay, transparent: false }));
  assert.ok(!C.isInvisibleOverlay({ ...overlay, fixed: false, absolute: true, zIndex: 1 }));
});
