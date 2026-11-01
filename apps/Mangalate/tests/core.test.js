"use strict";

const test = require("node:test");
const assert = require("node:assert");
const path = require("node:path");

// translate-core.js gắn vào globalThis (không export) — nạp rồi đọc global.
require(path.join(__dirname, "..", "WebExtension", "content", "translate-core.js"));
const core = globalThis.MangalateCore;

test("gộp hai dòng cùng một bong bóng thành một block", () => {
  const blocks = core.groupLines(
    [
      { text: "Xin", box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff" },
      { text: "chào", box: { x: 0.4, y: 0.435, w: 0.2, h: 0.03 }, confidence: 0.8, bg: "#ffffff" },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].text, "Xin chào");
  assert.ok(Math.abs(blocks[0].box.y - 0.4) < 1e-9);
  assert.ok(Math.abs(blocks[0].box.h - 0.065) < 1e-9);
});

test("không gộp hai bong bóng nằm cạnh nhau", () => {
  const blocks = core.groupLines(
    [
      { text: "A", box: { x: 0.1, y: 0.1, w: 0.2, h: 0.05 }, confidence: 0.9, bg: "#ffffff" },
      { text: "B", box: { x: 0.55, y: 0.1, w: 0.2, h: 0.05 }, confidence: 0.9, bg: "#ffffff" },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 2);
});

test("không gộp hai bong bóng xếp dọc sát nhau", () => {
  const blocks = core.groupLines(
    [
      { text: "Trên", box: { x: 0.4, y: 0.4, w: 0.2, h: 0.04 }, confidence: 0.9, bg: "#ffffff" },
      { text: "Dưới", box: { x: 0.4, y: 0.468, w: 0.2, h: 0.04 }, confidence: 0.9, bg: "#ffffff" },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 2);
});

test("không gộp bong bóng thoại với SFX nằm cạnh bên phải", () => {
  const blocks = core.groupLines(
    [
      { text: "LIKE THIS", box: { x: 0.22, y: 0.6, w: 0.33, h: 0.1 }, confidence: 0.9, bg: "#ffffff" },
      { text: "SQUIELCH", box: { x: 0.68, y: 0.55, w: 0.3, h: 0.25 }, confidence: 0.9, bg: "#ffffff" },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 2);
  assert.ok(Math.max(...blocks.map((block) => block.box.w)) < 0.35);
});

test("gộp cột chữ dọc theo thứ tự phải sang trái, không thêm dấu cách", () => {
  const blocks = core.groupLines(
    [
      { text: "あい", box: { x: 0.5, y: 0.2, w: 0.03, h: 0.2 }, confidence: 0.9, bg: "#ffffff" },
      { text: "うえ", box: { x: 0.535, y: 0.2, w: 0.03, h: 0.2 }, confidence: 0.9, bg: "#ffffff" },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].vertical, true);
  assert.equal(blocks[0].text, "うえあい");
});

test("bỏ block phủ gần cả ảnh, giữ block lớn của ảnh bị crop sát", () => {
  const huge = core.groupLines(
    [{ text: "nhiễu", box: { x: 0.02, y: 0.02, w: 0.96, h: 0.96 }, confidence: 0.9, bg: "#ffffff" }],
    1000,
    1000
  );
  assert.equal(huge.length, 0);
  // Bong bóng chiếm ~60% ảnh crop sát vẫn phải giữ (trước đây ngưỡng 0.4 loại oan).
  const cropped = core.groupLines(
    [{ text: "thoại", box: { x: 0.2, y: 0.2, w: 0.6, h: 0.6 }, confidence: 0.9, bg: "#ffffff" }],
    1000,
    1000
  );
  assert.equal(cropped.length, 1);
});

test("mapTileBox chuyển toạ độ tile về toạ độ ảnh", () => {
  const mapped = core.mapTileBox({ x: 0.5, y: 0.5, w: 0.1, h: 0.1 }, { x: 0, y: 0.25, w: 1, h: 0.25 });
  assert.deepEqual(mapped, { x: 0.5, y: 0.375, w: 0.1, h: 0.025 });
});

test("chunk chia lô đúng kích thước", () => {
  assert.deepEqual(core.chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepEqual(core.chunk([], 40), []);
});

test("batchByChars gộp chapter ngắn vào một request, chia khi quá dài", () => {
  const blocks = [
    { id: 1, text: "a".repeat(100) },
    { id: 2, text: "b".repeat(100) },
    { id: 3, text: "c".repeat(100) },
  ];
  assert.equal(core.batchByChars(blocks, 1000, 300).length, 1);
  const split = core.batchByChars(blocks, 150, 300);
  assert.deepEqual(split.map((batch) => batch.length), [1, 1, 1]);
  assert.equal(core.batchByChars(blocks, 1000, 2).length, 2);
  assert.deepEqual(core.batchByChars([], 1000, 300), []);
});

test("luminance phân biệt nền sáng/tối", () => {
  assert.ok(core.luminance("#ffffff") > 0.9);
  assert.ok(core.luminance("#000000") < 0.05);
  assert.ok(core.luminance("không phải màu") > 0.9);
});

test("joinLineText thêm dấu cách cho Latin, bỏ cho CJK", () => {
  assert.equal(core.joinLineText([{ text: "Xin" }, { text: "chào" }], false), "Xin chào");
  assert.equal(core.joinLineText([{ text: "あ" }, { text: "い" }], false), "あい");
  assert.equal(core.joinLineText([{ text: "あ" }, { text: "い" }], true), "あい");
});

test("dedupeLines bỏ dòng lặp giữa hai tile chồng mép, giữ dòng chữ khác", () => {
  const lines = [
    { text: "Xin chào", box: { x: 0.1, y: 0.5, w: 0.2, h: 0.03 }, confidence: 0.6 },
    { text: "Xin chào", box: { x: 0.1, y: 0.505, w: 0.2, h: 0.03 }, confidence: 0.9 },
    { text: "tạm biệt", box: { x: 0.1, y: 0.6, w: 0.2, h: 0.03 }, confidence: 0.8 },
  ];
  const kept = core.dedupeLines(lines);
  assert.equal(kept.length, 2);
  assert.equal(kept[0].confidence, 0.9);
});

test("cache: key tách theo model và URL", () => {
  const a = core.cacheKey("gemini-2.5-flash", "https://x.test/1.jpg");
  const b = core.cacheKey("gemini-2.5-flash", "https://x.test/2.jpg");
  const c = core.cacheKey("gemini-2.5-pro", "https://x.test/1.jpg");
  assert.notEqual(a, b);
  assert.notEqual(a, c);
  assert.equal(core.cacheKey("", "https://x.test/1.jpg"), core.cacheKey("default", "https://x.test/1.jpg"));
});

test("cache: encode/decode block giữ vị trí, nền, bản dịch", () => {
  const blocks = [
    { box: { x: 0.1, y: 0.2, w: 0.3, h: 0.04 }, bg: "#fefefe", translation: "Xin chào" },
    { box: { x: 0.2, y: 0.4, w: 0.1, h: 0.05 }, bg: "#000000", translation: "tạm biệt" },
  ];
  const encoded = core.encodeCacheBlocks(blocks);
  assert.deepEqual(encoded[0].b, [0.1, 0.2, 0.3, 0.04]);
  assert.equal(encoded[0].g, "#fefefe");
  assert.equal(encoded[0].t, "Xin chào");
  const decoded = core.decodeCacheBlocks(encoded);
  assert.equal(decoded.length, 2);
  assert.deepEqual(decoded[1].box, { x: 0.2, y: 0.4, w: 0.1, h: 0.05 });
  assert.equal(decoded[1].translation, "tạm biệt");
});

test("cache: bỏ item hỏng và block không có bản dịch", () => {
  const decoded = core.decodeCacheBlocks([null, { b: [0, 1] }, { b: [0, 0, 0.1, 0.1], t: "" }, { b: [0, 0, 0.1, 0.1], t: "ok" }]);
  assert.equal(decoded.length, 1);
  assert.equal(decoded[0].translation, "ok");
  assert.equal(core.encodeCacheBlocks([{ box: { x: 0, y: 0, w: 1, h: 1 }, translation: "" }]).length, 0);
});

test("groupLines giữ fill trung bình của các dòng trong bong bóng", () => {
  const blocks = core.groupLines(
    [
      { text: "Xin", box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff", fill: 0.9 },
      { text: "chào", box: { x: 0.4, y: 0.435, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff", fill: 0.5 },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  assert.ok(Math.abs(blocks[0].fill - 0.7) < 1e-9);
});

test("selectSpeechBlocks bỏ chữ đè lên tranh (fill thấp)", () => {
  const blocks = [
    { text: "thoại 1", fill: 0.95, enclose: 1, bg: "#ffffff" },
    { text: "SFX", fill: 0.1, enclose: 1, bg: "#ffffff" },
    { text: "thoại 2", fill: 0.8, enclose: 1, bg: "#ffffff" },
    { text: "chú thích", fill: 0.3, enclose: 1, bg: "#ffffff" },
  ];
  const kept = core.selectSpeechBlocks(blocks);
  assert.deepEqual(kept.map((block) => block.text), ["thoại 1", "thoại 2"]);
});

test("selectSpeechBlocks bỏ chữ trôi trên nền không có ô khép kín", () => {
  const blocks = [
    { text: "thoại 1", fill: 0.95, enclose: 1, bg: "#ffffff" },
    { text: "thoại 2", fill: 0.9, enclose: 1, bg: "#f6f0e4" },
    { text: "trang trí trên nền trắng", fill: 0.99, enclose: 0, bg: "#ffffff" },
    { text: "SFX trên tranh", fill: 0.5, enclose: 0, bg: "#ffffff" },
  ];
  const kept = core.selectSpeechBlocks(blocks);
  assert.deepEqual(kept.map((block) => block.text), ["thoại 1", "thoại 2"]);
});

test("groupLines lấy trung bình tỉ lệ enclose của các dòng trong block", () => {
  const blocks = core.groupLines(
    [
      { text: "Xin", box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff", fill: 0.9, enclose: 1 },
      { text: "chào", box: { x: 0.4, y: 0.435, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff", fill: 0.9, enclose: 1 },
      { text: "bạn", box: { x: 0.4, y: 0.47, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff", fill: 0.9, enclose: 0 },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  assert.ok(Math.abs(blocks[0].enclose - 2 / 3) < 1e-9);
});

test("selectSpeechBlocks giữ nguyên khi lọc quá tay", () => {
  const blocks = [
    { text: "thoại", fill: 0.9, enclose: 1, bg: "#ffffff" },
    { text: "a", fill: 0.2, bg: "#ffffff" },
    { text: "b", fill: 0.2, bg: "#ffffff" },
    { text: "c", fill: 0.2, bg: "#ffffff" },
    { text: "d", fill: 0.2, bg: "#ffffff" },
    { text: "e", fill: 0.2, bg: "#ffffff" },
    { text: "f", fill: 0.2, bg: "#ffffff" },
  ];
  assert.equal(core.selectSpeechBlocks(blocks).length, blocks.length);
});

test("selectSpeechBlocks giữ block không có fill (dữ liệu cache cũ)", () => {
  const blocks = [{ text: "không rõ fill", bg: "#ffffff" }];
  assert.deepEqual(core.selectSpeechBlocks(blocks), blocks);
});

test("selectSpeechBlocks bỏ ô hội thoại nền tối hoặc nền màu", () => {
  const blocks = [
    { text: "trắng", fill: 0.95, enclose: 1, bg: "#ffffff" },
    { text: "kem nhạt", fill: 0.95, enclose: 1, bg: "#f7f0e2" },
    { text: "nền xám", fill: 0.95, enclose: 1, bg: "#999999" },
    { text: "nền vàng", fill: 0.95, enclose: 1, bg: "#ffd54f" },
  ];
  const kept = core.selectSpeechBlocks(blocks);
  assert.deepEqual(kept.map((block) => block.text), ["trắng", "kem nhạt"]);
});

test("isBubbleBackground nhận nền trắng/kem/đen, loại nền màu", () => {
  assert.equal(core.isBubbleBackground("#ffffff"), true);
  assert.equal(core.isBubbleBackground("#f4f0e6"), true);
  assert.equal(core.isBubbleBackground("#111111"), true);
  assert.equal(core.isBubbleBackground("#999999"), false);
  assert.equal(core.isBubbleBackground("#9fd0ff"), false);
  assert.equal(core.isBubbleBackground(""), false);
});

test("không gộp SFX cỡ chữ lớn nằm sát dòng thoại", () => {
  const blocks = core.groupLines(
    [
      { text: "LỜI THOẠI", box: { x: 0.3, y: 0.4, w: 0.4, h: 0.04 }, confidence: 0.9, bg: "#ffffff", fill: 0.9, enclose: 1 },
      { text: "THRUST", box: { x: 0.3, y: 0.445, w: 0.4, h: 0.1 }, confidence: 0.9, bg: "#ffffff", fill: 0.9, enclose: 1 },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 2);
});

test("selectSpeechBlocks bỏ dòng credit/quảng cáo của trang đọc truyện", () => {
  const blocks = [
    { text: "MANGA18FX.COM", fill: 1, enclose: 1, bg: "#ffffff" },
    { text: "Lời thoại thật", fill: 0.9, enclose: 1, bg: "#ffffff" },
    { text: "Read Manga Online in English Free", fill: 1, enclose: 1, bg: "#ffffff" },
  ];
  assert.deepEqual(core.selectSpeechBlocks(blocks).map((block) => block.text), ["Lời thoại thật"]);
});

test("selectSpeechBlocks bỏ SFX đặt trên khoảng trắng của tranh (fill thấp)", () => {
  const blocks = [
    { text: "Lời thoại thật", fill: 0.83, enclose: 0.95, bg: "#ffffff" },
    { text: "CLENCH CLENCH", fill: 0.67, enclose: 0.78, bg: "#ffffff" },
    { text: "SMOOCH", fill: 0.52, enclose: 0.5, bg: "#ffffff" },
  ];
  assert.deepEqual(core.selectSpeechBlocks(blocks).map((block) => block.text), ["Lời thoại thật"]);
});

test("groupLines dùng ô bong bóng (bubble) làm khung dán đè", () => {
  const blocks = core.groupLines(
    [
      {
        text: "Xin chào",
        box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 },
        confidence: 0.9,
        bg: "#ffffff",
        fill: 0.9,
        enclose: 1,
        bubble: { x: 0.33, y: 0.35, w: 0.34, h: 0.13 },
      },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  assert.ok(Math.abs(blocks[0].box.x - 0.33) < 1e-9);
  assert.ok(Math.abs(blocks[0].box.w - 0.34) < 1e-9);
  assert.ok(Math.abs(blocks[0].box.h - 0.13) < 1e-9);
});

test("selectSpeechBlocks giữ bong bóng nền đen chữ trắng", () => {
  const blocks = [
    { text: "AIZAS!", fill: 0.97, enclose: 0.9, bg: "#0d0d0d" },
    { text: "Lời thoại nền trắng", fill: 0.9, enclose: 0.9, bg: "#ffffff" },
  ];
  assert.equal(core.selectSpeechBlocks(blocks).length, 2);
});

test("cache: encode/decode giữ đường bao bong bóng, vị trí chữ gốc, số dòng", () => {
  const blocks = [
    {
      box: { x: 0.1, y: 0.2, w: 0.3, h: 0.1 },
      bg: "#ffffff",
      translation: "Xin chào",
      poly: [0.1, 0.2, 0.1, 0.3, 0.4, 0.3, 0.4, 0.2],
      textBox: { x: 0.15, y: 0.22, w: 0.2, h: 0.06 },
      lines: 3,
    },
  ];
  const decoded = core.decodeCacheBlocks(core.encodeCacheBlocks(blocks));
  assert.equal(decoded.length, 1);
  assert.deepEqual(decoded[0].poly, [0.1, 0.2, 0.1, 0.3, 0.4, 0.3, 0.4, 0.2]);
  assert.deepEqual(decoded[0].textBox, { x: 0.15, y: 0.22, w: 0.2, h: 0.06 });
  assert.equal(decoded[0].lines, 3);
});

test("groupLines trả đa giác bong bóng ở toạ độ chuẩn hoá 0..1", () => {
  const blocks = core.groupLines(
    [
      {
        text: "Xin chào",
        box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 },
        confidence: 0.9,
        bg: "#ffffff",
        fill: 0.9,
        enclose: 1,
        bubble: { x: 0.35, y: 0.35, w: 0.3, h: 0.13 },
        poly: [0.35, 0.35, 0.35, 0.48, 0.65, 0.48, 0.65, 0.35],
      },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  const poly = blocks[0].poly;
  assert.ok(Array.isArray(poly) && poly.length >= 8);
  for (const value of poly) assert.ok(value >= 0 && value <= 1);
  const xs = poly.filter((_, index) => index % 2 === 0);
  const ys = poly.filter((_, index) => index % 2 === 1);
  assert.ok(Math.min(...xs) > 0.34 && Math.min(...xs) < 0.36);
  assert.ok(Math.max(...xs) > 0.64 && Math.max(...xs) < 0.66);
  assert.ok(Math.min(...ys) > 0.34 && Math.min(...ys) < 0.36);
  assert.ok(Math.max(...ys) > 0.47 && Math.max(...ys) < 0.49);
});

test("bubblePolygon ghép dải của nhiều dòng thành một hình liền", () => {
  const blocks = core.groupLines(
    [
      {
        text: "Dòng một",
        box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 },
        confidence: 0.9,
        bg: "#ffffff",
        fill: 0.9,
        enclose: 1,
        bubble: { x: 0.35, y: 0.35, w: 0.3, h: 0.13 },
        // Dải nền quanh dòng 1 (chỉ cao ~0.04).
        poly: [0.35, 0.35, 0.35, 0.39, 0.65, 0.39, 0.65, 0.35],
      },
      {
        text: "Dòng hai",
        box: { x: 0.4, y: 0.44, w: 0.2, h: 0.03 },
        confidence: 0.9,
        bg: "#ffffff",
        fill: 0.9,
        enclose: 1,
        // Dải nền quanh dòng 2 — rời hẳn khỏi dải trên.
        poly: [0.35, 0.44, 0.35, 0.48, 0.65, 0.48, 0.65, 0.44],
      },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  const ys = blocks[0].poly.filter((_, index) => index % 2 === 1);
  assert.ok(Math.min(...ys) > 0.34 && Math.min(...ys) < 0.36);
  assert.ok(Math.max(...ys) > 0.47 && Math.max(...ys) < 0.49);
});

function intersects(a, b) {
  return Math.min(a.x + a.w, b.x + b.w) > Math.max(a.x, b.x) && Math.min(a.y + a.h, b.y + b.h) > Math.max(a.y, b.y);
}

function contains(outer, inner) {
  const eps = 1e-9;
  return inner.x >= outer.x - eps && inner.y >= outer.y - eps
    && inner.x + inner.w <= outer.x + outer.w + eps && inner.y + inner.h <= outer.y + outer.h + eps;
}

test("groupLines giữ textBox = hợp các hộp chữ OCR, tách khỏi box nền", () => {
  const blocks = core.groupLines(
    [
      { text: "Một", box: { x: 0.4, y: 0.4, w: 0.2, h: 0.03 }, confidence: 0.9, bg: "#ffffff", bubble: { x: 0.3, y: 0.3, w: 0.4, h: 0.2 } },
      { text: "Hai", box: { x: 0.42, y: 0.435, w: 0.16, h: 0.03 }, confidence: 0.9, bg: "#ffffff" },
    ],
    1000,
    1000
  );
  assert.equal(blocks.length, 1);
  const text = blocks[0].textBox;
  assert.ok(Math.abs(text.x - 0.4) < 1e-9 && Math.abs(text.w - 0.2) < 1e-9);
  assert.ok(Math.abs(text.y - 0.4) < 1e-9 && Math.abs(text.h - 0.065) < 1e-9);
  assert.ok(blocks[0].box.w > text.w);
});

test("layoutTextAreas: hai bong bóng dính nhau chung box nền → vùng chữ không chồng nhau", () => {
  // Ca thật: "MY LOYAL RETAINERS..." (trái) và "I CANNOT ALLOW..." (phải trên) loang chung một vùng.
  const shared = { x: 0.6, y: 0.3, w: 0.2, h: 0.12 };
  const blocks = [
    { imageIndex: 0, box: { ...shared }, textBox: { x: 0.61, y: 0.34, w: 0.1, h: 0.05 } },
    { imageIndex: 0, box: { ...shared }, textBox: { x: 0.72, y: 0.31, w: 0.07, h: 0.02 } },
  ];
  core.layoutTextAreas(blocks);
  assert.equal(intersects(blocks[0].textArea, blocks[1].textArea), false);
  for (const block of blocks) assert.ok(contains(block.textArea, block.textBox));
});

test("layoutTextAreas: một bong bóng → vùng chữ neo tâm chữ gốc, nới dọc nhiều, ngang ít", () => {
  const blocks = [{ imageIndex: 0, box: { x: 0.3, y: 0.3, w: 0.4, h: 0.4 }, textBox: { x: 0.45, y: 0.45, w: 0.1, h: 0.1 } }];
  core.layoutTextAreas(blocks);
  const area = blocks[0].textArea;
  assert.ok(Math.abs(area.x + area.w / 2 - 0.5) < 1e-9);
  assert.ok(Math.abs(area.y + area.h / 2 - 0.5) < 1e-9);
  assert.ok(Math.abs(area.w - 0.13) < 1e-9);
  // Nới dọc tối đa 2 lần chiều cao chữ gốc, rồi lấy 85% khoảng cách tới mép bong bóng.
  assert.ok(Math.abs(area.h - 0.17) < 1e-9);
});

test("fitTextAreaToPolygon cắt vùng chữ theo cung hẹp nhất của bong bóng", () => {
  // Bong bóng thoi: hẹp dần về hai đầu; vùng chữ hình chữ nhật rộng bằng phần giữa sẽ tràn ra.
  const shape = [0.4, 0.2, 0.4, 0.5, 0.4, 0.8, 0.6, 0.8, 0.6, 0.65, 0.6, 0.5, 0.6, 0.2];
  const blocks = [{
    imageIndex: 0,
    box: { x: 0.4, y: 0.2, w: 0.2, h: 0.6 },
    textBox: { x: 0.44, y: 0.44, w: 0.12, h: 0.12 },
    poly: shape,
  }];
  core.layoutTextAreas(blocks);
  const area = blocks[0].textArea;
  assert.ok(area.x > 0.4 + 1e-6);
  assert.ok(area.x + area.w < 0.6 - 1e-6);
  assert.ok(Math.abs(area.x + area.w / 2 - 0.5) < 1e-9);
});

test("layoutTextAreas: không chia vùng giữa block của hai ảnh khác nhau", () => {
  const box = { x: 0.3, y: 0.3, w: 0.4, h: 0.4 };
  const blocks = [
    { imageIndex: 0, box: { ...box }, textBox: { x: 0.35, y: 0.45, w: 0.1, h: 0.1 } },
    { imageIndex: 1, box: { ...box }, textBox: { x: 0.46, y: 0.45, w: 0.1, h: 0.1 } },
  ];
  core.layoutTextAreas(blocks);
  assert.ok(Math.abs(blocks[0].textArea.w - 0.13) < 1e-9);
  assert.ok(Math.abs(blocks[1].textArea.w - 0.13) < 1e-9);
  // Cùng ảnh thì phải bị chia tại giữa khe (0.455) → hẹp lại.
  const same = blocks.map((block) => ({ ...block, imageIndex: 0 }));
  core.layoutTextAreas(same);
  assert.ok(Math.abs(same[0].textArea.x + same[0].textArea.w - 0.455) < 1e-9);
});

test("groupLines mở rộng đường bao cho phủ kín hộp chữ thay vì bỏ hẳn", () => {
  const line = (poly) => ({
    text: "một dòng thoại",
    box: { x: 0.4, y: 0.4, w: 0.2, h: 0.05 },
    confidence: 0.9,
    bg: "#ffffff",
    fill: 0.9,
    enclose: 1,
    poly,
  });
  // Bao hẹp hơn vùng chữ ở phía phải → phải nới ra, không được để lộ chữ.
  const narrow = core.groupLines([line([0.4, 0.39, 0.4, 0.46, 0.55, 0.46, 0.55, 0.39])], 1000, 1000);
  const poly = narrow[0].poly;
  assert.ok(Array.isArray(poly) && poly.length >= 6);
  assert.equal(core.polygonCoversBox(poly, 0.4, 0.4, 0.2, 0.05), true);
});
test("fitPolyToText nới đa giác bằng bao lồi để phủ kín chữ", () => {
  // Bao hẹp hơn chữ: giữ nguyên thì nền hụt, phải nới ra và vẫn giữ dạng đa giác.
  const narrow = [0.42, 0.38, 0.42, 0.48, 0.58, 0.48, 0.58, 0.38];
  assert.equal(core.polygonCoversBox(narrow, 0.4, 0.4, 0.2, 0.05), false);
  const fitted = core.fitPolyToText(narrow, 0.4, 0.4, 0.2, 0.05);
  assert.ok(Array.isArray(fitted) && fitted.length >= 6);
  assert.equal(core.polygonCoversBox(fitted, 0.4, 0.4, 0.2, 0.05), true);
  // Bao đã phủ đủ thì giữ nguyên (không phình thêm).
  const wide = [0.35, 0.35, 0.35, 0.65, 0.65, 0.65, 0.65, 0.35];
  assert.deepEqual(core.fitPolyToText(wide, 0.4, 0.4, 0.2, 0.05), wide);
});