// Chống theo dõi phía trang (isolated world), chạy khi bật "Chống theo dõi":
// xoá tham số theo dõi khỏi thanh địa chỉ và link, gỡ link bọc chuyển hướng, bỏ thuộc tính ping,
// thay widget mạng xã hội (đã bị ruleset tracking chặn) bằng ô "Chạm để tải".
(() => {
  "use strict";

  // background nạp lại script (askPage) khi trang không trả lời → không chạy lần hai.
  if (globalThis.AdsBlockerPrivacyLoaded) return;
  globalThis.AdsBlockerPrivacyLoaded = true;

  const { cleanUrl, unwrapLink, siteKey, resolveSite } = globalThis.AdsBlockerRules;
  const OWN_ATTR = "data-adsblocker";
  const IS_TOP = window === window.top;

  // Widget nhúng theo nhà cung cấp: iframe (src) hoặc phần tử SDK tự dựng thành widget.
  const WIDGETS = [
    { provider: "facebook", name: "Facebook", frame: /facebook\.com\/plugins\//, selector: ".fb-post, .fb-video, .fb-page, .fb-like, .fb-comments, .fb-share-button" },
    { provider: "twitter", name: "X (Twitter)", frame: /platform\.twitter\.com\//, selector: "blockquote.twitter-tweet, blockquote.twitter-video, a.twitter-timeline" },
    { provider: "instagram", name: "Instagram", frame: /instagram\.com\/(p|reel)\/[^/]+\/embed/, selector: "blockquote.instagram-media" },
    { provider: "tiktok", name: "TikTok", frame: /tiktok\.com\/embed/, selector: "blockquote.tiktok-embed" },
  ];

  let trackingOn = false;
  let allowedWidgets = [];

  async function loadConfig() {
    const { features, aliases } = await browser.storage.local.get(["features", "aliases"]);
    trackingOn = !features || features.tracking !== false;
    const key = "site:" + resolveSite(siteKey(location.hostname), aliases);
    allowedWidgets = ((await browser.storage.local.get(key))[key] || {}).allowWidgets || [];
    if (!trackingOn) return;
    cleanAddressBar();
    scanWidgets();
  }

  browser.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes.features || changes.aliases || Object.keys(changes).some((k) => k.startsWith("site:"))) loadConfig();
  });

  // ---------------------------------------------------------------- tham số theo dõi & link bọc

  function cleanAddressBar() {
    if (!IS_TOP) return;
    const clean = cleanUrl(location.href);
    if (clean !== location.href) history.replaceState(history.state, "", clean);
  }

  /** Làm sạch link ngay trước khi trình duyệt dùng nó (trang có thể đổi href lúc mousedown, nên xử lý cả click). */
  function cleanAnchor(event) {
    if (!trackingOn) return;
    const target = event.composedPath()[0];
    const anchor = target instanceof Element ? target.closest("a[href]") : null;
    if (!anchor) return;
    anchor.removeAttribute("ping");
    const clean = unwrapLink(cleanUrl(anchor.href));
    if (clean !== anchor.href) anchor.href = clean;
  }
  for (const type of ["pointerdown", "mousedown", "touchstart", "click", "auxclick"]) {
    window.addEventListener(type, cleanAnchor, { capture: true, passive: true });
  }

  // Trang SPA đổi URL bằng history.pushState sau khi tải.
  window.addEventListener("popstate", () => trackingOn && cleanAddressBar());

  // ---------------------------------------------------------------- widget mạng xã hội

  function widgetOf(el) {
    if (el.tagName === "IFRAME") return WIDGETS.find((w) => w.frame.test(el.src || ""));
    return WIDGETS.find((w) => el.matches(w.selector));
  }

  function placeholder(widget, el) {
    const box = document.createElement("div");
    box.setAttribute(OWN_ATTR, "widget");
    const rect = el.getBoundingClientRect();
    const shadow = box.attachShadow({ mode: "open" });
    shadow.innerHTML = `
      <style>
        :host { all: initial; display: block; margin: 8px 0; }
        div { box-sizing: border-box; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
          min-height: ${Math.max(90, Math.min(rect.height || 0, 400))}px; padding: 12px; border-radius: 12px;
          border: 1px dashed #999; background: rgba(127,127,127,.08); font: 14px -apple-system, system-ui, sans-serif;
          color: #555; text-align: center; }
        button { font: 600 14px -apple-system, system-ui, sans-serif; border: 0; border-radius: 8px; padding: 8px 14px;
          background: #15a37a; color: #fff; }
        @media (prefers-color-scheme: dark) { div { color: #bbb; } }
      </style>
      <div><span></span><button></button></div>`;
    shadow.querySelector("span").textContent = `🔒 Nội dung ${widget.name} bị chặn để chống theo dõi.`;
    const button = shadow.querySelector("button");
    button.textContent = `Chạm để tải (${widget.name} sẽ theo dõi bạn trên trang này)`;
    button.addEventListener("click", async (event) => {
      event.stopPropagation();
      button.disabled = true;
      button.textContent = "Đang cho phép…";
      try {
        const reply = await browser.runtime.sendMessage({ type: "allowWidget", url: location.href, provider: widget.provider });
        if (!reply || !reply.ok) throw new Error(reply ? reply.error : "Extension không phản hồi");
        // SDK của widget chỉ chạy khi trang tải lại sau khi rule cho phép có hiệu lực.
        location.reload();
      } catch (error) {
        button.disabled = false;
        button.textContent = `Lỗi: ${error.message} — chạm để thử lại`;
      }
    });
    return box;
  }

  function scanWidgets(root = document) {
    if (!trackingOn || !root.querySelectorAll) return;
    const selector = ["iframe", ...WIDGETS.map((w) => w.selector)].join(", ");
    for (const el of root.querySelectorAll(selector)) {
      if (el.dataset.adsblockerWidget) continue;
      const widget = widgetOf(el);
      if (!widget || allowedWidgets.includes(widget.provider)) continue;
      el.dataset.adsblockerWidget = widget.provider;
      const box = placeholder(widget, el);
      // iframe bị chặn chỉ còn khung trống → thay hẳn; bài nhúng dạng blockquote vẫn đọc được chữ → chèn ô phía trên.
      if (el.tagName === "IFRAME") el.replaceWith(box);
      else el.before(box);
    }
  }

  new MutationObserver((records) => {
    if (!trackingOn) return;
    for (const record of records) {
      record.addedNodes.forEach((node) => {
        if (!(node instanceof Element) || node.hasAttribute(OWN_ATTR)) return;
        if (node.tagName === "IFRAME" || node.matches(WIDGETS.map((w) => w.selector).join(", "))) scanWidgets(node.parentElement || document);
        else scanWidgets(node);
      });
    }
  }).observe(document, { childList: true, subtree: true });

  document.addEventListener("DOMContentLoaded", () => scanWidgets());
  loadConfig();
})();
