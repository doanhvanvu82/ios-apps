// Chấm điểm phần tử nghi là quảng cáo / lớp phủ, từ "features" đã đo sẵn (thuần, test được bằng Node).
(function (root) {
  "use strict";

  const { hasAdWord } = typeof module !== "undefined" && module.exports
    ? require("../rules/validate.js")
    : root.AdsBlockerRules;

  // Kích thước banner IAB chuẩn (px CSS).
  const BANNER_SIZES = [
    [300, 250], [336, 280], [728, 90], [970, 90], [970, 250], [320, 50], [320, 100],
    [300, 50], [300, 600], [160, 600], [120, 600], [468, 60], [250, 250],
  ];
  const SIZE_TOLERANCE = 8;
  const MIN_SCORE = 2;

  function isBannerSize(width, height) {
    return BANNER_SIZES.some(([w, h]) =>
      Math.abs(width - w) <= SIZE_TOLERANCE && Math.abs(height - h) <= SIZE_TOLERANCE);
  }

  /** Class kiểu CSS-in-JS / build hash ("x1a2b3c", "css-1q2w3e"): đổi mỗi lần deploy, không dùng làm selector. */
  function isRandomToken(token) {
    if (token.length >= 24) return true;
    const core = token.replace(/^(css|sc|jsx|styles?)[-_]/i, "");
    const digits = (core.match(/\d/g) || []).length;
    return core.length >= 5 && digits >= 2 && /[a-z]/i.test(core) && !/[-_]/.test(core);
  }

  /**
   * f: {
   *   tag, idClass (id + class + vài attribute), thirdPartyFrame, fixed, sticky, zIndex,
   *   width, height, viewportRatio (diện tích / viewport), transparent, textLength,
   *   thirdPartyLinks, hasMedia, pointerEventsNone
   * }
   */
  function scoreCandidate(f) {
    const hints = [];
    let score = 0;
    const add = (hint, points) => { hints.push(hint); score += points; };

    if (hasAdWord(f.idClass)) add("ad-keyword", 2);
    if (f.thirdPartyFrame) add("third-party-iframe", 2);
    if (f.tag === "ins") add("ins-tag", 1);
    if (isBannerSize(f.width, f.height)) add("banner-size", 2);
    if (f.thirdPartyLinks > 0) add("third-party-link", 1);
    if (f.fixed) add("fixed", 1);
    if (f.sticky) add("sticky", 1);
    if (f.zIndex >= 1000) add("high-z-index", 1);
    if (isInvisibleOverlay(f)) add("invisible-overlay", 3);
    return { score, hints, isCandidate: score >= MIN_SCORE };
  }

  /** Lớp phủ trong suốt bắt click: phủ gần hết màn hình, không có nội dung. */
  function isInvisibleOverlay(f) {
    if (f.pointerEventsNone || f.hasMedia || f.textLength > 4 || !f.transparent) return false;
    if (f.fixed) return f.viewportRatio >= 0.5;
    return f.absolute === true && f.viewportRatio >= 0.9 && f.zIndex >= 1000;
  }

  /**
   * Khung chứa quảng cáo khi người dùng chạm: ngón tay thường trúng ảnh/link bên trong, còn thứ ổn định qua các lần
   * tải là khung bao ngoài cùng cỡ. chainRects[0] là phần tử được chạm, phần tử sau là tổ tiên lần lượt.
   * Trả về index tổ tiên cao nhất có hộp gần trùng phần tử được chạm.
   */
  function slotIndex(chainRects) {
    const base = chainRects[0];
    const baseArea = Math.max(1, base.width * base.height);
    let index = 0;
    for (let i = 1; i < chainRects.length; i++) {
      const r = chainRects[i];
      const nearEdges = Math.abs(r.left - base.left) <= 8 && Math.abs(r.top - base.top) <= 8 &&
        Math.abs(r.width - base.width) <= 8 && Math.abs(r.height - base.height) <= 8;
      if (!nearEdges && r.width * r.height > baseArea * 1.15) break;
      index = i;
    }
    return index;
  }

  const api = { hasAdWord, isBannerSize, isRandomToken, scoreCandidate, isInvisibleOverlay, slotIndex, MIN_SCORE };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.AdsBlockerCandidates = api;
})(globalThis);
