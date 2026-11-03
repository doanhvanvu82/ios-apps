#!/usr/bin/env node
// Bổ sung `textArea` / `vertical` / `lines` vào file JSON do render_test.py sinh ra.
//
// Harness Python không tự tính được layout (đó là logic của translate-core.js), nên nếu dán
// chữ theo `box` thì ảnh .after.png không phản ánh cái WebExtension thực sự vẽ — cột chữ dọc
// bị bóp thành dải hẹp và trông như lỗi UI. Script này chạy đúng core để có cùng vùng đặt chữ.
//
//     node tools/apply_layout.js <thư mục review>

const fs = require("fs");
const path = require("path");

require(path.join(__dirname, "..", "WebExtension", "content", "translate-core.js"));
const core = globalThis.MangalateCore;

function collect(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...collect(full));
    else if (entry.name.endsWith(".json")) files.push(full);
  }
  return files;
}

function applyLayout(file) {
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  const originals = data.blocks || [];
  // core dùng box dạng object; JSON lưu box dạng mảng [x, y, w, h] nên giữ bản gốc để ghi lại.
  const work = originals.map((block) => {
    const [x, y, w, h] = block.box;
    const text = String(block.text || "");
    const t = Array.isArray(block.textBox) ? block.textBox : null;
    // Cùng quy tắc với isVerticalBlock: cờ do groupLines đặt, không có thì suy từ hình dạng.
    return {
      kind: block.kind,
      text,
      box: { x, y, w, h },
      textBox: t ? { x: t[0], y: t[1], w: t[2], h: t[3] } : null,
      poly: Array.isArray(block.poly) && block.poly.length >= 6 ? block.poly.slice() : null,
      vertical: typeof block.vertical === "boolean" ? block.vertical : h > w * 1.4,
      lines: Math.max(1, text.split("\n").length),
    };
  });
  core.layoutTextAreas(work);
  data.blocks = originals.map((block, index) => {
    // Bong bóng thoại: box (cả bong bóng) lớn hơn hẳn hộp chữ. Harness không có đường bao
    // nên vẽ elip theo box; nền phải phủ cả bong bóng, không kẹp về hộp chữ.
    const textBox = work[index].textBox;
    // Bong bóng bị cắt bởi mép trang: elip nội tiếp không phủ hết vùng chữ sát mép, chữ gốc
    // còn lộ ra. Dùng hình chữ nhật cho các block chạm mép.
    const touchesEdge = block.box[0] <= 0.005 || block.box[1] <= 0.005
      || block.box[0] + block.box[2] >= 0.995 || block.box[1] + block.box[3] >= 0.995;
    const hasPoly = Array.isArray(block.poly) && block.poly.length >= 6;
    const bubble = !hasPoly && block.kind === "dialogue" && block.bubble !== false && textBox && !touchesEdge
      && block.box[2] * block.box[3] > textBox.w * textBox.h * 1.2;
    let area = work[index].textArea;
    if (Array.isArray(block.maskRows) && block.maskRows.length && !hasPoly) {
      // Block tự dựng khung (model không trả bubble hợp lệ): mask có thể hụt ở mép nên đừng
      // lấy vùng chữ đã bị co theo mask — dùng thẳng hộp chữ OCR.
      const t = textBox || block.textBox;
      if (t) area = { x: t.x, y: t.y, w: t.w, h: t.h };
    }
    if (bubble) {
      // Harness vẽ nền bằng elip nội tiếp `box`; vùng chữ phải nằm trong hình elip đó, nếu
      // không chữ sẽ tràn ra tranh ở bốn góc. Elip nội tiếp hình chữ nhật 72% cùng tâm là
      // ước lượng an toàn.
      const cx = block.box[0] + block.box[2] / 2;
      const cy = block.box[1] + block.box[3] / 2;
      const halfW = (block.box[2] * 0.72) / 2;
      const halfH = (block.box[3] * 0.72) / 2;
      const x0 = Math.max(area.x, cx - halfW);
      const x1 = Math.min(area.x + area.w, cx + halfW);
      const y0 = Math.max(area.y, cy - halfH);
      const y1 = Math.min(area.y + area.h, cy + halfH);
      if (x1 - x0 > 0.02 && y1 - y0 > 0.015) area = { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }
    // Mask harness dựng từ ảnh có thể hụt so với bong bóng thật; không để nó bóp vùng chữ
    // nhỏ hơn hộp chữ OCR (cỡ chữ sẽ tụt xuống vài px).
    if (textBox) {
      if (area.w < textBox.w) {
        area.x = textBox.x;
        area.w = textBox.w;
      }
      if (area.h < textBox.h) {
        // Dùng đúng vị trí hộp chữ: canh tâm theo vùng đã fit có thể đẩy vùng chữ lên
        // ngoài bong bóng (chữ tràn lên panel phía trên).
        area.y = textBox.y;
        area.h = textBox.h;
      }
    }
    return {
      ...block,
      vertical: work[index].vertical,
      lines: work[index].lines,
      ellipse: Boolean(bubble),
      textArea: [area.x, area.y, area.w, area.h],
      // Khung nền phải do core quyết định, nếu không ảnh review lệch với cái app vẽ.
      backdrop: bubble ? block.box.slice() : (() => {
        const frame = core.backdropFrame(work[index]);
        return frame ? [frame.x, frame.y, frame.w, frame.h] : null;
      })(),
    };
  });
  fs.writeFileSync(file, JSON.stringify(data, null, 1), "utf8");
  return originals.length;
}

const root = process.argv[2];
if (!root) {
  console.error("dùng: node tools/apply_layout.js <thư mục review>");
  process.exit(1);
}
let pages = 0;
let blocks = 0;
for (const file of collect(root)) {
  blocks += applyLayout(file);
  pages += 1;
}
console.log(`${pages} trang, ${blocks} block đã có textArea`);
