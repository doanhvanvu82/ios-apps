// GameHub: gắn tệp lớn của game Ren'Py PC vào FS dạng lazy.
//
// Bản web chuẩn giải nén cả game.zip vào RAM; game PC 1–5 GB thì không thể.
// game.zip chỉ chứa main.py + renpy/ + script; ảnh/âm thanh/video liệt kê ở
// gh_lazy.json và được đọc khi Python mở tệp: XHR đồng bộ có Range, server trả
// base64 (?gh_b64=1, XHR đồng bộ chỉ trả text). Một bộ đệm LRU chung cho mọi
// tệp để RAM không tăng theo số tệp đã đọc.
(function () {
  var CHUNK = 256 * 1024;
  var MAX_BYTES = 48 * 1024 * 1024;
  var cache = new Map();
  var cachedBytes = 0;

  function url(path) {
    return encodeURI(path).replace(/#/g, '%23').replace(/\?/g, '%3F') + '?gh_b64=1';
  }

  function loadChunk(path, size, ci) {
    var key = path + '#' + ci;
    var hit = cache.get(key);
    if (hit) {
      cache.delete(key);
      cache.set(key, hit);
      return hit;
    }
    var from = ci * CHUNK, to = Math.min(size, from + CHUNK) - 1, n = to - from + 1;
    var xhr = new XMLHttpRequest();
    xhr.open('GET', url(path), false);
    xhr.setRequestHeader('Range', 'bytes=' + from + '-' + to);
    xhr.send(null);
    var bin = xhr.status === 200 ? atob(xhr.responseText) : '';
    if (bin.length !== n) {
      console.error('gamehub_lazyfs: ' + path + ' ' + from + '-' + to + ' → HTTP ' + xhr.status);
      throw new FS.ErrnoError(29);  // EIO
    }
    var bytes = new Uint8Array(n);
    for (var i = 0; i < n; i++) bytes[i] = bin.charCodeAt(i);
    cache.set(key, bytes);
    cachedBytes += n;
    while (cachedBytes > MAX_BYTES && cache.size > 1) {
      var oldest = cache.keys().next().value;
      cachedBytes -= cache.get(oldest).length;
      cache.delete(oldest);
    }
    return bytes;
  }

  function mount(path, size) {
    var dir = path.substring(0, path.lastIndexOf('/')) || '/';
    FS.mkdirTree(dir);
    var node = FS.createFile(dir, path.substring(path.lastIndexOf('/') + 1), {}, true, false);
    Object.defineProperty(node, 'usedBytes', { get: function () { return size; } });
    var ops = {};
    Object.keys(node.stream_ops).forEach(function (k) { ops[k] = node.stream_ops[k]; });
    ops.read = function (stream, buffer, offset, length, position) {
      if (position >= size) return 0;
      var total = Math.min(size - position, length), done = 0;
      while (done < total) {
        var pos = position + done, ci = Math.floor(pos / CHUNK);
        var c = loadChunk(path, size, ci), o = pos - ci * CHUNK;
        var k = Math.min(c.length - o, total - done);
        buffer.set(c.subarray(o, o + k), offset + done);
        done += k;
      }
      return total;
    };
    node.stream_ops = ops;
  }

  Module.preRun.push(function () {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', 'gh_lazy.json', false);
    xhr.send(null);
    if (xhr.status !== 200) return;
    var files = JSON.parse(xhr.responseText);
    files.forEach(function (f) { mount('/' + f[0], f[1]); });
    console.log('gamehub_lazyfs: ' + files.length + ' tệp gắn lazy');
  });

  // Giải nén xong thì bỏ /game.zip khỏi RAM (bản chuẩn giữ cả zip lẫn bản giải nén).
  var progress = window.progress;
  window.progress = function (done, total) {
    if (progress) progress(done, total);
    if (done === total) {
      try { FS.unlink('/game.zip'); } catch (e) {}
    }
  };
})();
