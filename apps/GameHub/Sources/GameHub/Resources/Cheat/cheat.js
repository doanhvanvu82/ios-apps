// Bảng chỉnh thông số (kiểu Cheat Engine) — chèn lúc document start mọi game.
//
// Ref (mã tham chiếu một giá trị) có 3 dạng:
//   w:<type>:<index>        ô nhớ wasm (index theo kích thước kiểu)
//   j:<n>                   thuộc tính số trong object JS (đăng ký lúc quét)
//   r:<kind>:<id>[:<field>] giá trị RPG Maker MV/MZ, ghi qua API của game
(function() {
  if (window.__ghCheat) return;

  // ---- Bắt WebAssembly.Memory của engine (Unity, Godot, Ruffle, KiriKiri…) ----
  var memories = [];
  function keep(m) { if (m instanceof WebAssembly.Memory && memories.indexOf(m) < 0) memories.push(m); }
  function keepExports(x) {
    var inst = x && (x.instance || x);
    var ex = inst && inst.exports;
    if (ex) for (var k in ex) keep(ex[k]);
    return x;
  }
  function keepImports(imports) {
    if (!imports) return;
    for (var mod in imports) for (var k in imports[mod]) keep(imports[mod][k]);
  }
  if (typeof WebAssembly === 'object') {
    var W = WebAssembly, origInst = W.instantiate, origStream = W.instantiateStreaming,
        OrigInstance = W.Instance, OrigMemory = W.Memory;
    W.instantiate = function(src, imports) {
      keepImports(imports);
      return origInst.apply(this, arguments).then(keepExports);
    };
    if (origStream) W.instantiateStreaming = function(src, imports) {
      keepImports(imports);
      return origStream.apply(this, arguments).then(keepExports);
    };
    var Instance = function(module, imports) {
      keepImports(imports);
      return keepExports(new OrigInstance(module, imports));
    };
    Instance.prototype = OrigInstance.prototype;
    W.Instance = Instance;
    var Memory = function(desc) { var m = new OrigMemory(desc); keep(m); return m; };
    Memory.prototype = OrigMemory.prototype;
    W.Memory = Memory;
  }
  function heap() {
    var best = null;
    memories.forEach(function(m) { if (!best || m.buffer.byteLength > best.buffer.byteLength) best = m; });
    return best && best.buffer;
  }

  // Đo RAM ngoài heap wasm: texture GPU (ước lượng từ kích thước + định dạng) và audio đã giải mã.
  var texBytes = 0, audioBytes = 0, bound = {};
  function bpp(fmt) {
    if (fmt >= 0x93B0 && fmt <= 0x93BD) { var b = ASTC_BLOCK[fmt - 0x93B0]; return 16 / (b[0] * b[1]); }
    if (fmt >= 0x93D0 && fmt <= 0x93DD) { var c = ASTC_BLOCK[fmt - 0x93D0]; return 16 / (c[0] * c[1]); }
    if (fmt >= 0x9270 && fmt <= 0x9279) return (fmt === 0x9270 || fmt === 0x9271 || fmt === 0x9274 || fmt === 0x9275 || fmt === 0x9276 || fmt === 0x9277) ? 0.5 : 1;
    if (fmt === 0x881A) return 8;
    if (fmt === 0x8814) return 16;
    return 4;
  }
  var ASTC_BLOCK = [[4,4],[5,4],[5,5],[6,5],[6,6],[8,5],[8,6],[8,8],[10,5],[10,6],[10,8],[10,10],[12,10],[12,12]];
  function mipChain(w, h, levels) {
    var t = 0;
    for (var i = 0; i < levels; i++) { t += Math.max(1, w >> i) * Math.max(1, h >> i); }
    return t;
  }
  function track(tex, bytes) { if (tex) { tex.__gh = (tex.__gh || 0) + bytes; texBytes += bytes; } }
  [window.WebGL2RenderingContext, window.WebGLRenderingContext].forEach(function(C) {
    if (!C) return;
    var P = C.prototype, bind = P.bindTexture, del = P.deleteTexture;
    P.bindTexture = function(target, tex) { bound[target] = tex; return bind.apply(this, arguments); };
    P.deleteTexture = function(tex) { if (tex && tex.__gh) { texBytes -= tex.__gh; tex.__gh = 0; } return del.apply(this, arguments); };
    if (P.texStorage2D) {
      var ts = P.texStorage2D;
      P.texStorage2D = function(target, levels, fmt, w, h) {
        track(bound[target], mipChain(w, h, levels) * bpp(fmt) * (target === 0x8513 ? 6 : 1));
        return ts.apply(this, arguments);
      };
    }
    var ti = P.texImage2D;
    P.texImage2D = function(target, level, fmt, w) {
      var h = arguments.length >= 9 ? arguments[4] : (arguments[5] && arguments[5].height) || 0;
      if (arguments.length < 9) w = (arguments[5] && arguments[5].width) || 0;
      if (w && h) track(bound[target], w * h * bpp(fmt));
      return ti.apply(this, arguments);
    };
    var ci = P.compressedTexImage2D;
    P.compressedTexImage2D = function(target, level, fmt, w, h) {
      track(bound[target], w * h * bpp(fmt));
      return ci.apply(this, arguments);
    };
  });
  [window.AudioContext, window.webkitAudioContext].forEach(function(A) {
    if (!A || !A.prototype.decodeAudioData) return;
    var dec = A.prototype.decodeAudioData;
    A.prototype.decodeAudioData = function(data, ok, err) {
      var p = dec.call(this, data, ok && function(b) { audioBytes += b.length * b.numberOfChannels * 4; ok(b); }, err);
      if (p && p.then && !ok) return p.then(function(b) { audioBytes += b.length * b.numberOfChannels * 4; return b; });
      return p;
    };
  });

  // Log khi tổng đổi ≥ 8MB, để biết bước nào làm WebKit hết RAM.
  var lastTotal = -1;
  setInterval(function() {
    var heapB = 0;
    memories.forEach(function(m) { heapB += m.buffer.byteLength; });
    var mb = function(b) { return Math.round(b / 1048576); };
    var total = mb(heapB + texBytes + audioBytes);
    if (Math.abs(total - lastTotal) < 8) return;
    lastTotal = total;
    var c = document.querySelector('canvas');
    console.log('[mem] total~' + total + 'MB = heap ' + mb(heapB) + ' + tex ' + mb(texBytes) + ' + audio ' + mb(audioBytes) +
      (c ? ' | canvas ' + c.width + 'x' + c.height : ''));
  }, 1000);

  var TYPES = {
    int32: [Int32Array, 4], int16: [Int16Array, 2], int8: [Int8Array, 1],
    float32: [Float32Array, 4], float64: [Float64Array, 8]
  };
  function view(type) { var b = heap(); return b && new TYPES[type][0](b); }

  // ---- RPG Maker MV/MZ ----
  function isRpgm() { return typeof $gameParty !== 'undefined' && !!$gameParty && typeof $gameActors !== 'undefined'; }
  function itemTable(kind) { return kind === 'weapon' ? $dataWeapons : kind === 'armor' ? $dataArmors : $dataItems; }
  var rpgm = {
    read: function() {
      var paramNames = [0, 1, 2, 3, 4, 5, 6, 7].map(function(i) { return TextManager.param(i); });
      var actors = $gameParty.members().map(function(a) {
        return {
          id: a.actorId(), name: a.name(), level: a.level, hp: a.hp, mhp: a.mhp, mp: a.mp, mmp: a.mmp,
          tp: a.tp, exp: a.currentExp(),
          params: paramNames.map(function(n, i) { return { id: i, name: n, value: a.param(i) }; })
        };
      });
      var items = [];
      ['item', 'weapon', 'armor'].forEach(function(kind) {
        itemTable(kind).forEach(function(d) {
          if (d && d.name) items.push({ kind: kind, id: d.id, name: d.name, count: $gameParty.numItems(d) });
        });
      });
      var variables = [], switches = [];
      $dataSystem.variables.forEach(function(n, i) {
        var v = $gameVariables.value(i);
        if (n && (typeof v === 'number' || typeof v === 'string')) variables.push({ id: i, name: n, value: v });
      });
      $dataSystem.switches.forEach(function(n, i) { if (n) switches.push({ id: i, name: n, value: $gameSwitches.value(i) }); });
      return { gold: $gameParty.gold(), maxGold: $gameParty.maxGold(), actors: actors, items: items,
               variables: variables, switches: switches };
    },
    get: function(p) {
      switch (p[0]) {
        case 'gold': return $gameParty.gold();
        case 'actor':
          var a = $gameActors.actor(+p[1]), f = p[2];
          if (f === 'exp') return a.currentExp();
          if (f.indexOf('param') === 0) return a.param(+f.slice(5));
          return a[f];
        case 'item': case 'weapon': case 'armor': return $gameParty.numItems(itemTable(p[0])[+p[1]]);
        case 'variable': return $gameVariables.value(+p[1]);
        case 'switch': return $gameSwitches.value(+p[1]);
      }
    },
    set: function(p, v) {
      switch (p[0]) {
        case 'gold': $gameParty.gainGold(v - $gameParty.gold()); return;
        case 'actor':
          var a = $gameActors.actor(+p[1]), f = p[2];
          if (f === 'hp') a.setHp(v);
          else if (f === 'mp') a.setMp(v);
          else if (f === 'tp') a.setTp(v);
          else if (f === 'level') a.changeLevel(v, false);
          else if (f === 'exp') a.changeExp(v, false);
          else if (f.indexOf('param') === 0) { var i = +f.slice(5); a.addParam(i, v - a.param(i)); }
          return;
        case 'item': case 'weapon': case 'armor':
          var d = itemTable(p[0])[+p[1]];
          $gameParty.gainItem(d, v - $gameParty.numItems(d));
          return;
        case 'variable': $gameVariables.setValue(+p[1], v); return;
        case 'switch': $gameSwitches.setValue(+p[1], !!v); return;
      }
    }
  };

  // ---- Đọc/ghi theo ref ----
  var jsRefs = [];
  function jsRef(obj, key, path) { jsRefs.push({ obj: obj, key: key, path: path }); return 'j:' + (jsRefs.length - 1); }
  function get(ref) {
    var p = ref.split(':');
    if (p[0] === 'w') { var a = view(p[1]); return a ? a[+p[2]] : null; }
    if (p[0] === 'j') { var r = jsRefs[+p[1]]; return r.obj[r.key]; }
    return rpgm.get(p.slice(1));
  }
  function set(ref, v) {
    var p = ref.split(':');
    if (p[0] === 'w') { view(p[1])[+p[2]] = v; return; }
    if (p[0] === 'j') { var r = jsRefs[+p[1]]; r.obj[r.key] = v; return; }
    rpgm.set(p.slice(1), v);
  }
  function label(ref) {
    var p = ref.split(':');
    if (p[0] === 'w') return '0x' + (+p[2] * TYPES[p[1]][1]).toString(16).toUpperCase().padStart(8, '0');
    if (p[0] === 'j') return jsRefs[+p[1]].path;
    return p.slice(1).join('.');
  }

  var frozen = {};
  setInterval(function() {
    for (var ref in frozen) { try { if (get(ref) !== frozen[ref]) set(ref, frozen[ref]); } catch (e) {} }
  }, 100);

  // ---- Quét ----
  // wasm: idx (Uint32Array) + prev (Float64Array). JS: refs + prev.
  var scan = null, progress = 0;
  var MAX_RESULTS = 5000000, CHUNK = 4 * 1024 * 1024, MAX_JS_OBJECTS = 300000;
  function tick() { return new Promise(function(r) { setTimeout(r, 0); }); }
  function matcher(mode, value, value2, isFloat) {
    var near = function(v, t) { return isFloat ? Math.abs(v - t) < 0.5 || Math.round(v) === t : v === t; };
    switch (mode) {
      case 'exact': return function(v) { return near(v, value); };
      case 'between': return function(v) { return v >= value && v <= value2; };
      case 'increased': return function(v, old) { return v > old; };
      case 'decreased': return function(v, old) { return v < old; };
      case 'changed': return function(v, old) { return v !== old; };
      case 'unchanged': return function(v, old) { return v === old; };
    }
    throw new Error('Chế độ quét không hợp lệ: ' + mode);
  }

  async function scanWasm(type, test) {
    var a = view(type);
    if (!a) throw new Error('Game này không có bộ nhớ wasm — dùng kiểu "number" (quét JS).');
    var idx = new Uint32Array(1 << 16), prev = new Float64Array(1 << 16), n = 0;
    for (var start = 0; start < a.length; start += CHUNK) {
      a = view(type);
      var end = Math.min(a.length, start + CHUNK);
      for (var i = start; i < end; i++) {
        var v = a[i];
        if (!test(v)) continue;
        if (n === idx.length) {
          if (n >= MAX_RESULTS) throw new Error('Quá ' + MAX_RESULTS + ' kết quả — chọn giá trị đặc trưng hơn (tránh 0, 1).');
          var i2 = new Uint32Array(n * 2); i2.set(idx); idx = i2;
          var p2 = new Float64Array(n * 2); p2.set(prev); prev = p2;
        }
        idx[n] = i; prev[n++] = v;
      }
      progress = end / a.length;
      await tick();
    }
    return { kind: 'w', type: type, idx: idx, prev: prev, count: n };
  }

  // BFS từ window qua object/array thường; bỏ DOM, typed array, hàm.
  async function scanJs(test) {
    var refs = [], prev = [], seen = new Set(), queue = [], visited = 0;
    Object.keys(window).forEach(function(k) {
      if (k.indexOf('__gh') === 0 || k === 'webkit') return;
      queue.push([window, k, k]);
    });
    for (var q = 0; q < queue.length && visited < MAX_JS_OBJECTS; q++) {
      var e = queue[q], v;
      try { v = e[0][e[1]]; } catch (err) { continue; }
      if (typeof v === 'number') {
        if (test(v)) { refs.push(jsRef(e[0], e[1], e[2])); prev.push(v); }
        continue;
      }
      if (!v || typeof v !== 'object' || seen.has(v) || v instanceof Node || ArrayBuffer.isView(v)
          || v instanceof ArrayBuffer || v instanceof WebAssembly.Memory || v === window) continue;
      seen.add(v);
      visited++;
      var keys;
      try { keys = Object.keys(v); } catch (err) { continue; }
      if (keys.length > 5000) continue;
      var arr = Array.isArray(v);
      for (var j = 0; j < keys.length; j++) queue.push([v, keys[j], e[2] + (arr ? '[' + keys[j] + ']' : '.' + keys[j])]);
      if (visited % 5000 === 0) { progress = Math.min(0.99, visited / MAX_JS_OBJECTS); await tick(); }
    }
    return { kind: 'j', refs: refs, prev: prev, count: refs.length };
  }

  async function scanNext(test) {
    var s = scan, n = 0;
    if (s.kind === 'w') {
      var a = view(s.type);
      for (var i = 0; i < s.count; i++) {
        var v = a[s.idx[i]];
        if (test(v, s.prev[i])) { s.idx[n] = s.idx[i]; s.prev[n++] = v; }
        if ((i & 0xFFFFF) === 0) { progress = i / s.count; await tick(); a = view(s.type); }
      }
    } else {
      for (var j = 0; j < s.count; j++) {
        var cur = get(s.refs[j]);
        if (typeof cur === 'number' && test(cur, s.prev[j])) { s.refs[n] = s.refs[j]; s.prev[n++] = cur; }
      }
      s.refs.length = n; s.prev.length = n;
    }
    s.count = n;
  }

  function results(limit) {
    var out = [];
    if (!scan) return { count: 0, items: out };
    for (var i = 0; i < Math.min(limit || 200, scan.count); i++) {
      var ref = scan.kind === 'w' ? 'w:' + scan.type + ':' + scan.idx[i] : scan.refs[i];
      out.push(entry(ref));
    }
    return { count: scan.count, items: out };
  }
  function entry(ref) {
    var v = null;
    try { v = get(ref); } catch (e) {}
    return { ref: ref, label: label(ref), value: v, frozen: ref in frozen };
  }

  var api = {
    info: function() {
      var b = heap();
      return { rpgm: isRpgm(), heapMB: b ? Math.round(b.byteLength / 1048576) : 0, scanning: progress < 1,
               count: scan ? scan.count : 0 };
    },
    progress: function() { return progress; },
    first: async function(a) {
      progress = 0;
      scan = null;
      try {
        var test = matcher(a.mode, +a.value, +a.value2, a.type === 'float32' || a.type === 'float64' || a.type === 'number');
        scan = a.type === 'number' ? await scanJs(test) : await scanWasm(a.type, test);
      } finally { progress = 1; }
      return results(a.limit);
    },
    next: async function(a) {
      if (!scan) throw new Error('Chưa quét lần đầu.');
      progress = 0;
      try {
        var isFloat = scan.kind === 'j' || scan.type === 'float32' || scan.type === 'float64';
        await scanNext(matcher(a.mode, +a.value, +a.value2, isFloat));
      } finally { progress = 1; }
      return results(a.limit);
    },
    results: function(a) { return results(a.limit); },
    reset: function() { scan = null; progress = 1; return true; },
    read: function(a) { return a.refs.map(entry); },
    write: function(a) {
      set(a.ref, a.value);
      if (a.ref in frozen) frozen[a.ref] = get(a.ref);
      return entry(a.ref);
    },
    freeze: function(a) {
      if (a.on) frozen[a.ref] = a.value === undefined ? get(a.ref) : a.value; else delete frozen[a.ref];
      return entry(a.ref);
    },
    rpgm: function() { if (!isRpgm()) throw new Error('Game chưa vào màn chơi (chưa có $gameParty).'); return rpgm.read(); }
  };
  progress = 1;

  window.__ghCheat = {
    call: function(name, args) {
      if (!api[name]) throw new Error('Không có lệnh cheat: ' + name);
      return api[name](args || {});
    }
  };
})();
