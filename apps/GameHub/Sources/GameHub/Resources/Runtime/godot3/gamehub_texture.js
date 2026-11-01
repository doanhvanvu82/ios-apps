// GameHub: game Godot 2D hay nạp sẵn hàng nghìn khung hình RGBA không nén
// (Buchicome ☆ High kick!: ~1.4 GB texture ngay ở màn tiêu đề) — quá nặng cho
// GPU iPhone. Thu nhỏ texture RGBA lớn lúc đưa lên GPU. Godot tính UV theo kích
// thước gốc của nó (toạ độ chuẩn hoá 0..1) nên sprite vẫn vẽ đúng chỗ, đúng cỡ.
//
// Tỉ lệ mặc định 2/3: canvas iPhone ngang (~814 px) chỉ hiện khung 1280 px của
// game ở ~0.64× → texture 2/3 vẫn dư điểm ảnh, không mờ (0.5× thì bị phóng lại
// → mờ). Trang có thể đặt window.GAMEHUB_TEXTURE_SCALE trước khi nạp file này
// (game Godot 4 khung 1920 px hiện ở ~0.42× → 0.5 là đủ nét).
// Riêng texture cạnh luỹ thừa 2 (có thể có mipmap) giữ 0.5× để vẫn là luỹ thừa 2
// và khớp chuỗi mipmap (WebGL 1 không cho mipmap texture không luỹ thừa 2).
(function () {
	'use strict';
	const MIN_PIXELS = 128 * 128;
	const NPOT_SCALE = window.GAMEHUB_TEXTURE_SCALE || 2 / 3;
	const TEXTURE_2D = 0x0DE1, TEXTURE0 = 0x84C0, TEXTURE_MAX_LEVEL = 0x813D;
	const RGBA = 0x1908, RGBA8 = 0x8058, UNSIGNED_BYTE = 0x1401;
	const isRGBA = (ifmt) => ifmt === RGBA8 || ifmt === RGBA;  // WebGL 2 / WebGL 1
	const stats = { halved: 0, savedBytes: 0, ms: 0 };
	window.__gamehubTextureStats = stats;

	const scaled = new WeakMap();  // texture → tỉ lệ [sx, sy] đã áp
	const unit = new WeakMap();   // gl → texture unit đang active
	const bound = new WeakMap();  // gl → { unit: WebGLTexture } (TEXTURE_2D)

	function boundTexture(gl) {
		const map = bound.get(gl);
		return map ? map[unit.get(gl) || 0] : null;
	}

	const isPow2 = (n) => (n & (n - 1)) === 0;

	// Kích thước mới cho texture w×h (null = giữ nguyên).
	function targetSize(w, h) {
		if (w * h < MIN_PIXELS) return null;
		if (isPow2(w) && isPow2(h)) return [Math.max(1, w >> 1), Math.max(1, h >> 1)];
		return [Math.max(1, Math.round(w * NPOT_SCALE)), Math.max(1, Math.round(h * NPOT_SCALE))];
	}

	// Thu nhỏ có trọng số alpha (pixel trong suốt không kéo màu viền sprite về
	// đen): mỗi điểm đích lấy trung bình vùng nguồn tương ứng (≤ 2×2 điểm vì tỉ
	// lệ ≥ 0.5).
	function resample(src, off, w, h, nw, nh) {
		const out = new Uint8Array(nw * nh * 4), stride = w * 4;
		const fx = w / nw, fy = h / nh;
		const cx0 = new Int32Array(nw), cx1 = new Int32Array(nw);
		for (let x = 0; x < nw; x++) {
			const x0 = Math.floor(x * fx);
			cx0[x] = 4 * x0;
			cx1[x] = 4 * Math.min(Math.max(Math.ceil((x + 1) * fx) - 1, x0), w - 1);
		}
		for (let y = 0; y < nh; y++) {
			const y0 = Math.floor(y * fy), y1 = Math.min(Math.max(Math.ceil((y + 1) * fy) - 1, y0), h - 1);
			const r0 = off + y0 * stride, r1 = off + y1 * stride;
			for (let x = 0; x < nw; x++) {
				const p0 = r0 + cx0[x], p1 = r0 + cx1[x], p2 = r1 + cx0[x], p3 = r1 + cx1[x];
				const a0 = src[p0 + 3], a1 = src[p1 + 3], a2 = src[p2 + 3], a3 = src[p3 + 3];
				const sa = a0 + a1 + a2 + a3, o = 4 * (y * nw + x);
				out[o + 3] = (sa + 2) >> 2;
				if (sa === 0) continue;
				for (let k = 0; k < 3; k++) {
					out[o + k] = (src[p0 + k] * a0 + src[p1 + k] * a1 + src[p2 + k] * a2 + src[p3 + k] * a3) / sa;
				}
			}
		}
		return out;
	}

	function isPlainRGBA(target, format, type, src) {
		return target === TEXTURE_2D && format === RGBA && type === UNSIGNED_BYTE && src && ArrayBuffer.isView(src);
	}

	for (const P of [WebGLRenderingContext.prototype, WebGL2RenderingContext.prototype]) {
	const origActive = P.activeTexture, origBind = P.bindTexture, origImage = P.texImage2D,
		origSub = P.texSubImage2D, origParam = P.texParameteri;

	P.activeTexture = function (u) {
		unit.set(this, u - TEXTURE0);
		return origActive.call(this, u);
	};
	P.bindTexture = function (target, tex) {
		if (target === TEXTURE_2D) {
			let map = bound.get(this);
			if (!map) bound.set(this, map = {});
			map[unit.get(this) || 0] = tex;
		}
		return origBind.call(this, target, tex);
	};
	P.texImage2D = function (target, level, ifmt, w, h, border, format, type, src, srcOffset) {
		if (arguments.length >= 9 && isRGBA(ifmt) && isPlainRGBA(target, format, type, src)) {
			const tex = boundTexture(this);
			const size = level === 0 ? targetSize(w, h) : null;
			if (size) {
				const t0 = Date.now();
				const data = resample(src, srcOffset || 0, w, h, size[0], size[1]);
				stats.ms += Date.now() - t0;
				stats.halved++;
				stats.savedBytes += w * h * 4 - data.length;
				if (tex) scaled.set(tex, [size[0] / w, size[1] / h, isPow2(w) && isPow2(h)]);
				return origImage.call(this, target, 0, ifmt, size[0], size[1], border, format, type, data);
			}
			// Mipmap của texture luỹ thừa 2 đã thu nhỏ 0.5×: level L gốc = level L-1 mới.
			const info = tex && scaled.get(tex);
			if (info && level > 0) {
				if (!info[2]) return;
				return origImage.call(this, target, level - 1, ifmt, w, h, border, format, type, src, srcOffset || 0);
			}
		}
		if (level === 0) {
			const tex = boundTexture(this);
			if (tex) scaled.delete(tex);
		}
		return origImage.apply(this, arguments);
	};
	P.texSubImage2D = function (target, level, x, y, w, h, format, type, src, srcOffset) {
		const tex = boundTexture(this);
		const info = tex && scaled.get(tex);
		if (info && level === 0 && isPlainRGBA(target, format, type, src)) {
			const nw = Math.max(1, Math.round(w * info[0])), nh = Math.max(1, Math.round(h * info[1]));
			return origSub.call(this, target, 0, Math.round(x * info[0]), Math.round(y * info[1]), nw, nh,
				format, type, resample(src, srcOffset || 0, w, h, nw, nh));
		}
		return origSub.apply(this, arguments);
	};
	P.texParameteri = function (target, pname, param) {
		if (pname === TEXTURE_MAX_LEVEL && target === TEXTURE_2D && param > 0) {
			const tex = boundTexture(this);
			const info = tex && scaled.get(tex);
			// Luỹ thừa 2 (0.5×): chuỗi mipmap lùi 1 bậc. Tỉ lệ khác: chỉ có level 0
			// (mipmap gốc bị bỏ) → MAX_LEVEL 0 để texture vẫn hợp lệ, không đen.
			if (info) param = info[2] ? param - 1 : 0;
		}
		return origParam.call(this, target, pname, param);
	};
	}
})();
