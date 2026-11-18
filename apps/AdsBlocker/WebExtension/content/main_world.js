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
  // Tab-under: trang mở nội dung thật ở tab mới rồi chuyển tab hiện tại sang quảng cáo ngay sau đó.
  const TAB_UNDER_MS = 3000;
  const INTERACTIVE = "a[href],button,input,select,textarea,label,summary,[role=button],[role=link],[role=menuitem],[role=tab]";
  const SCROLL_EVENTS = new Set(["touchmove", "wheel", "mousewheel"]);

  let popupDomains = [];
  // Cờ tính năng từ content.js (mặc định bật cho tới khi nhận config).
  let adsOn = true;
  let trackingOn = true;
  let youtubeOn = true;
  let unlockScroll = false;
  let lastGesture = null;
  let lastNewTab = -Infinity;
  // Tab mới gần nhất ({ win, url }; win = null với link target=_blank) và URL extension tự chuyển tab này tới.
  let lastOpened = null;
  let selfNavigation = null;

  document.addEventListener("adsblocker:config", (event) => {
    try {
      const config = JSON.parse(event.detail);
      popupDomains = Array.isArray(config.popupDomains) ? config.popupDomains : [];
      // Ngoại lệ "cho trang này mở tab mới" (từ chẩn đoán) = tắt chặn popup trên trang.
      adsOn = config.ads !== false && !config.allowPopups;
      trackingOn = config.tracking !== false;
      youtubeOn = config.youtube !== false;
      unlockScroll = config.unlockScroll === true;
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

  const absoluteUrl = (url) => {
    try {
      return new URL(url, location.href).href;
    } catch {
      return "";
    }
  };
  const isWebUrl = (url) => /^https?:/i.test(url || "");

  const markNewTab = (win, url) => {
    lastNewTab = performance.now();
    lastOpened = { win, url: url ? absoluteUrl(url) : "" };
  };

  const opensNewTab = (anchor) => {
    const target = (anchor.getAttribute("target") || "").toLowerCase();
    return target !== "" && target !== "_self" && target !== "_top" && target !== "_parent";
  };

  for (const type of ["pointerdown", "mousedown", "touchstart", "click", "keydown"]) {
    window.addEventListener(type, (event) => {
      if (!event.isTrusted) return;
      const target = elementOf(event.composedPath()[0]);
      lastGesture = { time: performance.now(), target: target instanceof Element ? target : null };
      const anchor = type === "click" && lastGesture.target && lastGesture.target.closest("a[href]");
      if (anchor && opensNewTab(anchor)) markNewTab(null, anchor.href);
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
    const win = nativeOpen.apply(this, arguments);
    markNewTab(win, url);
    return win;
  };
  Object.defineProperty(window, "open", { value: guardedOpen, writable: true, configurable: true });

  // Click giả (a.click() / dispatchEvent) lên link mở tab mới.
  const blockSyntheticClick = (anchor) => {
    if (!(anchor instanceof HTMLAnchorElement) || !anchor.href || !opensNewTab(anchor)) return false;
    const userClicked = lastGesture && lastGesture.target && anchor.contains(lastGesture.target);
    const reason = userClicked ? null : popupVerdict(anchor.href);
    if (reason) {
      report("popup", anchor.href, reason);
      return true;
    }
    markNewTab(null, anchor.href);
    return false;
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

  // Tab-under: location không bọc được (LegacyUnforgeable) → huỷ qua sự kiện navigate của Navigation API.
  // Ngay sau khi trang mở tab mới, tab hiện tại chuyển sang site khác = đổi tab cũ thành quảng cáo; trang thật
  // không làm cả hai cùng lúc. Safari chưa có Navigation API thì không chặn được (chỉ còn rule chặn domain).
  // Chặn xong thì đóng tab mới và mở nội dung của nó ngay tại tab này: giữ lịch sử (Back được), không dồn tab.
  // Tab không có handle (link target=_blank, noopener) hoặc không đóng được → background đóng hộ (message tabUnder).
  const takeBackOpenedTab = () => {
    const opened = lastOpened;
    lastOpened = null;
    if (!opened) return;
    let url = opened.url;
    if (opened.win) {
      try {
        if (!isWebUrl(url)) url = opened.win.location.href;
      } catch {
        // Tab mới đã sang origin khác: không đọc được URL, background lấy hộ.
      }
      try {
        opened.win.close();
      } catch {
        // Trang đã thay window.close: background đóng hộ.
      }
    }
    if (!isWebUrl(url)) url = "";
    const closed = !!(opened.win && opened.win.closed);
    document.dispatchEvent(new CustomEvent("adsblocker:tabunder", { detail: JSON.stringify({ url, closed }) }));
    if (!url) return;
    selfNavigation = url;
    // Không điều hướng ngay trong handler của lượt điều hướng vừa huỷ.
    setTimeout(() => location.assign(url), 0);
  };

  if (window === window.top && window.navigation) {
    window.navigation.addEventListener("navigate", (event) => {
      if (selfNavigation && event.destination.url === selfNavigation) {
        selfNavigation = null;
        return;
      }
      if (!adsOn || !event.cancelable || event.hashChange || event.downloadRequest != null) return;
      if (event.navigationType !== "push" && event.navigationType !== "replace") return;
      const host = hostOf(event.destination.url);
      if (!host || sameSite(host, location.hostname)) return;
      // Người dùng đã chạm lần nữa sau khi tab mới mở → chuyển trang thuộc cú chạm mới, không phải tab-under.
      const sameGesture = !lastGesture || lastGesture.time <= lastNewTab;
      const tabUnder = sameGesture && performance.now() - lastNewTab < TAB_UNDER_MS;
      let reason = null;
      if (tabUnder) reason = "đổi tab cũ sang trang khác ngay sau khi mở tab mới";
      else if (!event.userInitiated && popupDomains.some((d) => matchesDomain(host, d))) reason = "domain đã chặn";
      if (!reason) return;
      event.preventDefault();
      report("tabunder", event.destination.url, reason);
      if (tabUnder) takeBackOpenedTab();
    });
  }

  // Mở khoá cuộn (rule "Ẩn + mở khoá cuộn"): hộp thoại chống chặn quảng cáo khoá cuộn bằng preventDefault trên
  // touchmove/wheel ở cấp trang; listener của phần tử con (carousel, bản đồ) vẫn chặn được như cũ.
  const isPageRoot = (target) => target === window || target === document ||
    target === document.documentElement || target === document.body;
  const nativePreventDefault = Event.prototype.preventDefault;
  Event.prototype.preventDefault = function preventDefault() {
    if (unlockScroll && SCROLL_EVENTS.has(this.type) && isPageRoot(this.currentTarget)) return;
    return nativePreventDefault.apply(this, arguments);
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
