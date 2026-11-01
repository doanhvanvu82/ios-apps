const test = require("node:test");
const assert = require("node:assert/strict");
const { readdirSync, readFileSync } = require("node:fs");
const { join } = require("node:path");

// Safari nạp background/content script không kèm charset và đọc thành Latin-1 → chữ Việt vỡ ("KhÃ´ng").
// BOM UTF-8 ở đầu file là cách khai báo bảng mã mà trình duyệt luôn ưu tiên.
test("mọi file JS của extension bắt đầu bằng BOM UTF-8", () => {
  const root = join(__dirname, "..", "WebExtension");
  const files = readdirSync(root, { recursive: true }).filter((f) => f.endsWith(".js"));
  assert.ok(files.length > 0);
  for (const file of files) {
    assert.deepEqual([...readFileSync(join(root, file)).subarray(0, 3)], [0xef, 0xbb, 0xbf], file);
  }
});
