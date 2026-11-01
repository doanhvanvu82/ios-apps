// Chạy trong JS của chính trang (world MAIN, document_start) để chặn popup/tab quảng cáo:
// bọc window.open, chặn click giả lên <a target=_blank>. Liên lạc với content.js qua CustomEvent trên document.
(() => {
  "use strict";

  // Safari bỏ qua "world": "MAIN" thì script chạy ở isolated world (có browser.runtime):
  // tự chèn lại vào trang qua web_accessible_resources.
  if (typeof browser !== "undefined" && browser.runtime && browser.runtime.id) {
    const script = document.createElement("script");
    script.src = browser.runtime.getURL("content/main_world.js");
    script.onload = () => script.remove();
    (document.head || document.documentElement).appendChild(script);
    return;
  }

  const GUARD = Symbol.for("adsblocker.guard");
  if (window[GUARD]) return;
  Object.defineProperty(window, GUARD, { value: true });

  const GESTURE_WINDOW_MS = 1500;
  const INTERACTIVE = "a[href],button,input,select,textarea,label,summary,[role=button],[role=link],[role=menuitem],[role=tab]";

  let popupDomains = [];
  // Cờ tính năng từ content.js (mặc định bật cho tới khi nhận config).
  let adsOn = true;
  let trackingOn = true;
  let youtubeOn = true;
  let lastGesture = null;

  document.addEventListener("adsblocker:config", (event) => {
    try {
      const config = JSON.parse(event.detail);
      popupDomains = Array.isArray(config.popupDomains) ? config.popupDomains : [];
      // Ngoại lệ "cho trang này mở tab mới" (từ chẩn đoán) = tắt chặn popup trên trang.
      adsOn = config.ads !== false && !config.allowPopups;
      trackingOn = config.tracking !== false;
      youtubeOn = config.youtube !== false;
    } catch {
      // detail không phải JSON → event giả từ trang, bỏ qua.
    }
  });

  const report = (kind, url, reason) => {
    document.dispatchEvent(new CustomEvent("adsblocker:blocked", {
      detail: JSON.stringify({ kind, url: String(url || "").slice(0, 500), reason }),
    }));
  };

  const elementOf = (node) => (node && node.nodeType === Node.TEXT_NODE ? node.parentElement : node);

  for (const type of ["pointerdown", "mousedown", "touchstart", "click", "keydown"]) {
    window.addEventListener(type, (event) => {
      if (!event.isTrusted) return;
      const target = elementOf(event.composedPath()[0]);
      lastGesture = { time: performance.now(), target: target instanceof Element ? target : null };
    }, true);
  }

  const hostOf = (url) => {
    try {
      return new URL(url, location.href).hostname.toLowerCase();
    } catch {
      return "";
    }
  };
  // Gần đúng eTLD+1 — đủ để so "cùng site" (rules/validate.js có bản đầy đủ nhưng không chạy được ở world này).
  const siteOf = (host) => (/^[\d.]+$|:/.test(host) ? host : host.split(".").slice(-2).join("."));
  const sameSite = (a, b) => !!a && !!b && siteOf(a) === siteOf(b);
  const matchesDomain = (host, domain) => host === domain || host.endsWith("." + domain);

  /** Lý do chặn việc mở `url` ở tab/cửa sổ mới, hoặc null nếu cho phép. */
  const popupVerdict = (url) => {
    if (!adsOn) return null;
    const host = hostOf(url);
    if (host && popupDomains.some((d) => matchesDomain(host, d))) return "domain đã chặn";

    if (!lastGesture || performance.now() - lastGesture.time > GESTURE_WINDOW_MS) return "không do người dùng bấm";
    const control = lastGesture.target && lastGesture.target.closest(INTERACTIVE);
    // Click vào chữ/ảnh/nền trang mà lại mở tab mới = script gắn vào cả trang (click-hijack).
    if (!control) return "bấm vào nội dung thường";
    if (control.matches("a[href]")) {
      const linkHost = hostOf(control.href);
      if (host && !sameSite(host, linkHost) && !sameSite(host, location.hostname)) return "khác link được bấm";
    }
    return null;
  };

  // Beacon (navigator.sendBeacon) tới bên thứ ba gần như chỉ để gửi thống kê/theo dõi khi rời trang.
  if (navigator.sendBeacon) {
    const nativeBeacon = navigator.sendBeacon;
    navigator.sendBeacon = function sendBeacon(url) {
      const host = hostOf(url);
      // Báo "đã gửi" để script của trang không thử lại bằng cách khác.
      if (trackingOn && host && !sameSite(host, location.hostname)) return true;
      return nativeBeacon.apply(this, arguments);
    };
  }

  const nativeOpen = window.open;
  const guardedOpen = function open(url) {
    const reason = popupVerdict(url || "about:blank");
    if (reason) {
      report("popup", url, reason);
      return null;
    }
    return nativeOpen.apply(this, arguments);
  };
  Object.defineProperty(window, "open", { value: guardedOpen, writable: true, configurable: true });

  const opensNewTab = (anchor) => {
    const target = (anchor.getAttribute("target") || "").toLowerCase();
    return target !== "" && target !== "_self" && target !== "_top" && target !== "_parent";
  };

  // Click giả (a.click() / dispatchEvent) lên link mở tab mới.
  const blockSyntheticClick = (anchor) => {
    if (!(anchor instanceof HTMLAnchorElement) || !anchor.href || !opensNewTab(anchor)) return false;
    if (lastGesture && lastGesture.target && anchor.contains(lastGesture.target)) return false;
    const reason = popupVerdict(anchor.href);
    if (reason) report("popup", anchor.href, reason);
    return !!reason;
  };

  const nativeClick = HTMLElement.prototype.click;
  HTMLElement.prototype.click = function click() {
    if (blockSyntheticClick(this)) return;
    return nativeClick.apply(this, arguments);
  };

  const nativeDispatch = EventTarget.prototype.dispatchEvent;
  EventTarget.prototype.dispatchEvent = function dispatchEvent(event) {
    if (event && event.type === "click" && this instanceof Element) {
      const anchor = this.closest("a[href]");
      if (anchor && blockSyntheticClick(anchor)) return false;
    }
    return nativeDispatch.apply(this, arguments);
  };

  // YouTube: video quảng cáo tải từ cùng googlevideo.com với video thật → không chặn ở tầng mạng được.
  // Bỏ các trường quảng cáo khỏi dữ liệu player trước khi player đọc: player không biết có quảng cáo để chiếu.
  if (/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname)) {
    const AD_KEYS = ["adPlacements", "adSlots", "playerAds", "adBreakHeartbeatParams"];
    // Player response nằm ở gốc (youtubei/v1/player, ytInitialPlayerResponse) hoặc trong `playerResponse`
    // của phản hồi điều hướng (có thể là mảng các phần).
    const prune = (data, depth = 0) => {
      if (!youtubeOn || !data || typeof data !== "object" || depth > 2) return data;
      if (Array.isArray(data)) {
        data.forEach((item) => prune(item, depth + 1));
        return data;
      }
      for (const key of AD_KEYS) delete data[key];
      if (data.playerResponse) prune(data.playerResponse, depth + 1);
      return data;
    };

    const nativeParse = JSON.parse;
    JSON.parse = function parse() {
      return prune(nativeParse.apply(this, arguments));
    };
    const nativeJson = Response.prototype.json;
    Response.prototype.json = function json() {
      return nativeJson.apply(this, arguments).then((data) => prune(data));
    };

    // Quảng cáo trong feed/tìm kiếm/trang xem (ytd-* bản desktop, ytm-* bản mobile).
    const YOUTUBE_HIDE = [
      "ytd-ad-slot-renderer", "ytd-rich-item-renderer:has(ytd-ad-slot-renderer)", "ytd-in-feed-ad-layout-renderer",
      "ytd-promoted-sparkles-web-renderer", "ytd-promoted-video-renderer", "ytd-banner-promo-renderer",
      "ytd-statement-banner-renderer", "ytd-player-legacy-desktop-watch-ads-renderer", "#masthead-ad", "#player-ads",
      "ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads']",
      "ad-slot-renderer", "ytm-rich-item-renderer:has(ad-slot-renderer)", "ytm-promoted-sparkles-web-renderer",
      "ytm-promoted-video-renderer", "ytm-companion-ad-renderer", "ytm-companion-slot", ".ytp-ad-overlay-container",
    ];
    const hideStyle = document.createElement("style");
    // Mỗi selector một khối: một selector hỏng (vd. :has trên WebKit cũ) không làm hỏng cả stylesheet.
    hideStyle.textContent = YOUTUBE_HIDE.map((s) => `${s} { display: none !important; }`).join("\n");
    // Lúc document_start có thể chưa có <html>; trang cũng có thể thay <head> → gắn (lại) trong vòng lặp bên dưới.
    const applyHide = () => {
      const parent = document.head || document.documentElement;
      if (!youtubeOn) hideStyle.remove();
      else if (!hideStyle.isConnected && parent) parent.appendChild(hideStyle);
    };
    applyHide();

    // Trang gán `var ytInitialPlayerResponse = {…}` bằng script inline → setter trên window bắt được.
    let initialPlayer;
    Object.defineProperty(window, "ytInitialPlayerResponse", {
      configurable: true,
      get: () => initialPlayer,
      set: (value) => {
        initialPlayer = prune(value);
      },
    });

    // Dự phòng khi quảng cáo vẫn lọt: tắt tiếng, tua hết quảng cáo, bấm Bỏ qua; hết quảng cáo thì trả lại tiếng.
    const SKIP_BUTTONS = ".ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button";
    let mutedVideo = null;
    setInterval(() => {
      applyHide();
      const video = youtubeOn && document.querySelector(".ad-showing video");
      if (video) {
        if (!video.muted) {
          video.muted = true;
          mutedVideo = video;
        }
        if (Number.isFinite(video.duration) && video.currentTime < video.duration) video.currentTime = video.duration;
        const skip = document.querySelector(SKIP_BUTTONS);
        if (skip) nativeClick.call(skip);
      } else if (mutedVideo) {
        mutedVideo.muted = false;
        mutedVideo = null;
      }
    }, 300);
  }
})();
