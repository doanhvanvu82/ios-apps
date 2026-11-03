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

  // Ngưỡng chồng lấn dọc để coi hai cột chữ dọc là cùng một bong bóng. Cột CJK trong một bong
  // bóng thường so le (cột sau bắt đầu từ giữa cột trước) nên mốc 0.4 bỏ sót; mỗi cột thành một
  // block riêng thì bản dịch bị nhồi vào dải rộng vài chục pixel, không đọc được.
  const VERTICAL_MERGE_OVERLAP = 0.15;

  /** Hai dòng/khối chữ có cùng một bong bóng thoại không. */
  function shouldMerge(a, b) {
    const horizontalOverlap = overlap1D(a.x, a.x + a.w, b.x, b.x + b.w);
    const verticalOverlap = overlap1D(a.y, a.y + a.h, b.y, b.y + b.h);
    const horizontalGap = gap1D(a.x, a.x + a.w, b.x, b.x + b.w);
    const verticalGap = gap1D(a.y, a.y + a.h, b.y, b.y + b.h);
    const minWidth = Math.min(a.w, b.w);
    const minHeight = Math.min(a.h, b.h);
    // Cột chữ dọc (CJK) cạnh nhau — chỉ khi CẢ HAI đều là cột dọc. Nếu áp cho chữ ngang thì một
    // câu thoại nằm cạnh SFX (chồng trục y, cách nhau ít) bị gộp: khung trắng phủ cả hai và chữ
    // phóng to theo bề rộng union, tràn ra ngoài bong bóng. Cột dọc không dùng mốc chênh chiều
    // cao 1.8 lần: các cột trong cùng bong bóng dài ngắn rất khác nhau.
    if (a.h > a.w * 1.2 && b.h > b.w * 1.2) {
      return verticalOverlap > VERTICAL_MERGE_OVERLAP * minHeight && horizontalGap < minWidth;
    }
    // SFX vẽ bằng cỡ chữ lớn hơn hẳn dòng thoại: chênh chiều cao > 1.8 lần là hai cụm chữ khác
    // loại, không gộp — tránh chữ SFX nằm sát bong bóng bị dán chung vào bản dịch.
    const tall = Math.max(a.h, b.h);
    const short = Math.min(a.h, b.h);
    if (short > 0 && tall > short * 1.8) return false;
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
  // Cột chữ dọc dịch sang tiếng Việt phải viết ngang: giữ bề rộng cột gốc (vài chục pixel) thì
  // chữ bị bóp thành một dòng dọc không đọc được, nên phải nới — nhưng nới 5 lần thì vùng chữ
  // tràn hẳn ra ngoài bong bóng, đè lên tranh. 2.4 lần đủ cho câu tiếng Việt xuống 2–3 dòng mà
  // vẫn nằm trong bong bóng.
  const TEXT_AREA_MAX_WIDEN_VERTICAL = 2.4;
  const TEXT_AREA_MAX_TALLEN = 2;
  const TEXT_AREA_EDGE = 0.85;
  // Vùng chữ sau khi cắt phải còn đủ chỗ đặt chữ. Cắt sát hơn thì bản dịch bị bóp thành cột
  // vài chục pixel, cỡ chữ rơi xuống 7px — đúng lỗi "chữ bé tí" trên ảnh review.
  const TEXT_AREA_MIN_SIZE = 0.06;

  /** Block là cột chữ dọc: dùng cờ từ groupLines, cache cũ không có thì suy từ hình dạng. */
  function isVerticalBlock(block, text) {
    if (typeof block.vertical === "boolean") return block.vertical;
    return text.h > text.w * 1.4;
  }

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
      const vertical = isVerticalBlock(block, text);
      const widen = vertical ? TEXT_AREA_MAX_WIDEN_VERTICAL : TEXT_AREA_MAX_WIDEN;
      // Chỉ cột dọc được nới ra ngoài `box` (box của nó chính là dải chữ) — block thường phải giữ
      // trong phạm vi đã chia với block bên cạnh, nếu không hai bản dịch sẽ đè nhau.
      const grow = vertical ? ((widen - 1) / 2) * text.w : 0;
      // Nới quá tay sang block bên cạnh thì block đó bị bóp còn vài chục pixel (cỡ chữ rơi
      // xuống 7px). Chỉ nới tới mép block gần nhất cùng dải hàng, phần còn lại để trống.
      let growLeft = grow;
      let growRight = grow;
      if (grow > 0) {
        for (let k = 0; k < blocks.length; k += 1) {
          if (k === index) continue;
          const other = blocks[k];
          if (other.imageIndex !== block.imageIndex || other.image !== block.image) continue;
          const neighbour = other.textBox || other.box;
          if (Math.min(text.y + text.h, neighbour.y + neighbour.h) <= Math.max(text.y, neighbour.y)) continue;
          const end = neighbour.x + neighbour.w;
          if (end <= text.x) {
            growLeft = Math.min(growLeft, text.x - end);
          } else if (neighbour.x >= text.x + text.w) {
            growRight = Math.min(growRight, neighbour.x - (text.x + text.w));
          }
        }
        growLeft = Math.max(0, growLeft);
        growRight = Math.max(0, growRight);
      }
      const x0 = Math.max(0, area.x0 - growLeft);
      const x1 = Math.min(1, area.x1 + growRight);
      const centerX = text.x + text.w / 2;
      const centerY = text.y + text.h / 2;
      const halfW = Math.max(
        text.w / 2,
        Math.min(centerX - x0, x1 - centerX, (text.w / 2) * widen)
      );
      const halfH = Math.max(
        text.h / 2,
        Math.min(centerY - area.y0, area.y1 - centerY, (text.h / 2) * TEXT_AREA_MAX_TALLEN) * TEXT_AREA_EDGE
      );
      block.textArea = { x: centerX - halfW, y: centerY - halfH, w: halfW * 2, h: halfH * 2 };
      fitTextAreaToPolygon(block);
    });
    resolveTextAreaOverlaps(blocks);
    return blocks;
  }

  /**
   * Khung vẽ nền che chữ gốc.
   *
   * Có đa giác bong bóng thì `box` đã là bao đúng biên bong bóng, dùng nguyên. Không có đa giác
   * thì `box` là hợp các ô bong bóng do OCR loang — flood fill tràn qua nét vẽ làm ô rộng gấp
   * nhiều lần vùng chữ, vẽ nguyên hình chữ nhật đó ra một khối đặc che cả panel. Trường hợp này
   * lấy nền đúng bằng `textArea` (nới nhẹ): `textArea` đã bao trùm `textBox` nên che hết chữ gốc,
   * đồng thời luôn chứa chữ dịch — kẹp nền vào `box` sẽ hụt nền ở cột dọc đã nới rộng.
   */
  function backdropFrame(block) {
    const box = block && block.box;
    if (!box) return null;
    const poly = block.poly;
    if (Array.isArray(poly) && poly.length >= 6) return box;
    // Cột chữ dọc: `textArea` đã nới ngang cho bản dịch tiếng Việt (có khi rộng gấp 5 lần cột
    // gốc). Lấy nền theo `textArea` thì thành dải xám phủ ngang tranh, nên nền chỉ ôm đúng cột
    // chữ gốc (`box`).
    // Caption không có đa giác: `box` là hợp các hộp OCR của cả cụm chữ, còn `textArea` bị
    // neo vào hộp của TỪNG dòng — dòng ngắn hơn cụm nên nền theo textArea để lộ đầu/cuối chữ
    // gốc. Không có bong bóng thì dùng thẳng `box`.
    const captionFrame = block.kind === "caption";
    let text;
    if (captionFrame) {
      const textBox = block.textBox;
      // Caption: `box` (hợp vùng OCR) bao đúng cả dòng chữ cách điệu, nhưng có lúc là khung
      // bong bóng/panel cao hơn hẳn hộp chữ — khi đó chỉ dùng hộp chữ để không phủ lên tranh.
      text = (textBox && box.h > textBox.h * 1.5) ? textBox : box;
    } else {
      text = block.textArea || block.textBox || box;
    }
    if (!text || text.w <= 0 || text.h <= 0) return box;
    // Nới quá tay theo bề rộng câu (câu dài 0.85 trang -> nền tràn gần hết trang): chặn trần.
    // Đệm nền phải đủ để phủ nét ngoài của chữ gốc (font truyện hay có viền dày / chữ
    // cách điệu vượt khỏi hộp OCR vài pixel). Đệm 0.008 từng để lộ mép chữ gốc dưới bản dịch.
    // Nhãn chương/tập và caption dùng font cách điệu, hộp OCR thường chỉ ôm phần giữa con chữ
    // nên cần đệm dọc lớn hơn hẳn — nếu không nửa dưới chữ gốc vẫn lộ ra.
    // Chỉ nhãn chương/tập mới dùng font cách điệu vượt hộp OCR; caption thường (bảng chỉ số
    // trong truyện) mà đệm dọc lớn sẽ thành khối trắng phủ lên tranh.
    const titleCaption = block.kind === "caption"
      && /(chapter|chương|tập|episode|ngoại truyện|side story)/i.test(String(block.text || ""));
    const padX = titleCaption
      ? Math.min(Math.max(text.w * 0.12, 0.012), 0.03)
      : Math.min(Math.max(text.w * 0.03, 0.006), 0.02);
    const padY = titleCaption
      ? Math.min(Math.max(text.h, 0.025), 0.06)
      : Math.min(Math.max(text.h * 0.25, 0.01), 0.03);
    let x0 = Math.max(0, text.x - padX);
    let y0 = Math.max(0, text.y - padY);
    let x1 = Math.min(1, text.x + text.w + padX);
    let y1 = Math.min(1, text.y + text.h + padY);
    // `box` là vùng chữ GỐC: nền phải che hết, nếu không chữ gốc còn lộ ra cạnh bản dịch. Trước
    // đây nền lấy một trong hai (`box` cho cột dọc, `textArea` cho phần còn lại) nên luôn hụt
    // một phía: cột dọc thì chữ dịch trôi ra ngoài nền, chữ nhật thì chữ gốc không bị che hết.
    // Nhưng `box` do OCR loang có khi phủ cả panel — chỉ mở rộng khi nó không quá lớn.
    const boxArea = box.w * box.h;
    if (!captionFrame && boxArea > 0 && boxArea <= text.w * text.h * 3) {
      x0 = Math.min(x0, box.x);
      y0 = Math.min(y0, box.y);
      x1 = Math.max(x1, box.x + box.w);
      y1 = Math.max(y1, box.y + box.h);
    }
    if (x1 <= x0 || y1 <= y0) return box;
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }

  /**
   * Vùng chữ đã nới có thể chồng lên block bên cạnh (block hẹp nới ngang/dọc nhiều lần) làm hai
   * bản dịch đè lên nhau. Cắt đôi phần chồng theo trục chồng nhiều hơn; bỏ qua nếu cắt xong một
   * bên còn quá nhỏ để đặt chữ.
   */
  function resolveTextAreaOverlaps(blocks) {
    for (let i = 0; i < blocks.length; i += 1) {
      for (let j = i + 1; j < blocks.length; j += 1) {
        const first = blocks[i];
        const second = blocks[j];
        if (first.imageIndex !== second.imageIndex || first.image !== second.image) continue;
        if (!first.textArea || !second.textArea) continue;
        const a = first.textArea;
        const b = second.textArea;
        const overlapX = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
        const overlapY = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
        // Ngưỡng cũ 0.004 bỏ qua dải chồng mỏng (4px trên ảnh 1378px) — đủ để dòng chữ cuối
        // của block trên chạm dòng đầu của block dưới. Hạ xuống 0.0015 để cắt luôn.
        if (overlapX <= 0.0015 || overlapY <= 0.0015) continue;
        // Luôn cắt bằng MỘT đường: hai vùng chữ không bao giờ được chồng nhau, nên không có
        // nhánh "bỏ qua". Đường cắt lấy giữa phần chồng, nhưng nếu tổng bề rộng đủ chỗ thì
        // kẹp lại để mỗi bên còn tối thiểu TEXT_AREA_MIN_SIZE — tránh vừa đè nhau vừa bóp
        // một bên thành dải vài chục pixel (cỡ chữ rơi xuống 7px).
        // Chia đều phần chồng hay cắt mất gần hết một bên khi block dọc nới rộng đè lên block
        // hẹp bên cạnh: bên hẹp còn ~30px nên câu dài tràn ra ngoài. Chia theo tỉ lệ bề rộng
        // hiện có — bên rộng vẫn đủ chỗ xuống dòng, bên hẹp giữ được phần của nó.
        if (overlapX >= overlapY) {
          const [left, right] = a.x <= b.x ? [a, b] : [b, a];
          const span = right.x + right.w - left.x;
          const total = left.w + right.w;
          let cut = left.x + (total > 0 ? span * (left.w / total) : span / 2);
          if (span >= TEXT_AREA_MIN_SIZE * 2) {
            cut = Math.min(
              Math.max(cut, left.x + TEXT_AREA_MIN_SIZE),
              left.x + span - TEXT_AREA_MIN_SIZE
            );
          }
          left.w = cut - left.x;
          right.x = cut;
          right.w = left.x + span - cut;
        } else {
          const [top, bottom] = a.y <= b.y ? [a, b] : [b, a];
          const span = bottom.y + bottom.h - top.y;
          const total = top.h + bottom.h;
          let cut = top.y + (total > 0 ? span * (top.h / total) : span / 2);
          if (span >= TEXT_AREA_MIN_SIZE * 2) {
            cut = Math.min(
              Math.max(cut, top.y + TEXT_AREA_MIN_SIZE),
              top.y + span - TEXT_AREA_MIN_SIZE
            );
          }
          top.h = cut - top.y;
          bottom.y = cut;
          bottom.h = top.y + span - cut;
        }
      }
    }
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
   * Vùng đặt chữ phải nằm trong bong bóng cong. Trước đây cắt bề rộng theo cung HẸP NHẤT
   * trong cả dải dọc của vùng chữ: với bong bóng tròn, hàng sát đỉnh/đáy rất hẹp nên cả vùng
   * co còn ~nửa bề rộng, chữ dịch bị bóp nhỏ và xuống dòng vụn. Nay chọn hình chữ nhật có
   * DIỆN TÍCH lớn nhất nằm gọn trong đa giác, neo tâm ở tâm chữ gốc — đổi chiều cao lấy bề
   * rộng khi cần.
   */
  function fitTextAreaToPolygon(block) {
    const poly = block.poly;
    const area = block.textArea;
    if (!Array.isArray(poly) || poly.length < 8 || !area) return;
    const text = block.textBox || block.box;
    const centerX = text.x + text.w / 2;
    const centerY = text.y + text.h / 2;
    // Đa giác ở đây là đường bao bong bóng, nên có thể nới tới mép bong bóng thay vì chỉ 1.3
    // lần bề rộng chữ gốc: chữ Việt dài hơn, khung hẹp làm cỡ chữ tụt xuống một nửa.
    const centerSpan = polygonSpanAt(poly, centerY);
    if (!centerSpan) return;
    const widen = isVerticalBlock(block, text) ? TEXT_AREA_MAX_WIDEN_VERTICAL : TEXT_AREA_MAX_WIDEN;
    const limit = Math.min(
      (centerSpan.right - centerSpan.left) * 0.95,
      text.w * Math.max(widen, 2.2)
    );
    const maxHalf = Math.min(0.3, Math.max(area.h, text.h * TEXT_AREA_MAX_TALLEN) / 2);
    // Ưu tiên BỀ RỘNG: chữ càng rộng càng ít phải xuống dòng, cỡ chữ giữ được lớn. Chiều cao
    // chỉ cần đủ chỗ cho số dòng gốc; đổi thêm chiều cao lấy bề rộng là lỗi cũ.
    const minHeight = Math.min(maxHalf * 2, Math.max(text.h, 0.03));
    const step = 0.004;
    const fits = (y, left, right) => {
      const span = polygonSpanAt(poly, y);
      return Boolean(span) && span.left <= left && span.right >= right;
    };
    // Tâm chữ OCR thường lệch tâm bong bóng vài phần trăm. Cho phép dời khung tối đa 2% trang
    // (≈19px) để lấy được bề rộng/chiều cao lớn hơn — lệch này không nhìn ra, còn giữ nguyên
    // tâm thì khung bị cắt cụt ở phía hẹp.
    const offsets = [];
    for (let d = -0.02; d <= 0.0201; d += 0.004) offsets.push(d);
    // Chọn hình chữ nhật có DIỆN TÍCH lớn nhất nằm gọn trong bong bóng: bong bóng to thì bản
    // dịch được dùng hết chỗ (chữ to, ít dòng), thay vì chỉ rộng bằng hộp chữ gốc rồi dồn cục.
    let best = null;
    for (let index = 0; index <= 24; index += 1) {
      const width = limit * (1 - (0.7 * index) / 24);
      const halfW = width / 2;
      for (const dx of offsets) {
        const left = centerX + dx - halfW;
        const right = centerX + dx + halfW;
        if (left < 0 || right > 1) continue;
        let up = 0;
        while (up + step <= maxHalf && fits(centerY - up - step, left, right)) up += step;
        let down = 0;
        while (down + step <= maxHalf && fits(centerY + down + step, left, right)) down += step;
        const height = 2 * Math.min(up, down);
        if (height < minHeight) continue;
        const score = width * height;
        if (!best || score > best.score) best = { dx, width, height, score };
      }
    }
    if (!best) return;
    area.x = centerX + best.dx - best.width / 2;
    area.y = centerY - best.height / 2;
    area.w = best.width;
    area.h = best.height;
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
   * Đa giác về toạ độ pixel của ảnh, chấp nhận đầu vào lẫn đơn vị.
   *
   * Native trả đa giác đã chuẩn hoá, nhưng model OCR trong harness lại trả `poly` bằng pixel
   * trong khi `box` chuẩn hoá. Nhân thẳng đa giác pixel với kích thước ảnh ra vùng phủ kín
   * trang — nền đè lên tranh. Toạ độ vượt hẳn 1 nghĩa là đang ở pixel: chia về 0..1 trước.
   */
  function normalizedPoly(poly, width, height) {
    if (!Array.isArray(poly) || poly.length < 6 || poly.length % 2 !== 0) return null;
    const values = poly.map(Number);
    if (values.some((value) => !Number.isFinite(value))) return null;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (let index = 0; index < values.length; index += 2) {
      maxX = Math.max(maxX, values[index]);
      maxY = Math.max(maxY, values[index + 1]);
    }
    const scaleX = maxX > 1.5 ? width : 1;
    const scaleY = maxY > 1.5 ? height : 1;
    const result = [];
    for (let index = 0; index < values.length; index += 2) {
      const x = values[index] / scaleX;
      const y = values[index + 1] / scaleY;
      // Còn tràn ra ngoài trang nhiều thì đa giác không dùng được — về hình chữ nhật.
      if (x < -0.2 || x > 1.2 || y < -0.2 || y > 1.2) return null;
      result.push(Math.max(0, Math.min(1, x)) * width, Math.max(0, Math.min(1, y)) * height);
    }
    return result;
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
        poly: normalizedPoly(line.poly, width, height),
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
  const CACHE_VERSION = "v30";

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
        ...(block.vertical ? { v: 1 } : {}),
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
        ...(item.v === 1 ? { vertical: true } : {}),
        lines: Number(item.n) || 1,
        text: String(item.t || ""),
        translation: String(item.t || ""),
      }))
      .filter((block) => block.text);
  }

  root.MangalateCore = {
    backdropFrame,
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
