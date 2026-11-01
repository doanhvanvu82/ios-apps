// Hàm thuần dùng chung cho content script và test node. Không đụng DOM.
(function (root) {
  "use strict";

  // Chỉ cần nhận diện "chữ không phải Latin" để ghép dòng không thêm dấu cách.
  const CJK_START = /^[぀-ヿ㐀-䶿一-鿿가-힯豈-﫿]/;
  const CJK_END = /[぀-ヿ㐀-䶿一-鿿가-힯豈-﫿]$/;

  function overlap1D(a0, a1, b0, b1) {
    return Math.max(0, Math.min(a1, b1) - Math.max(a0, b0));
  }

  function gap1D(a0, a1, b0, b1) {
    return Math.max(0, Math.max(a0, b0) - Math.min(a1, b1));
  }

  function iou(a, b) {
    const width = overlap1D(a.x, a.x + a.w, b.x, b.x + b.w);
    const height = overlap1D(a.y, a.y + a.h, b.y, b.y + b.h);
    const intersection = width * height;
    if (intersection <= 0) return 0;
    const union = a.w * a.h + b.w * b.h - intersection;
    return union > 0 ? intersection / union : 0;
  }

  /** box chuẩn hoá trong tile + tile chuẩn hoá trong ảnh → box chuẩn hoá trong ảnh. */
  function mapTileBox(box, tile) {
    return {
      x: tile.x + box.x * tile.w,
      y: tile.y + box.y * tile.h,
      w: box.w * tile.w,
      h: box.h * tile.h,
    };
  }

  function chunk(items, size) {
    const result = [];
    for (let index = 0; index < items.length; index += size) {
      result.push(items.slice(index, index + size));
    }
    return result;
  }

  /** Gộp block theo tổng số ký tự để một chapter thường chỉ cần 1 request Gemini. */
  function batchByChars(items, maxChars, maxItems) {
    const batches = [];
    let current = [];
    let chars = 0;
    for (const item of items) {
      const length = String((item && item.text) || "").length;
      if (current.length && (chars + length > maxChars || current.length >= maxItems)) {
        batches.push(current);
        current = [];
        chars = 0;
      }
      current.push(item);
      chars += length;
    }
    if (current.length) batches.push(current);
    return batches;
  }

  /** Hai dòng/khối chữ có cùng một bong bóng thoại không. */
  function shouldMerge(a, b) {
    const horizontalOverlap = overlap1D(a.x, a.x + a.w, b.x, b.x + b.w);
    const verticalOverlap = overlap1D(a.y, a.y + a.h, b.y, b.y + b.h);
    const horizontalGap = gap1D(a.x, a.x + a.w, b.x, b.x + b.w);
    const verticalGap = gap1D(a.y, a.y + a.h, b.y, b.y + b.h);
    const minWidth = Math.min(a.w, b.w);
    const minHeight = Math.min(a.h, b.h);
    // SFX vẽ bằng cỡ chữ lớn hơn hẳn dòng thoại: chênh chiều cao > 1.8 lần là hai cụm chữ khác
    // loại, không gộp — tránh chữ SFX nằm sát bong bóng bị dán chung vào bản dịch.
    const tall = Math.max(a.h, b.h);
    const short = Math.min(a.h, b.h);
    if (short > 0 && tall > short * 1.8) return false;
    // Cột chữ dọc (CJK) cạnh nhau — chỉ khi CẢ HAI đều là cột dọc. Nếu áp cho chữ ngang thì một
    // câu thoại nằm cạnh SFX (chồng trục y, cách nhau ít) bị gộp: khung trắng phủ cả hai và chữ
    // phóng to theo bề rộng union, tràn ra ngoài bong bóng.
    if (a.h > a.w * 1.2 && b.h > b.w * 1.2) {
      return verticalOverlap > 0.4 * minHeight && horizontalGap < 0.45 * minWidth;
    }
    // Hai dòng của cùng một đoạn chữ ngang: chồng theo trục x, cách nhau dưới nửa chiều cao dòng
    // (rộng hơn nữa là hai bong bóng riêng — gộp sẽ ra khung trắng phủ cả khoảng giữa).
    return horizontalOverlap > 0.4 * minWidth && verticalGap < 0.45 * minHeight;
  }

  function isVertical(group) {
    if (group.length < 2) {
      const box = group[0].box;
      return box.h > box.w * 1.4;
    }
    const averageWidth = group.reduce((sum, line) => sum + line.box.w, 0) / group.length;
    const averageHeight = group.reduce((sum, line) => sum + line.box.h, 0) / group.length;
    return averageHeight > averageWidth * 1.2;
  }

  function joinLineText(lines, vertical) {
    const pieces = lines.map((line) => String(line.text || "").trim()).filter(Boolean);
    if (vertical) return pieces.join("");
    let text = "";
    for (const piece of pieces) {
      if (!text) {
        text = piece;
        continue;
      }
      text += CJK_END.test(text) && CJK_START.test(piece) ? "" : " ";
      text += piece;
    }
    return text;
  }

  // Vùng đặt chữ dịch được nới tối đa: bề ngang 1.3 lần chữ gốc (tiếng Việt dài hơn thì ưu tiên
  // xuống dòng), bề dọc tới 85% khoảng từ tâm chữ gốc tới mép bong bóng (mép cong không chứa chữ).
  const TEXT_AREA_MAX_WIDEN = 1.3;
  const TEXT_AREA_MAX_TALLEN = 2;
  const TEXT_AREA_EDGE = 0.85;

  /**
   * Gán `textArea` (0..1) cho mỗi block: vùng đặt chữ dịch, tách khỏi `box` là vùng nền che chữ gốc.
   * Neo vào tâm chữ gốc (`textBox`) và nới đối xứng trong phạm vi bong bóng. Hai block cùng ảnh
   * chia nhau tại giữa khe giữa hai `textBox` — hai `textBox` không bao giờ chồng nhau nên luôn có
   * khe, kể cả khi hai bong bóng dính nhau và cho chung một đa giác/`box`.
   */
  function layoutTextAreas(blocks) {
    const bounds = blocks.map((block) => {
      const text = block.textBox || block.box;
      return {
        x0: Math.min(block.box.x, text.x),
        y0: Math.min(block.box.y, text.y),
        x1: Math.max(block.box.x + block.box.w, text.x + text.w),
        y1: Math.max(block.box.y + block.box.h, text.y + text.h),
      };
    });
    for (let i = 0; i < blocks.length; i += 1) {
      for (let j = i + 1; j < blocks.length; j += 1) {
        const first = blocks[i];
        const second = blocks[j];
        if (first.imageIndex !== second.imageIndex || first.image !== second.image) continue;
        const areaA = bounds[i];
        const areaB = bounds[j];
        if (Math.min(areaA.x1, areaB.x1) <= Math.max(areaA.x0, areaB.x0)) continue;
        if (Math.min(areaA.y1, areaB.y1) <= Math.max(areaA.y0, areaB.y0)) continue;
        const a = first.textBox || first.box;
        const b = second.textBox || second.box;
        const gapX = Math.max(a.x, b.x) - Math.min(a.x + a.w, b.x + b.w);
        const gapY = Math.max(a.y, b.y) - Math.min(a.y + a.h, b.y + b.h);
        if (gapX <= 0 && gapY <= 0) continue;
        if (gapX >= gapY) {
          const cut = Math.min(a.x + a.w, b.x + b.w) + gapX / 2;
          const [left, right] = a.x <= b.x ? [areaA, areaB] : [areaB, areaA];
          left.x1 = Math.min(left.x1, cut);
          right.x0 = Math.max(right.x0, cut);
        } else {
          const cut = Math.min(a.y + a.h, b.y + b.h) + gapY / 2;
          const [top, bottom] = a.y <= b.y ? [areaA, areaB] : [areaB, areaA];
          top.y1 = Math.min(top.y1, cut);
          bottom.y0 = Math.max(bottom.y0, cut);
        }
      }
    }
    blocks.forEach((block, index) => {
      const text = block.textBox || block.box;
      const area = bounds[index];
      const centerX = text.x + text.w / 2;
      const centerY = text.y + text.h / 2;
      const halfW = Math.max(
        text.w / 2,
        Math.min(centerX - area.x0, area.x1 - centerX, (text.w / 2) * TEXT_AREA_MAX_WIDEN)
      );
      const halfH = Math.max(
        text.h / 2,
        Math.min(centerY - area.y0, area.y1 - centerY, (text.h / 2) * TEXT_AREA_MAX_TALLEN) * TEXT_AREA_EDGE
      );
      block.textArea = { x: centerX - halfW, y: centerY - halfH, w: halfW * 2, h: halfH * 2 };
      fitTextAreaToPolygon(block);
    });
    return blocks;
  }

  /**
   * Đa giác bong bóng cho cả block. Flood fill ở native bị chính các dòng chữ khác chặn nên mỗi
   * dòng chỉ loang được dải nền quanh nó; ghép các dải theo hàng và nội suy bề rộng ở khoảng giữa
   * để ra một hình bong bóng liền (thay vì nhiều dải rời).
   */
  function bubblePolygon(group, width, height) {
    if (width <= 0 || height <= 0) return null;
    const samples = [];
    for (const line of group) {
      const poly = line.poly;
      if (!Array.isArray(poly) || poly.length < 8 || poly.length % 2 !== 0) continue;
      const points = [];
      for (let index = 0; index < poly.length; index += 2) {
        points.push({ x: poly[index], y: poly[index + 1] });
      }
      const half = points.length / 2;
      const left = points.slice(0, half);
      const right = points.slice(half).sort((a, b) => a.y - b.y);
      if (!left.length || !right.length) continue;
      for (const point of left) {
        let nearest = right[0];
        for (const candidate of right) {
          if (Math.abs(candidate.y - point.y) < Math.abs(nearest.y - point.y)) nearest = candidate;
        }
        samples.push({ y: point.y, left: point.x, right: nearest.x });
      }
    }
    if (samples.length < 2) return null;
    samples.sort((a, b) => a.y - b.y);
    const y0 = samples[0].y;
    const y1 = samples[samples.length - 1].y;
    if (y1 - y0 < 4) return null;

    const rows = 24;
    const leftColumn = [];
    const rightColumn = [];
    for (let index = 0; index < rows; index += 1) {
      const y = y0 + ((y1 - y0) * index) / (rows - 1);
      let before = samples[0];
      let after = samples[samples.length - 1];
      for (const sample of samples) {
        if (sample.y <= y) before = sample;
        if (sample.y >= y) {
          after = sample;
          break;
        }
      }
      const span = after.y - before.y;
      const ratio = span > 0 ? (y - before.y) / span : 0;
      const left = before.left + (after.left - before.left) * ratio;
      const right = before.right + (after.right - before.right) * ratio;
      leftColumn.push([left / width, y / height]);
      rightColumn.push([right / width, y / height]);
    }
    const poly = [];
    for (const point of leftColumn) poly.push(point[0], point[1]);
    for (let index = rightColumn.length - 1; index >= 0; index -= 1) {
      poly.push(rightColumn[index][0], rightColumn[index][1]);
    }
    return poly;
  }

  /**
   * Vùng đặt chữ phải nằm trong bong bóng cong: cắt chiều rộng theo cung hẹp nhất của đa giác
   * trong dải dọc mà vùng chữ chiếm. Không có bước này, chữ gần đỉnh/đáy bong bóng tràn ra ngoài
   * viền vì hình chữ nhật rộng hơn cung của vòng tròn ở độ cao đó.
   */
  function fitTextAreaToPolygon(block) {
    const poly = block.poly;
    const area = block.textArea;
    if (!Array.isArray(poly) || poly.length < 8 || !area) return;
    const half = poly.length / 2;
    const leftSide = [];
    const rightSide = [];
    for (let index = 0; index < poly.length; index += 2) {
      const point = { x: poly[index], y: poly[index + 1] };
      if (index < half) leftSide.push(point);
      else rightSide.push(point);
    }
    if (leftSide.length < 2 || rightSide.length < 2) return;
    const edgeAt = (side, y) => {
      for (let i = 0; i + 1 < side.length; i += 1) {
        const a = side[i];
        const b = side[i + 1];
        const low = Math.min(a.y, b.y);
        const high = Math.max(a.y, b.y);
        if (y < low || y > high || high === low) continue;
        const t = (y - a.y) / (b.y - a.y);
        return a.x + (b.x - a.x) * t;
      }
      return null;
    };
    let narrowest = Infinity;
    for (let step = 0; step <= 8; step += 1) {
      const y = area.y + (area.h * step) / 8;
      const left = edgeAt(leftSide, y);
      const right = edgeAt(rightSide, y);
      if (left === null || right === null) continue;
      narrowest = Math.min(narrowest, right - left);
    }
    if (!Number.isFinite(narrowest) || narrowest <= 0) return;
    const allowed = Math.max(area.w * 0.35, narrowest * 0.92);
    if (allowed < area.w) {
      area.x += (area.w - allowed) / 2;
      area.w = allowed;
    }
  }

  /** Bao lồi (Andrew monotone chain) — đa giác lồi nhỏ nhất chứa mọi điểm. */
  function convexHull(points) {
    const sorted = points.slice().sort((a, b) => (a[0] - b[0]) || (a[1] - b[1]));
    if (sorted.length < 3) return sorted;
    const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
    const lower = [];
    for (const point of sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], point) <= 0) lower.pop();
      lower.push(point);
    }
    const upper = [];
    for (let index = sorted.length - 1; index >= 0; index -= 1) {
      const point = sorted[index];
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], point) <= 0) upper.pop();
      upper.push(point);
    }
    upper.pop();
    lower.pop();
    return lower.concat(upper);
  }

  /**
   * Bảo đảm đa giác phủ kín hộp chữ. Hụt thì lấy bao lồi của (đa giác ∪ 4 góc hộp chữ): vẫn giữ
   * dáng cong của bong bóng, khác với hình chữ nhật. Bỏ nếu bao lồi phình quá lớn (hộp chữ sai).
   */
  function fitPolyToText(poly, x, y, w, h) {
    if (!Array.isArray(poly) || poly.length < 6) return null;
    if (polygonCoversBox(poly, x, y, w, h)) return poly;
    const points = [];
    for (let index = 0; index < poly.length; index += 2) points.push([poly[index], poly[index + 1]]);
    points.push([x, y], [x + w, y], [x, y + h], [x + w, y + h]);
    const hull = convexHull(points);
    if (hull.length < 3) return null;
    let hullArea = 0;
    for (let index = 0; index < hull.length; index += 1) {
      const a = hull[index];
      const b = hull[(index + 1) % hull.length];
      hullArea += a[0] * b[1] - b[0] * a[1];
    }
    let polyArea = 0;
    for (let index = 0; index < poly.length; index += 2) {
      const a = [poly[index], poly[index + 1]];
      const b = [poly[(index + 2) % poly.length], poly[(index + 3) % poly.length]];
      polyArea += a[0] * b[1] - b[0] * a[1];
    }
    // Phình quá 2.2 lần = hộp chữ không thuộc bong bóng này → bỏ đa giác, dùng hình chữ nhật.
    if (Math.abs(hullArea) > Math.abs(polyArea) * 2.2) return null;
    const flat = [];
    for (const point of hull) flat.push(point[0], point[1]);
    return flat;
  }

  /** Bề rộng đa giác cắt ngang tại độ cao `y` (giao với các cạnh) — trả null nếu không cắt. */
  function polygonSpanAt(poly, y) {
    let left = Infinity;
    let right = -Infinity;
    for (let index = 0; index < poly.length; index += 2) {
      const x1 = poly[index];
      const y1 = poly[index + 1];
      const nextIndex = (index + 2) % poly.length;
      const x2 = poly[nextIndex];
      const y2 = poly[nextIndex + 1];
      if (y1 === y2) continue;
      const low = Math.min(y1, y2);
      const high = Math.max(y1, y2);
      if (y < low || y > high) continue;
      const x = x1 + ((x2 - x1) * (y - y1)) / (y2 - y1);
      left = Math.min(left, x);
      right = Math.max(right, x);
    }
    return Number.isFinite(left) && right > left ? { left, right } : null;
  }

  /**
   * Đa giác có phủ KÍN hộp chữ không. Phải so bề rộng đa giác tại từng hàng của chữ, không phải
   * hộp bao: đa giác lõm có hộp bao trùm chữ nhưng ở hàng của chữ thì hẹp, và nền vẽ theo nó sẽ
   * để lộ chữ gốc dù phép so hộp bao "đạt".
   */
  function polygonCoversBox(poly, x, y, w, h) {
    if (!Array.isArray(poly) || poly.length < 6) return false;
    const tol = 0.008;
    for (let step = 0; step <= 4; step += 1) {
      const span = polygonSpanAt(poly, y + (h * step) / 4);
      if (!span) return false;
      if (span.left > x + tol || span.right < x + w - tol) return false;
    }
    return true;
  }

  function mostCommonBackground(lines) {
    const counts = new Map();
    for (const line of lines) {
      const bg = typeof line.bg === "string" && /^#[0-9a-f]{6}$/i.test(line.bg) ? line.bg.toLowerCase() : "#ffffff";
      counts.set(bg, (counts.get(bg) || 0) + 1);
    }
    let best = "#ffffff";
    let bestCount = 0;
    for (const [bg, count] of counts) {
      if (count > bestCount) {
        best = bg;
        bestCount = count;
      }
    }
    return best;
  }

  // Ô hội thoại = vùng nền sáng gần như không màu, đồng nhất quanh chữ VÀ khép kín cả 4 phía.
  // Chữ trôi trên nền trang/tranh có thể đồng nhất nhưng không có biên — phải loại.
  // Thoại thật trong bong bóng có dải nền quanh chữ gần như đồng nhất; SFX đặt trên khoảng trắng
  // của tranh chỉ đạt ~0.5-0.67 (đo trên chapter thật: thoại thấp nhất 0.72).
  const SPEECH_MIN_FILL = 0.68;
  // Tỉ lệ hướng quanh chữ gặp nét vẽ. Hạ thấp để không bỏ oan bong bóng trắng trên trang trắng,
  // nhưng đủ cao để chữ credit (phần lớn hướng trống) vẫn bị loại.
  const SPEECH_MIN_ENCLOSE = 0.45;
  const SPEECH_MIN_RATIO = 0.15;
  // Dòng credit/quảng cáo của trang đọc truyện — không bao giờ là lời thoại.
  const NON_DIALOGUE = /(https?:\/\/|www\.|\.com\b|read manga online|manga\s*\d*\s*fx)/i;
  const SPEECH_MIN_LIGHT = 0.65;
  const SPEECH_MAX_CHROMA = 0.12;
  // Bong bóng đen chữ trắng: gần như không màu và rất tối.
  const SPEECH_DARK_MAX_LIGHT = 0.22;
  const SPEECH_DARK_MAX_CHROMA = 0.2;

  /** Nền bong bóng: trắng/kem/xám rất nhạt, hoặc đen gần như không màu (bong bóng chữ trắng). */
  function isBubbleBackground(background) {
    const match = /^#?([0-9a-f]{6})$/i.exec(String(background || ""));
    if (!match) return false;
    const value = parseInt(match[1], 16);
    const red = (value >> 16) & 255;
    const green = (value >> 8) & 255;
    const blue = value & 255;
    const chroma = (Math.max(red, green, blue) - Math.min(red, green, blue)) / 255;
    const light = luminance(match[1]);
    if (light >= SPEECH_MIN_LIGHT && chroma <= SPEECH_MAX_CHROMA) return true;
    return light <= SPEECH_DARK_MAX_LIGHT && chroma <= SPEECH_DARK_MAX_CHROMA;
  }

  /**
   * Chỉ giữ block nằm trong ô hội thoại. Lọc quá tay (không còn block hoặc còn dưới
   * SPEECH_MIN_RATIO) thì trả nguyên danh sách — thà dịch thừa còn hơn mất cả chapter.
   */
  function selectSpeechBlocks(blocks, options) {
    const all = Array.isArray(blocks) ? blocks : [];
    const minFill = (options && options.minFill) ?? SPEECH_MIN_FILL;
    const minEnclose = (options && options.minEnclose) ?? SPEECH_MIN_ENCLOSE;
    const minRatio = (options && options.minRatio) ?? SPEECH_MIN_RATIO;
    const speech = all.filter((block) => {
      if (NON_DIALOGUE.test(String(block.text || ""))) return false;
      if (typeof block.fill === "number" && block.fill < minFill) return false;
      if (typeof block.enclose === "number" && block.enclose < minEnclose) return false;
      if (!isBubbleBackground(block.bg)) return false;
      return true;
    });
    if (!speech.length || speech.length < Math.ceil(all.length * minRatio)) return all.slice();
    return speech;
  }

  /**
   * Gộp các dòng OCR cùng bong bóng thành block. Toạ độ vào/ra đều chuẩn hoá 0..1;
   * việc gộp chạy trong toạ độ pixel để khoảng cách không bị méo bởi tỉ lệ ảnh.
   */
  function groupLines(lines, width, height) {
    const pixels = (Array.isArray(lines) ? lines : [])
      .filter((line) => line && line.box && String(line.text || "").trim())
      .map((line) => ({
        text: String(line.text).trim(),
        confidence: Number(line.confidence) || 0,
        bg: line.bg,
        fill: Number(line.fill) || 0,
        enclose: Number(line.enclose) || 0,
        box: {
          x: line.box.x * width,
          y: line.box.y * height,
          w: line.box.w * width,
          h: line.box.h * height,
        },
        bubble: line.bubble
          ? {
              x: line.bubble.x * width,
              y: line.bubble.y * height,
              w: line.bubble.w * width,
              h: line.bubble.h * height,
            }
          : null,
        poly: Array.isArray(line.poly) && line.poly.length >= 6
          ? line.poly.map((value, index) => (index % 2 === 0 ? value * width : value * height))
          : null,
      }));

    const parent = pixels.map((_, index) => index);
    function find(index) {
      let current = index;
      while (parent[current] !== current) {
        parent[current] = parent[parent[current]];
        current = parent[current];
      }
      return current;
    }
    function union(a, b) {
      const rootA = find(a);
      const rootB = find(b);
      if (rootA !== rootB) parent[rootB] = rootA;
    }

    for (let i = 0; i < pixels.length; i++) {
      for (let j = i + 1; j < pixels.length; j++) {
        if (shouldMerge(pixels[i].box, pixels[j].box)) union(i, j);
      }
    }

    const groups = new Map();
    pixels.forEach((line, index) => {
      const root = find(index);
      if (!groups.has(root)) groups.set(root, []);
      groups.get(root).push(line);
    });

    const blocks = [];
    for (const group of groups.values()) {
      const vertical = isVertical(group);
      const ordered = group.slice().sort(vertical
        ? (a, b) => (Math.abs(a.box.x - b.box.x) > 2 ? b.box.x - a.box.x : a.box.y - b.box.y)
        : (a, b) => (Math.abs(a.box.y - b.box.y) > 2 ? a.box.y - b.box.y : a.box.x - b.box.x));
      // Khung dán đè = hợp các ô bong bóng của các dòng (rộng hơn hộp chữ, khớp bong bóng hơn).
      const areas = group.map((line) => line.bubble || line.box);
      const textX0 = Math.min(...group.map((line) => line.box.x));
      const textY0 = Math.min(...group.map((line) => line.box.y));
      const textX1 = Math.max(...group.map((line) => line.box.x + line.box.w));
      const textY1 = Math.max(...group.map((line) => line.box.y + line.box.h));
      let x0 = Math.min(...group.map((line) => line.box.x), ...areas.map((area) => area.x));
      let y0 = Math.min(...group.map((line) => line.box.y), ...areas.map((area) => area.y));
      let x1 = Math.max(...group.map((line) => line.box.x + line.box.w), ...areas.map((area) => area.x + area.w));
      let y1 = Math.max(...group.map((line) => line.box.y + line.box.h), ...areas.map((area) => area.y + area.h));
      // Có đường bao thì khung = bao của đa giác (đúng biên bong bóng), tránh phủ sang bong bóng bên.
      const poly = bubblePolygon(group, width, height);
      if (poly) {
        for (let index = 0; index < poly.length; index += 2) {
          x0 = Math.min(x0, poly[index] * width);
          x1 = Math.max(x1, poly[index] * width);
          y0 = Math.min(y0, poly[index + 1] * height);
          y1 = Math.max(y1, poly[index + 1] * height);
        }
      }
      blocks.push({
        text: joinLineText(ordered, vertical),
        box: {
          x: x0 / width,
          y: y0 / height,
          w: (x1 - x0) / width,
          h: (y1 - y0) / height,
        },
        // Vị trí chữ gốc — mốc đặt chữ dịch; `box` ở trên là vùng nền (có thể phủ cả bong bóng bên).
        textBox: {
          x: textX0 / width,
          y: textY0 / height,
          w: (textX1 - textX0) / width,
          h: (textY1 - textY0) / height,
        },
        // Đường bao chỉ dùng khi nó bao trọn vùng chữ. Hụt thì về hình chữ nhật: nền phải che kín
        // chữ gốc, thà hơi vuông còn hơn để chữ gốc lộ ra dưới bản dịch.
        poly: fitPolyToText(poly, textX0 / width, textY0 / height, (textX1 - textX0) / width, (textY1 - textY0) / height),
        bg: mostCommonBackground(group),
        fill: group.reduce((sum, line) => sum + line.fill, 0) / group.length,
        enclose: group.reduce((sum, line) => sum + line.enclose, 0) / group.length,
        vertical,
        confidence: Math.max(...group.map((line) => line.confidence)),
        lines: group.length,
      });
    }

    // Khối chiếm gần cả ảnh thường là chữ giao diện/nhiễu, không phải lời thoại.
    return blocks
      // Chỉ loại khối gần như phủ cả ảnh (OCR đọc nhầm cả trang). Ngưỡng cũ 0.4 loại luôn bong bóng
      // của ảnh bị crop sát — loại ảnh mà app vẫn gặp.
      .filter((block) => block.box.w * block.box.h < 0.85)
      .sort((a, b) => (a.box.y - b.box.y) || (a.box.x - b.box.x));
  }

  /** Độ sáng tương đối (WCAG) để chọn màu chữ đen/trắng trên nền bong bóng. */
  function luminance(hex) {
    const match = /^#?([0-9a-f]{6})$/i.exec(String(hex || ""));
    if (!match) return 1;
    const value = parseInt(match[1], 16);
    const channel = (component) => {
      const c = component / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * channel((value >> 16) & 255) + 0.7152 * channel((value >> 8) & 255) + 0.0722 * channel(value & 255);
  }

  /** Tile chồng mép làm một dòng xuất hiện ở hai tile — gộp lại theo vị trí trùng nhau. */
  function dedupeLines(lines) {
    const kept = [];
    for (const line of lines) {
      if (!line || !line.box) continue;
      const duplicate = kept.find((other) => other.text === line.text && iou(other.box, line.box) > 0.5);
      if (!duplicate) {
        kept.push(line);
      } else if ((line.confidence || 0) > (duplicate.confidence || 0)) {
        Object.assign(duplicate, line);
      }
    }
    return kept;
  }

  // Cache bản dịch theo ảnh. Tăng CACHE_VERSION khi đổi prompt/định dạng để bỏ cache cũ.
  const CACHE_VERSION = "v25";

  function cacheKey(model, url) {
    return `mangalate:${CACHE_VERSION}:${model || "default"}:${url}`;
  }

  function encodeCacheBlocks(blocks) {
    return blocks
      .filter((block) => block && block.box && block.translation)
      .map((block) => ({
        b: [block.box.x, block.box.y, block.box.w, block.box.h],
        g: block.bg || "#ffffff",
        t: String(block.translation),
        ...(Array.isArray(block.poly) && block.poly.length >= 6
          ? { p: block.poly.map((value) => Math.round(value * 1000) / 1000) }
          : {}),
        ...(block.textBox ? { x: [block.textBox.x, block.textBox.y, block.textBox.w, block.textBox.h] } : {}),
        n: Number(block.lines) || 1,
      }));
  }

  function decodeCacheBlocks(items) {
    return (Array.isArray(items) ? items : [])
      .filter((item) => item && Array.isArray(item.b) && item.b.length === 4)
      .map((item) => ({
        box: { x: item.b[0], y: item.b[1], w: item.b[2], h: item.b[3] },
        bg: typeof item.g === "string" ? item.g : "#ffffff",
        poly: Array.isArray(item.p) && item.p.length >= 6 ? item.p.slice() : null,
        textBox: Array.isArray(item.x) && item.x.length === 4
          ? { x: item.x[0], y: item.x[1], w: item.x[2], h: item.x[3] }
          : null,
        lines: Number(item.n) || 1,
        text: String(item.t || ""),
        translation: String(item.t || ""),
      }))
      .filter((block) => block.text);
  }

  root.MangalateCore = {
    batchByChars,
    cacheKey,
    chunk,
    decodeCacheBlocks,
    dedupeLines,
    encodeCacheBlocks,
    groupLines,
    isBubbleBackground,
    fitPolyToText,
    polygonCoversBox,
    layoutTextAreas,
    iou,
    joinLineText,
    luminance,
    mapTileBox,
    selectSpeechBlocks,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
