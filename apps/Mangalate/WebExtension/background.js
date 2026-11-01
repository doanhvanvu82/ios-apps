// Background (non-persistent): proxy gọi appex native (OCR + Gemini) và cung cấp cài đặt cho content/popup.
"use strict";

const NATIVE_TIMEOUT_MS = {
  ocr: 45000,
  ocrUrl: 90000,
  translate: 120000,
  analyze: 120000,
  listModels: 30000,
  log: 5000,
};
const NATIVE_DEFAULT_TIMEOUT_MS = 8000;

// Sau khi cập nhật app, Safari còn giữ đường dẫn extension cũ: lần gọi đầu thường hỏng khi khởi chạy phần native.
const NATIVE_LAUNCH_FAILURE = /RBSLaunchRequest|Launch failed|launchd|Invalid call to runtime\.sendNativeMessage/i;
const NATIVE_RETRY_DELAY_MS = 1000;

async function native(payload) {
  try {
    return await nativeOnce(payload);
  } catch (error) {
    if (!NATIVE_LAUNCH_FAILURE.test(error.message)) throw error;
    await new Promise((resolve) => setTimeout(resolve, NATIVE_RETRY_DELAY_MS));
    return nativeOnce(payload);
  }
}

async function nativeOnce(payload) {
  const timeoutMs = NATIVE_TIMEOUT_MS[payload.action] || NATIVE_DEFAULT_TIMEOUT_MS;
  let timer;
  let reply;
  try {
    // Không có hạn chờ thì phần native treo sẽ khoá nút trong popup/trên trang mãi mãi.
    reply = await Promise.race([
      browser.runtime.sendNativeMessage("application.id", payload),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`không phản hồi sau ${timeoutMs / 1000} giây`)), timeoutMs);
      }),
    ]);
  } catch (error) {
    throw new Error(`Không gọi được phần native của app (${payload.action}): ${error.message || error}`);
  } finally {
    clearTimeout(timer);
  }
  if (!reply || reply.ok !== true) throw new Error((reply && reply.error) || "Phần native không phản hồi.");
  return reply;
}

async function settings() {
  const reply = await native({ action: "getSettings" });
  const value = { hasKey: reply.hasKey === true, model: String(reply.model || "") };
  // Content script đọc model này để kiểm tra cache khi vào chapter mà không cần đánh thức appex.
  browser.storage.local.set({ mangalateModel: value.model }).catch(() => {});
  return value;
}

async function handle(message) {
  switch (message.type) {
    case "native":
      return native(message.payload || {});

    case "getSettings":
      return settings();

    case "saveSettings":
      await native({ action: "saveSettings", apiKey: message.apiKey, model: message.model });
      return settings();

    case "listModels": {
      const reply = await native({ action: "listModels" });
      return reply.models || [];
    }

    case "log":
      // Log không được chặn hay làm hỏng thao tác chính.
      native({ action: "log", text: String(message.text || "").slice(0, 2000) }).catch(() => {});
      return { logged: true };

    default:
      throw new Error(`Lệnh không hợp lệ: ${message.type}`);
  }
}

browser.runtime.onMessage.addListener((message) => {
  if (!message || typeof message.type !== "string") return undefined;
  return handle(message).then(
    (result) => ({ ok: true, result }),
    (error) => ({ ok: false, error: error.message || String(error) })
  );
});
